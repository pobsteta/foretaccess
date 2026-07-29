# Prepare le banc oracle sur l'AOI reelle (Cevennes, data-raw/aoi.gpkg).
#
# 1. Acquiert les entrees (IGN/OSM) via acquire_inputs().
# 2. Les exporte au format attendu par Sylvaccess (CL_SVAC, forest_area, area).
# 3. Ecrit le fichier de parametres Sylvaccess, derive du scenario ColduPre.
# 4. Fait tourner ForetAccess et chronometre.
#
# Sylvaccess se lance ensuite a la main :
#   cd ~/dev/sylvaccess-upstream/scripts
#   ~/miniforge3/envs/sylvaccess/bin/python 0_Lance_sylvaccess.py \
#       -file <repo>/data-raw/oracle/aoi/param_aoi.csv
#
# Usage : Rscript data-raw/oracle_aoi.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

RACINE <- normalizePath("data-raw/oracle/aoi", mustWork = FALSE)
IN <- file.path(RACINE, "input")
RES <- file.path(RACINE, "results")
FA <- file.path(RACINE, "foretaccess")
for (d in c(IN, RES, FA)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

# --- 1. Acquisition ---------------------------------------------------------
aoi <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
# FA_DFCI=0 saute le flag DFCI. Utile car acquire_dfci() n'ecrit PAS de cache
# quand OSM ne rend rien (le cas ici : 0 troncon ref:FR:DFCI, repli geometrique
# a 0 aussi) : chaque execution re-interroge Overpass, qui finit par throttler
# et bloquer le script en backoff 60 s. Neutre sur la sortie tant qu'aucun
# troncon ne devient classe = "dfci".
DFCI <- !identical(Sys.getenv("FA_DFCI"), "0")
if (!DFCI) cat("  DFCI         SAUTE (FA_DFCI=0)\n")
inp <- acquire_inputs(aoi,
  sources = c("mnt", "desserte", "foret"),
  cache_dir = file.path(RACINE, "cache"), res_m = 5, buffer_m = 100,
  dfci = DFCI
)
mnt <- rast(inp$mnt)
desserte <- inp$desserte
foret <- inp$foret

cat(sprintf(
  "AOI : %d x %d cellules (%g m) | %d troncons | %d ha de foret\n",
  nrow(mnt), ncol(mnt), res(mnt)[1], nrow(desserte),
  round(sum(as.numeric(st_area(foret))) / 1e4)
))

# --- 2. Export au format Sylvaccess -----------------------------------------
# CL_SVAC : 1 = piste, 2 = route forestiere, 3 = reseau public.
# L'AOI n'a ni reseau public ni obstacles : elle n'exerce donc PAS les defauts
# que ColduPre a reveles. C'est exactement pourquoi le banc a ete rode sur
# ColduPre d'abord.
cl <- c(piste = 1L, route = 2L, dfci = 2L, reseau_public = 3L)
rn <- st_sf(
  CL_SVAC = unname(cl[as.character(desserte$classe)]),
  geom = st_geometry(desserte)
)
if (anyNA(rn$CL_SVAC)) stop("classe de desserte inconnue")
# Sylvaccess lit le champ CABLE pour les places de depot ; sans lui, tout le
# reseau sert de depart. On garde les routes forestieres seules.
rn$CABLE <- as.integer(rn$CL_SVAC == 2L)
st_write(rn, file.path(IN, "forest_roadnetwork.gpkg"), delete_dsn = TRUE, quiet = TRUE)

st_write(st_sf(FORET = 1L, geom = st_geometry(foret)), file.path(IN, "forest_area.gpkg"),
  delete_dsn = TRUE, quiet = TRUE
)
st_write(st_sf(geom = st_geometry(aoi)), file.path(IN, "area.gpkg"),
  delete_dsn = TRUE, quiet = TRUE
)
writeRaster(mnt, file.path(IN, "mnt.tif"), overwrite = TRUE)

# --- 3. Fichier de parametres Sylvaccess ------------------------------------
modele <- "~/dev/sylvaccess-upstream/scripts/ressource/Tab_Param_test.csv"
par <- read.csv(path.expand(modele), stringsAsFactors = FALSE)

fixer <- function(nom, valeur) par$value[par$var_name == nom] <<- as.character(valeur)
fixer("g_fold_work", paste0(RACINE, "/"))
fixer("g_fold_res", paste0(RES, "/"))
fixer("g_file_dtm", file.path(IN, "mnt.tif"))
fixer("g_file_roadnet", file.path(IN, "forest_roadnetwork.gpkg"))
fixer("g_file_forest", file.path(IN, "forest_area.gpkg"))
fixer("g_file_area", file.path(IN, "area.gpkg"))
fixer("g_file_vha", "")
fixer("c_file_departure", file.path(IN, "forest_roadnetwork.gpkg"))
# Aucun obstacle disponible sur l'AOI.
for (nm in c("c_fold_obs", "s_fold_obs_p", "s_fold_obs_f", "f_fold_obs")) fixer(nm, "")

param <- file.path(RACINE, "param_aoi.csv")
write.csv(par, param, row.names = FALSE, quote = TRUE)
cat("Parametres Sylvaccess :", param, "\n")

# --- 4. ForetAccess ---------------------------------------------------------
# Config alignee sur le scenario (identique a celle d'oracle_coldupre.R).
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
    coeff_securite = 2 # c_safe du scenario (le defaut v3.6 est 2,5)
  )
)

chrono <- function(nom, expr) {
  t <- system.time(v <- force(expr))
  cat(sprintf("  %-12s CPU %6.1f s | ecoule %6.1f s\n", nom, t[["user.self"]], t[["elapsed"]]))
  v
}

cat("\nForetAccess sur l'AOI\n")
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
