test_that(".as_raster accepte un chemin et un SpatRaster (ADR-004)", {
  depuis_chemin <- .as_raster(toy_file("mnt.tif"), "mnt")
  expect_s4_class(depuis_chemin, "SpatRaster")

  objet <- toy_mnt()
  expect_identical(.as_raster(objet, "mnt"), objet)
})

test_that(".as_vector accepte un chemin, un sf et un SpatVector", {
  depuis_chemin <- .as_vector(toy_file("foret.gpkg"), "foret")
  expect_s3_class(depuis_chemin, "sf")

  objet <- toy_foret()
  expect_identical(.as_vector(objet, "foret"), objet)

  depuis_spatvector <- .as_vector(terra::vect(objet), "foret")
  expect_s3_class(depuis_spatvector, "sf")
})

test_that("les entrées d'un type inattendu échouent avec un message ciblé", {
  expect_error(.as_raster(42, "mnt"), regexp = "mnt")
  expect_error(.as_vector(42, "foret"), regexp = "foret")
  expect_error(.as_raster("absent.tif", "mnt"))
  expect_error(.as_vector("absent.gpkg", "foret"))
})

test_that("preprocess() lit le jeu jouet depuis des chemins (CA-1.1)", {
  pre <- preprocess(
    mnt = toy_file("mnt.tif"),
    desserte = toy_file("desserte.gpkg"),
    foret = toy_file("foret.gpkg")
  )
  expect_s3_class(pre, "foretaccess_preprocessing")
  expect_null(pre$volume)
  expect_null(pre$parcellaire)
  expect_s3_class(pre$desserte_sf, "sf")
})

test_that("preprocess() accepte les couches facultatives (CA-1.1)", {
  pre <- preprocess(
    mnt = toy_mnt(),
    desserte = toy_desserte(),
    foret = toy_foret(),
    obstacles_complets = toy_obstacles(),
    volume = toy_volume(),
    parcellaire = toy_foret()
  )
  expect_s4_class(pre$volume, "SpatRaster")
  expect_s3_class(pre$parcellaire, "sf")
})

test_that("print.foretaccess_preprocessing résume la grille", {
  expect_message(print(toy_preprocess()), regexp = "Pretraitement")
})
