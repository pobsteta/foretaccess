# Passthrough volume de acquire_inputs (spec 019) : le volume est INJECTE (jamais
# fetche), aligne sur la grille du MNT bufferise, sous trois formes -- raster, sf
# d'unites (P1), chemin -- avec les gardes CRS / grille / couverture. acquire_mnt
# est mocke (hors-ligne) : il rend un CHEMIN de raster, comme en vrai.

# MNT jouet ecrit sur disque (acquire_mnt rend un chemin).
mnt_fichier <- function() {
  r <- terra::rast(
    nrows = 20, ncols = 20, xmin = 700000, xmax = 701000,
    ymin = 6600000, ymax = 6601000, crs = "EPSG:2154"
  )
  terra::values(r) <- 100
  names(r) <- "altitude"
  f <- tempfile(fileext = ".tif")
  terra::writeRaster(r, f, overwrite = TRUE)
  f
}

# Unites P1 : deux polygones couvrant l'AOI, volume/ha dans `champ`.
unites_p1 <- function(champ = "P1", v = c(220, 380)) {
  carre <- function(x0, x1) {
    sf::st_polygon(list(rbind(
      c(x0, 6600000), c(x1, 6600000), c(x1, 6601000),
      c(x0, 6601000), c(x0, 6600000)
    )))
  }
  d <- sf::st_sf(geometry = sf::st_sfc(carre(699500, 700500), carre(700500, 701500), crs = 2154))
  d[[champ]] <- v
  d
}

test_that("sans volume, acquire_inputs est inchange (CA-19.1)", {
  f <- mnt_fichier()
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  inp <- acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c")
  expect_null(inp$volume)
  expect_true("volume" %in% names(inp)) # le slot existe, a NULL
})

test_that("un sf d'unites est rasterise via P1 sur la grille du MNT (CA-19.3)", {
  f <- mnt_fichier()
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  inp <- suppressMessages(
    acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c", volume = unites_p1())
  )
  expect_s4_class(inp$volume, "SpatRaster")
  expect_equal(names(inp$volume), "volume")
  expect_true(terra::compareGeom(inp$volume, terra::rast(f), stopOnError = FALSE))
  expect_setequal(stats::na.omit(unique(terra::values(inp$volume)[, 1])), c(220, 380))
})

test_that("champ_volume selectionne la colonne du sf", {
  f <- mnt_fichier()
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  inp <- suppressMessages(acquire_inputs(
    aoi_test(), sources = "mnt", cache_dir = "c",
    volume = unites_p1(champ = "vol_ha"), champ_volume = "vol_ha"
  ))
  expect_s4_class(inp$volume, "SpatRaster")
})

test_that("un raster deja m3/ha, meme grille, passe tel quel (CA-19.2)", {
  f <- mnt_fichier()
  vol <- terra::rast(f)
  terra::values(vol) <- 250
  names(vol) <- "P1"
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  inp <- suppressMessages(
    acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c", volume = vol)
  )
  expect_s4_class(inp$volume, "SpatRaster")
  expect_equal(names(inp$volume), "volume")
  expect_equal(unique(terra::values(inp$volume)[, 1]), 250)
})

test_that("un raster de grille differente (meme CRS) est reechantillonne + averti", {
  f <- mnt_fichier()
  grossier <- terra::rast(
    nrows = 10, ncols = 10, xmin = 700000, xmax = 701000,
    ymin = 6600000, ymax = 6601000, crs = "EPSG:2154"
  )
  terra::values(grossier) <- 300
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  expect_message(
    inp <- acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c", volume = grossier),
    "reechantillonnage"
  )
  expect_true(terra::compareGeom(inp$volume, terra::rast(f), stopOnError = FALSE))
})

test_that("un CRS different du MNT est refuse (CA-19.5, ADR-004)", {
  f <- mnt_fichier()
  autre <- terra::rast(
    nrows = 20, ncols = 20, xmin = 6, xmax = 7, ymin = 45, ymax = 46,
    crs = "EPSG:4326"
  )
  terra::values(autre) <- 200
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  expect_error(
    suppressMessages(acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c", volume = autre)),
    "CRS"
  )
})

test_that("un volume ne couvrant pas toute l'emprise avertit (CA-19.4)", {
  f <- mnt_fichier()
  demi <- terra::rast(f)
  vals <- rep(NA_real_, terra::ncell(demi))
  vals[seq_len(terra::ncell(demi) / 2)] <- 200
  terra::values(demi) <- vals
  names(demi) <- "P1"
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  expect_message(
    acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c", volume = demi),
    "n'a pas de volume"
  )
})

test_that("un volume sans MNT est une erreur actionnable", {
  # acquire_mnt echoue -> out$mnt NULL -> pas de grille cible pour le volume.
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) NULL)
  expect_error(
    suppressMessages(acquire_inputs(
      aoi_test(), sources = "mnt", cache_dir = "c", volume = unites_p1()
    )),
    "exige un MNT"
  )
})

test_that("le print liste le volume", {
  f <- mnt_fichier()
  vol <- terra::rast(f)
  terra::values(vol) <- 100
  names(vol) <- "P1"
  testthat::local_mocked_bindings(acquire_mnt = function(aoi, ...) f)
  inp <- suppressMessages(
    acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c", volume = vol)
  )
  expect_message(print(inp), "volume : raster")
})
