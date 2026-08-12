# Le diagnostic d'integrite DEGRADE quand `dessertR`/`igraph` manquent. La
# degradation est voulue -- l'objet garde sa forme, les appelants ne cassent pas
# -- mais elle ne doit pas etre SILENCIEUSE : un `resume` tout en `NA` rendu dans
# une interface se lit comme « aucune infraction », c'est-a-dire l'inverse de ce
# qu'il dit. Signale par le brief nemetonshiny du 2026-08-12 (A.2), qui avait du
# poser son propre `requireNamespace()` pour afficher « non controlee ».

desserte_jouet <- function() {
  seg <- function(a, b) sf::st_linestring(rbind(a, b))
  sf::st_sf(
    classe = c("piste", "reseau_public"),
    geometry = sf::st_sfc(seg(c(0, 0), c(100, 0)), seg(c(200, 0), c(300, 0)),
                          crs = 2154)
  )
}

test_that("dessertR_disponible() repond sans lancer de calcul", {
  d <- dessertR_disponible()
  expect_type(d, "logical")
  expect_length(d, 1L)
  expect_false(is.na(d))
  # Le predicat public et la sonde interne disent la meme chose.
  expect_identical(d, foretaccess:::.dessertr_dispo())
})

test_that("le diagnostic vide se DECLARE non effectue", {
  vide <- foretaccess:::.integrite_vide(desserte_jouet(), "raison de test")
  expect_false(vide$disponible)
  expect_identical(vide$raison, "raison de test")
  # `n_infractions` reste NA : c'est « on ne sait pas », et le champ
  # `disponible` est ce qui permet de le distinguer d'un zero.
  expect_true(is.na(vide$resume[["n_infractions"]]))
})

test_that("print() dit NON EFFECTUE au lieu d'omettre la ligne", {
  # Le defaut d'origine : `print()` sautait simplement la ligne « Infractions »
  # quand elle valait NA, et le lecteur voyait un rapport d'apparence normale.
  vide <- foretaccess:::.integrite_vide(desserte_jouet(), "paquet absent : dessertR")
  sortie <- paste(capture.output(print(vide), type = "message"),
                  capture.output(print(vide)), collapse = " ")
  expect_match(sortie, "NON EFFECTUE")
  expect_match(sortie, "on ne sait pas")
})

test_that("un diagnostic REELLEMENT effectue se declare disponible", {
  skip_if_not(dessertR_disponible(), "dessertR absent")
  skip_if_not_installed("igraph")
  res <- suppressWarnings(verifier_integrite_desserte(desserte_jouet()))
  # Soit il a abouti (disponible), soit dsr_reseau a echoue sur cette couche
  # degeneree -- et alors il doit le DIRE, pas rendre un vide muet.
  expect_type(res$disponible, "logical")
  if (isFALSE(res$disponible)) {
    expect_false(is.na(res$raison))
  }
})

test_that("l'indisponibilite AVERTIT, elle n'informe pas", {
  # Un `cli_inform` se perd dans le log d'un worker ; un warning se capture.
  # On simule l'absence en interrogeant le chemin qui la detecte.
  if (dessertR_disponible() && requireNamespace("igraph", quietly = TRUE)) {
    skip("dessertR et igraph presents : chemin d'indisponibilite non atteignable")
  }
  expect_warning(verifier_integrite_desserte(desserte_jouet()), "NON CONTROLEE")
})
