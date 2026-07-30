# Diagnostic : que contient OSM que la BD TOPO n'a pas, et reciproquement ?
#
# POURQUOI : la spec 026 cherche la desserte ABSENTE de la reference. La detection
# LiDAR (dsr_detecter) en est une source ; OSM en est une autre, deja vectorisee
# et attribuee, donc bien moins couteuse a exploiter et sans faux positifs
# geomorphologiques. Encore faut-il savoir ce qu'elle apporte reellement.
#
# Ce script ne conclut pas a la place de l'analyste : il mesure du LINEAIRE, par
# type OSM, dedans/dehors d'un corridor autour de la BD TOPO. Un lineaire OSM
# hors corridor n'est PAS ipso facto une desserte manquante -- ce peut etre un
# sentier de randonnee, une trace erronee, ou un decalage de saisie. C'est un
# GISEMENT A INSTRUIRE, pas un resultat.
#
# Usage : Rscript data-raw/diag_osm_vs_bdtopo.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  library(osmdata)
  pkgload::load_all(quiet = TRUE)
})

AOI <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
CACHE <- Sys.getenv("ACCESSFOR_CACHE", "/tmp/accessfor-cache")
CORRIDOR_M <- 15 # demi-largeur du corridor BD TOPO (celui de dsr_detecter)

# --- 1. BD TOPO -------------------------------------------------------------
bdt <- acquire_desserte(st_buffer(AOI, 100), cache_dir = CACHE)
bdt <- bdt[lengths(st_intersects(st_geometry(bdt), st_geometry(AOI))) > 0, ]
cat(sprintf("BD TOPO : %d troncons | %.2f km\n", nrow(bdt),
  sum(as.numeric(st_length(bdt))) / 1000))
print(table(bdt$classe))

# --- 2. OSM -----------------------------------------------------------------
# Une seule requete : `highway` toutes valeurs. Overpass nous throttle des qu'on
# multiplie les appels, et filtrer en local coute moins cher qu'un aller-retour.
bb <- st_bbox(st_transform(AOI, 4326))
# Passe par .fetch_osm() : rotation d'instances Overpass, l'instance par defaut
# refusant toute requete apres une session active.
osm <- foretaccess:::.fetch_osm(bb, key = "highway", timeout = 180)
lignes <- osm$osm_lines
if (is.null(lignes) || nrow(lignes) == 0) {
  cat("\nAUCUNE ligne OSM sur l'emprise -- rien a comparer.\n")
  quit(status = 0)
}
lignes <- st_transform(lignes, 2154)
lignes <- lignes[lengths(st_intersects(st_geometry(lignes), st_geometry(AOI))) > 0, ]
lignes$long_m <- as.numeric(st_length(lignes))
cat(sprintf("\nOSM : %d lignes | %.2f km\n", nrow(lignes),
  sum(lignes$long_m) / 1000))
cat("\n--- lineaire OSM par type (km) ---\n")
print(round(tapply(lignes$long_m, lignes$highway, sum) / 1000, 2))

# --- 3. Recoupement ---------------------------------------------------------
# Corridor autour de la BD TOPO : ce qui tombe dedans est deja connu.
corr <- st_union(st_buffer(st_geometry(bdt), CORRIDOR_M))
dedans <- st_intersection(st_geometry(lignes), corr)
l_dedans <- if (length(dedans)) sum(as.numeric(st_length(dedans))) else 0
l_total <- sum(lignes$long_m)
cat(sprintf("\n--- OSM vs corridor BD TOPO (%d m) ---\n", CORRIDOR_M))
cat(sprintf("  deja couvert par la BD TOPO : %.2f km (%.1f %%)\n",
  l_dedans / 1000, 100 * l_dedans / l_total))
cat(sprintf("  HORS corridor              : %.2f km (%.1f %%)\n",
  (l_total - l_dedans) / 1000, 100 * (l_total - l_dedans) / l_total))

# Par type : c'est la ventilation qui dit si le gisement est exploitable. Un
# `track` hors corridor est un candidat serieux ; un `path` ou un `footway`
# beaucoup moins.
cat("\n--- lineaire OSM HORS corridor, par type (km) ---\n")
hors <- st_difference(st_geometry(lignes), corr)
idx <- which(lengths(st_intersects(st_geometry(lignes), corr)) == 0 |
  lengths(st_intersects(st_geometry(lignes), corr)) > 0)
lignes$hors_m <- 0
d2 <- st_difference(st_geometry(lignes), corr)
# st_difference conserve l'ordre des entrees non vides : on reattribue par index.
if (length(d2)) {
  gardes <- attr(d2, "idx")
  if (is.null(gardes)) {
    # Repli robuste : recalcul un a un (couteux mais sur).
    for (i in seq_len(nrow(lignes))) {
      g <- st_difference(st_geometry(lignes)[i], corr)
      lignes$hors_m[i] <- if (length(g)) as.numeric(st_length(g)) else 0
    }
  } else {
    lignes$hors_m[gardes[, 1]] <- as.numeric(st_length(d2))
  }
}
print(round(tapply(lignes$hors_m, lignes$highway, sum) / 1000, 2))

# --- 4. Le sens inverse -----------------------------------------------------
corr_osm <- st_union(st_buffer(st_geometry(lignes), CORRIDOR_M))
bdt$hors_m <- 0
for (i in seq_len(nrow(bdt))) {
  g <- st_difference(st_geometry(bdt)[i], corr_osm)
  bdt$hors_m[i] <- if (length(g)) as.numeric(st_length(g)) else 0
}
cat("\n--- lineaire BD TOPO HORS corridor OSM, par classe (km) ---\n")
print(round(tapply(bdt$hors_m, bdt$classe, sum) / 1000, 2))

st_write(lignes[lignes$hors_m > 50, ], "data-raw/oracle/aoi/osm_hors_bdtopo.gpkg",
  delete_dsn = TRUE, quiet = TRUE)
cat("\nsortie : data-raw/oracle/aoi/osm_hors_bdtopo.gpkg",
    "(lignes OSM avec > 50 m hors corridor)\n")
cat("\nRAPPEL : un lineaire hors corridor n'est PAS une desserte manquante\n")
cat("prouvee -- c'est un gisement a instruire (sentiers, erreurs, decalages).\n")
