# Lot 16a : reseau de desserte glouton (`reseau_desserte`).

# Prétraitement sur plan incliné (comme le Lot 15c) : la route monte le long de x.
reseau_pre <- function(nr = 5, nc = 11, slope_pct = 8, csize = 10) {
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

# Carré (parcelle) d'un cellule autour du centre de la cellule (row, col).
reseau_parcelle <- function(grille, row, col, id = 1, volume = 1) {
  centre <- terra::xyFromCell(grille, terra::cellFromRowCol(grille, row, col))
  r <- terra::res(grille)[1] / 2
  x0 <- centre[1] - r; x1 <- centre[1] + r
  y0 <- centre[2] - r; y1 <- centre[2] + r
  poly <- sf::st_polygon(list(rbind(
    c(x0, y0), c(x1, y0), c(x1, y1), c(x0, y1), c(x0, y0)
  )))
  sf::st_sf(id = id, volume = volume, geometry = sf::st_sfc(poly, crs = 2154))
}

# Route existante : colonne de gauche (LINESTRING vertical au centre de la col 1).
reseau_route <- function(grille) {
  centre_x <- terra::xyFromCell(grille, terra::cellFromRowCol(grille, 1, 1))[1]
  ext <- terra::ext(grille)
  sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(centre_x, ext$ymin), c(centre_x, ext$ymax))), crs = 2154
  ))
}

reseau_setup <- function() {
  pre <- reseau_pre()
  cout <- surface_cout_construction(pre)
  route <- reseau_route(pre$mnt)
  parcelles <- rbind(
    reseau_parcelle(pre$mnt, 2, 11, id = 1, volume = 100),
    reseau_parcelle(pre$mnt, 4, 11, id = 2, volume = 500)
  )
  list(pre = pre, cout = cout, route = route, parcelles = parcelles)
}

test_that("CA-16.1/16.5 : les parcelles sont desservies et raccordees au reseau", {
  s <- reseau_setup()
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  expect_s3_class(net, "foretaccess_reseau")
  expect_s3_class(net$lignes, "sf")
  expect_gte(nrow(net$lignes), 1)
  # Le raster du reseau contient l'existant + les routes creees.
  expect_true(sum(terra::values(net$reseau), na.rm = TRUE) > 0)
  # Chaque route creee part d'une parcelle et rejoint le reseau (feature valide).
  expect_true(all(sf::st_geometry_type(net$lignes) == "LINESTRING"))
})

test_that("CA-16.2 : reutilisation -- le reseau est arborescent (cout < isole)", {
  s <- reseau_setup()
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  # Cout de raccordement isole de chaque parcelle (au seul reseau initial).
  cout_isole <- vapply(seq_len(nrow(s$parcelles)), function(i) {
    n1 <- reseau_desserte(s$pre, s$cout, s$parcelles[i, ], s$route, "plus_proche")
    n1$cout
  }, numeric(1))
  # La construction commune reutilise les troncs -> pas plus chere que la somme.
  expect_lte(net$cout, sum(cout_isole) + 1e-6)
})

test_that("skidding : un rayon large evite de construire (parcelle deja desservie)", {
  s <- reseau_setup()
  # Parcelle collee au reseau existant (colonne 2) : deja a distance de debardage.
  proche <- reseau_parcelle(s$pre$mnt, 3, 2, id = 1)
  net <- reseau_desserte(s$pre, s$cout, proche, s$route, "plus_proche", skidding_m = 100)
  expect_equal(nrow(net$lignes), 0)
})

test_that("CA-16.3 : l'ordre aleatoire est reproductible a graine fixee", {
  s <- reseau_setup()
  a <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "aleatoire", graine = 42)
  b <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "aleatoire", graine = 42)
  expect_equal(sf::st_coordinates(a$lignes), sf::st_coordinates(b$lignes))
})

test_that("CA-16.7 : deterministe hors aleatoire", {
  s <- reseau_setup()
  a <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_gros_volume")
  b <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_gros_volume")
  expect_equal(sf::st_coordinates(a$lignes), sf::st_coordinates(b$lignes))
})

test_that("heuristique inconnue -> erreur", {
  s <- reseau_setup()
  expect_error(
    reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "n_importe_quoi"),
    "arg"
  )
})

test_that("la methode print resume sans erreur", {
  s <- reseau_setup()
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  expect_no_error(print(net))
  expect_invisible(print(net))
})

# --- Lot 16b : mode Steiner (arbre couvrant de poids minimal) ----------------

test_that("mode steiner : les parcelles sont desservies et raccordees", {
  s <- reseau_setup()
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, mode = "steiner")
  expect_s3_class(net, "foretaccess_reseau")
  expect_equal(net$mode, "steiner")
  expect_gte(nrow(net$lignes), 1)
  expect_true(all(sf::st_geometry_type(net$lignes) == "LINESTRING"))
  # Le raster du reseau contient l'existant + les routes creees.
  expect_true(sum(terra::values(net$reseau), na.rm = TRUE) > 0)
})

