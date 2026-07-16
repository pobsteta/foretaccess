# Lot 15a -- distance-de-cout inverse (heuristique A* de la conception de
# desserte). Tests d'integration du binding Rust `desserte_dist_to_end`
# (spec 015 Sec. 4.2). Le solveur A* complet (15b) et la sortie `sf` (15c) suivent.

# La grille est passee aplatie ligne par ligne ; `y_end`/`x_end` sont 0-based.
test_that("la cible vaut 0 et les voisins immediats la resolution", {
  zone <- rep(1L, 9)              # 3x3 tout franchissable
  d <- desserte_dist_to_end(zone, nr = 3L, nc = 3L, csize = 10,
                            y_end = 1L, x_end = 1L, max_distance = 1e9)
  m <- matrix(d, nrow = 3, byrow = TRUE)
  expect_equal(m[2, 2], 0)                      # cible (centre)
  expect_equal(m[1, 2], 10)                     # orthogonal
  expect_equal(m[1, 1], 10 * sqrt(2))           # diagonale
})

test_that("un mur infranchissable coupe la propagation", {
  zone <- rep(1L, 9)
  zone[c(2, 5, 8)] <- 0L          # colonne du milieu bloquee (indices 1-based R)
  d <- desserte_dist_to_end(zone, nr = 3L, nc = 3L, csize = 10,
                            y_end = 0L, x_end = 0L, max_distance = 1e9)
  m <- matrix(d, nrow = 3, byrow = TRUE)
  expect_equal(m[1, 1], 0)
  expect_true(all(is.na(m[, 3])))               # colonne de droite inatteignable
})

test_that("max_distance plafonne la propagation", {
  zone <- rep(1L, 25)
  d <- desserte_dist_to_end(zone, nr = 5L, nc = 5L, csize = 10,
                            y_end = 0L, x_end = 0L, max_distance = 15)
  m <- matrix(d, nrow = 5, byrow = TRUE)
  expect_true(is.na(m[5, 5]))                   # coin oppose (> 15 m)
  expect_false(is.na(m[1, 2]))                  # voisin proche atteint
})

test_that("l'heuristique est une borne inferieure du cout reel (admissibilite)", {
  # Sur un cout uniforme (chaque pas coute >= sa distance), la distance-de-cout
  # inverse ne surestime jamais le cout du plus court chemin : ici le cout d'un
  # pas orthogonal (surface_cout=1 EUR/m x 10 m) egale sa distance geometrique.
  zone <- rep(1L, 25)
  h <- desserte_dist_to_end(zone, nr = 5L, nc = 5L, csize = 10,
                           y_end = 4L, x_end = 4L, max_distance = 1e9)
  cout <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 50,
                      ymin = 0, ymax = 50, crs = "EPSG:2154")
  terra::values(cout) <- 1
  src <- terra::rast(cout)
  terra::values(src) <- NA
  src[5, 5] <- 1                                # meme cible (coin bas-droit)
  cc <- terra::values(propager_cout(cout, src)$cout_cumule)[, 1]
  # h <= cout cumule reel, cellule a cellule (tolerance numerique).
  ok <- is.finite(h) & is.finite(cc)
  expect_true(all(h[ok] <= cc[ok] + 1e-6))
})

test_that("le resultat est deterministe", {
  zone <- rep(1L, 16)
  a <- desserte_dist_to_end(zone, 4L, 4L, 5, 2L, 2L, 1e9)
  b <- desserte_dist_to_end(zone, 4L, 4L, 5, 2L, 2L, 1e9)
  expect_identical(a, b)
})
