# Loi de bascule (spec 002 §4.4, CA-2.6). Valeurs de reference lues dans
# Sylvaccess_1_skidder.py:336-370 et sylvaccess_cython3.pyx:3164.
#
# Le piege du lot : Dmax est affine en DENIVELE, pas en pente. A plat, la
# distance admissible vaut 80,23 m -- ni 50 (amont), ni 100 (aval).

test_that("les coefficients reproduisent ceux du code source (CA-2.6)", {
  cf <- coefficients_bascule()

  expect_equal(cf$coeff, -1.0078285397041846, tolerance = 1e-12)
  expect_equal(cf$orig, 80.23485619112554, tolerance = 1e-12)
  expect_equal(cf$p_up, 0.75)
  expect_equal(cf$p_down, -0.20)
  expect_equal(cf$dmin, 50)
})

test_that("Dmax reproduit le tableau de reference (CA-2.6)", {
  attendu <- c(
    "-1.00" = 100, "-0.50" = 100, "-0.20" = 100,
    "-0.10" = 89.177851, "0.00" = 80.234856,
    "0.10" = 72.922038, "0.30" = 62.216980, "0.50" = 55.307126,
    "0.75" = 50, "1.00" = 50
  )
  pentes <- as.numeric(names(attendu))

  expect_equal(distance_treuillage_max(pentes), unname(attendu), tolerance = 1e-6)
})

test_that("a plat, la distance admissible vaut 80,23 m -- ni 50 ni 100", {
  d <- distance_treuillage_max(0)
  expect_equal(d, 80.234856, tolerance = 1e-6)
  expect_false(isTRUE(all.equal(d, 50)))
  expect_false(isTRUE(all.equal(d, 100)))
})

test_that("les deux hypotheses lineaires en pente sont fausses", {
  # A 30 % de pente, la verite vaut 62,22 m. Les deux lectures « naturelles »
  # de la doc -- qui ne parle que de pentes de bascule -- se trompent toutes deux.
  verite <- distance_treuillage_max(0.30)
  expect_equal(verite, 62.216980, tolerance = 1e-6)

  cf <- coefficients_bascule()

  # H1 : interpolation lineaire entre les deux pentes de bascule.
  h1 <- stats::approx(c(cf$p_down, cf$p_up), c(cf$daval, cf$damont), xout = 0.30)$y
  expect_equal(h1, 73.684211, tolerance = 1e-6)

  # H2 : Dmax vaut deja le plafond amont des le seuil skidder (30 %).
  h2 <- cf$damont
  expect_equal(h2, 50)

  # Les deux s'ecartent de plus de 18 % de la verite, et silencieusement.
  expect_gt(abs(h1 - verite) / verite, 0.18)
  expect_gt(abs(h2 - verite) / verite, 0.19)
})

test_that("la loi est continue aux deux ancrages", {
  eps <- 1e-9
  expect_equal(distance_treuillage_max(-0.20 - eps), 100, tolerance = 1e-6)
  expect_equal(distance_treuillage_max(-0.20 + eps), 100, tolerance = 1e-6)
  expect_equal(distance_treuillage_max(0.75), 50, tolerance = 1e-6)
  expect_equal(distance_treuillage_max(0.75 + eps), 50, tolerance = 1e-6)
})

test_that("Dmax decroit avec la pente (l'amont est plus contraignant)", {
  pentes <- seq(-0.2, 0.75, by = 0.05)
  d <- distance_treuillage_max(pentes)
  expect_true(all(diff(d) < 0))
  expect_equal(max(d), 100, tolerance = 1e-6)
  expect_equal(min(d), 50, tolerance = 1e-6)
})

test_that("cas particulier : amont == aval", {
  cfg <- foretaccess_config(skidder = list(debardage_aval_max_m = 50))
  cf <- coefficients_bascule(cfg)

  expect_equal(cf$coeff, 0)
  expect_equal(cf$orig, 50)
  expect_equal(distance_treuillage_max(c(-1, 0, 0.5), cfg), c(50, 50, 50))
})

test_that("cas particulier : amont nul", {
  cfg <- foretaccess_config(skidder = list(debardage_amont_max_m = 0))
  cf <- coefficients_bascule(cfg)

  expect_equal(cf$coeff, 0)
  expect_equal(cf$orig, 100)
  expect_equal(cf$p_down, 0)
  # Toute pente strictement positive retombe sur damont = 0.
  expect_equal(distance_treuillage_max(0.5, cfg), 0)
  expect_equal(distance_treuillage_max(-0.5, cfg), 100)
})

test_that("cas particulier : aval nul", {
  cfg <- foretaccess_config(skidder = list(debardage_aval_max_m = 0))
  cf <- coefficients_bascule(cfg)

  expect_equal(cf$coeff, 0)
  expect_equal(cf$orig, 50)
  expect_equal(distance_treuillage_max(-0.5, cfg), 0)
  expect_equal(distance_treuillage_max(0.9, cfg), 50)
})

test_that("Dmax est bien affine en denivele dans la bande d'interpolation", {
  cf <- coefficients_bascule()
  pentes <- c(-0.15, 0, 0.25, 0.6)
  d <- distance_treuillage_max(pentes)
  deniv <- d * pentes / sqrt(1 + pentes^2)

  expect_equal(d, cf$coeff * deniv + cf$orig, tolerance = 1e-8)
})

test_that("cas degenere : les deux pentes de bascule nulles", {
  # deniv_up == deniv_down == 0 : Sylvaccess retombe sur la moyenne des deux
  # distances (`orig = 0.5 * (damont + daval)`).
  cfg <- foretaccess_config(skidder = list(
    pente_bascule_amont_pct = 0, pente_bascule_aval_pct = 0
  ))
  cf <- coefficients_bascule(cfg)

  expect_equal(cf$coeff, 0)
  expect_equal(cf$orig, 75)
})
