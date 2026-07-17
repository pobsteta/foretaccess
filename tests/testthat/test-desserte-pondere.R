# Ponderation du trace par la surface de coût €/m (Lot 14 consommee par le solveur).

# Terrain plat + surface de coût avec un corridor bon marche sur la ligne du haut.
pondere_setup <- function(nr = 5, nc = 9, csize = 10) {
  mnt <- terra::rast(
    nrows = nr, ncols = nc, xmin = 0, xmax = nc * csize, ymin = 0, ymax = nr * csize,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 0 # terrain plat
  names(mnt) <- "mnt"
  slope <- terra::rast(mnt)
  terra::values(slope) <- 0
  names(slope) <- "slope_pct"
  obst <- terra::rast(mnt)
  terra::values(obst) <- 0
  names(obst) <- "obstacles_complets_mask"
  pre <- structure(
    list(mnt = mnt, slope_pct = slope, obstacles_complets_mask = obst),
    class = "foretaccess_preprocessing"
  )

  # Surface de coût : cher (10) partout sauf la ligne du haut (1), bon marche.
  franch <- terra::rast(mnt)
  terra::values(franch) <- 1
  names(franch) <- "franchissable"
  cr <- terra::rast(mnt)
  vals <- matrix(10, nrow = nr, ncol = nc)
  vals[1, ] <- 1 # ligne 0 (haut) bon marche
  terra::values(cr) <- as.numeric(t(vals))
  names(cr) <- "cout"
  cout <- structure(list(cout = cr, franchissable = franch),
                    class = "foretaccess_cout_construction")

  # Config autorisant les segments a plat (pente longitudinale min = 0).
  cfg <- foretaccess_config()
  cfg$desserte$trace$pente_long_min <- 0
  list(pre = pre, cout = cout, config = cfg)
}

test_that("pondere_cout = FALSE reproduit le trace geometrique (defaut)", {
  s <- pondere_setup()
  wps <- c(
    terra::cellFromRowCol(s$pre$mnt, 3, 1),
    terra::cellFromRowCol(s$pre$mnt, 3, 9)
  )
  t_neu <- tracer_desserte(s$pre, s$cout, wps, config = s$config)
  expect_true(t_neu$faisable)
  # Sans ponderation, le trace direct reste sur sa ligne (n'a aucune raison de
  # remonter vers le corridor bon marche).
  y_neu <- sf::st_coordinates(t_neu$ligne)[, "Y"]
  y_haut <- terra::ext(s$pre$mnt)$ymax
  expect_true(max(y_neu) < y_haut - 1e-6)
})

test_that("pondere_cout = TRUE detourne le trace par le corridor bon marche", {
  s <- pondere_setup()
  wps <- c(
    terra::cellFromRowCol(s$pre$mnt, 3, 1),
    terra::cellFromRowCol(s$pre$mnt, 3, 9)
  )
  t_neu <- tracer_desserte(s$pre, s$cout, wps, pondere_cout = FALSE, config = s$config)
  t_pon <- tracer_desserte(s$pre, s$cout, wps, pondere_cout = TRUE, config = s$config)
  expect_true(t_pon$faisable)
  # Le trace pondere emprunte la ligne du haut (bon marche) : il monte plus haut.
  y_neu <- sf::st_coordinates(t_neu$ligne)[, "Y"]
  y_pon <- sf::st_coordinates(t_pon$ligne)[, "Y"]
  expect_gt(max(y_pon), max(y_neu))
  # Les deux traces different geometriquement.
  expect_false(isTRUE(all.equal(
    sf::st_coordinates(t_neu$ligne), sf::st_coordinates(t_pon$ligne)
  )))
})

test_that("reseau_desserte accepte pondere_cout sans regression", {
  s <- pondere_setup()
  cx <- terra::xyFromCell(s$pre$mnt, terra::cellFromRowCol(s$pre$mnt, 1, 1))[1]
  ext <- terra::ext(s$pre$mnt)
  route <- sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(cx, ext$ymin), c(cx, ext$ymax))), crs = 2154
  ))
  centre <- terra::xyFromCell(s$pre$mnt, terra::cellFromRowCol(s$pre$mnt, 1, 9))
  r <- terra::res(s$pre$mnt)[1] / 2
  parc <- sf::st_sf(id = 1, volume = 100, geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(centre[1] - r, centre[2] - r), c(centre[1] + r, centre[2] - r),
    c(centre[1] + r, centre[2] + r), c(centre[1] - r, centre[2] + r),
    c(centre[1] - r, centre[2] - r)
  ))), crs = 2154))
  net <- reseau_desserte(s$pre, s$cout, parc, route, "plus_proche",
                         pondere_cout = TRUE, config = s$config)
  expect_s3_class(net, "foretaccess_reseau")
  expect_true(all(net$desservies))
})
