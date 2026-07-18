# Fixtures pour le Lot 10 (acquisition depuis AOI), en memoire.
#
# Les appels reseau (happign / osmdata) sont mockes via local_mocked_bindings :
# ces fixtures fournissent des retours deterministes, sans reseau.

# AOI de test : carre de 1 km en Lambert-93.
aoi_test <- function() {
  e <- rbind(
    c(700000, 6600000), c(701000, 6600000),
    c(701000, 6601000), c(700000, 6601000), c(700000, 6600000)
  )
  sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_polygon(list(e)), crs = 2154))
}

# Retour WFS simule pour la desserte : deux troncons avec un attribut `nature`
# accentue (une route, un chemin), traversant l'AOI.
roads_fixture <- function() {
  l1 <- sf::st_linestring(rbind(c(700200, 6600200), c(700800, 6600800)))
  l2 <- sf::st_linestring(rbind(c(700200, 6600800), c(700800, 6600200)))
  sf::st_sf(
    nature = c("Route \u00e0 1 chauss\u00e9e", "Chemin"),
    geometry = sf::st_sfc(l1, l2, crs = 2154)
  )
}

# Retour WFS simule pour un jeu de polygones (foret / cadastre), chevauchant l'AOI.
polys_fixture <- function() {
  p1 <- sf::st_polygon(list(rbind(
    c(700300, 6600300), c(700700, 6600300),
    c(700700, 6600700), c(700300, 6600700), c(700300, 6600300)
  )))
  sf::st_sf(id = 1, geometry = sf::st_sfc(p1, crs = 2154))
}

# Retour osmdata_sf simule : un batiment (polygone) et une voie (ligne).
osmdata_fixture <- function() {
  poly <- sf::st_sf(osm_id = "1", geometry = sf::st_sfc(sf::st_polygon(list(rbind(
    c(700400, 6600400), c(700600, 6600400),
    c(700600, 6600600), c(700400, 6600600), c(700400, 6600400)
  ))), crs = 2154))
  line <- sf::st_sf(osm_id = "2", geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(700100, 6600500), c(700900, 6600500))), crs = 2154))
  list(osm_points = NULL, osm_lines = line, osm_polygons = poly, osm_multipolygons = NULL)
}

# Retour osmdata_sf simule : une piste DFCI (ligne) portant `ref:FR:DFCI`,
# traversant l'AOI d'ouest en est. Coordonnees en L93 (comme osmdata_fixture :
# les fixtures simulent un osmdata deja dans le CRS cible).
osmdata_dfci_fixture <- function() {
  ln <- sf::st_sf(osm_id = "10", geometry = sf::st_sfc(
    sf::st_linestring(rbind(c(700100, 6600500), c(700900, 6600500))), crs = 2154))
  ln[["ref:FR:DFCI"]] <- "AL 04"
  list(osm_points = NULL, osm_lines = ln, osm_polygons = NULL, osm_multipolygons = NULL)
}

# Retour osmdata_sf simule : une aire de retournement (point) au centre de l'AOI.
osmdata_retournement_fixture <- function() {
  pt <- sf::st_sf(osm_id = "20",
    geometry = sf::st_sfc(sf::st_point(c(700500, 6600500)), crs = 2154))
  list(osm_points = pt, osm_lines = NULL, osm_polygons = NULL, osm_multipolygons = NULL)
}

# Desserte de repli : trois pistes alignees P1-P2-P3-P4 (noeuds a 100 m). La piste
# centrale est traversante (deg 2/2), les deux autres en cul-de-sac (bout pendant
# en P1 et P4). `largeur2` fixe l'emprise de la piste centrale.
desserte_repli_fixture <- function(largeur2 = 12) {
  l1 <- sf::st_linestring(rbind(c(0, 0), c(100, 0)))
  l2 <- sf::st_linestring(rbind(c(100, 0), c(200, 0)))
  l3 <- sf::st_linestring(rbind(c(200, 0), c(300, 0)))
  sf::st_sf(
    classe  = c("piste", "piste", "piste"),
    largeur = c(NA_real_, largeur2, NA_real_),
    geometry = sf::st_sfc(l1, l2, l3, crs = 2154)
  )
}

# Aire de retournement au bout pendant P4 de la desserte de repli.
retournement_p4_fixture <- function() {
  sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(300, 0)), crs = 2154))
}

# Garde-fou des tests reseau : opt-in explicite + hors CI par defaut.
# (comme le garde-fou PostGIS). Ne tourne que si FORETACCESS_RUN_ONLINE_TESTS=TRUE.
skip_if_no_online <- function() {
  if (!identical(Sys.getenv("FORETACCESS_RUN_ONLINE_TESTS"), "TRUE")) {
    testthat::skip("FORETACCESS_RUN_ONLINE_TESTS != TRUE (tests reseau opt-in)")
  }
  for (pkg in c("happign", "osmdata")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      testthat::skip(paste(pkg, "non disponible"))
    }
  }
  testthat::skip_if_offline()
}

# Ecrit un petit MNT dans `filename` (mock de .fetch_wms_raster).
mnt_fixture_writer <- function(aoi, layer, res, crs, filename) {
  r <- terra::rast(terra::ext(terra::vect(aoi)), resolution = res, crs = paste0("EPSG:", crs))
  terra::values(r) <- seq_len(terra::ncell(r))
  terra::writeRaster(r, filename, overwrite = TRUE)
  r
}
