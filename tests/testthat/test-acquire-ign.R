# Acquisition IGN (mockee, hors-ligne) : mapping classe, reproj/clip, cache
# (spec 010 §4, CA-A.2/A.6).

test_that("le mapping de classe derive route/piste depuis la nature BD TOPO", {
  d <- roads_fixture()
  cl <- .mapper_classe_desserte(d)
  expect_equal(cl, c("route", "piste")) # "Route a 1 chaussee" -> route ; "Chemin" -> piste
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
