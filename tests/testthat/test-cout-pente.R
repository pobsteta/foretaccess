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

test_that("le seuil d'abattage porte sur le MAXIMUM LOCAL de la pente (3 x 3)", {
  # Trouve par confrontation a l'oracle : `slopes_skid()` de Sylvaccess
  # (sylvaccess_cython3.pyx:3417-3424) teste le maximum de la pente sur la
  # fenetre 3 x 3, pas la pente de la cellule. La zone d'exclusion est donc
  # DILATEE d'une cellule. Sans cela notre zone d'abattage etait 1,7 fois trop
  # large sur ColduPre, et les rayons de treuillage traversaient des trous que
  # Sylvaccess referme.
  #
  # MNT plat, sauf une falaise ponctuelle : la cellule raide et ses 8 voisines
  # doivent sortir de la zone treuillable, pas la seule cellule raide.
  mnt <- terra::rast(nrows = 11, ncols = 11, xmin = 0, xmax = 55, ymin = 0, ymax = 55, crs = "EPSG:2154")
  terra::values(mnt) <- 100
  centre <- terra::cellFromRowCol(mnt, 6, 6)
  mnt[centre] <- 200 # falaise : pente locale tres au-dela de 100 %

  e <- terra::ext(mnt)
  foret <- sf::st_sf(geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(e[1], e[3]), c(e[2], e[3]), c(e[2], e[4]), c(e[1], e[4]), c(e[1], e[3])
  ))), crs = 2154))
  d <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(5, 5), c(10, 5))), crs = 2154)
  )
  pre <- preprocess(mnt = mnt, desserte = d, foret = foret)

  z <- terra::values(zone_treuillable(pre, foretaccess_config()))
  voisines <- terra::adjacent(mnt, centre, directions = 8)[1, ]

  expect_equal(as.numeric(z[centre]), 0)
  # La dilatation : les huit voisines aussi, alors que leur propre pente peut
  # etre sous le seuil.
  expect_true(all(z[voisines] == 0))
})
