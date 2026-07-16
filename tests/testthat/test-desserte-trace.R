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

# --- Lot 15b : solveur A* complet (`desserte_trace`) -------------------------

# Grille inclinee `slope_pct` % vers l'est (dz = slope/100 * csize par cellule).
# Sur ce plan, une route peut monter le long de x en respectant [min, max] %.
plan_incline <- function(nr, nc, slope_pct, csize = 10) {
  m <- matrix(0, nr, nc)
  for (x in seq_len(nc)) m[, x] <- (x - 1) * slope_pct / 100 * csize
  as.vector(t(m)) # ligne par ligne
}

# Paramètres SylvaRoad (défauts `SylvaRoaD_0_param.py`).
trace_args <- function(alt, nr, nc, waypoints, obs = NULL, bufgoal = 0,
                       d_neighborhood = 30, csize = 10) {
  n <- nr * nc
  if (is.null(obs)) obs <- rep(0L, n)
  list(
    alt = alt, obs = as.integer(obs), obs2 = rep(0L, n),
    local_slope = rep(0, n), zone = rep(1L, n),
    nr = as.integer(nr), nc = as.integer(nc),
    waypoints = as.integer(waypoints), bufgoal = bufgoal, csize = csize,
    min_slope = 2, max_slope = 12, penalty_xy = 150, penalty_z = 80,
    max_diff_z = 3, d_neighborhood = d_neighborhood, angle_hairpin = 110,
    lmax_ab_sl = 40, radius = 8, prop_sl_max = 0.25, max_slope_hairpin = 10,
    tal = 1.5, modhair = 1.5
  )
}

test_that("CA-15.1 : un tracé faisable relie départ et arrivée", {
  nr <- 5L; nc <- 9L
  alt <- plan_incline(nr, nc, 8)
  start0 <- 2 * nc + 0            # (ligne 2, col 0), 0-based aplati
  end0 <- 2 * nc + 8
  r <- do.call(desserte_trace, trace_args(alt, nr, nc, c(start0, end0)))
  expect_true(r$feasible)
  expect_equal(r$path[1], start0 + 1)              # 1-based en sortie
  expect_equal(r$path[length(r$path)], end0 + 1)
  expect_gt(r$cost, 0)
})

test_that("CA-15.6 : les points de passage obligatoires sont tous traversés", {
  nr <- 5L; nc <- 9L
  alt <- plan_incline(nr, nc, 8)
  a <- 2 * nc + 0; b <- 2 * nc + 4; c <- 2 * nc + 8
  r <- do.call(desserte_trace, trace_args(alt, nr, nc, c(a, b, c)))
  expect_true(r$feasible)
  expect_true((b + 1) %in% r$path)                 # passage intermédiaire
  expect_equal(r$path[1], a + 1)
  expect_equal(r$path[length(r$path)], c + 1)
})

test_that("CA-15.4 : un obstacle infranchissable n'est jamais traversé", {
  nr <- 5L; nc <- 9L
  alt <- plan_incline(nr, nc, 8)
  obs <- rep(0L, nr * nc)
  obs[2 * nc + 4 + 1] <- 1L                        # bloque (2,4) au milieu
  r <- do.call(desserte_trace, trace_args(alt, nr, nc, c(2 * nc + 0, 2 * nc + 8), obs = obs))
  # La cellule obstacle (1-based) n'apparaît pas dans le tracé.
  expect_false((2 * nc + 4 + 1) %in% r$path)
})

test_that("CA-15.9 : le tracé est déterministe", {
  nr <- 5L; nc <- 9L
  alt <- plan_incline(nr, nc, 8)
  args <- trace_args(alt, nr, nc, c(2 * nc + 0, 2 * nc + 8))
  r1 <- do.call(desserte_trace, args)
  r2 <- do.call(desserte_trace, args)
  expect_identical(r1$path, r2$path)
})
