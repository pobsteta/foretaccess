# Banc de balayage de `long_min` selon le protocole CA-26.5 (spec 026 sec.6.0).
#
# BLOC PARAMETRABLE (`FA_BLOC`) : le protocole exige un banc DISJOINT du jeu de
# calibration (P6). `wsfi` ne l'est pas -- la dalle de calibration en est le quart
# sud-ouest. `ltcp` l'est, et le banc doit pouvoir passer de l'un a l'autre.
#
# SOUS-EMPRISE (`FA_SOUS_EMPRISE`, en metres de cote) : depuis que l'indice est
# ancre (bornes absolues + `c_vessel`), analyser une sous-emprise donne le MEME
# resultat qu'analyser le tout -- c'est exactement la propriete qu'on a corrigee.
# Decouper est donc devenu LEGITIME, ce qui ne l'etait pas le matin meme. On s'en
# sert pour borner le cout : 25 km2 a 1 m font 25 M cellules et ~6 Go de nuage
# relus a chaque appel.
#
# POURQUOI `long_min` ET NON `seuil`. L'ancien protocole balayait `seuil` en
# tenant l'emprise pour neutre : il mesurait un artefact. La mesure a montre que
# c'est `long_min` qui decide -- 23 lineaires a 5 m contre 1 a 30 m sur la meme
# fenetre. `seuil` n'est redevenu interpretable que depuis que les bornes sont
# figees (`specs_desserte_calibrees()`), et il vient en second.
#
# CE BANC PUBLIE SES PRECONDITIONS (sec.6.0.1). Une mesure sans elles est nulle
# et non avenue (sec.6.0.5) -- c'est la regle qui manquait, et qui a laisse
# passer une journee entiere de mesures invalides le 2026-07-31.
#
# Usage : Rscript data-raw/banc_wsfi_longmin.R [long_min separes par des virgules]
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf); library(terra); pkgload::load_all(quiet = TRUE)
})

ARGS <- commandArgs(trailingOnly = TRUE)
LM <- if (length(ARGS)) as.numeric(strsplit(ARGS[[1]], ",")[[1]]) else c(5, 10, 15, 20, 30)
SEUIL <- 0.4          # bas de la plage : on cherche le VOLUME, pas la purete
METHODE <- "squelette" # P5 : NOMME. `auto` replierait ici en silence.
BUFFER_REF <- 15

BLOC <- Sys.getenv("FA_BLOC",
  "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache/layers")
NOM <- basename(dirname(dirname(BLOC)))
MNT <- file.path(BLOC, "lidar_mnt_mosaic.tif")
LAZ <- file.path(BLOC, "lidar_nuage")
COTE <- suppressWarnings(as.numeric(Sys.getenv("FA_SOUS_EMPRISE", "")))
SORTIE <- normalizePath(file.path("data-raw/oracle", NOM), mustWork = FALSE)
dir.create(SORTIE, recursive = TRUE, showWarnings = FALSE)
CACHE <- file.path(SORTIE, "cache")
stopifnot(file.exists(MNT), dir.exists(LAZ))

r0 <- rast(MNT)
r <- if (is.finite(COTE)) {
  cx <- (xmin(r0) + xmax(r0)) / 2; cy <- (ymin(r0) + ymax(r0)) / 2
  f <- file.path(SORTIE, sprintf("mnt_sous_%dm.tif", as.integer(COTE)))
  writeRaster(crop(r0, ext(cx - COTE/2, cx + COTE/2, cy - COTE/2, cy + COTE/2)),
    f, overwrite = TRUE)
  MNT <- f
  rast(f)
} else {
  r0
}
cat("bloc :", NOM, "|", if (is.finite(COTE)) sprintf("sous-emprise %d m", as.integer(COTE)) else "emprise complete", "\n")
emprise <- st_as_sf(st_as_sfc(st_bbox(r)))
aire <- as.numeric(st_area(emprise)) / 1e6
ref <- acquire_desserte(emprise, cache_dir = CACHE, politique_cache = "echouer")
corr <- st_union(st_buffer(st_geometry(ref), BUFFER_REF))
km2_hors <- as.numeric(st_area(st_difference(st_geometry(emprise), corr))) / 1e6

# --- PRECONDITIONS (spec 026 sec.6.0.1) ------------------------------------
sp <- specs_desserte_calibrees()
bornes_ok <- all(vapply(c(sp$geomorpho, sp$surface), function(s) {
  is.numeric(s$a) && is.numeric(s$b) && is.finite(s$a) && is.finite(s$b)
}, logical(1)))
v_dsr <- as.character(utils::packageVersion("dessertR"))
# La dalle de calibration : quart sud-ouest de wsfi. P6 mesure le recouvrement.
dalle_cal <- st_as_sfc(st_bbox(c(xmin = 737000, ymin = 6384000,
  xmax = 738000, ymax = 6385000), crs = st_crs(2154)))
# `st_intersection` rend une geometrie VIDE quand les emprises sont disjointes,
# donc `st_area()` rend numeric(0) -- pas 0. Sans cette garde, le banc echoue
# exactement dans le cas pour lequel il existe : P6 satisfaite.
inter_cal <- st_intersection(st_geometry(emprise), dalle_cal)
rec <- if (length(inter_cal)) as.numeric(sum(st_area(inter_cal))) / 1e6 else 0

