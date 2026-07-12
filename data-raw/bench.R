# Benchmark chronometre de chaque etage du pipeline sur l'AOI complete (721 ha).
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressMessages({ library(sf); library(terra); pkgload::load_all(quiet = TRUE) })

chrono <- function(label, expr) {
  t <- system.time(val <- force(expr))["elapsed"]
  cat(sprintf("%-32s %7.1f s\n", label, t))
  invisible(val)
}

aoi <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
cache <- file.path(tempdir(), "bench-cache")
cat("== AOI complete (721 ha) ==\n")

inp <- chrono("acquisition IGN (mnt+desserte+foret)",
  acquire_inputs(aoi, sources = c("mnt", "desserte", "foret"), cache_dir = cache, res_m = 5, buffer_m = 100))
pre <- chrono("preprocess", preprocess(inp$mnt, inp$desserte, inp$foret))

ncell <- terra::ncell(pre$mnt)
nforet <- sum(terra::values(pre$foret_mask) == 1, na.rm = TRUE)
cat(sprintf("  grille : %d cellules (%d foret)\n", ncell, nforet))

sk <- chrono("skidder", skidder(pre))
po <- chrono("porteur", porteur(pre))
cfg_dfci <- foretaccess_config(dfci = list(classes_source = c("route", "piste")))
df <- chrono("camion_dfci", camion_dfci(pre, cfg_dfci))

# Agregation (zones = 4 quadrants).
e <- st_bbox(aoi); xm <- (e[["xmin"]]+e[["xmax"]])/2; ym <- (e[["ymin"]]+e[["ymax"]])/2
q <- function(x0,x1,y0,y1,n){z<-st_as_sf(st_as_sfc(st_bbox(c(xmin=x0,xmax=x1,ymin=y0,ymax=y1),crs=st_crs(aoi))));z$nom<-n;z[,"nom"]}
zones <- rbind(q(e[["xmin"]],xm,e[["ymin"]],ym,"SO"),q(xm,e[["xmax"]],e[["ymin"]],ym,"SE"),
               q(e[["xmin"]],xm,ym,e[["ymax"]],"NO"),q(xm,e[["xmax"]],ym,e[["ymax"]],"NE"))
agg <- chrono("agreger_zones", agreger_zones(sk$accessibilite, zones, id = "nom"))

# --- Cable : mesure sur une fenetre puis extrapolation ----------------------
cat("\n== Cable : mesure sur fenetre + extrapolation ==\n")
ctr <- st_coordinates(st_centroid(st_union(aoi)))
win <- function(demi){
  r <- st_bbox(c(xmin=ctr[1]-demi,xmax=ctr[1]+demi,ymin=ctr[2]-demi,ymax=ctr[2]+demi),crs=st_crs(aoi))
  st_as_sf(st_as_sfc(r))
}
w <- win(250) # fenetre 500 x 500 m
inw <- acquire_inputs(w, sources=c("mnt","desserte","foret"), cache_dir=cache, res_m=5, buffer_m=50)
prew <- preprocess(inw$mnt, inw$desserte, inw$foret)
nforet_w <- sum(terra::values(prew$foret_mask)==1, na.rm=TRUE)
tcab <- system.time(potentiel_cable(prew))["elapsed"]
cat(sprintf("cable sur fenetre 500m       %7.1f s  (%d cellules foret)\n", tcab, nforet_w))
par_cell <- tcab / max(1, nforet_w)
cat(sprintf("  cout ~ %.4f s / cellule foret\n", par_cell))
cat(sprintf("  -> extrapolation cable 721 ha (%d cellules foret) : %.0f s (~%.1f min)\n",
    nforet, par_cell*nforet, par_cell*nforet/60))
