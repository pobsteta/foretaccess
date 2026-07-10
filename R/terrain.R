#' Pente et exposition depuis un MNT
#'
#' Dérive la **pente en pourcentage** et l'**exposition en degrés** (0–360 depuis
#' le nord, sens horaire) d'un modèle numérique de terrain, via
#' [terra::terrain()].
#'
#' La méthode par défaut est **Horn** (8 voisins), celle de `terra`. Elle reste
#' configurable (`config$general$methode_pente`) pour permettre une réconciliation
#' ultérieure avec l'oracle Sylvaccess v3.6 sans refonte (spec 001 §10, décision 2).
#'
#' @details
#' Conventions de sortie :
#' * `slope_pct` = `tan(pente_radians) * 100`.
#' * `aspect_deg` vaut `NA` sur les cellules **plates** (pente nulle), là où
#'   `terra` renvoie conventionnellement 90.
#' * Les cellules de **bordure** valent `NA` dans les deux couches : le calcul
#'   exige les 8 voisins. C'est un effet de bord documenté (spec 001 §8) ; les
#'   comparaisons à l'oracle portent sur l'intérieur du raster.
#'
#' @param mnt `SpatRaster` mono-couche, ou chemin de fichier.
#' @param methode Méthode de calcul : `"Horn"` (8 voisins) ou `"Evans"`
#'   (4 voisins).
#'
#' @return Une liste de deux `SpatRaster` : `slope_pct` et `aspect_deg`, sur la
#'   grille du MNT.
#' @export
#' @examples
#' mnt <- terra::rast(system.file("extdata/toy/mnt.tif", package = "foretaccess"))
#' terr <- calculer_terrain(mnt)
#' terra::global(terr$slope_pct, "mean", na.rm = TRUE)
calculer_terrain <- function(mnt, methode = "Horn") {
  mnt <- .as_raster(mnt, "mnt")
  checkmate::assert_choice(methode, .methodes_terrain())

  voisins <- .voisins_terrain(methode)

  pente_rad <- terra::terrain(mnt, v = "slope", unit = "radians", neighbors = voisins)
  aspect <- terra::terrain(mnt, v = "aspect", unit = "degrees", neighbors = voisins)

  slope_pct <- tan(pente_rad) * 100
  # Sur une cellule plate, terra renvoie 90 par convention : on marque NA.
  aspect_deg <- terra::ifel(pente_rad > 0, aspect, NA)

  names(slope_pct) <- "slope_pct"
  names(aspect_deg) <- "aspect_deg"

  list(slope_pct = slope_pct, aspect_deg = aspect_deg)
}

# Méthodes de calcul de pente supportées.
.methodes_terrain <- function() c("Horn", "Evans")

# Nombre de voisins passé à terra::terrain pour chaque méthode.
.voisins_terrain <- function(methode) {
  c(Horn = 8L, Evans = 4L)[[methode]]
}
