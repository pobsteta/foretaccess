# Acquisition IGN (mockee, hors-ligne) : mapping classe, reproj/clip, cache
# (spec 010 §4, CA-A.2/A.6).

test_that("le mapping de classe derive route/piste depuis la nature BD TOPO", {
  d <- roads_fixture()
  cl <- .mapper_classe_desserte(d) # defaut clsvac
  expect_equal(cl, c("route", "piste")) # "Route a 1 chaussee" -> route ; "Chemin" -> piste
})

# Jeu couvrant les cas discriminants entre les deux classifications.
roads_clsvac_fixture <- function() {
  seg <- function(o) sf::st_linestring(rbind(c(700200 + o, 6600200), c(700800 + o, 6600800)))
  sf::st_sf(
    nature = c("Chemin", "Sentier", "Route empierrée", "Route à 1 chaussée",
               "Type autoroutier"),
    importance = c(5L, 6L, 5L, 4L, 2L),
    geometry = sf::st_sfc(seg(0), seg(10), seg(20), seg(30), seg(40), crs = 2154)
  )
}

test_that("classification CL_SVAC : la route empierree devient route (terminus), pas piste", {
  cl <- .mapper_classe_desserte(roads_clsvac_fixture(), "clsvac")
  # Chemin/Sentier -> piste ; Route empierree + Route a 1 chaussee -> route ;
  # Type autoroutier (importance 2) -> reseau public (barriere).
  expect_equal(cl, c("piste", "piste", "route", "route", "reseau_public"))
})

test_that("classification heuristique : retro-compat bit-pour-bit (empierree -> piste)", {
  cl <- .mapper_classe_desserte(roads_clsvac_fixture(), "heuristique")
  # L'ancien mapping range la Route empierree en PISTE (le bug corrige par clsvac).
  expect_equal(cl, c("piste", "piste", "piste", "route", "route"))
})

test_that("acquire_desserte reprojette, decoupe et pose le champ classe", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = function(aoi, typename) roads_fixture())
    d <- acquire_desserte(aoi_test(), cache_dir = "cache")

    expect_s3_class(d, "sf")
    expect_true("classe" %in% names(d))
    expect_true(all(d$classe %in% c("route", "piste", "dfci")))
    expect_equal(sf::st_crs(d), sf::st_crs(2154))
    # Cache ecrit.
    expect_true(file.exists(file.path("cache", "layers", "desserte", "desserte.gpkg")))
  })
})

test_that("acquire_mnt ecrit un raster en cache et est idempotent (CA-A.6)", {
  withr::with_tempdir({
    appels <- 0L
    testthat::local_mocked_bindings(.fetch_wms_raster = function(aoi, layer, res, crs, filename) {
      appels <<- appels + 1L
      mnt_fixture_writer(aoi, layer, res, crs, filename)
    })
    p1 <- acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache")
    expect_true(file.exists(p1))
    expect_equal(appels, 1L)

    # 2e appel : servi du cache, aucun nouvel appel reseau.
    p2 <- acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache")
    expect_equal(p2, p1)
    expect_equal(appels, 1L)

    # overwrite force un nouvel appel.
    acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache", overwrite = TRUE)
    expect_equal(appels, 2L)
  })
})

test_that("acquire_mnt bascule sur une couche de repli si la principale est vide", {
  withr::with_tempdir({
    principale <- "IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93"
    couches <- character(0)
    testthat::local_mocked_bindings(.fetch_wms_raster = function(aoi, layer, res, crs, filename) {
      couches <<- c(couches, layer)
      r <- terra::rast(terra::ext(terra::vect(aoi)), resolution = res, crs = paste0("EPSG:", crs))
      # La couche principale (LIDAR HD) n'a pas de donnee ici -> tout NA.
      terra::values(r) <- if (identical(layer, principale)) NA_real_ else seq_len(terra::ncell(r))
      terra::writeRaster(r, filename, overwrite = TRUE)
      r
    })
    p <- acquire_mnt(aoi_test(), res_m = 50, cache_dir = "cache")
    expect_true(file.exists(p))
    # La principale a ete tentee puis abandonnee au profit du 1er repli.
    expect_equal(couches[1], principale)
    expect_gte(length(couches), 2L)
    # Le MNT rendu est celui du repli (valeurs finies).
    expect_true(any(is.finite(terra::values(terra::rast(p), mat = FALSE))))
  })
})

test_that("acquire_mnt telecharge le LIDAR HD fin puis l'agrege a res_m", {
  withr::with_tempdir({
    res_vues <- numeric(0)
    testthat::local_mocked_bindings(.fetch_wms_raster = function(aoi, layer, res, crs, filename) {
      res_vues <<- c(res_vues, res)
      mnt_fixture_writer(aoi, layer, res, crs, filename)
    })
    p <- acquire_mnt(aoi_test(), res_m = 5, res_lidar_m = 1, cache_dir = "cache")

    # La couche primaire est telechargee a la resolution FINE (1 m), pas 5 m.
    expect_equal(res_vues[1], 1)
    # Produit fin intermediaire conserve, a ~1 m.
    p_fin <- file.path("cache", "layers", "mnt", "lidar_mnt_aoi_buffer.tif")
    expect_true(file.exists(p_fin))
    expect_equal(terra::res(terra::rast(p_fin)), c(1, 1))
    # Base de calcul agregee a res_m = 5 m.
    expect_true(file.exists(p))
    expect_equal(terra::res(terra::rast(p)), c(5, 5))
  })
})

test_that("acquire_mnt : res_lidar_m >= res_m telecharge en direct (pas d'agregation)", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wms_raster = mnt_fixture_writer)
    p <- acquire_mnt(aoi_test(), res_m = 5, res_lidar_m = 5, cache_dir = "cache")
    expect_true(file.exists(p))
    expect_equal(terra::res(terra::rast(p)), c(5, 5))
    # Pas de produit fin ecrit quand l'agregation est desactivee.
    expect_false(file.exists(file.path("cache", "layers", "mnt", "lidar_mnt_aoi_buffer.tif")))
  })
})

test_that("acquire_foret et acquire_cadastre renvoient des polygones decoupes", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_wfs = function(aoi, typename) polys_fixture())
    f <- acquire_foret(aoi_test(), cache_dir = "cache")
    p <- acquire_cadastre(aoi_test(), cache_dir = "cache")
    expect_s3_class(f, "sf")
    expect_s3_class(p, "sf")
    expect_gt(nrow(f), 0)
    expect_equal(sf::st_crs(f), sf::st_crs(2154))
  })
})

test_that("une dependance absente leve un message d'installation cible (CA-A.5)", {
  expect_error(.require_pkg("paquet.qui.n.existe.pas"), regexp = "install.packages")
})
