# Confrontation de `places_depot()` a l'oracle Sylvaccess (jeu ColduPre).
#
# Le reseau de desserte ColduPre porte l'attribut CABLE de la couche de depart
# (`c_file_departure`) : la VERITE TERRAIN des places de depot, 2 troncons sur
# 125. On mesure le RAPPEL (les 2 sont-ils retrouves ?) et la PRECISION (parmi
# combien ?), et on verifie que la pente EN LONG separe la ou la pente du MNT
# echouait (cf. entete de R/depot.R).
#
#   SYLVA=~/dev/sylvaccess-upstream Rscript data-raw/oracle_places_depot.R

.libPaths(c(.libPaths(), "~/R/x86_64-pc-linux-gnu-library/4.6"))
suppressPackageStartupMessages({
  library(terra)
  library(sf)
})
devtools::load_all(quiet = TRUE)

SYLVA <- Sys.getenv("SYLVA", "~/dev/sylvaccess-upstream")
IN <- file.path(path.expand(SYLVA), "test", "ColduPre", "Input")

res <- st_read(file.path(IN, "forest_roadnetwork.gpkg"), quiet = TRUE)
mnt <- terra::rast(file.path(IN, "mnt.tif"))
foret <- st_read(file.path(IN, "forest_area.gpkg"), quiet = TRUE)

# Verite terrain.
vrai <- which(res$CABLE != 0)
cat(sprintf("Oracle : %d places de depot sur %d troncons (%s)\n\n",
  length(vrai), nrow(res), paste(vrai, collapse = ", ")))

# Traduction des attributs ColduPre vers ceux que lit places_depot().
res$dfci <- res$CL_DFCI
res$classe <- c(
  "Route forestiere" = "route", "Piste forestiere" = "piste",
  "Reseau public" = "route"
)[res$TYPE_FR]

banc <- function(etiquette, ...) {
  p <- suppressMessages(places_depot(res, mnt, ...))
  tr <- sort(unique(p$troncon))
  trouve <- intersect(vrai, tr)
  cat(sprintf(
    "%-28s %3d places | %3d/%d troncons (%.0f%%) | rappel %d/%d | precision %.1f%%\n",
    etiquette, nrow(p), length(tr), nrow(res), 100 * length(tr) / nrow(res),
    length(trouve), length(vrai), 100 * length(trouve) / length(tr)
  ))
  invisible(tr)
}

banc("defauts")
banc("+ foret", foret = foret)
banc("pente <= 10 %", foret = foret, pente_max_pct = 10)
banc("pente <= 5 %", foret = foret, pente_max_pct = 5)
banc("esp = 400 m", foret = foret, espacement_min_m = 400)

# Ou tombent les 2 vraies places dans les deux mesures de pente ?
cat("\n--- pente MNT (versant) vs pente EN LONG (plateforme), sur les 2 vraies ---\n")
pente_mnt <- terra::extract(calculer_terrain(mnt)$slope_pct,
  terra::vect(res), fun = median, na.rm = TRUE)[, 2]
lg <- as.numeric(st_length(res))
z <- t(sapply(st_geometry(res), function(g) {
  m <- st_coordinates(g)[, 1:2, drop = FALSE]
  as.numeric(terra::extract(mnt, rbind(m[1, ], m[nrow(m), ]))[, 1])
}))
en_long <- 100 * abs(z[, 2] - z[, 1]) / lg
for (i in vrai) {
  cat(sprintf("  troncon %3d : versant %5.1f %% (percentile %2.0f) | en long %4.1f %% (percentile %2.0f)\n",
    i, pente_mnt[i], 100 * rank(pente_mnt)[i] / nrow(res),
    en_long[i], 100 * rank(en_long)[i] / nrow(res)))
}

# --- Balayage du seuil de pente en long : rappel vs precision ----------------
cat("\n--- arbitrage rappel / precision selon `pente_max_pct` ---\n")
cat("seuil   troncons retenus   rappel   marge du pire vrai\n")
for (s in c(4, 5, 6, 8, 10, 15)) {
  p <- suppressMessages(places_depot(res, mnt, foret = foret, pente_max_pct = s))
  tr <- sort(unique(p$troncon))
  pv <- sapply(vrai, function(i) {
    q <- p$pente_pct[p$troncon == i]
    if (length(q)) min(q) else NA_real_
  })
  cat(sprintf("%4d %%  %3d/125 (%2.0f %%)      %d/%d      %s\n",
    s, length(tr), 100 * length(tr) / nrow(res),
    length(intersect(vrai, tr)), length(vrai),
    if (all(is.na(pv))) "-" else sprintf("%.1f pt", s - max(pv, na.rm = TRUE))))
}
