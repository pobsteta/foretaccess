# Precalcul du CVAT sur AOI + buffer avec garantie de couverture. La (re)acquisition
# WMS n'est pas testee (reseau) ; on teste le controle de couverture .emprise_couverte
# et le chemin nominal (MNT fourni couvrant -> CVAT ecrit, pas de reseau).

.aoi_carre <- function(xmin, xmax, ymin, ymax) {
  sf::st_as_sf(sf::st_sfc(
    sf::st_polygon(list(rbind(
      c(xmin, ymin), c(xmax, ymin), c(xmax, ymax), c(xmin, ymax), c(xmin, ymin)
    ))),
    crs = 2154
  ))
}

test_that(".emprise_couverte : FALSE si MNT trop court, TRUE s'il englobe l'emprise", {
  aoi <- .aoi_carre(0, 20, 0, 20)
  emprise <- sf::st_buffer(aoi, 5) # -> [-5, 25]
  mk <- function(xmin, xmax, ymin, ymax, na_frac = 0) {
    r <- terra::rast(
      xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
      resolution = 1, crs = "EPSG:2154"
    )
    v <- rep(100, terra::ncell(r))
    if (na_frac > 0) v[seq_len(round(na_frac * length(v)))] <- NA
    terra::values(r) <- v
    d <- withr::local_tempdir(.local_envir = parent.frame())
    p <- file.path(d, "m.tif")
    terra::writeRaster(r, p, overwrite = TRUE)
    p
  }
  # MNT trop court (n'atteint pas -5..25) -> FALSE.
  expect_false(.emprise_couverte(mk(0, 20, 0, 20), emprise))
  # MNT englobant l'emprise, plein -> TRUE.
  expect_true(.emprise_couverte(mk(-10, 30, -10, 30), emprise))
  # MNT englobant mais majoritairement NA -> FALSE (trous).
  expect_false(.emprise_couverte(mk(-10, 30, -10, 30, na_frac = 0.8), emprise))
})

