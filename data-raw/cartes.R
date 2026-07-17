# Génère les cartes de sortie (fond OSM) pour la vignette "cartes".
#
# Exécuté MANUELLEMENT (réseau requis : IGN Géoplateforme + tuiles OSM via
# maptiles). Écrit des PNG dans vignettes/figures/ ; ces images sont commitées et
# la vignette les embarque (aucun calcul lourd ni réseau à la construction du site).
#
#   Rscript data-raw/cartes.R
#
# Données © IGN (Géoplateforme) et © contributeurs OpenStreetMap.

.libPaths(c("/home/pascal/R/x86_64-pc-linux-gnu-library/4.6", .libPaths()))
suppressMessages({
  library(sf)
  library(terra)
  library(maptiles)
  pkgload::load_all(quiet = TRUE)
})

set.seed(1)
fig_dir <- "vignettes/figures"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
cache <- file.path(tempdir(), "cartes-cache")

# --- 1. AOI : fenetre representative au centre de l'AOI fournie ---------------
# data-raw/aoi.gpkg est une emprise fournie localement (gitignore : *.gpkg) ;
# remplacer par n'importe quel polygone d'emprise a CRS defini.
aoi_full <- st_read("data-raw/aoi.gpkg", quiet = TRUE)
ctr <- st_coordinates(st_centroid(st_union(aoi_full)))
# Fenetre volontairement petite : le balayage cable monte jusqu'a longueur_max
# (750 m) par rayon et devient impraticable sur une grande emprise (cf. data-raw/
# bench.R). 350 x 350 m -> pipeline complet, cable compris, en ~1-2 min.
demi <- c(175, 175)
rect <- st_bbox(c(
  xmin = ctr[1] - demi[1], xmax = ctr[1] + demi[1],
  ymin = ctr[2] - demi[2], ymax = ctr[2] + demi[2]
), crs = st_crs(aoi_full))
aoi <- st_as_sf(st_as_sfc(rect))

# --- 2. Acquisition (IGN) + pretraitement + moteurs --------------------------
message("Acquisition IGN...")
inp <- acquire_inputs(aoi, sources = c("mnt", "desserte", "foret"),
  cache_dir = cache, res_m = 5, buffer_m = 50)

# BD TOPO ne distingue pas la classe DFCI (spec 010 Q2). Le camion lit desormais
# le flag `dfci` de la desserte (attribut CL_DFCI chez Sylvaccess), rasterise par
# preprocess en `dfci_source_mask`. Pour la demonstration, on marque les
# routes/pistes forestieres comme sources du camion (realiste en foret).
inp$desserte$dfci <- as.integer(inp$desserte$classe %in% c("route", "piste"))
pre <- preprocess(inp$mnt, inp$desserte, inp$foret)
message("Moteurs terrestres...")
sk <- skidder(pre)
po <- porteur(pre)
df <- camion_dfci(pre)
message("Cable...")
cab <- potentiel_cable(pre)
sel <- selectionner_lignes(cab)

# Agregation zonale sur 4 quadrants (a defaut de parcellaire).
e <- st_bbox(aoi)
xm <- (e[["xmin"]] + e[["xmax"]]) / 2
ym <- (e[["ymin"]] + e[["ymax"]]) / 2
quad <- function(x0, x1, y0, y1, nom) {
  z <- st_as_sf(st_as_sfc(st_bbox(c(xmin = x0, xmax = x1, ymin = y0, ymax = y1),
    crs = st_crs(aoi))))
  z$nom <- nom
  z[, "nom"]
}
zones <- rbind(
  quad(e[["xmin"]], xm, e[["ymin"]], ym, "SO"), quad(xm, e[["xmax"]], e[["ymin"]], ym, "SE"),
  quad(e[["xmin"]], xm, ym, e[["ymax"]], "NO"), quad(xm, e[["xmax"]], ym, e[["ymax"]], "NE")
)
agg <- agreger_zones(sk$accessibilite, zones, id = "nom")

# --- 3. Fond OSM (une fois) --------------------------------------------------
message("Tuiles OSM...")
bm <- get_tiles(aoi, provider = "OpenStreetMap", crop = TRUE, zoom = 15, cachedir = cache)
crs_web <- terra::crs(bm)
en_web_r <- function(r, method = "near") terra::project(r, crs_web, method = method)
en_web_v <- function(v) sf::st_transform(v, sf::st_crs(crs_web))

# Cadre commun : ouvre un PNG, dessine le fond OSM, execute `dessin()`, ajoute
# titre / legende / credits, ferme.
carte <- function(fichier, titre, dessin, legende = NULL) {
  png(file.path(fig_dir, fichier), width = 900, height = 680, res = 110)
  op <- par(mar = c(0.5, 0.5, 2.2, 0.5))
  on.exit({
    par(op)
    dev.off()
  })
  terra::plotRGB(bm)
  dessin()
  title(titre, cex.main = 1)
  if (!is.null(legende)) {
    legend("bottomright", legend = legende$labels, fill = legende$fill,
      col = legende$col, lwd = legende$lwd, bg = "white", cex = 0.8, inset = 0.01)
  }
  mtext("Fond : OpenStreetMap | Donnees : IGN", side = 1, line = -1, adj = 0.01, cex = 0.6)
}

