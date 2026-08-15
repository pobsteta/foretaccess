# Lot 18a : optimisation multi-start du reseau (`optimiser_reseau`).

optim_pre <- function(nr = 5, nc = 11, slope_pct = 8, csize = 10) {
  mnt <- terra::rast(
    nrows = nr, ncols = nc, xmin = 0, xmax = nc * csize, ymin = 0, ymax = nr * csize,
    crs = "EPSG:2154"
  )
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  col <- terra::colFromX(mnt, xy[, 1]) - 1L
  terra::values(mnt) <- col * slope_pct / 100 * csize
  names(mnt) <- "mnt"
  slope <- terra::rast(mnt)
  terra::values(slope) <- slope_pct
  names(slope) <- "slope_pct"
  obst <- terra::rast(mnt)
  terra::values(obst) <- 0
  names(obst) <- "obstacles_complets_mask"
  structure(list(mnt = mnt, slope_pct = slope, obstacles_complets_mask = obst),
            class = "foretaccess_preprocessing")
}

optim_parcelle <- function(grille, row, col, id = 1, volume = 1) {
  centre <- terra::xyFromCell(grille, terra::cellFromRowCol(grille, row, col))
  r <- terra::res(grille)[1] / 2
  poly <- sf::st_polygon(list(rbind(
    c(centre[1] - r, centre[2] - r), c(centre[1] + r, centre[2] - r),
    c(centre[1] + r, centre[2] + r), c(centre[1] - r, centre[2] + r),
    c(centre[1] - r, centre[2] - r)
  )))
  sf::st_sf(id = id, volume = volume, geometry = sf::st_sfc(poly, crs = 2154))
}

optim_setup <- function() {
  pre <- optim_pre()
  cout <- surface_cout_construction(pre)
  cx <- terra::xyFromCell(pre$mnt, terra::cellFromRowCol(pre$mnt, 1, 1))[1]
  ext <- terra::ext(pre$mnt)
  route <- sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(cx, ext$ymin), c(cx, ext$ymax))), crs = 2154
  ))
  parcelles <- rbind(
    optim_parcelle(pre$mnt, 2, 11, id = 1, volume = 100),
    optim_parcelle(pre$mnt, 4, 11, id = 2, volume = 500),
    optim_parcelle(pre$mnt, 3, 8, id = 3, volume = 200),
    optim_parcelle(pre$mnt, 5, 10, id = 4, volume = 150)
  )
  list(pre = pre, cout = cout, route = route, parcelles = parcelles)
}

test_that("CA-18.1 : le multi-start n'est jamais pire que le glouton simple", {
  s <- optim_setup()
  glou <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "multistart",
                          n_start = 12, graine = 7)
  expect_s3_class(opt, "foretaccess_reseau")
  expect_lte(opt$cout, glou$cout + 1e-6)
  # L'essai 0 est l'ordre de base -> son cout est celui du glouton.
  expect_equal(opt$journal[1], glou$cout)
  # Le meilleur reseau correspond au minimum du journal.
  expect_equal(opt$cout, min(opt$journal))
  expect_length(opt$journal, 12)
})

test_that("CA-18.2 : reproductible a graine fixee", {
  s <- optim_setup()
  a <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "multistart",
                        n_start = 10, graine = 3)
  b <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "multistart",
                        n_start = 10, graine = 3)
  expect_equal(a$journal, b$journal)
  expect_equal(sf::st_coordinates(a$lignes), sf::st_coordinates(b$lignes))
})

test_that("le multi-start explore reellement plusieurs ordres", {
  s <- optim_setup()
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "multistart",
                          n_start = 12, graine = 7)
  # Au moins deux couts distincts dans le journal (des ordres differents).
  expect_gt(length(unique(round(opt$journal, 6))), 1)
})

test_that("CA-18.5 : le reseau optimise reste valide (desservi, connexe)", {
  s <- optim_setup()
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "multistart",
                          n_start = 8, graine = 1)
  expect_true(all(opt$desservies))
  expect_true(opt$connexe)
  expect_equal(opt$strategie, "multistart")
})

# --- Lot 18c : rip-up & reroute ----------------------------------------------

test_that("CA-18.1 : le rip-up & reroute n'est jamais pire que le glouton", {
  s <- optim_setup()
  glou <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "riprute",
                          max_passes = 6)
  expect_s3_class(opt, "foretaccess_reseau")
  expect_lte(opt$cout, glou$cout + 1e-6)
  expect_equal(opt$strategie, "riprute")
})

test_that("CA-18.4 : le journal du rip-up est monotone decroissant", {
  s <- optim_setup()
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "riprute",
                          max_passes = 6)
  expect_gte(length(opt$journal), 1)
  expect_true(all(diff(opt$journal) <= 1e-9))
})

test_that("CA-18.2/18.5 : rip-up deterministe et reseau valide", {
  s <- optim_setup()
  a <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "riprute", max_passes = 6)
  b <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "riprute", max_passes = 6)
  expect_equal(sf::st_coordinates(a$lignes), sf::st_coordinates(b$lignes))
  expect_true(all(a$desservies))
  expect_true(a$connexe)
})

# --- Lot 18b : recuit simule -------------------------------------------------

test_that("CA-18.1 : le recuit n'est jamais pire que le glouton simple", {
  s <- optim_setup()
  glou <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "recuit",
                          n_iter = 40, graine = 7)
  expect_s3_class(opt, "foretaccess_reseau")
  expect_lte(opt$cout, glou$cout + 1e-6)
  expect_equal(opt$strategie, "recuit")
})

test_that("CA-18.4 : la courbe de convergence du recuit est monotone decroissante", {
  s <- optim_setup()
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "recuit",
                          n_iter = 50, graine = 3)
  expect_length(opt$journal, 50)
  # Le meilleur cout rencontre ne remonte jamais.
  expect_true(all(diff(opt$journal) <= 1e-9))
  # Le cout final egale le minimum du journal.
  expect_equal(opt$cout, min(opt$journal))
})

test_that("CA-18.2 : recuit reproductible a graine fixee", {
  s <- optim_setup()
  a <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "recuit",
                        n_iter = 30, graine = 5)
  b <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "recuit",
                        n_iter = 30, graine = 5)
  expect_equal(a$journal, b$journal)
  expect_equal(sf::st_coordinates(a$lignes), sf::st_coordinates(b$lignes))
})

test_that("CA-18.5 : le reseau du recuit reste valide (desservi, connexe)", {
  s <- optim_setup()
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "recuit",
                          n_iter = 30, graine = 1)
  expect_true(all(opt$desservies))
  expect_true(opt$connexe)
})

test_that("la methode print affiche la strategie", {
  s <- optim_setup()
  opt <- optimiser_reseau(s$pre, s$cout, s$parcelles, s$route, "multistart",
                          n_start = 6, graine = 2)
  expect_no_error(print(opt))
  expect_invisible(print(opt))
})

test_that("CA-28.4 : optimiser_reseau refuse aussi un candidat non qualifie", {
  # Les deux entrees partagent `.reseau_preparer()` : l'invariant ne doit pas
  # pouvoir etre contourne en passant par l'optimisation.
  s <- optim_setup()
  osm <- s$route
  osm$source <- "osm"
  expect_error(
    optimiser_reseau(s$pre, s$cout, s$parcelles, osm, "multistart",
                     n_start = 2, graine = 1),
    "CA-28.4")
})
