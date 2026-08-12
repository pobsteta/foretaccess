# Integrite du reseau de desserte (spec 025). dessertR + igraph sont des
# dependances OPTIONNELLES absentes en CI : les tests exercent le REPLI (colonnes
# a NA, jamais d'echec) et la LOGIQUE PURE des contraintes, testable sans graphe.

test_that(".integrite_violations applique les deux contraintes de l'annexe p.51", {
  g <- sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)),
    sf::st_point(c(2, 2)), sf::st_point(c(3, 3)), crs = 2154)

  # Composante 1 : piste + route + reseau public -> tout est conforme.
  # Composante 2 : piste seule -> la piste viole (pas de route ni de public).
  ar <- sf::st_sf(
    classe = c("piste", "route", "reseau_public", "piste"),
    composant = c(1L, 1L, 1L, 2L), geometry = g)
  expect_identical(foretaccess:::.integrite_violations(ar),
    c(FALSE, FALSE, FALSE, TRUE))
})

test_that("une route non connectee au reseau public viole, une piste non", {
  g <- sf::st_sfc(sf::st_point(c(0, 0)), sf::st_point(c(1, 1)), crs = 2154)
  # Composante sans reseau public : la ROUTE viole (contrainte 2 -> 3), la PISTE
  # non (contrainte 1 -> 2 ou 3, et la route suffit).
  ar <- sf::st_sf(classe = c("piste", "route"), composant = c(1L, 1L),
    geometry = g)
  expect_identical(foretaccess:::.integrite_violations(ar), c(FALSE, TRUE))
})

test_that("le reseau public ne viole jamais (il EST le terminus)", {
  g <- sf::st_sfc(sf::st_point(c(0, 0)), crs = 2154)
  ar <- sf::st_sf(classe = "reseau_public", composant = 1L, geometry = g)
  expect_identical(foretaccess:::.integrite_violations(ar), FALSE)
})

test_that("sans dessertR/igraph : diagnostic vide, colonnes presentes, pas d'echec", {
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  d <- sf::st_sf(classe = c("piste", "route"),
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(0, 0), c(10, 10))),
      sf::st_linestring(rbind(c(10, 10), c(20, 20))), crs = 2154))
  # La degradation AVERTIT desormais : un `cli_inform` se perdait dans le log
  # d'un worker, et l'appelant rendait un resume tout en NA qui se lit comme
  # « aucune infraction ». C'est l'objet du brief nemetonshiny du 2026-08-12.
  expect_warning(out <- verifier_integrite_desserte(d), "NON CONTROLEE")
  expect_s3_class(out, "foretaccess_integrite")
  # CA-25.1 : degradation PROPRE -- les colonnes existent, a NA.
  expect_true(all(c("composant", "connecte_public", "viole_contrainte", "cause")
    %in% names(out$troncons)))
  expect_true(all(is.na(out$troncons$viole_contrainte)))
  expect_equal(unname(out$resume[["n_troncons"]]), 2L)
  # ... et elle se DECLARE, pour que l'appelant puisse distinguer « on ne sait
  # pas » de « rien a signaler » sans lire un message.
  expect_false(out$disponible)
  expect_match(out$raison, "dessertR")
})

test_that("verifier_integrite_desserte exige le champ classe", {
  d <- sf::st_sf(x = 1, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(0, 0), c(1, 1))), crs = 2154))
  expect_error(verifier_integrite_desserte(d), "classe")
})

test_that("isTRUE_vec neutralise les NA au lieu de les propager", {
  # `viole_contrainte` porte des NA sur les troncons non diagnostiques : les
  # sommer directement rendrait NA et ferait disparaitre la mesure.
  expect_identical(foretaccess:::isTRUE_vec(c(TRUE, NA, FALSE)),
    c(TRUE, FALSE, FALSE))
  expect_identical(sum(foretaccess:::isTRUE_vec(c(NA, NA))), 0L)
})

