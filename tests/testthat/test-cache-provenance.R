# Provenance des caches (spec 027). Cinq incidents en deux jours, tous de la
# meme cause : un cache est nomme d'apres ce qu'il CONTIENT, jamais d'apres ce
# qui l'a PRODUIT, donc toute correction du code est annulee en silence pour
# quiconque possede deja un cache.

fichier_cache <- function(dir = ".") {
  f <- file.path(dir, "couche.gpkg")
  writeLines("contenu", f)
  f
}

test_that("un cache concordant est reutilise", {
  withr::with_tempdir({
    f <- fichier_cache()
    foretaccess:::.provenance_ecrire(f, "desserte", "BDTOPO_V3:troncon_de_route",
      list(classification = "accessfor", crs = 2154))
    expect_true(cache_utilisable(f, "desserte", "BDTOPO_V3:troncon_de_route",
      list(classification = "accessfor", crs = 2154)))
  })
})

test_that("LES CINQ INCIDENTS sont detectes (CA-27.4)", {
  withr::with_tempdir({
    f <- fichier_cache()

    # 1. Classification de desserte changee (heuristique -> clsvac -> accessfor).
    foretaccess:::.provenance_ecrire(f, "desserte", "roads",
      list(classification = "heuristique"))
    expect_false(suppressMessages(
      cache_utilisable(f, "desserte", "roads", list(classification = "accessfor"))))

    # 2. Filtre des landes du masque foret.
    foretaccess:::.provenance_ecrire(f, "foret", "bdforet",
      list(exclure_landes = FALSE))
    expect_false(suppressMessages(
      cache_utilisable(f, "foret", "bdforet", list(exclure_landes = TRUE))))

    # 3. MNT : la COUCHE servie differe (RGE ALTI par WMS -> LIDAR HD). C'est
    #    l'incident qui a fait tourner le banc deux semaines sur un terrain
    #    fictif, avec des pentes fausses jusqu'a 382 %.
    foretaccess:::.provenance_ecrire(f, "mnt", "ELEVATION.ELEVATIONGRIDCOVERAGE",
      list(res_m = 5))
    expect_false(suppressMessages(
      cache_utilisable(f, "mnt", "IGNF_LIDAR-HD_MNT", list(res_m = 5))))

    # 4. Tuilage WFS (acquisition tronquee avant le correctif).
    foretaccess:::.provenance_ecrire(f, "desserte", "roads", list(tuile_m = NA))
    expect_false(suppressMessages(
      cache_utilisable(f, "desserte", "roads", list(tuile_m = 2000))))

    # 5. Cache SANS provenance : anterieur a la v1.29.0. On ne peut pas savoir,
    #    donc on ne suppose pas que c'est bon.
    unlink(paste0(f, ".provenance.json"))
    expect_false(suppressMessages(cache_utilisable(f, "desserte", "roads",
      list(classification = "accessfor"))))
  })
})

test_that("la politique gouverne le comportement sur divergence", {
  withr::with_tempdir({
    f <- fichier_cache()
    foretaccess:::.provenance_ecrire(f, "desserte", "roads",
      list(classification = "heuristique"))
    att <- list(classification = "accessfor")

    expect_message(cache_utilisable(f, "desserte", "roads", att, "reacquerir"),
      "Re-acquisition")
    expect_warning(r <- cache_utilisable(f, "desserte", "roads", att, "avertir"))
    expect_true(r) # sert quand meme, mais l'a dit
    expect_error(cache_utilisable(f, "desserte", "roads", att, "echouer"),
      "parametres")
    # CA-27.5 : "ignorer" reproduit le comportement anterieur -- le cache existe
    # donc il est servi, sans aucun controle.
    expect_true(cache_utilisable(f, "desserte", "roads", att, "ignorer"))
  })
})

test_that("un cache absent n'est jamais utilisable, quelle que soit la politique", {
  withr::with_tempdir({
    for (pol in politique_cache_valeurs()) {
      expect_false(cache_utilisable("inexistant.gpkg", "x", NULL, list(), pol))
    }
  })
})

test_that("la provenance enregistre la version du paquet et la date", {
  withr::with_tempdir({
    f <- fichier_cache()
    foretaccess:::.provenance_ecrire(f, "mnt", "LIDAR", list(res_m = 5))
    p <- foretaccess:::.provenance_lire(f)
    expect_identical(p$couche, "mnt")
    expect_identical(p$source, "LIDAR")
    expect_true(nzchar(p$version_paquet))
    expect_match(p$date, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T")
  })
})

test_that("un cache ecrit A LA MAIN est re-acquis, faute de provenance", {
  # C'est le comportement VOULU depuis la spec 027, et il a casse un test
  # ecrit la veille : celui-ci fabriquait un cache sans sidecar puis attendait
  # qu'il soit servi. Un cache dont on ignore l'origine ne doit pas etre servi
  # en silence -- c'est exactement ce qui a fait tourner le banc `aoi` deux
  # semaines sur un MNT blocky du 14 juillet.
  withr::with_tempdir({
    d <- file.path("cache", "layers", "foret")
    dir.create(d, recursive = TRUE)
    geom <- sf::st_sfc(sf::st_point(c(0, 0)), crs = 2154)
    sf::st_write(sf::st_sf(code_tfv = "FF1-00", geometry = geom),
      file.path(d, "foret.gpkg"), quiet = TRUE)

    appels <- 0L
    testthat::local_mocked_bindings(.fetch_wfs = function(aoi, typename, ...) {
      appels <<- appels + 1L
      sf::st_sf(code_tfv = c("FF1-00", "LA4"), geometry = sf::st_sfc(
        sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 2154))
    })
    suppressMessages(acquire_foret(aoi_test(), cache_dir = "cache"))
    expect_identical(appels, 1L) # re-acquis malgre le cache present

    # Le second appel trouve le sidecar ecrit par le premier : plus de requete.
    suppressMessages(acquire_foret(aoi_test(), cache_dir = "cache"))
    expect_identical(appels, 1L)
  })
})
