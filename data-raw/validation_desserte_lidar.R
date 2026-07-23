# Validation Phase B de acquire_desserte_lidar() sur donnee FRANCAISE (spec 020,
# CA-20.5). Documentaire / reproductible -- PAS execute en CI (reseau + LiDAR + dep
# ALSroads). Sous-tend le finding POSITIF du sec. 6bis de la spec 020 : avec un MNT
# >= 1 m, ALSroads mesure bien les pistes forestieres francaises.
#
#   Rscript data-raw/validation_desserte_lidar.R
#
# Prerequis : lidR + ALSroads installes (remotes::install_github("r-lidar-lab/ALSroads")).
# Resultat 2026-07-23, Chastel-Nouvel (dep 48), MNT 1 m derive des points sol :
# 12/12 pistes mesurees (carrossable 2,7-8,1 m, classes 1-2).
#
# LECON : le 0/6 du premier essai (v1.15.0) etait un FAUX NEGATIF -- MNT a 5 m
# (grille d'accessibilite) 10x trop grossier pour les profils ALSroads a 0,5 m.
# Le guide ALSroads exige un MNT >= 1 m. acquire_desserte_lidar() derive donc un
# MNT 1 m des points sol quand le MNT fourni est plus grossier (cf. .mnt_alsroads).
# Ne PAS reconclure au "defaut de calibrage" sans avoir verifie la resolution MNT.

.libPaths(c(.libPaths(), "~/R/x86_64-pc-linux-gnu-library/4.6"))
options(lidR.progress = FALSE)
suppressPackageStartupMessages({
  library(sf)
  library(terra)
})
devtools::load_all(quiet = TRUE)

# --- 1. Dalle LiDAR HD couvrant l'AOI ---------------------------------------
# Les dalles nuage sont trouvees par WFS (IGNF_NUAGES-DE-POINTS-LIDAR-HD:dalle)
# sur data.geopf.fr ; ATTENTION a l'ordre d'axe EPSG:4326 (lon,lat ici) et au fait
# que le nom de dalle encode un COIN (ex. LHD_..._0737_6385 -> X 737000-738000,
# Y 6384000-6385000 : le 6385 est le bord HAUT). Verifier l'emprise via l'entete
# LAS, pas via le nom.
aoi_bbox_4326 <- "3.45,44.544,3.492,44.564,EPSG:4326" # lon_min,lat_min,lon_max,lat_max
tile_url <- paste0(
  "https://data.geopf.fr/telechargement/download/LiDARHD-NUALID/",
  "NUALHD_1-0__LAZ_LAMB93_MN_2024-12-13/LHD_FXX_0737_6385_PTS_LAMB93_IGN69.copc.laz"
)
tile <- file.path(Sys.getenv("LIDAR_DIR", "/tmp/lidar-chastel"), "t1.copc.laz")
dir.create(dirname(tile), showWarnings = FALSE, recursive = TRUE)
if (!file.exists(tile)) {
  cat("Telechargement de la dalle (~260 Mo)...\n")
  utils::download.file(tile_url, tile, quiet = TRUE)
}
tile_ext <- sf::st_bbox(lidR::readLAScatalog(tile)) # emprise REELLE
cat("Emprise dalle :", paste(round(as.numeric(tile_ext)), collapse = " "), "\n")

# --- 2. Desserte BD TOPO + MNT du secteur -----------------------------------
IN <- Sys.getenv("ACCESSFOR_CACHE_LAYERS", "/tmp/accessfor-cache/layers")
des <- sf::st_transform(sf::st_read(file.path(IN, "desserte/desserte.gpkg"), quiet = TRUE), 2154)
mnt <- terra::rast(file.path(IN, "mnt/mnt.tif"))

# Troncons ENTIEREMENT dans la dalle (pas de crop -> pas de fragments < 40 m) et
# LONGS (>= 60 m). C'est la selection propre : les essais avec crop ou mauvaise
# emprise donnaient de faux « Road too short » / « No point found ».
tile_poly <- sf::st_as_sfc(tile_ext)
sel <- des[lengths(sf::st_within(des, tile_poly)) > 0, ]
sel <- sel[as.numeric(sf::st_length(sel)) >= 60, ]
cat("Troncons entiers >= 60 m dans la dalle :", nrow(sel), "\n")

# --- 3. Mesure ALSroads + verdict -------------------------------------------
out <- acquire_desserte_lidar(sel, las_source = tile, mnt = mnt, crs = 2154)
d <- sf::st_drop_geometry(out)
n_mes <- sum(!is.na(d$largeur_carrossable_m))
cat(sprintf("\n=== VERDICT PHASE B : %d / %d troncons mesures ===\n", n_mes, nrow(out)))
if (n_mes > 0) {
  cat("largeur_carrossable_m :", paste(round(d$largeur_carrossable_m, 1), collapse = ", "), "\n")
  cat("etat_classe           :", paste(d$etat_classe, collapse = ", "), "\n")
  cat("-> comparer a un releve/orthophoto pour trancher le go/no-go.\n")
} else {
  cat("0 mesure : verifier d'ABORD la resolution du MNT (>= 1 m exige) avant de\n")
  cat("conclure a un defaut de calibrage -- c'etait la cause du faux negatif v1.15.0.\n")
}
# Reference : l'exemple QUEBECOIS du paquet se mesure sans peine (sanity check).
#   d <- system.file("extdata", package = "ALSroads")
#   measure_road(lidR::readLAScatalog(c(...j5gr_1.laz, j5gr_2.laz)),
#                sf::st_read(file.path(d, "j5gr_centerline_971487.gpkg")),
#                raster::raster(file.path(d, "j5gr_dtm.tif")))  # -> ROADWIDTH 8.5, CLASS 1