# Raster categoriel semi-transparent + description de sa legende.
pal_acc <- c(parcourable = "#1a9850", accessible = "#a6d96a",
  non_accessible = "#d73027", hors_foret = "#bdbdbd")
# DFCI radial (Lot 12a.4) : 6 classes -- inaccessible, non defendable (pente),
# trois bandes de lance croissantes (c1 la plus proche = mieux defendue), hors foret.
pal_dfci <- c(
  inaccessible         = "#bdbdbd",
  non_defendable_pente = "#d73027",
  defendable_c1        = "#08519c",
  defendable_c2        = "#3182bd",
  defendable_c3        = "#9ecae1",
  hors_foret           = "#bdbdbd"
)

# Raster categoriel : classes metier semi-transparentes (fond OSM visible),
# `hors_foret` totalement transparent (on voit l'OSM en dessous).
dessine_categoriel <- function(r, pal, alpha_hex = "99") {
  niv <- terra::levels(r)[[1]]
  labs <- as.character(niv[[2]])
  base <- unname(pal[labs])
  a <- ifelse(labs == "hors_foret", "00", alpha_hex)
  terra::plot(en_web_r(r), add = TRUE, col = paste0(base, a), legend = FALSE,
    axes = FALSE, mar = NA)
  list(labels = labs, fill = paste0(base, "FF"), col = NA, lwd = NA)
}

# --- 4. Cartes des entrees (contexte) ---------------------------------------
message("Rendu des cartes...")
mnt_w <- en_web_r(terra::rast(inp$mnt), method = "bilinear")
carte("carte-mnt.png", "Entree : MNT (RGE ALTI 5 m)", function() {
  terra::plot(mnt_w, add = TRUE, col = terrain.colors(50), alpha = 0.6, legend = FALSE)
  plot(st_geometry(en_web_v(inp$desserte)), add = TRUE, col = "grey20", lwd = 1.4)
})

pal_desserte <- c(route = "#000000", piste = "#e6550d", dfci = "#3182bd")
carte("carte-desserte.png", "Entree : desserte (BD TOPO)", function() {
  d <- en_web_v(inp$desserte)
  plot(st_geometry(d), add = TRUE, col = pal_desserte[d$classe], lwd = 2)
}, legende = list(labels = names(pal_desserte), fill = NA,
  col = unname(pal_desserte), lwd = 2))

carte("carte-foret.png", "Entree : foret (BD Foret v2)", function() {
  plot(st_geometry(en_web_v(inp$foret)), add = TRUE, col = "#31a35455", border = "#238b45")
})

# --- 5. Cartes RASTER de sortie ---------------------------------------------
# Legende (couleurs pleines) construite a partir des niveaux du raster.
legende_cat <- function(r, pal) {
  labs <- as.character(terra::levels(r)[[1]][[2]])
  list(labels = labs, fill = unname(pal[labs]), col = NA, lwd = NA)
}

carte("carte-skidder.png", "Skidder : accessibilite",
  function() dessine_categoriel(sk$accessibilite, pal_acc),
  legende = legende_cat(sk$accessibilite, pal_acc))

carte("carte-porteur.png", "Porteur : accessibilite",
  function() dessine_categoriel(po$accessibilite, pal_acc),
  legende = legende_cat(po$accessibilite, pal_acc))

carte("carte-dfci.png", "Camion DFCI : zone defendable",
  function() dessine_categoriel(df$accessibilite, pal_dfci),
  legende = legende_cat(df$accessibilite, pal_dfci))

# --- 6. Cartes VECTEUR de sortie --------------------------------------------
carte("carte-cable.png", "Cable : lignes selectionnees", function() {
  plot(st_geometry(en_web_v(inp$desserte)), add = TRUE, col = "grey20", lwd = 1.5)
  if (nrow(sel$lignes)) {
    plot(st_geometry(en_web_v(sel$lignes)), add = TRUE, col = "#d9480199", lwd = 1.1)
  }
}, legende = list(labels = c("desserte", "ligne cable retenue"), fill = NA,
  col = c("grey20", "#d94801"), lwd = c(1.5, 1.5)))

carte("carte-agregation.png", "Agregation zonale : surface parcourable (ha)", function() {
  a <- en_web_v(agg)
  brk <- pretty(a$surface_parcourable_ha, 4)
  pal <- hcl.colors(max(1, length(brk) - 1), "Greens", rev = TRUE)
  ic <- as.integer(cut(a$surface_parcourable_ha, brk, include.lowest = TRUE))
  plot(st_geometry(a), add = TRUE, col = paste0(pal[ic], "aa"), border = "grey20")
  text(st_coordinates(st_centroid(st_geometry(a))),
    labels = round(a$surface_parcourable_ha, 1), cex = 0.85, font = 2)
})

message("OK : cartes ecrites dans ", fig_dir)
