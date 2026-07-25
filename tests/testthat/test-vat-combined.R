# Composite CVAT (Combined VAT) -- combinaison par defaut du plugin QGIS RVT.
# Les fonctions RVT portees (pente/ombrage/byte_scale) sont testees par invariants
# analytiques ; vat_combined() est validee pixel a pixel contre l'oracle RVT
# (fixtures/cvat_oracle.rds, genere par data-raw/oracle_rvt.R depuis le plugin).

test_that(".rvt_slope_aspect : terrain plat -> pente nulle ; plan incline -> pente connue", {
  flat <- matrix(100, 10, 10)
  sa <- foretaccess:::.rvt_slope_aspect(flat, 1, 1)
  expect_true(all(abs(sa$slope_deg) < 1e-9))
  # Plan incline en X (m[,j] = 2j, variation par colonne) : |dz/dx| = 2 -> atan(2).
  m <- matrix(rep(seq_len(10) * 2, each = 10), nrow = 10) # rempli par colonne
  sa2 <- foretaccess:::.rvt_slope_aspect(m, 1, 1)
  # Interieur (colonnes hors bord edge-pad) : tan(pente) = 2.
  interieur <- sa2$slope_deg[, 3:8]
  expect_true(all(abs(tan(interieur * pi / 180) - 2) < 1e-6))
})

test_that(".rvt_hillshade : terrain plat -> hillshade = sin(elevation)", {
  flat <- matrix(100, 12, 12)
  hs <- foretaccess:::.rvt_hillshade(flat, 1, 1, 315, 35)
  # Sur du plat : pente 0 -> hs = cos(zenith) = sin(elevation) = sin(35 deg).
  expect_true(all(abs(hs - sin(35 * pi / 180)) < 1e-9))
  expect_equal(dim(hs), c(12L, 12L))
})

test_that(".rvt_byte_scale01 : troncature IDL, ecretage, NA -> 255", {
  v <- c(0, 0.5, 1, -0.2, 1.5, NA)
  b <- foretaccess:::.rvt_byte_scale01(v)
  # 255.9999*v tronque : 0->0, 0.5->127, 1->255 (ecrete), <0->0, >1->255, NA->255.
  expect_equal(b, c(0L, 127L, 255L, 0L, 255L, 255L))
})

test_that("cvat_terrain_params : general = preset VAT, flat = parametres plats", {
  p <- cvat_terrain_params()
  expect_setequal(names(p), c("general", "flat"))
  # general reprend le preset blender_VAT.json.
  expect_equal(p$general$svf_r_max, 10)
  expect_equal(p$general$svf_r_min, 1)
  expect_equal(p$general$sun_elevation, 35)
  expect_equal(c(p$general$layers$svf$min, p$general$layers$svf$max), c(0.7, 1.0))
  # flat : SVF plus large + bruite, pentes/openness serres, soleil rasant.
  expect_equal(p$flat$svf_r_max, 20)
  expect_equal(p$flat$svf_r_min, 8) # noise 3 -> max(round(20*0.40),1)
  expect_equal(p$flat$sun_elevation, 15)
  expect_equal(c(p$flat$layers$svf$min, p$flat$layers$svf$max), c(0.9, 1.0))
  expect_equal(p$flat$layers$slope$max, 15)
  expect_equal(c(p$flat$layers$openness_pos$min, p$flat$layers$openness_pos$max), c(85, 93))
})

test_that("vat_combined colle a l'oracle RVT (plugin QGIS, CVAT)", {
  o <- readRDS(test_path("fixtures", "cvat_oracle.rds"))
  mnt <- terra::rast(
    nrows = o$nr, ncols = o$nc, xmin = 0, xmax = o$nc, ymin = 0, ymax = o$nr,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- o$dem
  got_f <- terra::values(vat_combined(mnt, as_byte = FALSE))[, 1]
  got_b <- terra::values(vat_combined(mnt, as_byte = TRUE))[, 1]
  # Float : accord au float32 pres (~4e-7 mesure).
  expect_equal(got_f, o$float, tolerance = 1e-5)
  # 8 bits : IDENTIQUE au pixel pres sur la fixture (max|delta| = 0 mesure).
  expect_identical(as.integer(got_b), as.integer(o$byte))
})

test_that("vat_combined : sortie float [0,1] et 8bit [0,255], alignee au MNT", {
  mnt <- terra::rast(
    nrows = 24, ncols = 24, xmin = 0, xmax = 24, ymin = 0, ymax = 24,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100 + terra::rowFromCell(mnt, 1:576) * 0.3
  f <- vat_combined(mnt)
  b <- vat_combined(mnt, as_byte = TRUE)
  expect_equal(names(f), "cvat")
  expect_equal(as.vector(terra::ext(f)), as.vector(terra::ext(mnt)))
  vf <- terra::values(f)[, 1]
  vb <- terra::values(b)[, 1]
  expect_true(all(vf >= 0 & vf <= 1, na.rm = TRUE))
  expect_true(all(vb >= 0 & vb <= 255, na.rm = TRUE))
})
