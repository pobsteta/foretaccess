# Preparation de la couche de volume sur pied (`pre$volume`) attendue par le
# moteur cable et la selection (Lot 5).
#
# Le volume est une ENTREE : ForetAccess ne le calcule pas. Sa source naturelle
# est un inventaire ou un MNH LiDAR -- typiquement l'indicateur P1 de Nemeton
# (`nemeton::indicateur_p1_volume()`), qui rend un `sf` d'unites porteuses d'un
# volume en m3/ha. `volume_depuis_p1()` n'est qu'un pont geometrique : il projette
# ce champ sur la grille du MNT. Il ne depend PAS de Nemeton -- il consomme un
# `sf` deja calcule, d'ou qu'il vienne (P1, BD Foret, releve terrain).
#
# Regle stricte 1 (`CLAUDE.md`) : la logique metier vit dans foretaccess. Le
# calcul du volume est un indicateur d'inventaire, domaine de Nemeton ; on se
# borne a consommer sa sortie.

#' Rasterise a per-hectare volume layer onto the DTM grid
#'
#' The cable engine and the line selection (Lot 5) read a **standing-volume
#' raster** from `pre$volume`, in m3/ha per cell: [potentiel_cable()] sums it over
#' the forest cells a line covers to get the line volume and the cable production
#' index (IPC = volume / length). ForetAccess does **not** compute that volume --
#' it is an input.
#'
#' Its natural source is a forest inventory or a LiDAR canopy-height model, e.g.
#' Nemeton's **P1** indicator (`nemeton::indicateur_p1_volume()`), which returns
#' an `sf` of units carrying a volume in **m3/ha**. `volume_depuis_p1()` bridges
#' that `sf` to the grid the engines expect. It takes no dependency on Nemeton:
#' it rasterises whatever per-hectare field you give it, wherever it comes from.
#'
#' @section Unites:
#' `champ` **must be a density in m3/ha**, not an absolute volume per unit. The
#' cable multiplies each cell by `aire_cellule / 10000` to turn m3/ha back into
#' m3; a field in absolute m3 would inflate the result by the number of cells per
#' unit. This is the same convention as `vol_ha.tif` in the Sylvaccess ColduPre
#' set.
#'
#' @param p1 Units carrying the per-hectare volume: path to a vector file or an
#'   `sf` of polygons (the output of `nemeton::indicateur_p1_volume()`, or any
#'   equivalent layer).
#' @param mnt DTM defining the target grid: `SpatRaster` or path. Must share the
#'   CRS of `p1` (no implicit reprojection, ADR-004).
#' @param champ Name of the m3/ha column to rasterise. Default `"P1"` (the column
#'   Nemeton writes).
#' @param fun How to combine when several units cover one cell. Default `"mean"`
#'   -- correct for a density; overlapping units are unusual but must not be
#'   summed. Passed to [terra::rasterize()].
#'
#' @return A single-layer `SpatRaster` named `volume`, aligned on `mnt`, ready for
#'   `preprocess(volume = )`. Cells no unit covers are `NA` (no wood, not zero).
#'
#' @seealso [preprocess()] (consumes the raster), [potentiel_cable()] (sums it per
#'   line into volume and IPC).
#' @export
#' @examples
#' \dontrun{
#' # Volume from Nemeton's P1 indicator (inventory or LiDAR CHM), then cable.
#' p1  <- nemeton::indicateur_p1_volume(parcelles, chm = mnh_lidar)
#' vol <- volume_depuis_p1(p1, mnt)
#' pre <- preprocess(mnt, desserte, foret, volume = vol)
#' ca  <- potentiel_cable(pre, departs = places)
#' }
volume_depuis_p1 <- function(p1, mnt, champ = "P1", fun = "mean") {
  checkmate::assert_string(champ)
  checkmate::assert_string(fun)

  mnt <- .as_raster(mnt, "mnt")
  p1 <- .as_vector(p1, "p1")
  p1 <- sf::st_zm(sf::st_as_sf(p1), drop = TRUE)

  if (nrow(p1) == 0) {
    cli::cli_abort("La couche {.arg p1} est vide.")
  }
  .verifier_crs(p1, mnt, "p1")

  if (!champ %in% names(p1)) {
    cli::cli_abort(c(
      "La couche {.arg p1} n'a pas de champ {.field {champ}}.",
      "i" = "Champs disponibles : {.val {setdiff(names(p1), attr(p1, 'sf_column'))}}.",
      "i" = "Preciser {.arg champ} si le volume/ha porte un autre nom."
    ))
  }
  v <- p1[[champ]]
  if (!is.numeric(v)) {
    cli::cli_abort("Le champ {.field {champ}} doit etre numerique (m3/ha).")
  }
  if (all(is.na(v))) {
    cli::cli_abort("Le champ {.field {champ}} vaut {.val NA} partout.")
  }
  if (any(!is.na(v) & v < 0)) {
    cli::cli_abort("Le champ {.field {champ}} contient des valeurs negatives.")
  }

  # Rasterisation par CENTRE de cellule (pas `touches`) : le volume/ha est une
  # densite, on l'affecte a la cellule dont le centre tombe dans l'unite -- pas a
  # toutes celles que l'unite effleure, ce qui gonflerait les bords.
  r <- terra::rasterize(terra::vect(p1), mnt, field = champ, fun = fun)
  names(r) <- "volume"

  n_vol <- sum(!is.na(terra::values(r)))
  n_tot <- terra::ncell(r)
  cli::cli_inform(c(
    "v" = "Volume rasterise : {n_vol}/{n_tot} cellule{?s} portent un volume
           ({round(100 * n_vol / n_tot)}% de la grille).",
    "i" = "Champ {.field {champ}} suppose en {.strong m3/ha}. Cellules hors unite :
           {.val NA} (pas de bois), non nulles."
  ))
  r
}
