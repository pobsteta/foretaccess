# Prepare une campagne d'annotation CA-26.5 sur UN BLOC quelconque.
#
# Generalisation de `tirage_tuiles.R`, ecrit d'abord pour `wsfi` puis rejoue sur
# `ltcp` : le protocole ne vaut que s'il se transporte, et un tirage code en dur
# ne se transporte pas. Meme logique que `FA_BLOC` dans `banc_longmin.R`.
#
# Usage :
#   FA_BLOC=/chemin/vers/projet FA_SORTIE=data-raw/annotation_xxx \
#     Rscript data-raw/annotation_wsfi/preparer_annotation.R
#
# Produit `annotation.gpkg` : `tuiles_a_scruter` (tirage stratifie par pente),
# `a_numeriser` (couche POLYLIGNE vide, au schema impose), et le contexte. Les
# `candidats` sont ajoutes ensuite par le script de detection -- ils coutent des
# dizaines de minutes, les tuiles quelques secondes.

.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressMessages(devtools::load_all("/home/pascal/dev/foretaccess", quiet = TRUE))
suppressMessages(library(sf)); suppressMessages(library(terra))
dire <- function(...) { cat(..., "\n"); flush.console() }

# GRAINE FIXE : un tirage non reproductible ne vaut rien comme banc -- on ne
# pourrait pas rejouer la campagne ni verifier qu'elle n'a pas ete choisie.
set.seed(26)

BLOC   <- Sys.getenv("FA_BLOC", "/home/pascal/.local/share/nemeton/projects/20260701_204501_ltcp")
SORTIE <- Sys.getenv("FA_SORTIE", "data-raw/annotation_ltcp")
MNT    <- Sys.getenv("FA_MNT", "")
REF    <- Sys.getenv("FA_REF", "")
COTE   <- as.numeric(Sys.getenv("FA_COTE", "1000"))   # cote de la sous-emprise (m)
N_TUILES <- as.integer(Sys.getenv("FA_N_TUILES", "10"))
dir.create(SORTIE, recursive = TRUE, showWarnings = FALSE)
GPKG <- file.path(SORTIE, "annotation.gpkg")

mnt0 <- rast(if (nzchar(MNT)) MNT else file.path(BLOC, "cache/layers/lidar_mnt_mosaic.tif"))
ref0 <- st_read(REF, quiet = TRUE)

# SOUS-EMPRISE. Legitime depuis que l'indice est ancre (bornes absolues +
# `c_vessel`) : analyser une sous-emprise rend le meme resultat que le tout.
# C'est ce qui borne le cout -- 2 500 ha a 0,5 m font 100 M cellules.
cx <- (xmin(mnt0) + xmax(mnt0)) / 2; cy <- (ymin(mnt0) + ymax(mnt0)) / 2
mnt <- crop(mnt0, ext(cx - COTE/2, cx + COTE/2, cy - COTE/2, cy + COTE/2))
emprise <- st_as_sf(st_as_sfc(st_bbox(mnt)))
ref <- suppressWarnings(st_intersection(ref0, emprise))
crs_l <- st_crs(emprise)
dire("bloc     :", basename(BLOC))
dire("emprise  :", round(as.numeric(st_area(emprise)) / 1e4, 1), "ha |",
     ncell(mnt), "cellules a", res(mnt)[1], "m")
dire("reference:", nrow(ref), "troncons |", round(sum(as.numeric(st_length(ref)))), "m")

# Corridor d'exclusion : le detecteur n'y regarde pas, inutile d'y annoter.
corridor <- st_union(st_buffer(st_geometry(ref), 15))

grille <- st_sf(geometry = st_make_grid(emprise, cellsize = 100, square = TRUE))
grille <- grille[as.numeric(st_area(grille)) > 9990, ]
aire_corr <- rep(0, nrow(grille))
for (k in which(lengths(st_intersects(st_geometry(grille), corridor)) > 0)) {
  inter <- suppressWarnings(st_intersection(st_geometry(grille)[k], corridor))
  aire_corr[k] <- if (length(inter)) sum(as.numeric(st_area(inter))) else 0
}
grille$part_libre <- pmin(pmax(1 - aire_corr / 10000, 0), 1)
cand <- grille[grille$part_libre >= 0.6, ]
dire("tuiles de 1 ha :", nrow(grille), "| analysables a >= 60 % :", nrow(cand))

