# Service least-cost (spec 002 §4.1), reproduisant calcul_distance_de_cout() du
# .pyx Sylvaccess v3.6. Oracle analytique : sur une surface de cout uniforme a 1,
# le cout cumule est la distance euclidienne 8-connexe.

test_that("sur un cout uniforme, le cout cumule est la distance euclidienne (CA-2.1)", {
  prop <- propager_cout(cout_uniforme(), source_centrale())

  expect_s3_class(prop, "foretaccess_propagation")
  expect_equal(prop$cout_cumule[11, 11][[1]], 0)

  # 10 cellules a gauche : 10 pas droits.
  expect_equal(prop$cout_cumule[11, 1][[1]], 10)
  # Coin : 10 pas diagonaux.
  expect_equal(prop$cout_cumule[1, 1][[1]], 10 * sqrt(2))

  # C'est precisement ce que terra::costDist() ne fait pas : il moyenne la
  # friction des deux cellules et renverrait 9,5 (spec 002 §10.1).
  expect_false(isTRUE(all.equal(prop$cout_cumule[11, 1][[1]], 9.5)))
})

test_that("le cout est celui de la cellule d'arrivee, pas la moyenne", {
  # Une colonne de cout 3 : franchir une de ses cellules coute 3, pas (1+3)/2.
  cout <- cout_uniforme()
  cout[, 10] <- 3
  prop <- propager_cout(cout, source_centrale())

  # De (11,11) vers (11,10) : un pas droit sur une cellule de cout 3.
  expect_equal(prop$cout_cumule[11, 10][[1]], 3)
  # Puis (11,9), cellule de cout 1.
  expect_equal(prop$cout_cumule[11, 9][[1]], 4)
})

test_that("la resolution est prise en compte", {
  cout <- terra::rast(
    nrows = 21, ncols = 21, xmin = 0, xmax = 105, ymin = 0, ymax = 105,
    crs = "EPSG:2154"
  )
  terra::values(cout) <- 1
  s <- terra::rast(cout)
  s[11, 11] <- 1

  prop <- propager_cout(cout, s)
  expect_equal(prop$cout_cumule[11, 1][[1]], 10 * 5)
})

test_that("l'allocation identifie la source atteinte au moindre cout (CA-2.2)", {
  cout <- cout_uniforme()
  s <- terra::rast(grille_test())
  s[11, 3] <- 7L # source « 7 » a gauche
  s[11, 19] <- 9L # source « 9 » a droite

  prop <- propager_cout(cout, s)

  expect_equal(prop$allocation[11, 1][[1]], 7)
  expect_equal(prop$allocation[11, 21][[1]], 9)
  expect_equal(prop$allocation[11, 3][[1]], 7)
  # Les distances sont symetriques autour du milieu.
  expect_equal(prop$cout_cumule[11, 1][[1]], prop$cout_cumule[11, 21][[1]])
})

test_that("une cellule de cout NA est infranchissable (CA-2.3)", {
  cout <- cout_uniforme()
  # Mur vertical complet : la colonne 5 isole les colonnes 1 a 4.
  cout[, 5] <- NA

  prop <- propager_cout(cout, source_centrale())

  expect_true(is.na(prop$cout_cumule[11, 5][[1]]))
  expect_true(is.na(prop$cout_cumule[11, 1][[1]]))
  expect_true(is.na(prop$allocation[11, 1][[1]]))
  # De ce cote du mur, tout reste atteint.
  expect_false(is.na(prop$cout_cumule[11, 6][[1]]))
})

test_that("zone restreint les cellules traversables", {
  cout <- cout_uniforme()
  zone <- terra::rast(grille_test())
  terra::values(zone) <- 1
  zone[, 5] <- 0

  prop <- propager_cout(cout, source_centrale(), zone = zone)
  expect_true(is.na(prop$cout_cumule[11, 1][[1]]))
})

test_that("cout_max tronque la propagation exactement au seuil (CA-2.1)", {
  prop <- propager_cout(cout_uniforme(), source_centrale(), cout_max = 5)

  expect_equal(prop$cout_cumule[11, 6][[1]], 5) # exactement au seuil : conserve
  expect_true(is.na(prop$cout_cumule[11, 5][[1]])) # au-dela : NA
})

test_that("les entrees invalides levent une erreur ciblee", {
  vide <- terra::rast(grille_test())
  terra::values(vide) <- NA_real_
  expect_error(propager_cout(cout_uniforme(), vide), regexp = "aucune cellule source")

  expect_error(propager_cout(cout_uniforme(), 42), regexp = "sources")

  # Cellules non carrees.
  rect <- terra::rast(
    nrows = 10, ncols = 20, xmin = 0, xmax = 20, ymin = 0, ymax = 5,
    crs = "EPSG:2154"
  )
  terra::values(rect) <- 1
  s <- terra::rast(rect)
  s[5, 5] <- 1
  expect_error(propager_cout(rect, s), regexp = "carrees")
})

test_that("les sources peuvent etre fournies en sf", {
  ligne <- sf::st_sf(
    id = 1L,
    geometry = sf::st_sfc(
      sf::st_linestring(rbind(c(0.5, 10.5), c(20.5, 10.5))),
      crs = 2154
    )
  )
  prop <- propager_cout(cout_uniforme(), ligne)
  expect_equal(prop$cout_cumule[11, 11][[1]], 0)
  expect_false(is.na(prop$cout_cumule[1, 11][[1]]))
})

test_that("print.foretaccess_propagation resume la propagation", {
  prop <- propager_cout(cout_uniforme(), source_centrale())
  expect_message(print(prop), regexp = "Propagation")
})
