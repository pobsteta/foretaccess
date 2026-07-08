# Génère le jeu de données jouet de ForêtAccess (déterministe).
#
# Sorties (versionnées) sous inst/extdata/toy/ :
#   - mnt.tif           : MNT synthétique (plan incliné, pente connue)
#   - desserte.gpkg     : dessertes classées (route / piste / dfci)
#   - foret.gpkg        : polygone forêt
#   - cable_profils.csv : profils câble analytiques (profil, distance, altitude)
#
# Lancer : Rscript data-raw/make_toy.R
suppressPackageStartupMessages({
  library(terra)
  library(sf)
})

set.seed(20260708)

out_dir <- file.path("inst", "extdata", "toy")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

epsg <- 2154L          # Lambert-93
res_m <- 5             # résolution du MNT (m)
n <- 50L               # nombre de cellules par côté
extent_m <- n * res_m  # 250 m

# --- MNT : plan incliné selon X, pente connue de 20 % ------------------------
slope_x <- 0.20        # 20 % de pente dans la direction X
r <- rast(
  nrows = n, ncols = n,
  xmin = 0, xmax = extent_m, ymin = 0, ymax = extent_m,
  crs = paste0("EPSG:", epsg)
)
xy <- xyFromCell(r, seq_len(ncell(r)))
values(r) <- 100 + slope_x * xy[, "x"]   # altitude (m)
names(r) <- "altitude"
writeRaster(r, file.path(out_dir, "mnt.tif"), overwrite = TRUE,
            gdal = c("COMPRESS=DEFLATE", "TILED=YES"))

# --- Desserte : 3 polylignes classées ---------------------------------------
mk_line <- function(coords) st_linestring(as.matrix(coords))
desserte <- st_sf(
  classe = c("route", "piste", "dfci"),
  geometry = st_sfc(
    mk_line(rbind(c(0, 125), c(250, 125))),     # route est-ouest
    mk_line(rbind(c(125, 0), c(125, 250))),     # piste nord-sud
    mk_line(rbind(c(0, 0), c(250, 250))),       # dfci diagonale
    crs = epsg
  )
)
st_write(desserte, file.path(out_dir, "desserte.gpkg"),
         layer = "desserte", delete_dsn = TRUE, quiet = TRUE)

# --- Forêt : polygone central -----------------------------------------------
foret <- st_sf(
  id = 1L,
  geometry = st_sfc(
    st_polygon(list(rbind(
      c(25, 25), c(225, 25), c(225, 225), c(25, 225), c(25, 25)
    ))),
    crs = epsg
  )
)
st_write(foret, file.path(out_dir, "foret.gpkg"),
         layer = "foret", delete_dsn = TRUE, quiet = TRUE)

# --- Profils câble analytiques ----------------------------------------------
# Deux profils rectilignes ; altitude = plan incliné le long de la distance.
profil <- function(id, angle_deg, len = 200, step = 10) {
  d <- seq(0, len, by = step)
  data.frame(
    profil = id,
    distance_m = d,
    altitude_m = 100 + slope_x * d * cos(angle_deg * pi / 180)
  )
}
cable <- rbind(profil("P1", 0), profil("P2", 30))
write.csv(cable, file.path(out_dir, "cable_profils.csv"), row.names = FALSE)

message("Jeu jouet écrit dans ", normalizePath(out_dir))
