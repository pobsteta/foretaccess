test_that("les défauts skidder sont ceux de Sylvaccess v3.6", {
  cfg <- foretaccess_config()
  expect_s3_class(cfg, "foretaccess_config")
  sk <- cfg$skidder
  expect_equal(sk$debardage_amont_max_m, 50)
  expect_equal(sk$debardage_aval_max_m, 100)
  expect_equal(sk$pente_bascule_amont_pct, 75)
  expect_equal(sk$pente_bascule_aval_pct, 20)
  expect_equal(sk$distance_hors_desserte_max_m, 50)
  expect_equal(sk$pente_skidder_max_pct, 30)
  expect_equal(sk$pente_abattage_max_pct, 100)
})

test_that("les défauts porteur sont ceux de Sylvaccess v3.6", {
  po <- foretaccess_config()$porteur
  expect_equal(po$pente_travers_max_pct, 15)
  expect_equal(po$pente_montee_max_pct, 30)
  # f_slope_down = 25 : divergence assumee de dic_AllParam.json (def_value 40),
  # alignee sur les deux references reelles -- scenario officiel ColduPre ET
  # ACCESSFOR (rapport 2025) -- qui retiennent 25 (cf. commentaire config.R).
  expect_equal(po$pente_descente_max_pct, 25)
  expect_equal(po$portee_grue_m, 8)
  expect_equal(po$distance_pente_forte_max_m, 300)
  expect_equal(po$distance_hors_desserte_max_m, 200)
  expect_equal(po$pente_abattage_max_pct, 100)
})

test_that("les défauts câble portent les matériels v3.6 (complétés au Lot 4)", {
  ca <- foretaccess_config()$cable
  # Gardes au sol v3.6 (c_h_min / c_h_max).
  expect_equal(ca$hauteur_cable_min_m, 3.5)
  expect_equal(ca$hauteur_cable_max_m, 50)
  expect_equal(ca$pas_angulaire_deg, 1)
  # Materiels completes depuis Tab_Param_cable.csv et le paramdict.
  expect_equal(ca$longueur_max_m, 750)
  expect_equal(ca$tension_rupture_kgf, 35000)
  expect_equal(ca$diametre_mm, 18)
  expect_equal(ca$nb_supports_max, 3)
})

test_that("les surcharges sont appliquées et validées", {
  cfg <- foretaccess_config(skidder = list(debardage_aval_max_m = 120))
  expect_equal(cfg$skidder$debardage_aval_max_m, 120)
  # les autres défauts restent intacts
  expect_equal(cfg$skidder$debardage_amont_max_m, 50)
})

test_that("une config invalide échoue avec un message ciblé", {
  expect_error(
    foretaccess_config(skidder = list(debardage_aval_max_m = -1)),
    class = "simpleError"
  )
  expect_error(
    foretaccess_config(skidder = list(debardage_amont_max_m = "beaucoup"))
  )
  # incohérence hauteur câble min/max
  expect_error(
    foretaccess_config(cable = list(hauteur_cable_min_m = 30, hauteur_cable_max_m = 4)),
    regexp = "hauteur_cable"
  )
})

test_that("round-trip YAML préserve la configuration", {
  cfg <- foretaccess_config(porteur = list(portee_grue_m = 10))
  path <- withr::local_tempfile(fileext = ".yaml")
  write_config(cfg, path)
  cfg2 <- read_config(path)
  expect_equal(cfg2$porteur$portee_grue_m, 10)
  expect_equal(cfg2$skidder, cfg$skidder)
})

test_that("les parametres skidder du Lot 2 sont ceux du .pyx", {
  sk <- foretaccess_config()$skidder
  expect_equal(sk$hauteur_attache_treuil_m, 10)
  expect_equal(sk$hauteur_degagement_max_m, 30)
  expect_equal(sk$surcout_obstacle_complet, 1000)
  expect_equal(as.integer(sk$option_modelisation), 1L)
  expect_equal(sk$classes_distance_m, c(0, 250, 500, 1000, 1500, 2000))
})

test_that("une hauteur de degagement incoherente echoue avec un message cible", {
  expect_error(
    foretaccess_config(skidder = list(hauteur_degagement_max_m = 5)),
    regexp = "hauteur_degagement_max_m"
  )
  expect_error(foretaccess_config(skidder = list(option_modelisation = 3L)))
  expect_error(foretaccess_config(skidder = list(classes_distance_m = c(500, 100))))
})
