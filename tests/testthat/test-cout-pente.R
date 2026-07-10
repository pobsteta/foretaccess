# Fonction de cout (spec 002 §4.2, CA-2.5) : Pond_pente de Sylvaccess.

test_that("la ponderation de pente vaut sqrt(1 + (p/100)^2) (CA-2.5)", {
  expect_equal(ponderation_pente(0), 1)
  expect_equal(ponderation_pente(100), sqrt(2))
  expect_equal(ponderation_pente(20), sqrt(1 + 0.04))

  # Isotrope : monter et descendre coutent identiquement.
  expect_equal(ponderation_pente(-30), ponderation_pente(30))
})

test_that("la surface de cout du jouet suit la pente de 20 %", {
  cout <- surface_cout_skidder(toy_preprocess())
  v <- as.numeric(terra::values(cout))

  attendu <- sqrt(1 + 0.20^2)
  expect_equal(unique(round(v[!is.na(v)], 9)), round(attendu, 9))
})

test_that("les obstacles complets recoivent un surcout additif fini", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_complets = toy_obstacles()
  )
  cout <- surface_cout_skidder(pre)
  v <- as.numeric(terra::values(cout))

  base <- sqrt(1 + 0.20^2)
  # Prohibitif, mais fini : 1000 + la ponderation de pente, jamais NA.
  expect_equal(max(v, na.rm = TRUE), 1000 + base, tolerance = 1e-9)
  expect_false(all(is.na(v[terra::values(pre$obstacles_complets_mask) == 1])))
})

test_that("le surcout des obstacles est configurable (ADR-003)", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_complets = toy_obstacles()
  )
  cfg <- foretaccess_config(skidder = list(surcout_obstacle_complet = 7))
  cout <- surface_cout_skidder(pre, cfg)

  base <- sqrt(1 + 0.20^2)
  expect_equal(max(terra::values(cout), na.rm = TRUE), 7 + base, tolerance = 1e-9)
})

test_that("zone_roulage exclut les obstacles partiels, zone_treuillable non (CA-2.13)", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_partiels = toy_obstacles()
  )
  partiels <- terra::values(pre$obstacles_partiels_mask) == 1

  roulage <- terra::values(zone_roulage(pre))
  treuil <- terra::values(zone_treuillable(pre))

  # On ne roule pas dessus...
  expect_true(all(roulage[partiels] == 0))
  # ...mais on treuille par-dessus.
  expect_true(all(treuil[partiels] == 1))
})

test_that("zone_treuillable exclut les obstacles complets et la pente d'abattage", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_complets = toy_obstacles()
  )
  complets <- terra::values(pre$obstacles_complets_mask) == 1
  expect_true(all(terra::values(zone_treuillable(pre))[complets] == 0))

  # Pente au-dela du seuil d'abattage manuel : non treuillable.
  cfg <- foretaccess_config(skidder = list(pente_abattage_max_pct = 10))
  z <- zone_treuillable(toy_preprocess(), cfg)
  expect_true(all(terra::values(z) == 0))
})

test_that("zone_roulage suit le seuil de pente skidder", {
  # Le jouet est a 20 % : tout roule avec le defaut (30 %), rien avec 10 %.
  expect_gt(sum(terra::values(zone_roulage(toy_preprocess()))), 0)

  cfg <- foretaccess_config(skidder = list(pente_skidder_max_pct = 10))
  expect_equal(sum(terra::values(zone_roulage(toy_preprocess(), cfg))), 0)
})
