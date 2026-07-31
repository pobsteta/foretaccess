# Calibration de REFERENCE de la detection (spec 026), contre dessertR >= 1.1.0.
#
# POURQUOI FIGER PLUTOT QUE CALIBRER PAR AOI. `dsr_calibrer_specs()` calibre sur
# les donnees qu'on lui donne. Appele par AOI, il rendrait des specs justes
# localement mais INCOMPARABLES entre sites -- exactement ce que le CA-26.5
# interdit. On calibre donc une fois, ici, et `specs_desserte_calibrees()` porte
# le resultat fige.
#
# HISTORIQUE. Ce banc a d'abord mesure les bornes a la main (2026-07-31) parce
# que dessertR 1.0.0 ne les produisait pas. L'audit qui en est sorti a fait
# corriger le paquet : la 1.1.0 rend les bornes (`bornes = TRUE`) et expose le
# `c` de Frangi (`dsr_c_vessel()`, `dsr_layers_dtm(c_vessel = )`). On CONSOMME
# desormais l'amont -- la logique de calibration ne nous appartient pas.
#
# ORDRE, QUI N'EST PAS INDIFFERENT : `c_vessel` d'abord, la pile construite avec,
# les bornes ensuite. Calibrer des bornes sur une vesselness elle-meme relative
# a l'emprise reproduirait le defaut un cran plus bas.
#
# PORTEE : un seul massif (Lozere, 830-1260 m, foret de montagne). dessertR 1.1.0
# calibre sur DEUX massifs ; nous n'en avons qu'un, et il recouvre `wsfi` a 54 %.
# Ces valeurs ancrent, elles ne generalisent pas.
#
# Usage : Rscript data-raw/calibrer_bornes_dsr.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({library(sf); library(terra); library(dessertR); pkgload::load_all(quiet=TRUE)})
cat("dessertR", as.character(packageVersion("dessertR")), "\n\n")
RACINE <- "data-raw/oracle/aoi"; SORTIE <- "data-raw/oracle/calibration"
r <- rast(file.path(RACINE, "phaseB/cache_0p5/layers/mnt/mnt.tif"))
LAZ <- file.path(RACINE, "cache/lidar_nuage", "LHD_FXX_0737_6385_PTS_LAMB93_IGN69.copc.laz")
emp <- st_as_sf(st_as_sfc(st_bbox(r)))
desserte <- acquire_desserte(emp, cache_dir = file.path(SORTIE, "cache"), politique_cache = "echouer")
cible <- desserte[desserte$classe %in% c("piste", "route"), ]
g <- dsr_grille_reference(r, res = 1)
m <- resample(r, g, method = "bilinear")

# 1. Le c de Frangi, mesure sur l'emprise de REFERENCE.
cv <- dsr_c_vessel(m, echelles_m = c(1, 2, 4))
cat("=== dsr_c_vessel (emprise de reference) ===\n"); print(cv)

# 2. La pile, construite AVEC ce c -- sinon les bornes seraient calibrees sur
#    une vesselness elle-meme relative a l'emprise.
cat("\npile (c_vessel ancre)...\n")
pile <- dsr_layers_dtm(r, grille = g, c_vessel = cv)
cat("nuage...\n"); pc <- dsr_layers_pc(LAZ, grille = g)
canaux <- c(pile, pc)

# 3. Les specs AVEC bornes.
cal <- dsr_calibrer_specs(canaux, st_geometry(cible), bornes = TRUE)
cat("\n=== diagnostic ===\n"); print(cal$diagnostic)
cat("\n=== specs (avec bornes) ===\n")
for (n in names(cal$specs)) {
  s <- cal$specs[[n]]
  cat(sprintf("  %-18s %-13s poids=%s a=%s b=%s\n", n, s$type, s$poids,
    if (is.null(s$a)) "NULL" else signif(s$a, 8),
    if (is.null(s$b)) "NULL" else signif(s$b, 8)))
}
saveRDS(list(specs = cal$specs, diagnostic = cal$diagnostic, c_vessel = cv,
  dessertR = as.character(packageVersion("dessertR"))),
  file.path(SORTIE, "reference_chastel_nouvel.rds"))
cat("\n--- avertissements ---\n"); print(warnings())
