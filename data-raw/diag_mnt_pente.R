# Diagnostic : l'ecart de pente entre NOTRE MNT (LiDAR HD) et celui d'ACCESSFOR
# (RGE Alti 5 m), sur l'AOI Chastel-Nouvel.
#
# POURQUOI : le porteur est le moteur ou nous sommes les plus CONSERVATEURS --
# 29,7 ha juges inaccessibles chez nous et accessibles chez ACCESSFOR, contre
# 18,9 ha en sens inverse (spec 024 CA-24.5). Or le porteur est gouverne par des
# seuils de PENTE serres (travers 15 %, montee 30 %, descente 25 %), bien plus
# que le skidder (30 %). Un MNT plus fin voit du micro-relief que le RGE Alti
# lisse : chaque aspérite qui franchit 15 % en travers coupe l'acces.
#
# C'est l'ecart n.4 de la revue de conformite, ASSUME (decision du 2026-07-29) :
# on garde le LiDAR HD, que le rapport ACCESSFOR lui-meme (p.16) annonce comme
# futur referentiel national. Ce script ne le remet pas en cause -- il en CHIFFRE
# la consequence, pour qu'on cesse d'attribuer au hasard un ecart explicable.
#
# Usage : Rscript data-raw/diag_mnt_pente.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

CACHE <- Sys.getenv("ACCESSFOR_CACHE", "/tmp/accessfor-cache")
aoi <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
emprise <- st_buffer(aoi, 100)

# --- 1. Les deux MNT, meme emprise, meme resolution -------------------------
mnt_lidar <- rast(acquire_mnt(emprise, res_m = 5, res_lidar_m = 5, cache_dir = CACHE))

# RGE Alti : les VRAIES DALLES departementales, pas le WMS.
#
# Premiere tentative (2026-07-29) : `.fetch_wms_raster("ELEVATION.ELEVATION-
# GRIDCOVERAGE")`. INVALIDE -- le WMS sert une pyramide web-mercator reprojetee
# qui rend un MNT « blocky » (blocs plats a marches). Symptomes mesures : 1er
# quartile de pente a 3,07 % pour une mediane a 26 % et un MAXIMUM a 382 %, et
# un ecart d'altitude au LiDAR de +-34 m. C'est l'artefact que documente deja
# `acquire_mnt()` et qui a motive le passage au LiDAR HD en v1.16.0.
#
# ACCESSFOR n'utilise pas ca : l'annexe p.50 prescrit « un MNT provenant du RGE
# Alti 5m converti en 32bit », telecharge par DEPARTEMENT depuis Geoservices.
# On lit donc les dalles ASC du departement 48, mosaiquees.
#
# Archive : https://data.geopf.fr/telechargement/download/RGEALTI/
#   RGEALTI_2-0_5M_ASC_LAMB93-IGN69_D048_2022-12-16/...7z  (443 Mo, 255 dalles)
# Deux dalles de 5 km suffisent pour l'AOI : 0735_6385 et 0735_6390.
DALLES <- Sys.glob(file.path("data-raw/oracle/aoi/cache/rgealti", "**",
  "RGEALTI_FXX_0735_63*_MNT_LAMB93_IGN69.asc"))
if (!length(DALLES)) {
  DALLES <- list.files("data-raw/oracle/aoi/cache/rgealti", pattern = "\\.asc$",
    recursive = TRUE, full.names = TRUE)
}
stopifnot(length(DALLES) > 0)
cat("dalles RGE Alti :", length(DALLES), "\n")
tuiles <- lapply(DALLES, function(f) {
  r <- rast(f)
  crs(r) <- "EPSG:2154" # l'ASC ne porte pas le CRS
  r
})
mnt_rge <- if (length(tuiles) == 1) tuiles[[1]] else do.call(terra::merge, tuiles)
mnt_rge <- crop(mnt_rge, ext(mnt_lidar), snap = "out")

# Alignement strict : on compare cellule a cellule, pas des statistiques globales.
mnt_rge <- resample(mnt_rge, mnt_lidar, method = "bilinear")

cat("MNT LiDAR HD :", paste(res(mnt_lidar), collapse = " x "), "|",
    paste(dim(mnt_lidar)[1:2], collapse = " x "), "\n")
cat("MNT RGE Alti :", paste(res(mnt_rge), collapse = " x "), "| dalles ASC (realigne)\n")

# --- 2. Altitude ------------------------------------------------------------
d_alt <- values(mnt_lidar - mnt_rge, mat = FALSE)
d_alt <- d_alt[is.finite(d_alt)]
cat("\n--- ecart d'ALTITUDE (LiDAR - RGE), m ---\n")
print(round(summary(d_alt), 3))
cat("|ecart| p95 :", round(quantile(abs(d_alt), 0.95, na.rm = TRUE), 2), "m\n")

# --- 3. Pente ---------------------------------------------------------------
p_lidar <- terrain(mnt_lidar, v = "slope", unit = "radians")
p_rge <- terrain(mnt_rge, v = "slope", unit = "radians")
pct <- function(r) tan(r) * 100
pl <- values(pct(p_lidar), mat = FALSE)
pr <- values(pct(p_rge), mat = FALSE)

# Restreint a la FORET : c'est la seule surface qui compte pour l'accessibilite.
foret <- acquire_foret(emprise, cache_dir = CACHE)
mfor <- rasterize(vect(foret), mnt_lidar, field = 1)
ok <- is.finite(pl) & is.finite(pr) & !is.na(values(mfor, mat = FALSE))
cat("\ncellules forestieres comparees :", sum(ok), "\n")

cat("\n--- PENTE (%) sur foret ---\n")
cat("LiDAR HD :"); print(round(summary(pl[ok]), 2))
cat("RGE Alti :"); print(round(summary(pr[ok]), 2))
d_p <- pl[ok] - pr[ok]
cat("\necart de pente (LiDAR - RGE), points de % :\n"); print(round(summary(d_p), 2))
cat("|ecart| p95 :", round(quantile(abs(d_p), 0.95), 2), "pts\n")

# --- 4. Les seuils du porteur ------------------------------------------------
# La pente de terrain n'est pas la pente EN TRAVERS que calcule le moteur (qui
# depend de la direction de circulation), mais elle la BORNE : un terrain a moins
# de 15 % ne peut pas presenter 15 % en travers. Le franchissement differentiel
# du seuil est donc un majorant de l'effet.
cfg <- foretaccess_config()
for (s in c(cfg$porteur$pente_travers_max_pct, cfg$porteur$pente_descente_max_pct,
            cfg$porteur$pente_montee_max_pct, cfg$skidder$pente_skidder_max_pct)) {
  a <- pl[ok] > s
  b <- pr[ok] > s
  cat(sprintf("\nseuil %2d %% : LiDAR %5.1f %% des cellules | RGE %5.1f %% | desaccord %5.2f %%",
    s, 100 * mean(a), 100 * mean(b), 100 * mean(a != b)))
  cat(sprintf(" (LiDAR seul %.1f ha, RGE seul %.1f ha)",
    sum(a & !b) * 25 / 1e4, sum(b & !a) * 25 / 1e4))
}
cat("\n\nLecture : au seuil du porteur (15 %), la surface que le LiDAR HD juge\n")
cat("trop pentue et le RGE Alti non est un MAJORANT de notre exces de\n")
cat("conservatisme -- a comparer aux 29,7 ha de flips porteur.\n")
