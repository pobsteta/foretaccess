# Reconstruction du trajet optimal (spec 002 §4.1, CA-2.4).

test_that("le trajet optimal aboutit sur la source et a la bonne longueur (CA-2.4)", {
  cout <- cout_uniforme()
  prop <- propager_cout(cout, source_centrale())

  depart <- terra::cellFromRowCol(cout, 11, 1)
  trajet <- chemin_optimal(prop, depart)

  expect_s3_class(trajet, "sf")
  expect_equal(nrow(trajet), 1L)
  expect_true(all(sf::st_is_valid(trajet)))
  expect_true(sf::st_crs(trajet) == sf::st_crs(2154))
  expect_equal(as.character(sf::st_geometry_type(trajet)), "LINESTRING")

  # Sur un cout uniforme, la longueur du trajet egale le cout cumule.
  expect_equal(as.numeric(sf::st_length(trajet)), trajet$cout, tolerance = 1e-8)
  expect_equal(trajet$cout, 10)

  # Le dernier sommet est la source.
  sommets <- sf::st_coordinates(trajet)[, c("X", "Y")]
  source_xy <- terra::xyFromCell(cout, terra::cellFromRowCol(cout, 11, 11))
  expect_equal(unname(sommets[nrow(sommets), ]), as.numeric(source_xy))
})

test_that("le trajet contourne un obstacle infranchissable", {
  cout <- cout_uniforme()
  # Mur partiel : la propagation doit le contourner.
  cout[9:13, 5] <- NA
  prop <- propager_cout(cout, source_centrale())

  depart <- terra::cellFromRowCol(cout, 11, 1)
  trajet <- chemin_optimal(prop, depart)

  expect_true(as.numeric(sf::st_length(trajet)) > 10)
  # Aucun sommet ne tombe sur une cellule du mur.
  xy <- sf::st_coordinates(trajet)[, c("X", "Y")]
  cellules <- terra::cellFromXY(cout, xy)
  expect_false(any(is.na(terra::values(cout)[cellules])))
})

test_that("plusieurs departs donnent plusieurs trajets, avec leur source", {
  cout <- cout_uniforme()
  s <- terra::rast(grille_test())
  s[11, 3] <- 7L
  s[11, 19] <- 9L
  prop <- propager_cout(cout, s)

  departs <- terra::cellFromRowCol(cout, c(11, 11), c(1, 21))
  trajets <- chemin_optimal(prop, departs)

  expect_equal(nrow(trajets), 2L)
  expect_equal(trajets$source, c(7, 9))
})

test_that("un depart sur la source elle-meme donne une ligne degeneree", {
  prop <- propager_cout(cout_uniforme(), source_centrale())
  trajet <- chemin_optimal(prop, terra::cellFromRowCol(cout_uniforme(), 11, 11))

  expect_equal(trajet$cout, 0)
  expect_equal(as.numeric(sf::st_length(trajet)), 0)
})

test_that("chemin_optimal accepte des points sf", {
  cout <- cout_uniforme()
  prop <- propager_cout(cout, source_centrale())

  pt <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(0.5, 10.5)), crs = 2154))
  trajet <- chemin_optimal(prop, pt)
  expect_equal(trajet$cout, 10)
})

test_that("les departs non atteints sont signales", {
  cout <- cout_uniforme()
  cout[, 5] <- NA
  prop <- propager_cout(cout, source_centrale())

  # Toutes non atteintes : erreur.
  expect_error(
    chemin_optimal(prop, terra::cellFromRowCol(cout, 11, 1)),
    regexp = "Aucune cellule"
  )
  # Mixte : avertissement, et seules les atteintes sont renvoyees.
  departs <- terra::cellFromRowCol(cout, c(11, 11), c(1, 8))
  expect_warning(trajets <- chemin_optimal(prop, departs), regexp = "non atteinte")
  expect_equal(nrow(trajets), 1L)
})
