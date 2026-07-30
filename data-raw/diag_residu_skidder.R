# Diagnostic : d'ou viennent les 22,3 ha ou NOUS disons `inaccessible` et
# ACCESSFOR `500-1000 m` (skidder, AOI Chastel-Nouvel, spec 024 CA-24.5) ?
#
# L'hypothese des composantes orphelines est REFUTEE (spec 025) : avec une
# acquisition correcte, il n'y a aucune infraction d'integrite dans l'AOI stricte.
#
# NOUVELLE HYPOTHESE : le MNT. Le skidder est borne par `pente_skidder_max_pct`
# (30 %) pour parcourir le terrain hors desserte. Notre MNT LiDAR HD voit du
# micro-relief que le RGE Alti d'ACCESSFOR lisse. Or l'effet d'un desaccord de
# pente n'est PAS symetrique en accessibilite, meme quand le desaccord PAR
# CELLULE l'est : une cellule bloquee coupe tout ce qui se trouve DERRIERE elle.
# Mesure du 2026-07-29 au seuil 30 % : 27,8 ha vus trop pentus par le LiDAR seul
# contre 25,1 ha par le RGE seul -- quasi symetrique par cellule, mais chaque
# micro-barriere peut condamner une zone entiere.
#
# PROTOCOLE : rejouer le skidder a entrees STRICTEMENT identiques, en ne changeant
# que le MNT (LiDAR HD -> dalles departementales RGE Alti), et mesurer le
# deplacement de la frontiere accessible/inaccessible.
#
# Prerequis : les dalles RGE Alti du dep. 48 en cache (cf. acquire_mnt_rgealti()).
#
# Usage : FA_DFCI=0 Rscript data-raw/diag_residu_skidder.R
.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressPackageStartupMessages({
  library(sf)
  library(terra)
  pkgload::load_all(quiet = TRUE)
})

AOI <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
CACHE <- Sys.getenv("ACCESSFOR_CACHE", "/tmp/accessfor-cache")
emprise <- st_buffer(AOI, 100)
DFCI <- !identical(Sys.getenv("FA_DFCI"), "0")

# --- 1. Entrees communes ----------------------------------------------------
inp <- acquire_inputs(emprise, sources = c("mnt", "desserte", "foret"),
  cache_dir = CACHE, res_m = 5, buffer_m = 0, dfci = DFCI)
mnt_lidar <- rast(inp$mnt)
desserte <- inp$desserte
foret <- inp$foret

# --- 2. Le MEME MNT, depuis les dalles RGE Alti ------------------------------
dalles <- list.files("data-raw/oracle/aoi/cache/rgealti", pattern = "\\.asc$",
  recursive = TRUE, full.names = TRUE)
if (!length(dalles)) {
  cli::cli_abort("Dalles RGE Alti absentes : voir acquire_mnt_rgealti().")
}
tuiles <- lapply(dalles, function(f) {
  r <- rast(f)
  crs(r) <- "EPSG:2154"
  r
})
mnt_rge <- if (length(tuiles) == 1) tuiles[[1]] else do.call(terra::merge, tuiles)
# Aligne STRICTEMENT sur la grille LiDAR : on ne compare que le MNT, pas la grille.
mnt_rge <- resample(crop(mnt_rge, ext(mnt_lidar), snap = "out"), mnt_lidar,
  method = "bilinear")

cat(sprintf("grille : %s | LiDAR HD et RGE Alti alignes\n",
  paste(dim(mnt_lidar)[1:2], collapse = " x ")))

# --- 3. Skidder sur chaque MNT ----------------------------------------------
config <- foretaccess_config()
lancer <- function(mnt, nom) {
  t <- system.time({
    pre <- preprocess(mnt, desserte, foret, config = config)
    sk <- skidder(pre, config)
  })
  cat(sprintf("  %-10s %5.1f s\n", nom, t[["elapsed"]]))
  list(pre = pre, sk = sk)
}
cat("\nskidder :\n")
a <- lancer(mnt_lidar, "LiDAR HD")
b <- lancer(mnt_rge, "RGE Alti")

# --- 4. Le deplacement de la frontiere --------------------------------------
acc <- function(x) {
  r <- x$sk$accessibilite
  lev <- try(levels(r)[[1]], silent = TRUE)
  v <- values(r, mat = FALSE)
  if (inherits(lev, "data.frame") && ncol(lev) >= 2) {
    codes <- lev[[1]][grepl("accessible", tolower(as.character(lev[[2]])))]
    v %in% codes
  } else {
    !is.na(v) & v > 0
  }
}
fa <- acc(a)
fb <- acc(b)
mfor <- !is.na(values(a$pre$foret_mask, mat = FALSE)) &
  values(a$pre$foret_mask, mat = FALSE) == 1
ha <- function(x) sum(x, na.rm = TRUE) * prod(res(mnt_lidar)) / 1e4

cat("\n--- surface forestiere accessible au skidder ---\n")
cat(sprintf("  LiDAR HD : %7.1f ha\n", ha(fa & mfor)))
cat(sprintf("  RGE Alti : %7.1f ha\n", ha(fb & mfor)))
cat(sprintf("  ecart    : %+7.1f ha\n", ha(fb & mfor) - ha(fa & mfor)))

cat("\n--- deplacement de la frontiere (foret) ---\n")
cat(sprintf("  inaccessible LiDAR / accessible RGE : %6.1f ha  <- notre residu\n",
  ha(!fa & fb & mfor)))
cat(sprintf("  accessible LiDAR / inaccessible RGE : %6.1f ha\n",
  ha(fa & !fb & mfor)))

cat("\nLecture : le bloc `inaccessible` x `500-1000` de la matrice ACCESSFOR vaut\n")
cat("22,3 ha. Si « inaccessible LiDAR / accessible RGE » en approche l'ordre de\n")
cat("grandeur, le MNT explique le residu ; sinon il faut chercher ailleurs.\n")
