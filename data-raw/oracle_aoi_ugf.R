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
# Usage : Rscript data-raw/oracle_aoi_ugf.R
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

RACINE <- normalizePath("data-raw/oracle/aoi-ugf", mustWork = TRUE)
IN <- file.path(RACINE, "input")
stopifnot(dir.exists(IN))

# --- 1. Acquisition (memes parametres que le banc aoi) ----------------------
# buffer 100 m / res 5 m / EPSG 2154 : retro-verifies sur l'emprise du MNT deja
# en cache (delta bbox MNT - area = -100 / +102 / -98 / +100, grille 5 m).
aoi <- st_read(file.path(IN, "area.gpkg"), quiet = TRUE)
inp <- acquire_inputs(aoi,
  sources = c("mnt", "desserte", "foret"),
  cache_dir = file.path(RACINE, "cache"), res_m = 5, buffer_m = 100
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
cat("ATTENTION : results/ est perime (calcule avec l'ancien reseau).\n")
