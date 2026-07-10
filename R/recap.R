#' Tableau récapitulatif surfaces / volumes par classe
#'
#' Agrège un raster catégoriel d'accessibilité en surfaces (ha) et, si un raster
#' de volume est fourni, en volumes (m³). Réutilisé par le porteur (Lot 3).
#'
#' Les cellules `NA` du raster de classes forment une ligne **`indetermine`**
#' explicite : elles ne sont jamais rangées silencieusement dans une classe
#' métier. Sur le jeu jouet elles correspondent aux bordures du calcul de pente
#' (Lot 1). La somme des surfaces égale donc toujours celle du raster entier.
#'
#' @param classes `SpatRaster` catégoriel (facteur).
#' @param volume `SpatRaster` de volume aligné, ou `NULL`.
#'
#' @return Un `data.frame` : `classe`, `cellules`, `surface_ha`, et
#'   `volume_m3` si `volume` est fourni.
#' @export
recapituler <- function(classes, volume = NULL) {
  checkmate::assert_class(classes, "SpatRaster")

  if (!terra::is.factor(classes)) {
    cli::cli_abort("{.arg classes} doit etre un raster categoriel.")
  }
  codes <- as.numeric(terra::values(classes))
  niveaux <- terra::levels(classes)[[1]]
  etiquettes <- as.character(niveaux[[2]])
  valeurs <- as.numeric(niveaux[[1]])

  aire_cellule <- prod(terra::res(classes)) / 10000 # ha

  cellules <- vapply(valeurs, function(v) sum(codes == v, na.rm = TRUE), numeric(1))
  cellules <- c(cellules, sum(is.na(codes)))
  etiquettes <- c(etiquettes, "indetermine")

  out <- data.frame(
    classe = etiquettes,
    cellules = cellules,
    surface_ha = cellules * aire_cellule,
    stringsAsFactors = FALSE
  )

  if (!is.null(volume)) {
    checkmate::assert_class(volume, "SpatRaster")
    .valider_grille(volume, classes, "volume")
    vol <- as.numeric(terra::values(volume))
    vols <- vapply(valeurs, function(v) sum(vol[!is.na(codes) & codes == v], na.rm = TRUE), numeric(1))
    out$volume_m3 <- c(vols, sum(vol[is.na(codes)], na.rm = TRUE))
  }

  rownames(out) <- NULL
  out
}
