# Lot 15c : orchestration R du solveur de trace (`tracer_desserte`).

# Fixture : prétraitement sur un plan incliné `slope_pct` % vers l'est, pour que
# la route puisse monter le long de x en respectant [pente_long_min, max].
fake_pre_incline <- function(nr = 5, nc = 11, slope_pct = 8, csize = 10) {
  mnt <- terra::rast(
    nrows = nr, ncols = nc,
    xmin = 0, xmax = nc * csize, ymin = 0, ymax = nr * csize,
    crs = "EPSG:2154"
  )
  # Altitude = plan incliné : +slope_pct % par cellule vers l'est.
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  col <- terra::colFromX(mnt, xy[, 1]) - 1L
  terra::values(mnt) <- col * slope_pct / 100 * csize
  names(mnt) <- "mnt"

  slope <- terra::rast(mnt)
  terra::values(slope) <- slope_pct # pente du terrain ~constante
  names(slope) <- "slope_pct"

  obst <- terra::rast(mnt)
  terra::values(obst) <- 0
  names(obst) <- "obstacles_complets_mask"

  structure(
    list(mnt = mnt, slope_pct = slope, obstacles_complets_mask = obst),
    class = "foretaccess_preprocessing"
  )
}

test_that("tracer_desserte relie depart et arrivee par une LINESTRING", {
  pre <- fake_pre_incline()
  cout <- surface_cout_construction(pre)
  start <- terra::cellFromRowCol(pre$mnt, 3, 1)
  end <- terra::cellFromRowCol(pre$mnt, 3, 11)

  tr <- tracer_desserte(pre, cout, c(start, end))
  expect_s3_class(tr, "foretaccess_trace")
  expect_true(tr$faisable)
  expect_s3_class(tr$ligne, "sf")
  expect_equal(as.character(sf::st_geometry_type(tr$ligne)[1]), "LINESTRING")

  # Le trace part du centre de la cellule de depart et finit a l'arrivee.
  coords <- sf::st_coordinates(tr$ligne)[, c("X", "Y")]
  centres <- terra::xyFromCell(pre$mnt, c(start, end))
  expect_equal(unname(coords[1, ]), unname(centres[1, ]), tolerance = 1e-6)
  expect_equal(unname(coords[nrow(coords), ]), unname(centres[2, ]), tolerance = 1e-6)
  expect_gt(tr$cout, 0)
})

test_that("un point de passage intermediaire est traverse", {
  pre <- fake_pre_incline()
  cout <- surface_cout_construction(pre)
  a <- terra::cellFromRowCol(pre$mnt, 3, 1)
  b <- terra::cellFromRowCol(pre$mnt, 3, 6)
  d <- terra::cellFromRowCol(pre$mnt, 3, 11)

  tr <- tracer_desserte(pre, cout, c(a, b, d))
  expect_true(tr$faisable)
  # Le centre du waypoint intermediaire est un sommet du trace.
  centre_b <- terra::xyFromCell(pre$mnt, b)
  coords <- sf::st_coordinates(tr$ligne)[, c("X", "Y")]
  d_min <- min(sqrt((coords[, 1] - centre_b[1])^2 + (coords[, 2] - centre_b[2])^2))
  expect_lt(d_min, 1e-6)
})

test_that("accepte des points sf comme waypoints", {
  pre <- fake_pre_incline()
  cout <- surface_cout_construction(pre)
  centres <- terra::xyFromCell(pre$mnt, c(
    terra::cellFromRowCol(pre$mnt, 3, 1),
    terra::cellFromRowCol(pre$mnt, 3, 11)
  ))
  pts <- sf::st_as_sf(
    data.frame(id = 1:2, x = centres[, 1], y = centres[, 2]),
    coords = c("x", "y"), crs = 2154
  )
  tr <- tracer_desserte(pre, cout, pts)
  expect_true(tr$faisable)
  expect_s3_class(tr$ligne, "sf")
})

test_that("accepte une matrice de coordonnees comme waypoints", {
  pre <- fake_pre_incline()
  cout <- surface_cout_construction(pre)
  centres <- terra::xyFromCell(pre$mnt, c(
    terra::cellFromRowCol(pre$mnt, 3, 1),
    terra::cellFromRowCol(pre$mnt, 3, 11)
  ))
  tr <- tracer_desserte(pre, cout, centres)
  expect_true(tr$faisable)
})

test_that("moins de deux points de passage -> erreur", {
  pre <- fake_pre_incline()
  cout <- surface_cout_construction(pre)
  expect_error(
    tracer_desserte(pre, cout, terra::cellFromRowCol(pre$mnt, 3, 1)),
    "au moins 2 points"
  )
})

test_that("la configuration du solveur est validee", {
  cfg <- foretaccess_config()
  cfg$desserte$trace$pente_long_max <- 1 # < pente_long_min (2)
  expect_error(validate_config(cfg), "[Pp]ente en long")
})

test_that("le parametrage de tracé est fusionné champ à champ", {
  cfg <- foretaccess_config(desserte = list(trace = list(penalty_xy = 999)))
  expect_equal(cfg$desserte$trace$penalty_xy, 999)
  # Les autres champs gardent leur défaut.
  expect_equal(cfg$desserte$trace$pente_long_max, 12)
  # Le bloc cout n'est pas écrasé.
  expect_equal(cfg$desserte$cout$cout_base_m, 20)
})

test_that("la methode print resume sans erreur", {
  pre <- fake_pre_incline()
  cout <- surface_cout_construction(pre)
  tr <- tracer_desserte(
    pre, cout,
    c(terra::cellFromRowCol(pre$mnt, 3, 1), terra::cellFromRowCol(pre$mnt, 3, 11))
  )
  expect_no_error(print(tr))
  expect_invisible(print(tr))
})
