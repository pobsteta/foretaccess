#' Agrégation zonale des surfaces et volumes (Lot 8)
#'
#' Agrège un raster catégoriel d'accessibilité (issu d'un moteur — [skidder()],
#' [porteur()], [camion_dfci()] — ou d'une couverture câble) en **surfaces** (ha)
#' et, si un raster de volume est fourni, en **volumes** (m³), **par zone** et par
#' classe. Les zones sont des polygones quelconques : massif, parcelle, commune
#' (US-8.2, EF-9/EF-12). C'est le pendant zonal de [recapituler()], qui agrège
#' sur l'emprise entière.
#'
#' @details
#' L'agrégation est un simple **croisement raster** : les zones sont rasterisées
#' sur la grille du raster de classes (par leur identifiant), puis on compte les
#' cellules de chaque classe dans chaque zone. La surface d'une cellule vaut
#' `prod(res)/10000` ha. Une cellule non couverte par une zone est ignorée ; une
#' cellule de classe `NA` (indéterminée) compte dans la colonne `indetermine`.
#'
#' Le résultat est un objet `sf` : **une ligne par zone**, la géométrie d'origine
#' conservée, augmentée de colonnes **larges** par classe — `surface_<classe>_ha`
#' (et `volume_<classe>_m3` si `volume`), plus `surface_totale_ha`. Cette forme
#' est directement **persistable et requêtable** en base ([sb_write_layer()]).
#'
#' @param classes `SpatRaster` catégoriel (facteur) — la sortie `accessibilite`
#'   d'un moteur.
#' @param zones Objet `sf` de polygones (les entités d'agrégation).
#' @param volume `SpatRaster` de volume aligné sur `classes`, ou `NULL`.
#' @param id Nom de la colonne de `zones` identifiant chaque zone. `NULL`
#'   (défaut) : un identifiant `1..n` est ajouté sous la colonne `zone_id`.
#'
#' @return Un objet `sf` (classe `foretaccess_agregation`) : `zones` augmenté des
#'   colonnes d'agrégation. Les zones sans aucune cellule ont des surfaces nulles.
#' @seealso [recapituler()], [sb_write_layer()]
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' sk <- skidder(pre)
#' # Deux zones : moitie ouest / moitie est de l'emprise.
#' e <- terra::ext(pre$mnt)
#' xm <- (e[1] + e[2]) / 2
#' za <- sf::st_as_sf(terra::as.polygons(terra::ext(e[1], xm, e[3], e[4]),
#'                    crs = terra::crs(pre$mnt)))
#' zb <- sf::st_as_sf(terra::as.polygons(terra::ext(xm, e[2], e[3], e[4]),
#'                    crs = terra::crs(pre$mnt)))
#' zones <- rbind(za, zb)
#' agreger_zones(sk$accessibilite, zones)
agreger_zones <- function(classes, zones, volume = NULL, id = NULL) {
  checkmate::assert_class(classes, "SpatRaster")
  if (!terra::is.factor(classes)) {
    cli::cli_abort("{.arg classes} doit etre un raster categoriel (facteur).")
  }
  if (!inherits(zones, "sf")) {
    cli::cli_abort("{.arg zones} doit etre un objet {.cls sf} de polygones.")
  }
  if (!is.null(volume)) {
    checkmate::assert_class(volume, "SpatRaster")
    .valider_grille(volume, classes, "volume")
  }

  # Verrou CRS (regle stricte du projet : aucune couche sans CRS admise).
  crs_r <- terra::crs(classes)
  if (is.na(sf::st_crs(zones))) {
    cli::cli_abort("{.arg zones} n'a pas de CRS ; il doit etre defini et egal a celui de {.arg classes}.")
  }
  if (!isTRUE(sf::st_crs(zones) == sf::st_crs(crs_r))) {
    zones <- sf::st_transform(zones, sf::st_crs(crs_r))
  }

  # Identifiant de zone : colonne fournie, ou 1..n.
  if (is.null(id)) {
    zones$zone_id <- seq_len(nrow(zones))
    id <- "zone_id"
  } else {
    checkmate::assert_choice(id, setdiff(names(zones), attr(zones, "sf_column")))
  }

  # Rasterisation des zones par leur rang (1..n) sur la grille des classes.
  zv <- terra::vect(zones)
  zv$rang_zone <- seq_len(nrow(zones))
  zr <- terra::rasterize(zv, classes, field = "rang_zone")

  rang  <- as.numeric(terra::values(zr))
  codes <- as.numeric(terra::values(classes))
  aire_cellule <- prod(terra::res(classes)) / 10000 # ha

  niveaux <- terra::levels(classes)[[1]]
  etiquettes <- as.character(niveaux[[2]])
  valeurs <- as.numeric(niveaux[[1]])
  # Colonne explicite pour les cellules indeterminees (classe NA), comme recapituler().
  classes_lbl <- c(etiquettes, "indetermine")

  dans <- !is.na(rang)
  vol <- if (is.null(volume)) NULL else as.numeric(terra::values(volume))

  # Comptage (et volume) par zone x classe.
  agg <- .compter_zones(rang[dans], codes[dans],
    if (is.null(vol)) NULL else vol[dans],
    n_zones = nrow(zones), valeurs = valeurs)

  # Colonnes larges : surface_<classe>_ha (+ volume_<classe>_m3).
  for (j in seq_along(classes_lbl)) {
    lab <- .nom_sur(classes_lbl[j])
    zones[[paste0("surface_", lab, "_ha")]] <- agg$cellules[, j] * aire_cellule
    if (!is.null(vol)) {
      zones[[paste0("volume_", lab, "_m3")]] <- agg$volume[, j]
    }
  }
  zones[["surface_totale_ha"]] <- rowSums(agg$cellules) * aire_cellule

  class(zones) <- c("foretaccess_agregation", class(zones))
  attr(zones, "id_zone") <- id
  zones
}