test_that("build_cvat_precomputed : MNT fourni couvrant -> CVAT 8 bits, sans reseau", {
  skip_if_not_installed("terra")
  d <- withr::local_tempdir()
  aoi <- .aoi_carre(0, 20, 0, 20)
  # MNT englobant largement l'emprise (AOI + buffer 5 m).
  mnt <- terra::rast(
    xmin = -10, xmax = 30, ymin = -10, ymax = 30, resolution = 1,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100 + terra::rowFromCell(mnt, seq_len(terra::ncell(mnt))) * 0.2
  mnt_path <- file.path(d, "lidar_mnt_mosaic.tif")
  terra::writeRaster(mnt, mnt_path)

  # acquire_mnt NE DOIT PAS etre appele (le MNT couvre) : on le remplace par un
  # stub qui echoue, pour prouver l'absence de reseau.
  testthat::local_mocked_bindings(
    acquire_mnt = function(...) stop("acquire_mnt ne doit pas etre appele")
  )
  out <- build_cvat_precomputed(aoi,
    cache_dir = d, buffer_m = 5,
    mnt_existant = mnt_path
  )
  expect_true(file.exists(out))
  r <- terra::rast(out)
  expect_equal(names(r), "cvat")
  v <- terra::values(r)[, 1]
  expect_true(all(v >= 0 & v <= 255, na.rm = TRUE))
  # 8 bits (entiers).
  expect_true(all(v == as.integer(v), na.rm = TRUE))
  # Idempotent : 2e appel renvoie le meme fichier sans recalcul (out existe).
  expect_identical(build_cvat_precomputed(aoi, cache_dir = d, buffer_m = 5,
    mnt_existant = mnt_path), out)
})

test_that("build_cvat_precomputed : MNT trop court -> (re)acquisition appelee", {
  d <- withr::local_tempdir()
  aoi <- .aoi_carre(0, 20, 0, 20)
  # MNT trop court (ne couvre pas l'emprise) -> doit declencher acquire_mnt.
  court <- terra::rast(xmin = 0, xmax = 10, ymin = 0, ymax = 10, resolution = 1,
    crs = "EPSG:2154")
  terra::values(court) <- 100
  court_path <- file.path(d, "trop_court.tif")
  terra::writeRaster(court, court_path)

  # Stub acquire_mnt : ecrit un MNT couvrant et renvoie son chemin (pas de reseau).
  appele <- FALSE
  testthat::local_mocked_bindings(
    acquire_mnt = function(aoi, ...) {
      appele <<- TRUE
      big <- terra::rast(xmin = -10, xmax = 30, ymin = -10, ymax = 30,
        resolution = 1, crs = "EPSG:2154")
      terra::values(big) <- 100 + terra::rowFromCell(big, seq_len(terra::ncell(big)))
      p <- file.path(d, "reacquis.tif")
      terra::writeRaster(big, p, overwrite = TRUE)
      p
    }
  )
  out <- build_cvat_precomputed(aoi, cache_dir = d, buffer_m = 5,
    mnt_existant = court_path, out = file.path(d, "cvat.tif"))
  expect_true(appele) # la reacquisition a bien ete declenchee
  expect_true(file.exists(out))
})

# --- Codage du fichier : relief valide 0..254, 255 = nodata declare (mission 053) ---

# MNT synthetique : rampe douce + une cuvette gaussienne en (10, 10) dont le fond
# donne un relief >= 0.9961 (octet RVT = 255), + une zone NA a l'ecart de la cuvette.
.mnt_053 <- function(d, na_zone = TRUE) {
  mnt <- terra::rast(
    xmin = -10, xmax = 30, ymin = -10, ymax = 30, resolution = 1,
    crs = "EPSG:2154"
  )
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  terra::values(mnt) <- 100 - 5 * exp(-((xy[, 1] - 10)^2 + (xy[, 2] - 10)^2) / 300)
  if (na_zone) {
    mnt[terra::cellFromRowColCombine(mnt, 5:9, 31:36)] <- NA
  }
  p <- file.path(d, "mnt053.tif")
  terra::writeRaster(mnt, p, overwrite = TRUE)
  # Le MNT relu du disque (float32), celui que voit build_cvat_precomputed().
  list(path = p, mnt = terra::rast(p))
}

.construire_053 <- function(d, mnt_path) {
  testthat::local_mocked_bindings(
    acquire_mnt = function(...) stop("acquire_mnt ne doit pas etre appele"),
    .env = parent.frame()
  )
  build_cvat_precomputed(.aoi_carre(0, 20, 0, 20),
    cache_dir = d, buffer_m = 5, mnt_existant = mnt_path
  )
}

test_that("cvat precalcule : relief maximal ecrete a 254, jamais confondu avec le nodata", {
  d <- withr::local_tempdir()
  m <- .mnt_053(d, na_zone = TRUE)
  # Precondition : le plugin RVT code bien des pixels valides a 255 (sinon le test
  # ne prouverait rien).
  brut <- terra::values(vat_combined(m$mnt, as_byte = TRUE))[, 1]
  fl <- terra::values(vat_combined(m$mnt, as_byte = FALSE))[, 1]
  expect_true(any(!is.na(fl) & brut == 255L))

  out <- .construire_053(d, m$path)
  v <- terra::values(terra::rast(out), na.rm = FALSE)[, 1]
  # Aucun 255 hors zone NA : les pixels valides les plus clairs valent 254.
  expect_false(any(v == 255L, na.rm = TRUE)) # 255 est lu comme NA
  valide_255 <- !is.na(fl) & brut == 255L
  expect_true(all(v[valide_255] == 254L))
  expect_false(anyNA(v[!is.na(fl)]))
})

test_that("cvat precalcule : zone NA du MNT = 255 dans le fichier, nodata declare, lu NA", {
  d <- withr::local_tempdir()
  m <- .mnt_053(d, na_zone = TRUE)
  out <- .construire_053(d, m$path)
  fl <- terra::values(vat_combined(m$mnt, as_byte = FALSE))[, 1]
  expect_true(any(is.na(fl)))

  r <- terra::rast(out)
  # Nodata declare explicitement dans le GeoTIFF.
  info <- paste(terra::describe(out), collapse = "\n")
  expect_match(info, "NoData Value=255")
  # Lu comme NA par terra, et uniquement sur la zone NA.
  v <- terra::values(r)[, 1]
  expect_identical(is.na(v), is.na(fl))
  # Octet brut = 255 sur la zone NA (lecture sans masque nodata).
  sans_nodata <- file.path(d, "sans_nodata.tif")
  sf::gdal_utils("translate", out, sans_nodata, options = c("-a_nodata", "none"), quiet = TRUE)
  brut <- terra::values(terra::rast(sans_nodata))[, 1]
  expect_true(all(brut[is.na(fl)] == 255))
})

test_that("vat_combined(as_byte = TRUE) reste fidele au plugin : 0..255, NA -> 255", {
  d <- withr::local_tempdir()
  m <- .mnt_053(d, na_zone = TRUE)
  b <- terra::values(vat_combined(m$mnt, as_byte = TRUE))[, 1]
  fl <- terra::values(vat_combined(m$mnt, as_byte = FALSE))[, 1]
  expect_identical(as.integer(b), .rvt_byte_scale01(fl))
  expect_true(all(b[is.na(fl)] == 255))
  expect_true(any(b[!is.na(fl)] == 255)) # le relief maximal garde 255 cote RVT
})

test_that("cvat precalcule : les autres valeurs (0..254) egalent vat_combined(as_byte = TRUE)", {
  d <- withr::local_tempdir()
  m <- .mnt_053(d, na_zone = TRUE)
  out <- .construire_053(d, m$path)
  v <- terra::values(terra::rast(out))[, 1]
  b <- terra::values(vat_combined(m$mnt, as_byte = TRUE))[, 1]
  fl <- terra::values(vat_combined(m$mnt, as_byte = FALSE))[, 1]
  # Meme grille : le fichier couvre AOI+buffer = tout le MNT (40 x 40) ici ?
  ok <- !is.na(fl) & b < 255L
  expect_true(any(ok))
  expect_identical(as.integer(v[ok]), as.integer(b[ok]))
})
