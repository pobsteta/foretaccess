# `pondere_cout = FALSE` (le defaut, parite SylvaRoad) n'utilise de `cout` que le
# masque `franchissable` : la surface EUR/m est calculee, payee, et JETEE.
#
# Le defaut ne change pas -- basculer casserait la parite SylvaRoad du Lot 15 et
# modifierait tous les traces existants. Mais il ne se suppose plus en silence :
# un appelant qui construit une surface de cout ne le fait pas pour son masque.
# Signale par le brief dessertR du 2026-08-11, ou le defaut avait produit des
# traces purement geometriques pendant des mois chez un appelant qui croyait
# ponderer.

# Grille minimale : deux moities de pente differente, donc une surface de cout
# qui VARIE (une surface constante ne changerait aucun trace).
pre_deux_pentes <- function() {
  mnt <- terra::rast(nrows = 4, ncols = 4, xmin = 0, xmax = 20, ymin = 0,
                     ymax = 20, crs = "EPSG:2154")
  terra::values(mnt) <- 100
  names(mnt) <- "mnt"
  sp <- terra::rast(mnt)
  terra::values(sp) <- rep(c(5, 5, 20, 20), each = 4)  # 0 EUR/m puis 25 EUR/m
  names(sp) <- "slope_pct"
  ob <- terra::rast(mnt)
  terra::values(ob) <- 0
  names(ob) <- "obstacles_complets_mask"
  structure(list(mnt = mnt, slope_pct = sp, obstacles_complets_mask = ob),
            class = "foretaccess_preprocessing")
}

test_that("une surface de cout VARIABLE laissee sans ponderation avertit", {
  cout <- surface_cout_construction(pre_deux_pentes())
  expect_warning(
    foretaccess:::.avertir_cout_ignore(cout, pondere_cout = FALSE, explicite = FALSE),
    "ignor"
  )
})

test_that("passer le drapeau EXPLICITEMENT n'avertit pas", {
  # Le silence n'est pas un choix ; un `FALSE` ecrit l'est. C'est la sortie
  # documentee pour garder la geometrie pure sans bruit.
  cout <- surface_cout_construction(pre_deux_pentes())
  expect_no_warning(
    foretaccess:::.avertir_cout_ignore(cout, pondere_cout = FALSE, explicite = TRUE)
  )
  expect_no_warning(
    foretaccess:::.avertir_cout_ignore(cout, pondere_cout = TRUE, explicite = FALSE)
  )
})

test_that("une surface CONSTANTE n'avertit pas -- elle ne changerait aucun trace", {
  # Le solveur minimise un cout relatif : un facteur constant est sans effet.
  # Avertir ici serait du bruit sur le cas le plus courant (cout de base seul).
  plat <- pre_deux_pentes()
  terra::values(plat$slope_pct) <- 5
  cout <- surface_cout_construction(plat)
  expect_no_warning(
    foretaccess:::.avertir_cout_ignore(cout, pondere_cout = FALSE, explicite = FALSE)
  )
})

# Fixture de reseau : plan incline, route a gauche, une parcelle a droite. La
# pente VARIE par colonne, sans quoi la surface de cout serait constante et
# l'avertissement resterait muet a bon droit.
pondere_setup <- function(nr = 5, nc = 11, csize = 10) {
  mnt <- terra::rast(nrows = nr, ncols = nc, xmin = 0, xmax = nc * csize,
                     ymin = 0, ymax = nr * csize, crs = "EPSG:2154")
  xy <- terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))
  col <- terra::colFromX(mnt, xy[, 1]) - 1L
  terra::values(mnt) <- col * 0.08 * csize
  names(mnt) <- "mnt"
  slope <- terra::rast(mnt)
  # 5 % a gauche, 20 % a droite : deux classes du bareme, donc un cout variable.
  terra::values(slope) <- ifelse(col < nc / 2, 5, 20)
  names(slope) <- "slope_pct"
  obst <- terra::rast(mnt)
  terra::values(obst) <- 0
  names(obst) <- "obstacles_complets_mask"
  pre <- structure(list(mnt = mnt, slope_pct = slope,
                        obstacles_complets_mask = obst),
                   class = "foretaccess_preprocessing")

  centre_x <- terra::xyFromCell(mnt, terra::cellFromRowCol(mnt, 1, 1))[1]
  ext <- terra::ext(mnt)
  route <- sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(centre_x, ext$ymin), c(centre_x, ext$ymax))),
    crs = 2154))

  centre <- terra::xyFromCell(mnt, terra::cellFromRowCol(mnt, 3, 10))
  r <- csize / 2
  poly <- sf::st_polygon(list(rbind(
    c(centre[1] - r, centre[2] - r), c(centre[1] + r, centre[2] - r),
    c(centre[1] + r, centre[2] + r), c(centre[1] - r, centre[2] + r),
    c(centre[1] - r, centre[2] - r))))
  parcelles <- sf::st_sf(id = 1, volume = 100,
                         geometry = sf::st_sfc(poly, crs = 2154))

  list(pre = pre, cout = surface_cout_construction(pre),
       route = route, parcelles = parcelles)
}

test_that("le defaut de reseau_desserte() avertit, l'appel explicite non", {
  s <- pondere_setup()
  expect_warning(reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche"),
                 "ignor")
  expect_no_warning(
    reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche",
                    pondere_cout = FALSE)
  )
})

test_that("tracer_desserte() suit la meme regle", {
  s <- pondere_setup()
  wp <- c(terra::cellFromRowCol(s$pre$mnt, 3, 1),
          terra::cellFromRowCol(s$pre$mnt, 3, 10))
  expect_warning(tracer_desserte(s$pre, s$cout, wp), "ignor")
  expect_no_warning(tracer_desserte(s$pre, s$cout, wp, pondere_cout = FALSE))
})
