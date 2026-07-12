# Noyau cable (Lot 4a) : catenaire elastique + Newton-Raphson, portes en Rust
# (crate cablehelp) et appeles via extendr. On valide chaque binding depuis R,
# sur une solution *manufacturee* : on choisit un couple de tensions (Th0, Tv0),
# on en deduit la geometrie (D, H) qui annule f_x et f_z par construction, puis
# on verifie que le solveur la retrouve. Oracle exact, sans execution Sylvaccess.

g <- 9.80665

# Parametres materiels v3.6 : q1 = 1,85 kg/m, d = 18 mm, c_E = 160000 N/mm2,
# charge 2500 kg + chariot 400 kg, travee de 200 m, charge a mi-travee.
params_cable <- function() {
  lo <- 200
  ao <- 0.25 * pi * 18^2 # section en mm2
  list(
    lo = lo,
    w = 1.85 * g * lo, # poids du cable (N)
    f = g * (2500 + 400), # force de la charge (N)
    eao = 160000 * ao, # N/mm2 * mm2 = N
    s1 = 100, # abscisse de la charge
    tmax = 35000 * g / 2 # tension admissible = c_rupt * g / c_safe
  )
}

test_that("le binding version traverse toujours extendr (heritage Lot 0)", {
  expect_type(cablehelp_version(), "character")
  expect_gt(nchar(cablehelp_version()), 0)
})

test_that("f_x et f_z s'annulent sur la geometrie manufacturee", {
  p <- params_cable()
  th0 <- 60000
  tv0 <- 25000
  d <- cable_calcul_xs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)
  h <- cable_calcul_zs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)

  expect_equal(cable_f_x(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, d), 0, tolerance = 1e-6)
  expect_equal(cable_f_z(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, h), 0, tolerance = 1e-6)
})

test_that("newton retrouve les tensions manufacturees a +-1 N", {
  p <- params_cable()
  th0 <- 60000
  tv0 <- 25000
  d <- cable_calcul_xs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)
  h <- cable_calcul_zs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)

  # Amorçage a +3 % : le solveur doit converger vers (Th0, Tv0).
  sol <- cable_newton_thtv(th0 * 1.03, tv0 * 1.03, h, d, p$lo, p$w, p$s1, p$f, p$eao, p$tmax, 0.01)
  expect_length(sol, 2)
  expect_equal(sol[1], th0, tolerance = 1e-4)
  expect_equal(sol[2], tv0, tolerance = 1e-4)

  # Residus quasi nuls a la solution (CA-4.2).
  expect_lt(abs(cable_f_x(sol[1], sol[2], p$lo, p$eao, p$w, p$f, p$s1, d)), 0.05)
  expect_lt(abs(cable_f_z(sol[1], sol[2], p$lo, p$eao, p$w, p$f, p$s1, h)), 0.05)
})

test_that("calcul_zs rejoint le support oppose a la solution (garde au sol)", {
  p <- params_cable()
  th0 <- 60000
  tv0 <- 25000
  d <- cable_calcul_xs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)
  h <- cable_calcul_zs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)
  sol <- cable_newton_thtv(th0 * 1.03, tv0 * 1.03, h, d, p$lo, p$w, p$s1, p$f, p$eao, p$tmax, 0.01)

  # A l'abscisse Lo, le cable atteint le support oppose : xs = D, zs = H (CA-4.3).
  expect_equal(cable_calcul_xs(sol[1], sol[2], p$lo, p$eao, p$w, p$f, p$s1, p$lo), d, tolerance = 1e-2)
  expect_equal(cable_calcul_zs(sol[1], sol[2], p$lo, p$eao, p$w, p$f, p$s1, p$lo), h, tolerance = 1e-2)
})

test_that("la grille trouve le noeud et juge la faisabilite selon Tmax", {
  p <- params_cable()
  th0 <- 60000 # multiples du pas de 50 N
  tv0 <- 25000
  d <- cable_calcul_xs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)
  h <- cable_calcul_zs(th0, tv0, p$lo, p$eao, p$w, p$f, p$s1, p$lo)

  # Tmax au-dessus du noeud : trouve (Th0, Tv0), travee faisable.
  ok <- cable_find_thtv_tmax(80000, p$w, p$eao, p$f, p$s1, d, h, p$lo, 50L)
  expect_equal(ok[1], th0)
  expect_equal(ok[2], tv0)
  expect_equal(ok[3], 1)

  # sqrt(60000^2 + 25000^2) = 65000 : sous Tmax = 64000, travee infaisable.
  ko <- cable_find_thtv_tmax(64000, p$w, p$eao, p$f, p$s1, d, h, p$lo, 50L)
  expect_equal(ko[3], 0)
})