pente <- terrain(mnt, v = "slope", unit = "degrees")
cand$pente_med <- terra::extract(pente, vect(cand), fun = median, na.rm = TRUE)[, 2]
cand <- cand[!is.na(cand$pente_med), ]
# STRATIFIER SUR UNE VARIABLE HOMOGENE NE STRATIFIE RIEN, et donne une fausse
# assurance : trois strates qui s'etalent de 2,3 a 3,6 degres decrivent le meme
# terrain. Sur `ltcp` (plaine : 28 m de denivele au km, pente mediane 2,7 deg)
# la stratification par pente est vide de sens ; sur `wsfi` (montagne, 337 m de
# denivele, 21,9 deg) elle protege reellement contre un tirage atypique. On
# mesure l'etendue avant de decider, plutot que d'appliquer la recette.
etendue <- diff(quantile(cand$pente_med, c(0.1, 0.9), na.rm = TRUE))
stratifier <- etendue >= 5
if (stratifier) {
  q <- quantile(cand$pente_med, c(1/3, 2/3), na.rm = TRUE)
  cand$strate <- cut(cand$pente_med, c(-Inf, q, Inf),
                     labels = c("douce", "moyenne", "raide"))
  n_par <- c(douce = floor(N_TUILES/3), moyenne = floor(N_TUILES/3),
             raide = N_TUILES - 2*floor(N_TUILES/3))
  sel <- do.call(rbind, lapply(names(n_par), function(s) {
    pool <- cand[cand$strate == s, ]
    pool[sample.int(nrow(pool), min(n_par[[s]], nrow(pool))), ]
  }))
  dire(sprintf("stratification par pente : etendue p10-p90 = %.1f deg", etendue))
} else {
  cand$strate <- "homogene"
  sel <- cand[sample.int(nrow(cand), min(N_TUILES, nrow(cand))), ]
  dire(sprintf("TIRAGE SIMPLE : etendue p10-p90 = %.1f deg seulement -- le bloc est",
               etendue))
  dire("  homogene en pente, stratifier n'y apporterait rien qu'une fausse assurance.")
}
sel$id_tuile <- seq_len(nrow(sel)); sel$origine <- "aleatoire"
sel$fait <- NA_character_; sel$n_trouve <- NA_integer_
dire("")
print(st_drop_geometry(sel)[, c("id_tuile", "strate", "pente_med", "part_libre")])

# Attribution d'un lineaire annote a SA tuile : par la PART DE LONGUEUR, jamais
# par le premier intersect. Un objet peut effleurer le bord d'une tuile voisine
# -- sur `ltcp`, une piste de 99 m entierement dans la tuile 7 se retrouvait
# comptee en 3, et le depouillement signalait a tort deux incoherences dans
# l'annotation. Le defaut etait dans le depouillement.
tuile_dominante <- function(objets, tuiles) {
  h <- sf::st_intersects(objets, tuiles)
  vapply(seq_along(h), function(i) {
    k <- h[[i]]
    if (!length(k)) return(NA_integer_)
    parts <- vapply(k, function(j) {
      p <- suppressWarnings(sf::st_intersection(sf::st_geometry(objets)[i],
                                                sf::st_geometry(tuiles)[j]))
      if (!length(p)) 0 else as.numeric(sf::st_length(p))
    }, numeric(1))
    tuiles$id_tuile[k[which.max(parts)]]
  }, integer(1))
}

# Couche a numeriser : LINESTRING explicite. Un `st_sfc()` vide n'a pas de type,
# GDAL ecrit « Unknown (any) » et QGIS refuse d'y numeriser.
a_num <- st_sf(id = 1L, id_tuile = NA_integer_, type = NA_character_,
               certitude = NA_character_, commentaire = NA_character_,
               geometry = st_sfc(st_linestring(), crs = crs_l))[0, ]

st_write(sel, GPKG, layer = "tuiles_a_scruter", delete_dsn = TRUE, quiet = TRUE)
st_write(a_num, GPKG, layer = "a_numeriser", append = TRUE, quiet = TRUE)
st_write(ref, GPKG, layer = "reference_bdtopo", append = TRUE, quiet = TRUE)
st_write(emprise, GPKG, layer = "emprise", append = TRUE, quiet = TRUE)
dire("")
dire("Ecrit :", GPKG)
print(st_layers(GPKG)$name)
