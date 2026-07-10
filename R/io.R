#' Normalisation des entrées (chemin ou objet)
#'
#' Le prétraitement accepte chaque entrée soit comme **chemin de fichier**, soit
#' comme **objet déjà chargé** (`SpatRaster` pour les rasters, `sf` pour les
#' vecteurs). Ces helpers internes uniformisent l'accès, pour rester testable et
#' découplé de l'I/O (ADR-004).
#'
#' @name io
#' @keywords internal
NULL

# Charge un raster depuis un chemin, ou renvoie l'objet SpatRaster tel quel.
.as_raster <- function(x, arg = "raster") {
  if (inherits(x, "SpatRaster")) {
    return(x)
  }
  if (is.character(x) && length(x) == 1L) {
    checkmate::assert_file_exists(x, access = "r", .var.name = arg)
    return(terra::rast(x))
  }
  cli::cli_abort(c(
    "{.arg {arg}} doit etre un chemin de fichier ou un {.cls SpatRaster}.",
    "x" = "Recu : {.cls {class(x)[1]}}."
  ))
}

# Charge un vecteur depuis un chemin, ou renvoie l'objet sf tel quel.
.as_vector <- function(x, arg = "vecteur") {
  if (inherits(x, "sf")) {
    return(x)
  }
  if (inherits(x, "SpatVector")) {
    return(sf::st_as_sf(x))
  }
  if (is.character(x) && length(x) == 1L) {
    checkmate::assert_file_exists(x, access = "r", .var.name = arg)
    return(sf::st_read(x, quiet = TRUE))
  }
  cli::cli_abort(c(
    "{.arg {arg}} doit etre un chemin de fichier ou un objet {.cls sf}.",
    "x" = "Recu : {.cls {class(x)[1]}}."
  ))
}
