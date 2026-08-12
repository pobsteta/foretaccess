.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressMessages(devtools::load_all("/home/pascal/dev/foretaccess", quiet = TRUE))
suppressMessages(library(sf)); suppressMessages(library(terra))
dire <- function(...) { cat(..., "\n"); flush.console() }
set.seed(26)   # CA-26.5 : tirage REPRODUCTIBLE, sinon le banc n'est pas rejouable.

P <- "/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi"
G <- file.path(P, "cache/desserte/desserte.gpkg")
SORTIE <- "/home/pascal/dev/foretaccess/data-raw/annotation_wsfi"
GPKG <- file.path(SORTIE, "annotation.gpkg")

parc <- st_read(G, layer = "parcelles", quiet = TRUE)
des  <- st_read(G, layer = "desserte_existante", quiet = TRUE)
mnt0 <- rast(file.path(P, "cache/layers/lidar_mnt_mosaic.tif"))
aoi  <- st_buffer(st_as_sf(st_as_sfc(st_bbox(parc))), 100)
mnt  <- crop(mnt0, ext(vect(aoi)))
emprise <- st_as_sf(st_as_sfc(st_bbox(mnt)))
ref <- suppressWarnings(st_intersection(des, emprise))
crs_l <- st_crs(emprise)

# Corridor de la reference : ces cellules sont exclues de la detection, donc
# inutile d'y chercher du non-detecte.
corridor <- st_union(st_buffer(st_geometry(ref), 15))

# --- Tuiles de 1 ha, grille reguliere ---------------------------------------
grille <- st_make_grid(emprise, cellsize = 100, square = TRUE)
grille <- st_sf(geometry = grille)
grille <- grille[as.numeric(st_area(grille)) > 9990, ]           # tuiles pleines
# Part de la tuile HORS corridor. `st_intersection` ne rend que les tuiles qui
# intersectent, dans un ordre qui n'est pas celui de la grille : on soustrait
# tuile par tuile plutot que d'apparier a l'aveugle (la version precedente
# rendait 1 partout, ce qui contredisait les 23,4 % de corridor mesures).
aire_corr <- rep(0, nrow(grille))
touche <- which(lengths(st_intersects(st_geometry(grille), corridor)) > 0)
for (k in touche) {
  inter <- suppressWarnings(st_intersection(st_geometry(grille)[k], corridor))
  aire_corr[k] <- if (length(inter)) sum(as.numeric(st_area(inter))) else 0
}
grille$part_libre <- pmin(pmax(1 - aire_corr / 10000, 0), 1)

# On ne retient que les tuiles majoritairement ANALYSABLES : annoter du corridor
# reviendrait a chercher du non-detecte la ou le detecteur ne regarde pas.
cand_tuiles <- grille[grille$part_libre >= 0.6, ]
dire("tuiles de 1 ha pleines :", nrow(grille), "| analysables a >= 60 % :", nrow(cand_tuiles))

# --- Stratification par pente ------------------------------------------------
pente <- terrain(mnt, v = "slope", unit = "degrees")
cand_tuiles$pente_med <- terra::extract(pente, vect(cand_tuiles), fun = median,
                                        na.rm = TRUE)[, 2]
cand_tuiles <- cand_tuiles[!is.na(cand_tuiles$pente_med), ]
q <- quantile(cand_tuiles$pente_med, c(1/3, 2/3), na.rm = TRUE)
cand_tuiles$strate <- cut(cand_tuiles$pente_med, c(-Inf, q, Inf),
                          labels = c("douce", "moyenne", "raide"))
dire("pente mediane par tuile :", paste(round(range(cand_tuiles$pente_med), 1), collapse = " a "), "deg")
print(table(strate = cand_tuiles$strate))

# 10 tuiles : 3 / 3 / 4, tirage reproductible dans chaque strate.
n_par <- c(douce = 3, moyenne = 3, raide = 4)
sel <- do.call(rbind, lapply(names(n_par), function(s) {
  pool <- cand_tuiles[cand_tuiles$strate == s, ]
  pool[sample.int(nrow(pool), min(n_par[[s]], nrow(pool))), ]
}))
sel$id_tuile <- seq_len(nrow(sel))
sel$fait <- NA_character_          # <- "oui" quand la tuile est scrutee
sel$n_trouve <- NA_integer_        # <- combien de lineaires reels y ont ete vus
dire("\ntuiles retenues :", nrow(sel))
print(st_drop_geometry(sel)[, c("id_tuile", "strate", "pente_med", "part_libre")])

# --- Couche VIDE a numeriser -------------------------------------------------
# Schema impose : c'est ce qui rendra l'annotation exploitable sans reprise.
a_num <- st_sf(
  id = integer(0), id_tuile = integer(0),
  type = character(0),        # piste | cloisonnement | fosse | limite | terrasse | autre
  certitude = character(0),   # sure | probable | douteuse
  commentaire = character(0),
  geometry = st_sfc(crs = crs_l)
)

# --- Ecriture ----------------------------------------------------------------
cands <- st_read(GPKG, layer = "candidats", quiet = TRUE)
cands$dans_tuile <- lengths(st_intersects(cands, sel)) > 0
st_write(cands, GPKG, layer = "candidats", delete_layer = TRUE, quiet = TRUE)
st_write(sel, GPKG, layer = "tuiles_a_scruter", delete_layer = TRUE, quiet = TRUE)
st_write(a_num, GPKG, layer = "a_numeriser", delete_layer = TRUE, quiet = TRUE)

dire("\ncandidats detectes :", nrow(cands), "| dont dans une tuile :", sum(cands$dans_tuile))
dire("Ecrit :", GPKG)
print(st_layers(GPKG)$name)
