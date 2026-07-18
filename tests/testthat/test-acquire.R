# Orchestrateur acquire_inputs (mocke, hors-ligne) : dispatch, CRS strict,
# buffer, enchainement vers preprocess (spec 010 §4-§5, CA-A.1/A.4/A.5).

test_that("acquire_inputs dispatche vers les sources demandees", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(
      acquire_mnt = function(aoi, ...) "mnt.tif",
      acquire_desserte = function(aoi, ...) roads_fixture(),
      acquire_foret = function(aoi, ...) polys_fixture(),
      acquire_obstacles = function(aoi, ...) polys_fixture(),
      acquire_cadastre = function(aoi, ...) polys_fixture(),
      acquire_dfci = function(aoi, ...) sf::st_sf(ref = character(0), geometry = sf::st_sfc(crs = 2154)),
      .acquire_retournements = function(aoi, ...) sf::st_sf(geometry = sf::st_sfc(crs = 2154))
    )
    inp <- acquire_inputs(aoi_test(), cache_dir = "cache")
    expect_s3_class(inp, "foretaccess_inputs")
    expect_equal(inp$mnt, "mnt.tif")
    expect_s3_class(inp$desserte, "sf")
    expect_s3_class(inp$parcellaire, "sf")
    expect_equal(inp$meta$crs, 2154)
    expect_equal(inp$meta$buffer_m, 100)
  })
})

test_that("un sous-ensemble de sources ne declenche que celles-la", {
  withr::with_tempdir({
    appelees <- character(0)
    testthat::local_mocked_bindings(
      acquire_mnt = function(aoi, ...) {
        appelees <<- c(appelees, "mnt")
        "mnt.tif"
      },
      acquire_cadastre = function(aoi, ...) {
        appelees <<- c(appelees, "cadastre")
        polys_fixture()
      }
    )
    inp <- acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "cache")
    expect_equal(appelees, "mnt")
    expect_null(inp$desserte)
    expect_null(inp$parcellaire)
  })
})

test_that("une AOI sans CRS est refusee (regle stricte)", {
  aoi_nocrs <- sf::st_set_crs(aoi_test(), NA)
  expect_error(acquire_inputs(aoi_nocrs), regexp = "CRS")
})

test_that("le buffer elargit l'emprise transmise aux sources", {
  withr::with_tempdir({
    aires <- numeric(0)
    testthat::local_mocked_bindings(
      acquire_mnt = function(aoi, ...) {
        aires <<- c(aires, as.numeric(sf::st_area(aoi)))
        "mnt.tif"
      }
    )
    acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c0", buffer_m = 0)
    acquire_inputs(aoi_test(), sources = "mnt", cache_dir = "c1", buffer_m = 100)
    expect_gt(aires[2], aires[1]) # bufferisee > stricte
  })
})

test_that("les sorties s'enchainent vers preprocess (CA-A.4)", {
  withr::with_tempdir({
    toy <- system.file("extdata", "toy", package = "foretaccess")
    testthat::local_mocked_bindings(
      acquire_mnt = function(aoi, ...) file.path(toy, "mnt.tif"),
      acquire_desserte = function(aoi, ...) sf::st_read(file.path(toy, "desserte.gpkg"), quiet = TRUE),
      acquire_foret = function(aoi, ...) sf::st_read(file.path(toy, "foret.gpkg"), quiet = TRUE),
      acquire_obstacles = function(aoi, ...) polys_fixture(),
      acquire_cadastre = function(aoi, ...) NULL,
      acquire_dfci = function(aoi, ...) sf::st_sf(ref = character(0), geometry = sf::st_sfc(crs = 2154)),
      .acquire_retournements = function(aoi, ...) sf::st_sf(geometry = sf::st_sfc(crs = 2154))
    )
    inp <- acquire_inputs(aoi_test(), cache_dir = "cache")
    pre <- preprocess(inp$mnt, inp$desserte, inp$foret)
    expect_s3_class(pre, "foretaccess_preprocessing")
  })
})

test_that("print.foretaccess_inputs resume l'acquisition", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(
      acquire_mnt = function(aoi, ...) "mnt.tif",
      acquire_desserte = function(aoi, ...) roads_fixture(),
      acquire_foret = function(aoi, ...) polys_fixture(),
      acquire_obstacles = function(aoi, ...) polys_fixture(),
      acquire_cadastre = function(aoi, ...) polys_fixture(),
      acquire_dfci = function(aoi, ...) sf::st_sf(ref = character(0), geometry = sf::st_sfc(crs = 2154)),
      .acquire_retournements = function(aoi, ...) sf::st_sf(geometry = sf::st_sfc(crs = 2154))
    )
    inp <- acquire_inputs(aoi_test(), cache_dir = "cache")
    expect_message(print(inp), regexp = "Entrees ForetAccess")
  })
})

test_that("acquire_inputs pose le flag dfci depuis le reseau OSM", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(
      acquire_mnt = function(aoi, ...) "mnt.tif",
      acquire_desserte = function(aoi, ...) sf::st_sf(
        classe = "route",
        geometry = sf::st_sfc(
          sf::st_linestring(rbind(c(700200, 6600500), c(700800, 6600500))), crs = 2154)),
      acquire_foret = function(aoi, ...) polys_fixture(),
      acquire_obstacles = function(aoi, ...) polys_fixture(),
      acquire_cadastre = function(aoi, ...) NULL,
      # Reseau DFCI OSM a 2 m du troncon -> flag pose (Voie A, appariement tampon).
      acquire_dfci = function(aoi, ...) sf::st_sf(ref = "AL 04",
        geometry = sf::st_sfc(
          sf::st_linestring(rbind(c(700200, 6600502), c(700800, 6600502))), crs = 2154))
    )
    inp <- acquire_inputs(aoi_test(), cache_dir = "cache")
    expect_true("dfci" %in% names(inp$desserte))
    expect_equal(sum(inp$desserte$dfci), 1L)
  })
})
