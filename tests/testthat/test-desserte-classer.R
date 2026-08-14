# Classement des lineaires detectes (spec 030 sec. 4). `dessertR` est une
# dependance OPTIONNELLE absente en CI : le test exerce le REPLI, dont tout
# l'interet est qu'il soit VISIBLE -- c'est la dette que ce wrapper solde
# (l'app appelait `dsr_classer()` derriere un `tryCatch(NULL)` muet).

.traces_test <- function() {
  sf::st_sf(id = 1:2, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(0, 0), c(100, 0))),
    sf::st_linestring(rbind(c(0, 20), c(100, 20))), crs = 2154))
}

test_that("sans dessertR : colonnes presentes a NA, AVERTISSEMENT, pas d'erreur", {
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  expect_warning(cl <- classer_desserte(.traces_test()), "NON CLASSES")
  expect_s3_class(cl, "sf")
  expect_identical(nrow(cl), 2L)
  expect_true(all(c("CLASSE", "CLASSE_CONF", "CLASSE_MOTIF", "OSM_TAGS") %in% names(cl)))
  expect_true(all(is.na(cl$CLASSE)))
  expect_false(attr(cl, "disponible"))
  # Les attributs d'entree survivent : l'appelant retrouve ses identifiants.
  expect_identical(cl$id, 1:2)
})

test_that("l'indisponibilite ne se lit pas comme un resultat", {
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  # Un `NA` de classe signifie NON CLASSE. Le contrat qui le porte est
  # l'attribut, pas l'absence de colonne : une colonne absente casse l'appelant,
  # une colonne pleine de NA sans attribut se lit comme "rien trouve".
  cl <- suppressWarnings(classer_desserte(.traces_test()))
  expect_identical(attr(cl, "disponible"), FALSE)
})

test_that("une couche vide est une erreur, pas un classement vide", {
  vide <- .traces_test()[0, ]
  expect_error(classer_desserte(vide), "vide")
})

test_that("un MULTILINESTRING est accepte (recast interne)", {
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  multi <- sf::st_sf(geometry = sf::st_sfc(
    sf::st_multilinestring(list(rbind(c(0, 0), c(50, 0)))), crs = 2154))
  expect_warning(cl <- classer_desserte(multi), "NON CLASSES")
  expect_identical(nrow(cl), 1L)
})

test_that("sous_type_parcelle n'accepte que les deux sous-types OSM", {
  testthat::local_mocked_bindings(.dessertr_dispo = function() FALSE)
  expect_error(
    classer_desserte(.traces_test(), sous_type_parcelle = "cadastre"),
    "arg"
  )
})
