# Canaux de micro-relief RVT (spec 021, J3). Noyau Rust rvt_svf_opns() +
# enveloppe terra micro_relief(). Non-regression PIXEL A PIXEL contre RVT_py
# (oracle gele, genere par data-raw/oracle_rvt.R sur un MNT synthetique) :
# l'ecart residuel est le float32 interne de RVT vs le float64 du crate.

test_that("rvt_svf_opns colle a l'oracle RVT_py (SVF + openness +/-)", {
  o <- readRDS(test_path("fixtures", "rvt_oracle.rds"))
  r <- rvt_svf_opns(
    o$dem, o$nr, o$nc, o$resolution, o$radius_max_px, o$radius_min_px,
    o$num_directions, TRUE, TRUE
  )
  rn <- rvt_svf_opns(
    -o$dem, o$nr, o$nc, o$resolution, o$radius_max_px, o$radius_min_px,
    o$num_directions, FALSE, TRUE
  )
  # Tolerances larges devant l'ecart mesure (~2e-6 SVF, ~2e-4 deg openness) :
  # elles bornent la non-regression sans etre fragiles au float32 de l'oracle.
  expect_equal(r$svf, o$svf, tolerance = 1e-4)
  expect_equal(r$opns, o$opns, tolerance = 1e-2)
  expect_equal(rn$opns, o$opns_neg, tolerance = 1e-2)
})

test_that("micro_relief : terrain plat -> svf = 1, openness = 90", {
  mnt <- terra::rast(
    nrows = 20, ncols = 20, xmin = 0, xmax = 20, ymin = 0, ymax = 20,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100
  mr <- micro_relief(mnt, radius_m = 5)
  expect_s4_class(mr, "SpatRaster")
  expect_setequal(names(mr), c("svf", "openness_pos", "openness_neg"))
  expect_equal(as.vector(terra::ext(mr)), as.vector(terra::ext(mnt)))
  v <- terra::values(mr)
  expect_true(all(abs(v[, "svf"] - 1) < 1e-9))
  expect_true(all(abs(v[, "openness_pos"] - 90) < 1e-9))
  expect_true(all(abs(v[, "openness_neg"] - 90) < 1e-9))
})

test_that("micro_relief : ne rend que les canaux demandes, MNT non raster rejete", {
  mnt <- terra::rast(
    nrows = 15, ncols = 15, xmin = 0, xmax = 15, ymin = 0, ymax = 15,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- runif(225, 90, 110)
  mr <- micro_relief(mnt, radius_m = 4, canaux = "svf")
  expect_equal(names(mr), "svf")
  expect_equal(terra::nlyr(mr), 1L)
  # SVF borne dans [0, 1].
  sv <- terra::values(mr)[, 1]
  expect_true(all(sv >= 0 & sv <= 1))
  expect_error(micro_relief(matrix(1, 3, 3)), "SpatRaster")
})

test_that("micro_relief : une cellule NA du MNT reste NA dans les canaux", {
  mnt <- terra::rast(
    nrows = 12, ncols = 12, xmin = 0, xmax = 12, ymin = 0, ymax = 12,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100
  mnt[5, 6] <- NA
  mr <- micro_relief(mnt, radius_m = 3, canaux = c("svf", "openness_pos"))
  cell <- terra::cellFromRowCol(mnt, 5, 6)
  expect_true(all(is.na(terra::values(mr)[cell, ])))
})
