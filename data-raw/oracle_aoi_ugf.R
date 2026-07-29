# Regenere les ENTREES Sylvaccess du banc `aoi-ugf` depuis le cache d'acquisition.
#
# Pourquoi ce script existe : `aoi-ugf` avait ete monte a la main (aucun script
# ne le reconstruisait, contrairement a `aoi` via oracle_aoi.R). Ses entrees
# etaient donc figees sur la classification `heuristique` d'avant la v1.20.0 --
# 23/23 troncons en CL_SVAC=1 et CABLE=0 partout, donc AUCUN point de depart
# cable. Le cache de desserte a ete rafraichi (classification `clsvac`) ; ce
# script reporte la correction dans `input/`.
#
# Il ne touche ni `param.csv` ni `results/` : les sorties Sylvaccess presentes
# ont ete calculees avec l'ancien reseau et sont donc PERIMEES -- les recalculer
# est une operation manuelle (lancer Sylvaccess sur param.csv).
#
# Sylvaccess se lance ensuite a la main :
#   cd ~/dev/sylvaccess-upstream/scripts
#   ~/miniforge3/envs/sylvaccess/bin/python 0_Lance_sylvaccess.py \
#       -file <repo>/data-raw/oracle/aoi-ugf/param.csv
#
# Usage : FA_DFCI=0 Rscript data-raw/oracle_aoi_ugf.R
#         FA_DFCI=0 FA_CABLE=0 Rscript data-raw/oracle_aoi_ugf.R   # sans le cable
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

RACINE <- normalizePath("data-raw/oracle/aoi-ugf", mustWork = TRUE)
IN <- file.path(RACINE, "input")
FA <- file.path(RACINE, "foretaccess")
stopifnot(dir.exists(IN))
dir.create(FA, recursive = TRUE, showWarnings = FALSE)

# Memes interrupteurs que oracle_aoi.R : FA_DFCI=0 saute le flag DFCI (evite le
# throttling Overpass quand OSM ne rend rien), FA_CABLE=0 saute le cable (poste
# le plus lourd, ~1 h sur l'AOI voisine).
DFCI <- !identical(Sys.getenv("FA_DFCI"), "0")
if (!DFCI) cat("  DFCI         SAUTE (FA_DFCI=0)\n")

# --- 1. Acquisition (memes parametres que le banc aoi) ----------------------
# buffer 100 m / res 5 m / EPSG 2154 : retro-verifies sur l'emprise du MNT deja
# en cache (delta bbox MNT - area = -100 / +102 / -98 / +100, grille 5 m).
aoi <- st_read(file.path(IN, "area.gpkg"), quiet = TRUE)
inp <- acquire_inputs(aoi,
  sources = c("mnt", "desserte", "foret"),
  cache_dir = file.path(RACINE, "cache"), res_m = 5, buffer_m = 100,
  dfci = DFCI
)
mnt <- rast(inp$mnt)
desserte <- inp$desserte
foret <- inp$foret

cat(sprintf(
  "aoi-ugf : %d x %d cellules (%g m) | %d troncons | %d ha de foret\n",
  nrow(mnt), ncol(mnt), res(mnt)[1], nrow(desserte),
  round(sum(as.numeric(st_area(foret))) / 1e4)
))
print(table(desserte$classe))

# --- 2. Export au format Sylvaccess -----------------------------------------
# CL_SVAC : 1 = piste, 2 = route forestiere, 3 = reseau public (cf. oracle_aoi.R).
cl <- c(piste = 1L, route = 2L, dfci = 2L, reseau_public = 3L)
rn <- st_sf(
  CL_SVAC = unname(cl[as.character(desserte$classe)]),
  geom = st_geometry(desserte)
)
if (anyNA(rn$CL_SVAC)) stop("classe de desserte inconnue")
# Sylvaccess lit CABLE pour les places de depot ; sans lui tout le reseau sert
# de depart. On garde les routes forestieres seules.
rn$CABLE <- as.integer(rn$CL_SVAC == 2L)
st_write(rn, file.path(IN, "forest_roadnetwork.gpkg"), delete_dsn = TRUE, quiet = TRUE)

st_write(st_sf(FORET = 1L, geom = st_geometry(foret)), file.path(IN, "forest_area.gpkg"),
  delete_dsn = TRUE, quiet = TRUE
)
writeRaster(mnt, file.path(IN, "mnt.tif"), overwrite = TRUE)
# `area.gpkg` est l'ENTREE de ce script (l'AOI stricte) : on ne le reecrit pas.

cat("\n--- reseau exporte ---\n")
print(table(CL_SVAC = rn$CL_SVAC))
cat("departs cable (CABLE=1) :", sum(rn$CABLE), "/", nrow(rn), "\n")
cat("\nEntrees regenerees :", IN, "\n")

# --- 3. ForetAccess ---------------------------------------------------------
# Config STRICTEMENT identique a oracle_aoi.R sec.4 : les deux bancs doivent se
# comparer entre eux, un ecart de parametrage les rendrait incomparables.
config <- foretaccess_config(
  general = list(pente_abattage_max_pct = 100),
  skidder = list(
    debardage_amont_max_m = 50, debardage_aval_max_m = 100,
    pente_bascule_amont_pct = 75, pente_bascule_aval_pct = 20,
    distance_hors_desserte_max_m = 50, pente_skidder_max_pct = 30,
    pente_abattage_max_pct = 100, option_modelisation = 1L
  ),
  porteur = list(
    pente_travers_max_pct = 15, pente_montee_max_pct = 30,
    pente_descente_max_pct = 25, portee_grue_m = 8,
    distance_pente_forte_max_m = 300, distance_hors_desserte_max_m = 200,
    pente_abattage_max_pct = 100
  ),
  cable = list(
    longueur_max_m = 750, longueur_min_m = 150, hauteur_mat_m = 10.5,
    hauteur_support_terminal_m = 12, distance_laterale_max_m = 40,
    coeff_securite = 2
  )
)

chrono <- function(nom, expr) {
  t <- system.time(v <- force(expr))
  cat(sprintf("  %-12s CPU %6.1f s | ecoule %6.1f s\n", nom, t[["user.self"]], t[["elapsed"]]))
  v
}

cat("\nForetAccess sur aoi-ugf\n")
pre <- chrono("preprocess", preprocess(mnt, desserte, foret, config = config))
sk <- chrono("skidder", skidder(pre, config, write_dir = file.path(FA, "skidder")))
po <- chrono("porteur", porteur(pre, config, write_dir = file.path(FA, "porteur")))

if (!identical(Sys.getenv("FA_CABLE"), "0")) {
  departs <- desserte[desserte$classe %in% c("route", "dfci"), ]
  departs$cable <- 1L
  ca <- chrono("cable", potentiel_cable(pre, config,
    departs = departs, write_dir = file.path(FA, "cable")
  ))
} else {
  cat("  cable        SAUTE (FA_CABLE=0)\n")
}

cat("\nSorties ForetAccess :", FA, "\n")
cat("ATTENTION : results/ (Sylvaccess) reste PERIME tant que Sylvaccess n'a pas\n")
cat("ete relance a la main sur", file.path(RACINE, "param.csv"), "\n")
