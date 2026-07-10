# Oracle analytique (spec 001 §6) : le MNT jouet est un plan incliné de 20 %
# vers l'est. À l'intérieur du raster, la pente vaut donc exactement 20 % et
# l'exposition 270° (le versant regarde vers l'ouest, sens de la descente).
#
# Les cellules de bordure valent NA : le calcul de pente exige les 8 voisins.
# On compare donc l'intérieur, ce que la spec autorise explicitement (§8).

interieur <- function(r) {
  v <- as.numeric(terra::values(r))
  v[!is.na(v)]
}

test_that("la pente du MNT jouet vaut 20 % à l'intérieur (CA-1.3)", {
  terr <- calculer_terrain(toy_mnt())
  pente <- interieur(terr$slope_pct)

  expect_length(pente, 48 * 48)
  oracle <- rep(20, length(pente))
  cmp <- compare_to_oracle(pente, oracle, tol_rel = 1e-8)
  expect_true(cmp$ok)
})

test_that("l'exposition du MNT jouet est constante à 270° (CA-1.3)", {
  terr <- calculer_terrain(toy_mnt())
  expo <- interieur(terr$aspect_deg)

  cmp <- compare_to_oracle(expo, rep(270, length(expo)), tol_rel = 1e-8)
  expect_true(cmp$ok)
})

test_that("les bordures sont NA dans les deux couches", {
  terr <- calculer_terrain(toy_mnt())
  expect_true(is.na(terra::values(terr$slope_pct)[1]))
  expect_true(is.na(terra::values(terr$aspect_deg)[1]))
})

test_that("l'exposition est NA sur les cellules plates", {
  plat <- terra::rast(toy_mnt())
  terra::values(plat) <- 100

  terr <- calculer_terrain(plat)
  expect_true(all(interieur(terr$slope_pct) == 0))
  expect_length(interieur(terr$aspect_deg), 0L)
})

test_that("la méthode de pente est configurable (Horn / Evans)", {
  horn <- calculer_terrain(toy_mnt(), methode = "Horn")
  evans <- calculer_terrain(toy_mnt(), methode = "Evans")

  # Sur un plan parfait, les deux méthodes coïncident.
  expect_true(compare_to_oracle(interieur(evans$slope_pct), rep(20, 48 * 48))$ok)
  expect_equal(interieur(horn$slope_pct), interieur(evans$slope_pct))

  expect_error(calculer_terrain(toy_mnt(), methode = "Zevenbergen"))
})

test_that("preprocess() honore config$general$methode_pente", {
  cfg <- foretaccess_config(general = list(methode_pente = "Evans"))
  pre <- preprocess(toy_mnt(), toy_desserte(), toy_foret(), config = cfg)
  expect_true(compare_to_oracle(interieur(pre$slope_pct), rep(20, 48 * 48))$ok)

  expect_error(foretaccess_config(general = list(methode_pente = "inconnue")))
})

test_that("calculer_terrain() accepte un chemin de MNT", {
  terr <- calculer_terrain(toy_file("mnt.tif"))
  expect_named(terr, c("slope_pct", "aspect_deg"))
})
