# Optimisation d'une travee de cable (Lot 4c) : find_lomin (Lo minimal a tension
# = Tmax + garde) et test_span (segment : pre-filtre, pente bornee, angle au
# support intermediaire). Portes en Rust, valides depuis R. On teste avec un
# tmax modere (50 kN) : le Lo minimal est alors bien conditionne ; au tmax
# materiel (~172 kN) le cable est quasi tendu (bord fragile, cf. specs/004 4d).

g <- 9.80665
tmax_test <- 50000

params_cable <- function() {
  ao <- 0.25 * pi * 18^2
  list(
    q1 = 1.85,
    f_o = g * (2500 + 400),
    eao = 160000 * ao,
    q = 0.9
  )
}

test_that("find_lomin atteint tmax (charge centree) et ferme la geometrie", {
  p <- params_cable()
  d <- 150
  h <- 20
  alts <- rep(0, 1000) # sol tres bas -> garde large
  r <- cable_find_lomin(d, h, 0, 60, 1, alts, p$f_o, tmax_test,
    p$q1, p$q, p$q, p$eao, 3.5, 50, 5)

  expect_length(r, 6)
  expect_equal(r[1], 1) # faisable
  # Tcalc atteint tmax a l'erreur pres (50 N).
  expect_lt(abs(r[5] - tmax_test), 50)
  # Lo dans la fenetre de recherche (cable elastique : peut etre un peu sous la corde).
  diag <- sqrt(d^2 + h^2)
  expect_gt(r[2], diag - 5)
  expect_lt(r[2], diag + 100)
})

test_that("find_lomin refuse une travee dont le sol touche le cable", {
  p <- params_cable()
  alts <- rep(58, 1000) # sol releve juste sous le support (60 m)
  r <- cable_find_lomin(150, 20, 0, 60, 1, alts, p$f_o, tmax_test,
    p$q1, p$q, p$q, p$eao, 3.5, 50, 5)
  expect_equal(r[1], 0) # infaisable
})

# Profil plat au demi-metre : line_z sert de profil et d'altitudes.
profil_plat <- function(n, z) {
  list(x = (0:(n - 1)) * 0.5, z = rep(z, n))
}

test_that("test_span accepte une travee courte a tours hautes", {
  p <- params_cable()
  pf <- profil_plat(400, 0)
  r <- cable_test_span(pf$x, pf$z, 0L, 160L, 40, 40, 3.5, 50, -1.5, 1.5, pf$z,
    p$f_o, tmax_test, p$q1, p$q, p$q, p$eao, 5, 0.5, 0, -9999)

  expect_length(r, 13)
  expect_equal(r[1], 1) # faisable
  expect_equal(r[2], 80) # D = 80 m
  expect_equal(r[5], 0) # pente nulle (travee plate)
})

test_that("test_span refuse une pente hors bornes (terrain en pente)", {
  p <- params_cable()
  x <- (0:399) * 0.5
  z <- 2 * x # pente ~63 deg, corde a garde constante -> check_droite passe
  r <- cable_test_span(x, z, 0L, 100L, 10, 10, 3.5, 50, -0.6, 0.6, z,
    p$f_o, tmax_test, p$q1, p$q, p$q, p$eao, 5, 0.5, 0, -9999)
  expect_equal(r[1], 0) # infaisable
  expect_gt(abs(r[5]), 0.6) # pente effectivement hors bornes
})

test_that("test_span refuse un angle trop ferme au support intermediaire", {
  p <- params_cable()
  pf <- profil_plat(400, 0)
  # Meme travee plate faisable, mais segment precedent a 0,5 rad et
  # angle_intsup = 0,3 : l'ecart 0,5 >= 0,3 refuse.
  r <- cable_test_span(pf$x, pf$z, 0L, 160L, 40, 40, 3.5, 50, -1.5, 1.5, pf$z,
    p$f_o, tmax_test, p$q1, p$q, p$q, p$eao, 5, 0.3, 0, 0.5)
  expect_equal(r[1], 0)
})
