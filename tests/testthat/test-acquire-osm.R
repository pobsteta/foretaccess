# Acquisition OSM (mockee, hors-ligne) : assemblage des obstacles (spec 010 §4, Q3).

test_that("acquire_obstacles assemble batiments et lignes avec un champ type", {
  withr::with_tempdir({
    # Depuis l'ADR-010, TOUS les filtres partent en UNE requete groupee : le mock
    # recoit une liste de filtres, et le type se lit ensuite sur le TAG de chaque
    # objet, plus sur la requete qui a repondu. Gain du brief : 5 -> 1.
    appels <- 0L
    testthat::local_mocked_bindings(.fetch_osm = function(bbox_wgs, key, value = NULL) {
      appels <<- appels + 1L
      osmdata_fixture()
    })
    obs <- acquire_obstacles(aoi_test(), cache_dir = "cache")

    expect_equal(appels, 1L)   # CA-8.2 : 5 requetes -> 1

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
    appels <- 0L
    testthat::local_mocked_bindings(.fetch_osm = function(bbox_wgs, key, value = NULL) {
      appels <<- appels + 1L
      vus <<- c(vus, vapply(key, function(f) f$cle, character(1)))
      list(osm_points = NULL, osm_lines = NULL, osm_polygons = NULL, osm_multipolygons = NULL)
    })
    acquire_obstacles(aoi_test(), features = "railway", cache_dir = "cache")
    # Le filtre demande part bien dans la requete, et les autres n'y sont pas :
    # regrouper ne doit pas rapatrier ce qu'on n'a pas demande.
    expect_equal(appels, 1L)
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
