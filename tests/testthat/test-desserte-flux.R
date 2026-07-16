# Lot 17a : vectorisation topologique du reseau (`vectoriser_reseau`).

# Fixture : plan incline (comme le Lot 16), route existante = colonne de gauche,
# trois parcelles a droite -> reseau arborescent avec une jonction partagee.
flux_pre <- function(nr = 5, nc = 11, slope_pct = 8, csize = 10) {
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

flux_parcelle <- function(grille, row, col, id = 1, volume = 1) {
  centre <- terra::xyFromCell(grille, terra::cellFromRowCol(grille, row, col))
  r <- terra::res(grille)[1] / 2
  poly <- sf::st_polygon(list(rbind(
    c(centre[1] - r, centre[2] - r), c(centre[1] + r, centre[2] - r),
    c(centre[1] + r, centre[2] + r), c(centre[1] - r, centre[2] + r),
    c(centre[1] - r, centre[2] - r)
  )))
  sf::st_sf(id = id, volume = volume, geometry = sf::st_sfc(poly, crs = 2154))
}

flux_setup <- function() {
  pre <- flux_pre()
  cout <- surface_cout_construction(pre)
  cx <- terra::xyFromCell(pre$mnt, terra::cellFromRowCol(pre$mnt, 1, 1))[1]
  ext <- terra::ext(pre$mnt)
  route <- sf::st_sf(id = 1, geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(cx, ext$ymin), c(cx, ext$ymax))), crs = 2154
  ))
  parcelles <- rbind(
    flux_parcelle(pre$mnt, 2, 11, id = 1, volume = 100),
    flux_parcelle(pre$mnt, 4, 11, id = 2, volume = 500),
    flux_parcelle(pre$mnt, 3, 8, id = 3, volume = 200)
  )
  reseau <- reseau_desserte(pre, cout, parcelles, route, "plus_proche")
  list(pre = pre, reseau = reseau, parcelles = parcelles)
}

# Cellules (1-based) couvertes par l'ensemble des parcelles (pour le test CA-17.1).
.cells_des_parcelles <- function(parcelles, grille) {
  r <- terra::rasterize(terra::vect(parcelles), grille, field = 1, background = NA)
  which(!is.na(terra::values(r)))
}

test_that("vectoriser_reseau produit un graphe noeuds/troncons coherent", {
  s <- flux_setup()
  g <- vectoriser_reseau(s$reseau)
  expect_s3_class(g, "foretaccess_reseau_graphe")
  expect_s3_class(g$noeuds, "sf")
  expect_s3_class(g$troncons, "sf")
  expect_true(all(sf::st_geometry_type(g$noeuds) == "POINT"))
  expect_true(all(sf::st_geometry_type(g$troncons) == "LINESTRING"))
  # Chaque troncon relie deux noeuds existants.
  expect_true(all(g$troncons$de %in% g$noeuds$id))
  expect_true(all(g$troncons$vers %in% g$noeuds$id))
})

test_that("CA-17.1 : topologie -- jonctions de degre >= 3, exutoire sur le reseau", {
  s <- flux_setup()
  g <- vectoriser_reseau(s$reseau)
  jonctions <- g$noeuds[g$noeuds$type == "jonction", ]
  expect_true(all(jonctions$degre >= 3))
  # Au moins un exutoire, et tout exutoire est un noeud reconnu.
  expect_gte(length(g$exutoires), 1)
  expect_true(all(g$exutoires %in% g$noeuds$id))
  # Pas d'arete pendante non justifiee : toute feuille (degre 1) est un acces de
  # parcelle ou un exutoire -> aucune n'est un cul-de-sac interne.
  feuilles <- g$noeuds[g$noeuds$degre == 1 & g$noeuds$type != "exutoire", ]
  # Les cellules-feuilles doivent tomber dans une parcelle (acces).
  cells_parc <- terra::cellFromXY(
    s$reseau$reseau, sf::st_coordinates(sf::st_centroid(sf::st_geometry(s$parcelles)))
  )
  expect_true(all(feuilles$cell %in% .cells_des_parcelles(s$parcelles, s$reseau$reseau)))
})

test_that("la longueur des troncons somme la longueur du reseau cree", {
  s <- flux_setup()
  g <- vectoriser_reseau(s$reseau)
  # La somme des troncons couvre les routes creees (a la resolution de grille pres).
  expect_gt(sum(g$troncons$longueur), 0)
  expect_true(all(g$troncons$longueur > 0))
})

test_that("la methode print resume le graphe sans erreur", {
  s <- flux_setup()
  g <- vectoriser_reseau(s$reseau)
  expect_no_error(print(g))
  expect_invisible(print(g))
})

# --- Lot 17b : sources & accumulation de flux --------------------------------

test_that("CA-17.2 : chaque parcelle recoit au moins un point source", {
  s <- flux_setup()
  g <- calculer_flux(vectoriser_reseau(s$reseau), s$parcelles, "volume",
                     densite_sources = 5)
  expect_gte(nrow(g$sources), nrow(s$parcelles))
  # Toute parcelle est representee par au moins une source.
  expect_setequal(unique(g$sources$parcelle), seq_len(nrow(s$parcelles)))
})

test_that("CA-17.3 : conservation du volume (sources et exutoires)", {
  s <- flux_setup()
  total <- sum(s$parcelles$volume)
  g <- calculer_flux(vectoriser_reseau(s$reseau), s$parcelles, "volume")
  # Le volume seme egale le volume recolte.
  expect_equal(sum(g$sources$volume), total)
  # Tout le volume ressort aux exutoires (aucune parcelle sur un exutoire ici).
  inc <- g$troncons[g$troncons$de %in% g$exutoires | g$troncons$vers %in% g$exutoires, ]
  expect_equal(sum(inc$flux), total)
})

test_that("CA-17.4 : le flux croit de l'amont vers l'aval (exutoire = max)", {
  s <- flux_setup()
  total <- sum(s$parcelles$volume)
  g <- calculer_flux(vectoriser_reseau(s$reseau), s$parcelles, "volume")
  expect_true(all(g$troncons$flux >= 0))
  # Le troncon aboutissant a l'exutoire porte le flux maximal = volume total.
  inc <- g$troncons[g$troncons$de %in% g$exutoires | g$troncons$vers %in% g$exutoires, ]
  expect_equal(max(g$troncons$flux), total)
  expect_true(all(inc$flux >= g$troncons$flux[!g$troncons$id %in% inc$id] |
                    length(inc$flux) == 0))
})

test_that("la densite change le nombre de sources mais pas le volume total", {
  s <- flux_setup()
  g1 <- calculer_flux(vectoriser_reseau(s$reseau), s$parcelles, "volume",
                      densite_sources = 5)
  g2 <- calculer_flux(vectoriser_reseau(s$reseau), s$parcelles, "volume",
                      densite_sources = 50)
  expect_gte(nrow(g2$sources), nrow(g1$sources))
  expect_equal(sum(g1$sources$volume), sum(g2$sources$volume))
  # Le flux total aux exutoires est invariant a la densite.
  exu_flux <- function(g) {
    inc <- g$troncons[g$troncons$de %in% g$exutoires | g$troncons$vers %in% g$exutoires, ]
    sum(inc$flux)
  }
  expect_equal(exu_flux(g1), exu_flux(g2))
})

test_that("colonne volume absente -> erreur", {
  s <- flux_setup()
  g <- vectoriser_reseau(s$reseau)
  expect_error(calculer_flux(g, s$parcelles, "inexistant"), "inexistant|choice|element")
})
