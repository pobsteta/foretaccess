# Politique stricte (spec 001 §10, décision 1) : aucune reprojection ni
# rééchantillonnage silencieux. Un test par cas d'erreur (CA-1.2).

test_that("le jeu jouet passe la validation", {
  expect_true(valider_entrees(toy_mnt(), toy_desserte(), toy_foret()))
})

test_that("un CRS divergent lève une erreur ciblée", {
  foret_wgs84 <- sf::st_transform(toy_foret(), 4326)
  expect_error(
    valider_entrees(toy_mnt(), toy_desserte(), foret_wgs84),
    regexp = "CRS divergent"
  )
})

test_that("un champ classe manquant lève une erreur ciblée", {
  desserte <- toy_desserte()
  desserte$classe <- NULL
  expect_error(
    valider_entrees(toy_mnt(), desserte, toy_foret()),
    regexp = "classe"
  )
})

test_that("une valeur de classe inconnue lève une erreur ciblée", {
  desserte <- toy_desserte()
  desserte$classe[1] <- "autoroute"
  expect_error(
    valider_entrees(toy_mnt(), desserte, toy_foret()),
    regexp = "autoroute"
  )
})

test_that("un NA dans classe lève une erreur ciblée", {
  desserte <- toy_desserte()
  desserte$classe[2] <- NA_character_
  expect_error(
    valider_entrees(toy_mnt(), desserte, toy_foret()),
    regexp = "classe"
  )
})

test_that("un volume non aligné lève une erreur ciblée", {
  volume <- terra::rast(
    nrows = 25, ncols = 25, xmin = 0, xmax = 250, ymin = 0, ymax = 250,
    crs = "EPSG:2154"
  )
  terra::values(volume) <- 1
  expect_error(
    valider_entrees(toy_mnt(), toy_desserte(), toy_foret(), volume = volume),
    regexp = "Grille non align"
  )
})

test_that("un volume aligné passe la validation", {
  expect_true(
    valider_entrees(toy_mnt(), toy_desserte(), toy_foret(), volume = toy_volume())
  )
})

test_that("une géométrie vide lève une erreur ciblée", {
  foret <- toy_foret()
  sf::st_geometry(foret)[1] <- sf::st_sfc(sf::st_polygon(), crs = 2154)
  expect_error(
    valider_entrees(toy_mnt(), toy_desserte(), foret),
    regexp = "vide"
  )
})

test_that("une couche sans aucune géométrie lève une erreur ciblée", {
  foret <- toy_foret()[0, ]
  expect_error(
    valider_entrees(toy_mnt(), toy_desserte(), foret),
    regexp = "aucune"
  )
})

test_that("une emprise disjointe du MNT lève une erreur ciblée", {
  loin <- toy_obstacles(xmin = 100000, ymin = 100000)
  expect_error(
    valider_entrees(toy_mnt(), toy_desserte(), toy_foret(), obstacles_complets = loin),
    regexp = "recoupe pas"
  )
})

test_that("un MNT multi-couches ou sans CRS lève une erreur ciblée", {
  mnt <- toy_mnt()
  expect_error(valider_entrees(c(mnt, mnt), toy_desserte(), toy_foret()), "seule couche")

  sans_crs <- toy_mnt()
  terra::crs(sans_crs) <- ""
  expect_error(valider_entrees(sans_crs, toy_desserte(), toy_foret()), "CRS")
})
