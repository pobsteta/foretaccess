# CA-1.5 : toutes les sorties raster partagent exactement la grille du MNT.

test_that("tous les rasters de sortie partagent la grille du MNT", {
  pre <- preprocess(
    mnt = toy_mnt(), desserte = toy_desserte(), foret = toy_foret(),
    obstacles_complets = toy_obstacles(),
    obstacles_partiels = toy_obstacles(xmin = 150, ymin = 150),
    volume = toy_volume()
  )
  mnt <- toy_mnt()

  couches <- c(
    "slope_pct", "aspect_deg", "foret_mask", "desserte",
    "obstacles_complets_mask", "obstacles_partiels_mask",
    "exclusion_mask", "volume"
  )
  for (nm in couches) {
    r <- pre[[nm]]
    expect_s4_class(r, "SpatRaster")
    expect_equal(dim(r)[1:2], dim(mnt)[1:2], info = nm)
    expect_equal(terra::res(r), terra::res(mnt), info = nm)
    expect_equal(as.vector(terra::ext(r)), as.vector(terra::ext(mnt)), info = nm)
    expect_true(sf::st_crs(terra::crs(r)) == sf::st_crs(terra::crs(mnt)), info = nm)
  }
})

test_that("les métadonnées de grille décrivent le MNT", {
  g <- toy_preprocess()$grid

  expect_equal(g$nrow, 50)
  expect_equal(g$ncol, 50)
  expect_equal(g$res, c(5, 5))
  expect_equal(unname(g$ext), c(0, 250, 0, 250))
  expect_true(sf::st_crs(g$crs) == sf::st_crs(2154))
})
