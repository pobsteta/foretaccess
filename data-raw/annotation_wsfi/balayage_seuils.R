.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressMessages(devtools::load_all("/home/pascal/dev/foretaccess", quiet = TRUE))
suppressMessages(library(sf)); suppressMessages(library(terra))
dire <- function(...) { cat(..., "\n"); flush.console() }

P <- "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi"
G <- file.path(P, "cache/desserte/desserte.gpkg")
SORTIE <- "/home/pascal/dev/foretaccess/data-raw/annotation_wsfi"
dir.create(SORTIE, recursive = TRUE, showWarnings = FALSE)

parc <- st_read(G, layer = "parcelles", quiet = TRUE)
des  <- st_read(G, layer = "desserte_existante", quiet = TRUE)
mnt0 <- rast(file.path(P, "cache/layers/lidar_mnt_mosaic.tif"))
laz  <- list.files(file.path(P, "cache/layers/lidar_nuage"), pattern = "laz$", full.names = TRUE)

aoi <- st_buffer(st_as_sf(st_as_sfc(st_bbox(parc))), 100)
mnt <- crop(mnt0, ext(vect(aoi)))
emprise <- st_as_sf(st_as_sfc(st_bbox(mnt)))
# Reference restreinte a l'emprise : inutile de faire porter 806 km au corridor
# quand 226 km seulement la traversent.
ref <- suppressWarnings(st_intersection(des, emprise))

dire("emprise :", round(as.numeric(st_area(emprise)) / 1e4, 1), "ha |",
     ncell(mnt), "cellules a", res(mnt)[1], "m")
dire("reference :", nrow(ref), "troncons")
dire("")

# On descend jusqu'a trouver des candidats. `long_min` abaisse aussi le plancher :
# a 30 m, un troncon de piste ancienne fragmente ne survit pas.
essais <- list(
  list(seuil = 0.50, long_min = 30),
  list(seuil = 0.40, long_min = 30),
  list(seuil = 0.30, long_min = 20),
  list(seuil = 0.20, long_min = 20)
)

trouve <- NULL
for (e in essais) {
  t <- Sys.time()
  d <- tryCatch(suppressWarnings(detecter_desserte(
    mnt, reference = ref, las_source = laz,
    seuil = e$seuil, long_min = e$long_min, specs = "auto")),
    error = function(err) structure(list(m = conditionMessage(err)), class = "err"))
  s <- as.numeric(difftime(Sys.time(), t, units = "secs"))
  if (inherits(d, "err")) { dire(sprintf("seuil %.2f -> ERREUR : %s", e$seuil, d$m)); next }
  m <- if (nrow(d)) sum(as.numeric(st_length(d))) else 0
  dire(sprintf("seuil %.2f / long_min %d -> %5.0f s | %4d troncon(s) | %7.0f m",
               e$seuil, e$long_min, s, nrow(d), m))
  if (nrow(d) > 0 && is.null(trouve)) {
    d$seuil <- e$seuil; d$long_min <- e$long_min
    trouve <- d
    dire("   -> premiers candidats a ce seuil, on s'arrete la pour l'annotation.")
    break
  }
  gc(verbose = FALSE)
}

if (is.null(trouve)) {
  dire("")
  dire("AUCUN CANDIDAT jusqu'a seuil 0,20. Le detecteur ne produit rien sur ce")
  dire("massif, quelles que soient les bornes ET le seuil : il n'y a pas de")
  dire("campagne d'annotation a monter sur les candidats -- il n'y en a pas.")
} else {
  # Couche pretes a annoter dans QGIS.
  trouve$id_candidat <- seq_len(nrow(trouve))
  trouve$verdict <- NA_character_     # <- a remplir sur le terrain / l'ortho
  trouve$commentaire <- NA_character_
  st_write(trouve, file.path(SORTIE, "annotation.gpkg"), layer = "candidats",
           delete_dsn = TRUE, quiet = TRUE)
  st_write(ref, file.path(SORTIE, "annotation.gpkg"), layer = "reference_bdtopo",
           append = TRUE, quiet = TRUE)
  st_write(emprise, file.path(SORTIE, "annotation.gpkg"), layer = "emprise",
           append = TRUE, quiet = TRUE)
  st_write(parc, file.path(SORTIE, "annotation.gpkg"), layer = "parcelles",
           append = TRUE, quiet = TRUE)
  dire("")
  dire("Ecrit :", file.path(SORTIE, "annotation.gpkg"))
  dire("  couches : candidats (a annoter), reference_bdtopo, emprise, parcelles")
}
