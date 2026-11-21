# Une couche amputee d'une tuile WFS ne doit PAS etre mise en cache : resservie
# au run suivant, elle resterait incomplete sans plus aucun avertissement (brief
# nemetonshiny 2026-11-21). Le prochain appel doit retenter l'IGN.

# AOI de 4 km x 2 km : deux tuiles WFS de 2 km.
aoi_2_tuiles <- function() {
  sf::st_sf(id = 1, geometry = sf::st_as_sfc(sf::st_bbox(
    c(xmin = 700000, ymin = 6600000, xmax = 704000, ymax = 6602000), crs = 2154)))
}

# Simule `.get_wfs_retente` : un troncon par tuile ; la tuile OUEST echoue tant
# que `env$panne` est vrai. Compte les requetes.
mock_retente <- function(env) {
  function(x, layer, ...) {
    env$requetes <- env$requetes + 1L
    bb <- sf::st_bbox(x)
    ouest <- bb[["xmin"]] < 701000
    if (ouest && isTRUE(env$panne)) {
      stop("Unexpected content type \"text/plain\"")
    }
    cx <- if (ouest) 701000 else 703000
    sf::st_sf(cleabs = if (ouest) "O" else "E", nature = "Chemin",
      geometry = sf::st_sfc(sf::st_linestring(rbind(
        c(cx - 200, 6601000), c(cx + 200, 6601000))), crs = 2154))
  }
}

test_that("acquire_desserte : couche a tuile perdue non mise en cache, retentee ensuite", {
  withr::local_options(foretaccess.wfs_pause = 0)
  testthat::local_mocked_bindings(.require_pkg = function(...) TRUE)
  env <- new.env()
  env$requetes <- 0L
  env$panne <- TRUE
  testthat::local_mocked_bindings(.get_wfs_retente = mock_retente(env))
  withr::with_tempdir({
    chemin <- file.path("cache", "layers", "desserte", "desserte.gpkg")

    # 1er appel : la tuile ouest est perdue -> alerte classee, couche partielle,
    # aucun cache.
    expect_warning(
      d1 <- suppressMessages(acquire_desserte(aoi_2_tuiles(), cache_dir = "cache",
                                              classification = "heuristique")),
      class = "foretaccess_tuiles_perdues"
    )
    expect_equal(nrow(d1), 1L)
    expect_false(file.exists(chemin))

    # 2e appel, IGN retabli : on RETENTE (pas de cache), couche complete, cachee.
    env$panne <- FALSE
    avant <- env$requetes
    expect_no_warning(d2 <- suppressMessages(acquire_desserte(aoi_2_tuiles(),
      cache_dir = "cache", classification = "heuristique")))
    expect_gt(env$requetes, avant)
    expect_equal(nrow(d2), 2L)
    expect_true(file.exists(chemin))

    # 3e appel : servie depuis le cache, sans requete.
    avant <- env$requetes
    d3 <- suppressMessages(acquire_desserte(aoi_2_tuiles(), cache_dir = "cache",
                                            classification = "heuristique"))
    expect_identical(env$requetes, avant)
    expect_equal(nrow(d3), 2L)
  })
})

test_that("une perte retire le cache anterieur (overwrite), meme sous politique 'ignorer'", {
  withr::local_options(foretaccess.wfs_pause = 0)
  testthat::local_mocked_bindings(.require_pkg = function(...) TRUE)
  env <- new.env()
  env$requetes <- 0L
  env$panne <- FALSE
  testthat::local_mocked_bindings(.get_wfs_retente = mock_retente(env))
  withr::with_tempdir({
    chemin <- file.path("cache", "layers", "desserte", "desserte.gpkg")
    suppressMessages(acquire_desserte(aoi_2_tuiles(), cache_dir = "cache",
                                      classification = "heuristique"))
    expect_true(file.exists(chemin))

    env$panne <- TRUE
    suppressMessages(suppressWarnings(acquire_desserte(aoi_2_tuiles(),
      cache_dir = "cache", classification = "heuristique", overwrite = TRUE)))
    expect_false(file.exists(chemin))
    expect_false(file.exists(paste0(chemin, ".provenance.json")))

    # Sous « ignorer », un fichier present serait servi tel quel : il n'y en a plus.
    env$panne <- FALSE
    avant <- env$requetes
    d <- suppressMessages(acquire_desserte(aoi_2_tuiles(), cache_dir = "cache",
      classification = "heuristique", politique_cache = "ignorer"))
    expect_gt(env$requetes, avant)
    expect_equal(nrow(d), 2L)
  })
})

test_that("foret, cadastre et obstacles BD TOPO suivent la meme regle", {
  # .fetch_wfs simule qui emet l'alerte classee puis rend une couche partielle.
  perte <- TRUE
  testthat::local_mocked_bindings(.fetch_wfs = function(aoi, typename, ...) {
    if (perte) {
      cli::cli_warn("1 tuile WFS sur 2 en echec pour {.val {typename}}.",
                    class = "foretaccess_tuiles_perdues")
    }
    polys_fixture()
  })
  withr::with_tempdir({
    suppressMessages(suppressWarnings({
      acquire_foret(aoi_test(), cache_dir = "cache")
      acquire_cadastre(aoi_test(), cache_dir = "cache")
      acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cache", zonages = FALSE)
    }))
    for (couche in c("foret", "cadastre", "obstacles_bdtopo")) {
      expect_false(file.exists(file.path("cache", "layers", couche,
                                         paste0(couche, ".gpkg"))), label = couche)
    }
    perte <- FALSE
    suppressMessages({
      acquire_foret(aoi_test(), cache_dir = "cache")
      acquire_cadastre(aoi_test(), cache_dir = "cache")
      acquire_obstacles_bdtopo(aoi_test(), cache_dir = "cache", zonages = FALSE)
    })
    for (couche in c("foret", "cadastre", "obstacles_bdtopo")) {
      expect_true(file.exists(file.path("cache", "layers", couche,
                                        paste0(couche, ".gpkg"))), label = couche)
    }
  })
})

test_that("toutes les tuiles en echec mais emprise entiere rattrapee : pas de fausse alarme", {
  # Relecture nemetonshiny 2026-11-21 : l'alerte partait AVANT la reprise sur
  # l'emprise entiere ; si celle-ci passe, la couche n'est pas amputee.
  withr::local_options(foretaccess.wfs_pause = 0)
  testthat::local_mocked_bindings(.require_pkg = function(...) TRUE)
  emprise_ok <- TRUE
  testthat::local_mocked_bindings(.get_wfs_retente = function(x, layer, ...) {
    bb <- sf::st_bbox(x)
    entiere <- (bb[["xmax"]] - bb[["xmin"]]) > 3000
    if (!entiere || !emprise_ok) stop("Unexpected content type \"text/plain\"")
    sf::st_sf(cleabs = "TOUT", nature = "Chemin", geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(701000, 6601000), c(703000, 6601000))), crs = 2154))
  })
  withr::with_tempdir({
    expect_no_warning(d <- suppressMessages(acquire_desserte(aoi_2_tuiles(),
      cache_dir = "cache", classification = "heuristique")))
    expect_equal(nrow(d), 1L)
    expect_true(file.exists(file.path("cache", "layers", "desserte", "desserte.gpkg")))

    # Emprise entiere en echec elle aussi : l'erreur remonte, sans alerte.
    emprise_ok <- FALSE
    expect_error(suppressMessages(acquire_desserte(aoi_2_tuiles(), cache_dir = "cache",
      classification = "heuristique", overwrite = TRUE)), "text/plain")
  })
})
