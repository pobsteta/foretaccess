# Source du reseau DFCI (flag CL_DFCI) : Voie A (OSM ref:FR:DFCI) + repli
# geometrique (spec 006 / spec 010 §10.2). Reseau mocke via .fetch_osm.

# --- Voie A : acquisition OSM ------------------------------------------------

test_that("acquire_dfci recupere les pistes DFCI OSM (ref:FR:DFCI)", {
  withr::with_tempdir({
    # Depuis l'ADR-010, les TROIS cles de reference DFCI partent en UNE seule
    # requete (union de filtres Overpass) : le mock recoit donc une LISTE de
    # filtres, non plus une cle par appel. Overpass plafonne le nombre de
    # requetes, pas la surface -- c'est le gain 3 -> 1 du brief.
    appels <- 0L
    testthat::local_mocked_bindings(.fetch_osm = function(bbox_wgs, key, value = NULL) {
      appels <<- appels + 1L
      cles <- if (is.list(key)) vapply(key, function(f) f$cle, character(1)) else key
      if ("ref:FR:DFCI" %in% cles) {
        osmdata_dfci_fixture()
      } else {
        list(osm_points = NULL, osm_lines = NULL, osm_polygons = NULL, osm_multipolygons = NULL)
      }
    })
    d <- acquire_dfci(aoi_test(), cache_dir = "cache")

    # CA-8.2 du brief : 3 requetes -> 1.
    expect_equal(appels, 1L)
    expect_s3_class(d, "sf")
    expect_gt(nrow(d), 0)
    expect_true("ref" %in% names(d))
    expect_true(any(d$ref == "AL 04"))
    expect_equal(sf::st_crs(d), sf::st_crs(2154))
    expect_true(file.exists(file.path("cache", "layers", "dfci", "dfci.gpkg")))
  })
})

test_that("acquire_dfci -> sf vide quand OSM ne rend aucune piste DFCI", {
  withr::with_tempdir({
    testthat::local_mocked_bindings(.fetch_osm = function(bbox_wgs, key, value = NULL) {
      list(osm_points = NULL, osm_lines = NULL, osm_polygons = NULL, osm_multipolygons = NULL)
    })
    d <- acquire_dfci(aoi_test(), cache_dir = "cache")
    expect_s3_class(d, "sf")
    expect_equal(nrow(d), 0)
    expect_equal(sf::st_crs(d), sf::st_crs(2154))
  })
})

# --- Voie A : appariement desserte <-> reseau OSM ----------------------------

test_that("flag_dfci (Voie A) marque le troncon coincidant, pas les autres", {
  d <- sf::st_sf(
    classe = c("route", "piste"),
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(0, 0), c(100, 0))),   # troncon aligne sur la DFCI
      sf::st_linestring(rbind(c(0, 50), c(100, 50))), # troncon a 50 m (hors tolerance)
      crs = 2154
    )
  )
  dfci <- sf::st_sf(ref = "AL 04",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(0, 2), c(100, 2))), crs = 2154))

  out <- flag_dfci(d, dfci_lignes = dfci, tol_appariement_m = 10)
  expect_equal(out$dfci, c(1L, 0L))
})

# --- Voie B : repli geometrique ---------------------------------------------

test_that(".degres_extremites compte les raccordements aux noeuds", {
  d <- desserte_repli_fixture()
  deg <- .degres_extremites(d)
  expect_equal(deg$deg_debut, c(1L, 2L, 2L))
  expect_equal(deg$deg_fin,   c(2L, 2L, 1L))
})

test_that("flag_dfci (repli) retient la piste traversante d'emprise suffisante", {
  d <- desserte_repli_fixture(largeur2 = 12)
  # piste2 : traversante + 12 m >= 10 -> retenue (branche a)
  # piste3 : cul-de-sac (P4) + retournement en P4 -> retenue (branche b)
  # piste1 : cul-de-sac (P1) sans retournement -> non
  out <- flag_dfci(d, dfci_lignes = NULL, retournements = retournement_p4_fixture())
  expect_equal(out$dfci, c(0L, 1L, 1L))
})

test_that("flag_dfci (repli) : piste traversante trop etroite non retenue", {
  d <- desserte_repli_fixture(largeur2 = 3)
  out <- flag_dfci(d, dfci_lignes = NULL, retournements = NULL)
  expect_equal(out$dfci, c(0L, 0L, 0L))
})

test_that("flag_dfci (repli) : cul-de-sac retenu seulement avec aire de retournement", {
  d <- desserte_repli_fixture(largeur2 = 3) # piste2 trop etroite -> branche a inactive
  avec <- flag_dfci(d, dfci_lignes = NULL, retournements = retournement_p4_fixture())
  expect_equal(avec$dfci, c(0L, 0L, 1L))    # seule piste3 (bout P4 = retournement)
  sans <- flag_dfci(d, dfci_lignes = NULL, retournements = NULL)
  expect_equal(sans$dfci, c(0L, 0L, 0L))
})

# --- Chaine complete : flag -> masque source du moteur DFCI ------------------

test_that("un troncon flagge DFCI produit un masque source non nul", {
  d <- sf::st_sf(classe = "route", dfci = 1L,
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(700200, 6600500), c(700800, 6600500))), crs = 2154))
  mnt <- terra::rast(terra::ext(700000, 701000, 6600000, 6601000),
    resolution = 50, crs = "EPSG:2154")
  terra::values(mnt) <- 1

  m <- .rasteriser_dfci_source(d, mnt)
  expect_gt(sum(terra::values(m, mat = FALSE)), 0)
})
