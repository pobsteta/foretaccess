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

# Prepare la couche de volume pour `acquire_inputs()`/`preprocess()` : un
# `SpatRaster` m3/ha aligne sur la grille du MNT, quelle que soit la forme fournie
# (raster, chemin, ou `sf` d'unites -> P1). `mnt` est la grille de reference
# (l'emprise BUFFERISEE, cf. spec 019 sec. 4 : le volume doit couvrir le halo,
# sinon les lignes de bord sous-estiment Vtot/IPC).
.preparer_volume <- function(volume, mnt, champ) {
  if (is.null(mnt)) {
    cli::cli_abort(c(
      "{.arg volume} exige un MNT pour definir la grille cible.",
      "i" = "Ajouter {.val mnt} a {.arg sources} (ou fournir un MNT en amont)."
    ))
  }
  # `out$mnt` est un chemin (acquire_mnt) : la grille de reference doit etre un
  # SpatRaster pour comparer/rasteriser. `.as_raster` est idempotent.
  mnt <- .as_raster(mnt, "mnt")
  # sf / SpatVector : unites portant un volume/ha -> rasterisation P1.
  if (inherits(volume, c("sf", "sfc", "SpatVector"))) {
    return(volume_depuis_p1(volume, mnt, champ = champ))
  }
  # Raster deja pret -> alignement.
  if (inherits(volume, "SpatRaster")) {
    return(.aligner_volume(volume, mnt))
  }
  # Chemin : raster ou vecteur ? On tente le raster, repli sur le vecteur.
  if (is.character(volume) && length(volume) == 1L) {
    r <- tryCatch(terra::rast(volume), error = function(e) NULL)
    if (!is.null(r)) {
      return(.aligner_volume(r, mnt))
    }
    return(volume_depuis_p1(volume, mnt, champ = champ))
  }
  cli::cli_abort(c(
    "{.arg volume} doit etre un {.cls SpatRaster}, un {.cls sf} d'unites, ou un chemin.",
    "x" = "Recu : {.cls {class(volume)[1]}}."
  ))
}

# Aligne un raster de volume/ha sur la grille du MNT. CRS different -> abort
# (ADR-004). Meme CRS, grille differente -> reechantillonnage (densite,
# bilineaire) avec avertissement. Signale la fraction non couverte de l'emprise.
.aligner_volume <- function(r, mnt) {
  r <- .as_raster(r, "volume")
  if (sf::st_crs(terra::crs(r)) != sf::st_crs(terra::crs(mnt))) {
    cli::cli_abort(c(
      "Le CRS de {.arg volume} differe de celui du MNT.",
      "i" = "Aucune reprojection implicite : reprojeter en amont (ADR-004)."
    ))
  }
  # Meme grille = meme emprise ET meme nombre de lignes/colonnes (donc meme
  # resolution). Comparaison manuelle : `compareGeom` refuse ses drapeaux nommes
  # selon la version de terra.
  meme_grille <- isTRUE(all.equal(
    as.vector(terra::ext(r)), as.vector(terra::ext(mnt))
  )) &&
    terra::nrow(r) == terra::nrow(mnt) &&
    terra::ncol(r) == terra::ncol(mnt)
  if (!meme_grille) {
    cli::cli_inform(c(
      "!" = "{.arg volume} n'est pas sur la grille du MNT : reechantillonnage
             (bilineaire, le volume/ha est une densite)."
    ))
    r <- terra::resample(r, mnt, method = "bilinear")
  }
  names(r) <- "volume"

  # Fraction de l'emprise (cellules de MNT valides) sans volume : ces cellules
  # comptent pour 0 dans la somme du cable -> Vtot/IPC sous-estimes sur les bords.
  emprise <- !is.na(terra::values(mnt, mat = FALSE))
  manque <- emprise & is.na(terra::values(r, mat = FALSE))
  if (any(manque)) {
    pct <- round(100 * sum(manque) / sum(emprise))
    cli::cli_inform(c(
      "!" = "{pct}% de l'emprise (MNT) n'a pas de volume : ces cellules comptent
             pour 0 dans la somme du cable (Vtot/IPC sous-estimes sur les bords).",
      "i" = "Le volume doit couvrir l'emprise BUFFERISEE, pas la seule AOI
             (spec 019). Verifier l'etendue de la source."
    ))
  }
  r
}
