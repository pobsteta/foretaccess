# Resolveur config-driven des sources de donnees (spec 010 §4, CA-A.3).

test_that("get_country_config lit le JSON FR et met en cache", {
  .clear_datasource_cache()
  cfg <- get_country_config("FR")
  expect_equal(as.integer(cfg$crs_national), 2154L)
  expect_true(!is.null(cfg$services$ign_wfs$url))
  # 2e appel : servi depuis le cache (meme objet).
  expect_identical(get_country_config("FR"), cfg)
})

test_that("get_layer_service resout couche + service (CA-A.3)", {
  dem <- get_layer_service("dem", "FR")
  expect_equal(dem$layer, "ELEVATION.ELEVATIONGRIDCOVERAGE")
  expect_equal(dem$url, "https://data.geopf.fr/wms-r/wms")
  expect_equal(as.integer(dem$resolution_m), 5L)

  roads <- get_layer_service("roads", "FR")
  expect_equal(roads$typename, "BDTOPO_V3:troncon_de_route")
  expect_match(roads$url, "wfs")

  # BD Foret v2 et cadastre presents.
  expect_match(get_layer_service("bdforet_v2", "FR")$typename, "FORESTINVENTORY.V2")
  expect_match(get_layer_service("cadastre", "FR")$typename, "PARCELLAIRE_EXPRESS")
})

test_that("une couche ou un pays inconnu est signale", {
  expect_null(get_layer_service("inexistante", "FR"))
  expect_null(get_data_source("inexistante", "FR"))
  expect_error(get_country_config("ZZ"), regexp = "Aucune configuration")
})

test_that("get_national_crs et list_countries", {
  expect_equal(get_national_crs("FR"), 2154L)
  expect_true("FR" %in% list_countries())
})

test_that("config-driven : le resolveur reflete le JSON, pas du code en dur", {
  # Le typename lu doit venir du JSON installe (aucun endpoint code en dur).
  fichier <- system.file("datasources", "FR.json", package = "foretaccess")
  expect_true(file.exists(fichier))
  brut <- jsonlite::read_json(fichier, simplifyVector = FALSE)
  expect_equal(get_layer_service("dem", "FR")$layer, brut$layers$dem$layer)
})
