# Banc barème / terrassement — spec 029 §7
# ------------------------------------------------------------------------------
# Le premier passage (2026-08-11) a été conduit à la main et n'a laissé que ses
# résultats dans la spec. Il a fallu le refaire après le calage des prix au m³ :
# d'où ce script, qui rend le banc REJOUABLE. C'est la leçon du premier tour.
#
# Ce qu'il mesure, dans l'ordre d'importance :
#   1. le FEASIBLE SET — quelles cellules chaque méthode déclare constructibles.
#      C'est le résultat qui décide, et le seul qui ne dépende pas des prix ;
#   2. les coûts sur le domaine commun ;
#   3. les tracés, et surtout leur RECOUVREMENT GÉOMÉTRIQUE — comparer deux
#      méthodes sur leurs totaux conclurait à tort à l'équivalence.
#
# Usage :  Rscript data-raw/banc_029_terrassement.R
#
#   FA_BANC_CACHE   cache desserte d'un projet nemeton (défaut : DABO/xpdk)
#   FA_BANC_SKID    distance de débardage, m (défaut 100 — celle du §7)
#   FA_BANC_LARGEUR largeur de plateforme, m (défaut 4)
#   FA_BANC_MOTEUR  "glouton" (défaut) ou "steiner"

suppressMessages({library(terra); library(sf)})
if (file.exists("DESCRIPTION") && requireNamespace("pkgload", quietly = TRUE)) {
  suppressMessages(pkgload::load_all(".", quiet = TRUE))
} else {
  library(foretaccess)
}

CACHE <- Sys.getenv("FA_BANC_CACHE",
  "/home/pascal/.local/share/nemeton/projects/20260801_130303_xpdk/cache/desserte")
SKID <- as.numeric(Sys.getenv("FA_BANC_SKID", "100"))
LARGEUR <- as.numeric(Sys.getenv("FA_BANC_LARGEUR", "4"))
MOTEUR <- Sys.getenv("FA_BANC_MOTEUR", "glouton")

emprise <- file.path(CACHE, "emprise_1000m")
stopifnot(dir.exists(emprise))

message("== Entrees ==")
mnt <- terra::rast(file.path(emprise, "mnt_highres_5m.tif"))
desserte <- sf::st_read(file.path(emprise, "layers/desserte/desserte.gpkg"), quiet = TRUE)
foret <- sf::st_read(file.path(emprise, "layers/foret/foret.gpkg"), quiet = TRUE)
parcelles <- sf::st_read(file.path(CACHE, "aoi_input.gpkg"), quiet = TRUE)
message(sprintf("  MNT %d cellules a %g m | %d troncons existants | %d parcelles / %.0f ha",
  terra::ncell(mnt), terra::res(mnt)[1], nrow(desserte), nrow(parcelles),
  sum(as.numeric(sf::st_area(parcelles))) / 1e4))

pre <- preprocess(mnt = mnt, desserte = desserte, foret = foret)
pente <- terra::values(pre$slope_pct, mat = FALSE)
message(sprintf("  pente : mediane %.1f %% | p90 %.1f %%",
  stats::median(pente, na.rm = TRUE), stats::quantile(pente, 0.9, na.rm = TRUE)))

cfg <- foretaccess_config()
te <- cfg$desserte$cout$terrassement
message(sprintf("  prix au m3 : deblai %g | remblai %g | evacuation %g",
  te$prix_deblai_m3, te$prix_remblai_m3, te$prix_evacuation_m3))

# --- 1. Feasible set ----------------------------------------------------------
message("\n== 1. Feasible set ==")
c_bar <- surface_cout_construction(pre, cfg)
c_ter <- surface_cout_construction(pre, cfg, methode_pente = "terrassement",
                                   largeur_m = LARGEUR)
f_bar <- terra::values(c_bar$franchissable, mat = FALSE)
f_ter <- terra::values(c_ter$franchissable, mat = FALSE)
ok <- function(v) !is.na(v) & v > 0
ouvre <- which(!ok(f_bar) & ok(f_ter))
ferme <- which(ok(f_bar) & !ok(f_ter))
message(sprintf("  franchissables : bareme %d | terrassement %d",
  sum(ok(f_bar)), sum(ok(f_ter))))
message(sprintf("  ouvertes par le terrassement : %d (%.2f %% du MNT) | fermees : %d",
  length(ouvre), 100 * length(ouvre) / terra::ncell(mnt), length(ferme)))
if (length(ouvre)) {
  po <- pente[ouvre]
  message(sprintf("    pente des cellules ouvertes : %.0f a %.0f %%",
    min(po, na.rm = TRUE), max(po, na.rm = TRUE)))
  vo <- terra::values(c_ter$cout, mat = FALSE)[ouvre]
  message(sprintf("    cout qu'on y paierait : %.0f a %.0f EUR/m",
    min(vo, na.rm = TRUE), max(vo, na.rm = TRUE)))
}

# --- 2. Couts sur le domaine commun ------------------------------------------
message("\n== 2. Couts, domaine commun ==")
v_bar <- terra::values(c_bar$cout, mat = FALSE)
v_ter <- terra::values(c_ter$cout, mat = FALSE)
commun <- is.finite(v_bar) & is.finite(v_ter)
message(sprintf("  bareme       : mediane %.1f | moyenne %.1f EUR/m",
  stats::median(v_bar[commun]), mean(v_bar[commun])))
message(sprintf("  terrassement : mediane %.1f | moyenne %.1f EUR/m",
  stats::median(v_ter[commun]), mean(v_ter[commun])))
message(sprintf("  rapport des medianes : x %.2f",
  stats::median(v_ter[commun]) / stats::median(v_bar[commun])))

# --- 3. Traces ----------------------------------------------------------------
message("\n== 3. Traces ==")
tracer <- function(cout, nom) {
  t0 <- Sys.time()
  r <- reseau_desserte(pre, cout, parcelles = parcelles,
                       desserte_existante = desserte, mode = MOTEUR,
                       skidding_m = SKID, pondere_cout = TRUE)
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  lg <- if (inherits(r$lignes, "sf") && nrow(r$lignes)) {
    sum(as.numeric(sf::st_length(r$lignes)))
  } else 0
  message(sprintf("  %-13s : %d routes | %.0f m | cout %.0f | %.0f s",
    nom, if (inherits(r$lignes, "sf")) nrow(r$lignes) else 0, lg,
    suppressWarnings(as.numeric(r$cout)), dt))
  r
}
r_bar <- tracer(c_bar, "bareme")
r_ter <- tracer(c_ter, "terrassement")

# Recouvrement : part du trace bareme reprise a moins d'une cellule par le
# trace terrassement. Les agregats se ressemblent meme quand la geometrie
# change de moitie -- c'est la mesure qui compte.
recouvrement <- function(a, b, tol) {
  if (!inherits(a, "sf") || !nrow(a) || !inherits(b, "sf") || !nrow(b)) return(NA_real_)
  pts <- sf::st_cast(sf::st_line_sample(sf::st_geometry(a), density = 1 / tol), "POINT")
  d <- as.numeric(sf::st_distance(pts, sf::st_union(sf::st_geometry(b))))
  mean(d <= tol, na.rm = TRUE)
}
tol <- terra::res(mnt)[1]
message(sprintf("\n  recouvrement bareme -> terrassement : %.1f %%",
  100 * recouvrement(r_bar$lignes, r_ter$lignes, tol)))
message(sprintf("  recouvrement terrassement -> bareme : %.1f %%",
  100 * recouvrement(r_ter$lignes, r_bar$lignes, tol)))