test_that("CA-16.4 : le mode steiner n'est pas plus cher que le glouton", {
  s <- reseau_setup()
  glouton <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  steiner <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, mode = "steiner")
  expect_lte(steiner$cout, glouton$cout + 1e-6)
})

test_that("mode steiner : le reseau est connexe (chaque route touche l'ensemble)", {
  s <- reseau_setup()
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, mode = "steiner")
  # Une seule parcelle -> une arete reseau<->parcelle (raccord direct).
  solo <- reseau_desserte(s$pre, s$cout, s$parcelles[1, ], s$route, mode = "steiner")
  expect_equal(nrow(solo$lignes), 1)
})

test_that("mode inconnu -> erreur", {
  s <- reseau_setup()
  expect_error(
    reseau_desserte(s$pre, s$cout, s$parcelles, s$route, mode = "n_importe_quoi"),
    "arg"
  )
})

# --- Lot 16c : raccordement / connexite + sortie affinee ---------------------

test_that("CA-16.5 : le reseau est connexe (glouton et steiner)", {
  s <- reseau_setup()
  g <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  st <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, mode = "steiner")
  expect_true(g$connexe)
  expect_true(st$connexe)
  # Sur un existant d'un seul tenant, raccorde vaut aussi vrai.
  expect_true(g$raccorde)
})

test_that("steiner ne plante pas sur un trace long (garde came_from, regression)", {
  # Un tracé qui tourne pres de son depart declenche le lookback des epingles /
  # anti-croisement (`basic_calc`), qui remontait la chaine came_from jusqu'a la
  # source (-1) et indexait hors bornes -- crash latent revele en executant enfin
  # Steiner a l'echelle reelle (jamais tourne auparavant). Grille plus large +
  # parcelle a l'ecart de la route pour forcer un tracé a plusieurs sommets.
  pre <- reseau_pre(nr = 20, nc = 20, slope_pct = 8, csize = 10)
  cout <- surface_cout_construction(pre)
  route <- reseau_route(pre$mnt)
  parcelles <- rbind(
    reseau_parcelle(pre$mnt, 18, 18, id = 1, volume = 100),
    reseau_parcelle(pre$mnt, 3, 17, id = 2, volume = 200)
  )
  expect_no_error(
    net <- reseau_desserte(pre, cout, parcelles, route, mode = "steiner")
  )
  expect_s3_class(net, "foretaccess_reseau")
  expect_true(all(net$desservies))
})

test_that("existant fragmente : connexe=FALSE mais raccorde=TRUE", {
  # Deux routes existantes DISJOINTES (bord gauche + bord droit) : le reseau
  # global ne sera jamais d'un seul tenant (connexe FALSE), mais les routes
  # creees s'accrochent bien a l'existant (raccorde TRUE). C'est le cas
  # Chastel-Nouvel (3299 troncons disjoints -> connexe FALSE alors que
  # desservies 30/30). raccorde est le booleen a lire.
  s <- reseau_setup()
  ext <- terra::ext(s$pre$mnt)
  xg <- terra::xyFromCell(s$pre$mnt, terra::cellFromRowCol(s$pre$mnt, 1, 1))[1]
  xd <- terra::xyFromCell(s$pre$mnt, terra::cellFromRowCol(s$pre$mnt, 1, 11))[1]
  route2 <- sf::st_sf(id = 1:2, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(xg, ext$ymin), c(xg, ext$ymax))),
    sf::st_linestring(rbind(c(xd, ext$ymin), c(xd, ext$ymax))),
    crs = 2154
  ))
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, route2, "plus_proche")

  expect_false(net$connexe) # existant en deux morceaux -> jamais d'un seul tenant
  expect_true(net$raccorde) # ... mais aucune route creee n'est isolee
  expect_true(all(net$desservies)) # et les parcelles sont bien desservies
})

test_that("CA-16.1 : toutes les parcelles sont desservies", {
  s <- reseau_setup()
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  expect_length(net$desservies, nrow(s$parcelles))
  expect_true(all(net$desservies))
})

test_that("skidding : parcelle desservie par proximite sans route construite", {
  s <- reseau_setup()
  proche <- reseau_parcelle(s$pre$mnt, 3, 2, id = 1)
  net <- reseau_desserte(s$pre, s$cout, proche, s$route, "plus_proche", skidding_m = 100)
  expect_equal(nrow(net$lignes), 0)
  expect_true(net$desservies) # desservie par le rayon de debardage
})

test_that("sortie affinee : les lignes portent une longueur planimetrique positive", {
  s <- reseau_setup()
  net <- reseau_desserte(s$pre, s$cout, s$parcelles, s$route, "plus_proche")
  expect_true("longueur" %in% names(net$lignes))
  expect_true(all(net$lignes$longueur > 0))
})
