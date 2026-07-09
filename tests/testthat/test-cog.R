# CA-1.6 : écriture GeoTIFF/COG optionnelle, round-trip fidèle.

test_that("sans write_dir, rien n'est écrit sur disque", {
  expect_null(toy_preprocess()$fichiers)
})

test_that("write_dir écrit les rasters et le round-trip est fidèle", {
  dir <- withr::local_tempdir()
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    volume = toy_volume(), write_dir = dir
  )

  attendus <- c(
    "slope_pct", "aspect_deg", "foret_mask", "desserte",
    "obstacles_complets_mask", "obstacles_partiels_mask",
    "exclusion_mask", "volume"
  )
  expect_named(pre$fichiers, attendus, ignore.order = TRUE)
  expect_true(all(file.exists(unlist(pre$fichiers))))

  relus <- lire_rasters(dir)
  expect_named(relus, attendus, ignore.order = TRUE)

  for (nm in attendus) {
    cmp <- compare_to_oracle(
      as.numeric(terra::values(relus[[nm]])),
      as.numeric(terra::values(pre[[nm]])),
      tol_rel = 1e-6
    )
    expect_true(cmp$ok, info = nm)
    expect_equal(as.vector(terra::ext(relus[[nm]])), as.vector(terra::ext(pre[[nm]])), info = nm)
  }
})

test_that("le raster de desserte relu conserve ses catégories", {
  dir <- withr::local_tempdir()
  preprocess(toy_mnt(), toy_desserte(), toy_foret(), write_dir = dir)

  desserte <- lire_rasters(dir)$desserte
  expect_true(terra::is.factor(desserte))

  # GDAL renomme la colonne de catégories d'après la couche : on compare les
  # libellés, pas le nom de colonne.
  niveaux <- terra::levels(desserte)[[1]]
  expect_equal(niveaux[[1]], 1:3)
  expect_equal(niveaux[[2]], c("route", "piste", "dfci"))
})

test_that("les couches absentes ne sont pas écrites", {
  dir <- withr::local_tempdir()
  pre <- preprocess(toy_mnt(), toy_desserte(), toy_foret(), write_dir = dir)

  expect_false("volume" %in% names(pre$fichiers))
  expect_false(file.exists(file.path(dir, "volume.tif")))
})

test_that("lire_rasters() échoue sur un répertoire sans raster", {
  dir <- withr::local_tempdir()
  expect_error(lire_rasters(dir), regexp = "Aucun raster")
})
