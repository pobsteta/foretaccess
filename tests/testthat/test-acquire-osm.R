# Acquisition OSM (mockee, hors-ligne) : assemblage des obstacles (spec 010 §4, Q3).

test_that("acquire_obstacles assemble batiments et lignes avec un champ type", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_osm = function(bbox_wgs, key, value = NULL) {
      # Ne renvoie des geometries que pour la 1ere requete (building), vide sinon.
      if (identical(key, "building")) {
        osmdata_fixture()
      } else {
        list(osm_points = NULL, osm_lines = NULL, osm_polygons = NULL, osm_multipolygons = NULL)
      }
    })
    obs <- acquire_obstacles(aoi_test(), cache_dir = "cache")

    expect_s3_class(obs, "sf")
    expect_true("type" %in% names(obs))
    expect_gt(nrow(obs), 0)
    expect_true(all(obs$type == "building"))
    expect_equal(sf::st_crs(obs), sf::st_crs(2154))
    expect_true(file.exists(file.path("cache", "layers", "obstacles", "obstacles.gpkg")))
  })
})

test_that("aucun obstacle trouve -> sf vide valide", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_osm = function(bbox_wgs, key, value = NULL) {
      list(osm_points = NULL, osm_lines = NULL, osm_polygons = NULL, osm_multipolygons = NULL)
    })
    obs <- acquire_obstacles(aoi_test(), features = "building", cache_dir = "cache")
    expect_s3_class(obs, "sf")
    expect_equal(nrow(obs), 0)
    expect_equal(sf::st_crs(obs), sf::st_crs(2154))
  })
})

test_that("le jeu d'obstacles est configurable", {
  withr::with_tempdir({
    vus <- character(0)
    testthat::local_mocked_bindings(.fetch_osm = function(bbox_wgs, key, value = NULL) {
      vus <<- c(vus, key)
      list(osm_points = NULL, osm_lines = NULL, osm_polygons = NULL, osm_multipolygons = NULL)
    })
    acquire_obstacles(aoi_test(), features = "railway", cache_dir = "cache")
    expect_true("railway" %in% vus)
    expect_false("building" %in% vus)
  })
})

test_that(".acquire_retournements met en cache, y compris un resultat VIDE", {
  # Sans cache, cette fonction re-interrogeait Overpass a CHAQUE execution des
  # que le DFCI etait vide -- le cas courant -- jusqu'au throttling (backoff
  # 60 s a repetition). Un vide legitime doit couter une requete, pas N.
  appels <- 0L
  testthat::local_mocked_bindings(.fetch_osm = function(...) {
    appels <<- appels + 1L
    list(osm_points = NULL)
  })
  aoi <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 0, ymin = 0, xmax = 100, ymax = 100), crs = 2154))

  withr::with_tempdir({
    r1 <- foretaccess:::.acquire_retournements(aoi, cache_dir = "cache")
    n1 <- appels
    expect_s3_class(r1, "sf")
    expect_equal(nrow(r1), 0L)
    expect_true(file.exists(file.path("cache", "layers", "retournements",
      "retournements.gpkg")))

    # Second appel : servi par le cache, aucune requete OSM supplementaire.
    r2 <- foretaccess:::.acquire_retournements(aoi, cache_dir = "cache")
    expect_identical(appels, n1)
    expect_equal(nrow(r2), 0L)

    # overwrite = TRUE re-interroge.
    foretaccess:::.acquire_retournements(aoi, cache_dir = "cache", overwrite = TRUE)
    expect_gt(appels, n1)
  })
})

test_that(".acquire_retournements sans cache_dir n'ecrit rien (retro-compat)", {
  testthat::local_mocked_bindings(.fetch_osm = function(...) list(osm_points = NULL))
  aoi <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 0, ymin = 0, xmax = 100, ymax = 100), crs = 2154))
  withr::with_tempdir({
    r <- foretaccess:::.acquire_retournements(aoi)
    expect_s3_class(r, "sf")
    expect_equal(length(list.files(".", recursive = TRUE)), 0L)
  })
})
