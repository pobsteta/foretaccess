# CA-1.4 : masques alignés et corrects sur le jeu jouet.

test_that("foret_mask couvre exactement le polygone forêt", {
  pre <- toy_preprocess()
  v <- terra::values(pre$foret_mask)

  expect_setequal(unique(as.numeric(v)), c(0, 1))
  # Polygone [25, 225]^2, cellules de 5 m dont le centre tombe dans le polygone :
  # centres de 27.5 à 222.5, soit 40 x 40 cellules.
  expect_equal(sum(v == 1), 40 * 40)
})

test_that("la desserte est un raster catégoriel à 3 classes", {
  pre <- toy_preprocess()

  expect_true(terra::is.factor(pre$desserte))
  niveaux <- terra::levels(pre$desserte)[[1]]
  expect_equal(niveaux$classe, c("route", "piste", "dfci"))

  # Les trois classes sont effectivement présentes sur le jouet.
  codes <- unique(as.numeric(terra::values(pre$desserte)))
  expect_setequal(sort(codes[!is.na(codes)]), c(1, 2, 3))

  # Hors desserte : NA (et non 0).
  expect_true(anyNA(terra::values(pre$desserte)))
})

test_that("les masques d'obstacles valent 0 partout quand la couche est absente", {
  pre <- toy_preprocess()

  for (nm in c("obstacles_complets_mask", "obstacles_partiels_mask")) {
    v <- terra::values(pre[[nm]])
    expect_false(anyNA(v))
    expect_true(all(v == 0))
  }
})

test_that("un obstacle fourni est rasterisé en 1 sur son emprise", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_complets = toy_obstacles()
  )
  v <- terra::values(pre$obstacles_complets_mask)

  expect_setequal(unique(as.numeric(v)), c(0, 1))
  # Carré [50, 100]^2 : centres de 52.5 à 97.5, soit 10 x 10 cellules.
  expect_equal(sum(v == 1), 10 * 10)
})

test_that("exclusion_mask vaut 0 partout sur le jouet (20 % < 100 %)", {
  pre <- toy_preprocess()
  v <- as.numeric(terra::values(pre$exclusion_mask))

  expect_true(all(v[!is.na(v)] == 0))
  # Les bordures héritent du NA de la pente (effet de bord documenté).
  expect_equal(sum(is.na(v)), 50 * 50 - 48 * 48)
})

test_that("exclusion_mask suit le seuil de config (ADR-003)", {
  cfg <- foretaccess_config(skidder = list(pente_abattage_max_pct = 10))
  pre <- preprocess(toy_mnt(), toy_desserte(), toy_foret(), config = cfg)

  v <- as.numeric(terra::values(pre$exclusion_mask))
  expect_true(all(v[!is.na(v)] == 1))
})