# Comptage (et somme de volume) par zone x classe, vectorise (pas de boucle sur
# les cellules). Renvoie deux matrices n_zones x (n_classes + 1), la derniere
# colonne etant l'indetermine (code NA).
.compter_zones <- function(rang, codes, vol, n_zones, valeurs) {
  nc <- length(valeurs) + 1L
  fz <- factor(rang, levels = seq_len(n_zones))
  # Index de classe : position dans `valeurs`, ou nc pour NA.
  cl <- match(codes, valeurs)
  cl[is.na(cl)] <- nc
  fc <- factor(cl, levels = seq_len(nc))

  cellules <- unclass(table(fz, fc)) # matrice n_zones x nc
  dimnames(cellules) <- NULL

  volume <- NULL
  if (!is.null(vol)) {
    v0 <- vol
    v0[is.na(v0)] <- 0
    volume <- tapply(v0, list(fz, fc), sum)
    volume[is.na(volume)] <- 0 # combinaisons zone x classe absentes
    dim(volume) <- c(n_zones, nc)
    dimnames(volume) <- NULL
  }
  list(cellules = cellules, volume = volume)
}

# Nettoie une etiquette de classe pour en faire un suffixe de colonne sur.
.nom_sur <- function(x) {
  x <- tolower(x)
  x <- gsub("[^a-z0-9]+", "_", x)
  gsub("^_|_$", "", x)
}

#' @export
print.foretaccess_agregation <- function(x, ...) {
  cols <- grep("^surface_.*_ha$", names(x), value = TRUE)
  cli::cli_inform(c(
    "Agregation zonale ForetAccess",
    "*" = "zones : {nrow(x)}",
    "*" = "colonnes de surface : {paste(cols, collapse = ', ')}",
    "*" = "surface totale : {signif(sum(x$surface_totale_ha, na.rm = TRUE), 5)} ha"
  ))
  NextMethod()
  invisible(x)
}