P <- list(
  P1_mnt_1m5 = max(res(r)) <= 1.5,
  P2_canal_surface = NA,   # renseigne apres la premiere detection
  P3_dessertr_1_1_0 = utils::compareVersion(v_dsr, "1.1.0") >= 0,
  P4_bornes_absolues = bornes_ok,
  P5_vectoriseur_nomme = !identical(METHODE, "auto"),
  P6_banc_disjoint = rec == 0
)
cat("=== PRECONDITIONS (spec 026 sec.6.0.1) ===\n")
cat(sprintf("  P1 MNT %.2f m (<= 1,5)            : %s\n", max(res(r)), P$P1_mnt_1m5))
cat(sprintf("  P3 dessertR %s (>= 1.1.0)      : %s\n", v_dsr, P$P3_dessertr_1_1_0))
cat(sprintf("  P4 bornes absolues (%d canaux)     : %s\n",
  length(c(sp$geomorpho, sp$surface)), P$P4_bornes_absolues))
cat(sprintf("  P5 vectoriseur = %-10s        : %s\n", METHODE, P$P5_vectoriseur_nomme))
cat(sprintf("  P6 recouvrement calibration       : %.3f km2 sur %.2f -> %s\n",
  rec, aire, if (P$P6_banc_disjoint) "DISJOINT" else "NON DISJOINT"))
cat(sprintf("  dessertR %s | seuil %.1f | methode %s\n", v_dsr, SEUIL, METHODE))
cat(sprintf("\n  emprise %.2f km2 | explorable %.2f km2 (%.1f %%) | reference %d obj.\n",
  aire, km2_hors, 100 * km2_hors / aire, nrow(ref)))
if (!P$P6_banc_disjoint) {
  cat("\n  !! P6 VIOLEE : la dalle de calibration est DANS l'emprise du banc.\n")
  cat("     Les resultats sont partiellement circulaires. Un score sur les\n")
  cat("     3 km2 restants est publie a part ci-dessous.\n")
}

# --- Balayage ---------------------------------------------------------------
hors_cal <- st_difference(st_geometry(emprise), dalle_cal)
cat("\n=== balayage long_min :", paste(LM, collapse = ", "), "| seuil", SEUIL, "===\n")
lignes <- lapply(LM, function(lm) {
  t0 <- proc.time()[["elapsed"]]
  d <- detecter_desserte(MNT, reference = ref, las_source = LAZ, seuil = SEUIL,
    buffer_ref = BUFFER_REF, long_min = lm, emprise = NULL, dtm_res = 1,
    methode = METHODE)
  if (is.na(P$P2_canal_surface)) P$P2_canal_surface <<- isTRUE(attr(d, "canal_surface"))
  m <- if (nrow(d)) sum(as.numeric(st_length(d))) else 0
  # Score hors dalle de calibration : le seul non circulaire (P6).
  # Meme garde : `hors_cal` peut etre l'emprise entiere (banc disjoint).
  m_hc <- if (nrow(d) && length(hors_cal)) {
    g <- st_intersection(st_geometry(d), hors_cal)
    if (length(g)) sum(as.numeric(st_length(g))) else 0
  } else if (nrow(d)) {
    sum(as.numeric(st_length(d)))
  } else 0
  if (nrow(d)) {
    st_write(d, file.path(SORTIE, sprintf("lm%02d_s0p4.gpkg", lm)),
      delete_dsn = TRUE, quiet = TRUE)
  }
  cat(sprintf("  long_min %2d m : %3d lin. | %7.0f m | hors calib %7.0f m | %.1f min\n",
    lm, nrow(d), m, m_hc, (proc.time()[["elapsed"]] - t0) / 60))
  data.frame(long_min = lm, n = nrow(d), m = m, m_hors_calib = m_hc)
})
bal <- do.call(rbind, lignes)
cat(sprintf("\n  P2 canal de surface CONSOMME      : %s\n", P$P2_canal_surface))

cat("\n=== bilan ===\n"); print(bal)
cat(sprintf("\ndensite hors calibration, meilleur cas : %.3f km/km2 explorable\n",
  max(bal$m_hors_calib) / 1000 / km2_hors))
cat("seuil de recevabilite (sec.6.0.4) : >= 0,5 km/km2 ET >= 20 lineaires\n")
cat(sprintf("  volume   : %s\n", if (max(bal$m_hors_calib)/1000/km2_hors >= 0.5) "ATTEINT" else "NON ATTEINT"))
cat(sprintf("  effectif : %s (max %d lineaires)\n",
  if (max(bal$n) >= 20) "ATTEINT" else "NON ATTEINT", max(bal$n)))

saveRDS(list(balayage = bal, preconditions = P, dessertR = v_dsr,
  seuil = SEUIL, methode = METHODE, km2_explorable = km2_hors,
  recouvrement_calibration_km2 = rec),
  file.path(SORTIE, "banc_longmin.rds"))
write.csv(bal, file.path(SORTIE, "balayage_longmin_protocole.csv"), row.names = FALSE)
cat("\nsorties :", SORTIE, "\n")
cat("\n--- avertissements ---\n"); print(warnings())