test_that("integrite_buffer_adaptatif mesure sur l'AOI STRICTE et converge", {
  # Le point qui fait la validite de la methode : mesuree sur l'emprise elargie,
  # la longueur en infraction augmenterait mecaniquement (plus de reseau) et la
  # suite ne convergerait jamais. Ici, un troncon en infraction LOIN de l'AOI
  # entre dans la couche quand le buffer grandit, mais ne doit PAS etre compte.
  aoi <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = 0, ymin = 0, xmax = 100, ymax = 100), crs = 2154))
  dedans <- sf::st_linestring(rbind(c(10, 10), c(90, 90)))
  loin <- sf::st_linestring(rbind(c(5000, 5000), c(5100, 5100)))

  appels <- 0L
  acq <- function(emprise) {
    appels <<- appels + 1L
    bb <- sf::st_bbox(emprise)
    geoms <- if (bb["xmax"] > 4000) list(dedans, loin) else list(dedans)
    sf::st_sf(classe = rep("piste", length(geoms)),
      geometry = sf::st_sfc(geoms, crs = 2154))
  }
  # Diagnostic mocke : tout troncon est en infraction, pour isoler le clip.
  testthat::local_mocked_bindings(
    verifier_integrite_desserte = function(desserte, ...) {
      d <- sf::st_as_sf(desserte)
      d$composant <- 1L; d$connecte_public <- FALSE
      d$viole_contrainte <- TRUE; d$cause <- "reel"
      structure(list(troncons = d, resume = c(n_troncons = nrow(d)),
        courbe = NULL), class = "foretaccess_integrite")
    })

  out <- integrite_buffer_adaptatif(aoi, acquerir = acq, buffer_initial = 100,
    buffer_max = 8000, facteur = 8, gain_min = 0)
  expect_s3_class(out, "foretaccess_integrite")
  expect_true(is.data.frame(out$courbe))
  expect_true(nrow(out$courbe) >= 2L)
  # Le troncon lointain n'est JAMAIS compte : la mesure reste sur l'AOI stricte.
  expect_true(all(out$courbe$n_infractions == 1L))
})

# --- CA-25.6 : marquage des infractions reelles, exclusion sur option ---------

desserte_diagnostiquee <- function() {
  seg <- function(a, b) sf::st_linestring(rbind(a, b))
  sf::st_sf(
    classe = c("route", "piste", "piste"),
    viole_contrainte = c(FALSE, TRUE, TRUE),
    cause = c(NA, "reel", "bord_aoi"),
    geometry = sf::st_sfc(
      seg(c(0, 0), c(100, 0)), seg(c(0, 50), c(100, 50)),
      seg(c(0, 90), c(100, 90)), crs = 2154)
  )
}

test_that("preprocess conserve les infractions PAR DEFAUT", {
  # Decision du 2026-07-29 : on ne retire pas une information terrain
  # potentiellement juste. On cesse seulement de la subir en aveugle.
  d <- desserte_diagnostiquee()
  expect_identical(nrow(foretaccess:::.ecarter_infractions_reelles(d, FALSE)), 3L)
})

test_that("ecarter_infractions ne retire QUE les infractions reelles", {
  d <- desserte_diagnostiquee()
  out <- suppressMessages(foretaccess:::.ecarter_infractions_reelles(d, TRUE))
  expect_equal(nrow(out), 2L)
  # Le troncon `bord_aoi` reste : son infraction est un artefact de decoupe,
  # pas un cul-de-sac reel. Le retirer amputerait le reseau sur la foi d'une
  # limite d'emprise arbitraire.
  expect_true("bord_aoi" %in% out$cause)
  expect_false(any(!is.na(out$cause) & out$cause == "reel"))
})

test_that("sans colonnes de diagnostic : avertissement, desserte inchangee", {
  # preprocess() ne doit pas EXIGER d'avoir ete precede du diagnostic.
  d <- sf::st_sf(classe = "piste", geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(0, 0), c(10, 10))), crs = 2154))
  expect_warning(out <- foretaccess:::.ecarter_infractions_reelles(d, TRUE),
    "sans colonnes de diagnostic")
  expect_identical(nrow(out), 1L)
})

test_that("une desserte sans aucune infraction reelle passe intacte", {
  d <- desserte_diagnostiquee()
  d$cause[d$cause %in% "reel"] <- "topologie"
  out <- foretaccess:::.ecarter_infractions_reelles(d, TRUE)
  expect_identical(nrow(out), 3L)
})
