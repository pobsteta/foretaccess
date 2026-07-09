#' Prétraitement commun aux moteurs d'accessibilité
#'
#' Socle commun aux quatre moteurs (skidder, porteur, câble, DFCI). Transforme des
#' entrées SIG hétérogènes en un jeu de rasters **alignés sur la grille du MNT**,
#' après validation stricte. Aucune règle de moteur n'est appliquée ici.
#'
#' Chaque entrée est acceptée soit comme **chemin de fichier**, soit comme objet
#' déjà chargé (`SpatRaster` pour les rasters, `sf` pour les vecteurs), cf. ADR-004.
#' Les seuils proviennent de `config` — aucune valeur métier n'est codée en dur
#' (ADR-003).
#'
#' @param mnt MNT : chemin de raster ou `SpatRaster`. Définit la grille, la
#'   résolution et le CRS de référence.
#' @param desserte Desserte : chemin de vecteur ou `sf` de lignes, avec un champ
#'   `classe` dans `route`, `piste`, `dfci`.
#' @param foret Forêt : chemin de vecteur ou `sf` de polygones.
#' @param obstacles_complets Obstacles bloquant tous les engins (facultatif).
#' @param obstacles_partiels Obstacles spécifiques au skidder (facultatif ; la
#'   sémantique est posée au Lot 2).
#' @param volume Volume sur pied : raster aligné sur la grille du MNT (facultatif).
#' @param parcellaire Parcellaire : vecteur de polygones (facultatif ; utilisé au
#'   Lot 8 pour l'agrégation).
#' @param config Objet [foretaccess_config()].
#' @param write_dir Répertoire où écrire les rasters en GeoTIFF/COG. `NULL`
#'   (défaut) : tout reste en mémoire.
#'
#' @return Un objet de classe `foretaccess_preprocessing` : une liste dont les
#'   rasters partagent exactement la grille du MNT.
#'   \describe{
#'     \item{`slope_pct`}{pente en pourcentage.}
#'     \item{`aspect_deg`}{exposition en degrés depuis le nord (plat = `NA`).}
#'     \item{`foret_mask`}{1 dans les polygones forêt, 0 ailleurs.}
#'     \item{`desserte`}{raster catégoriel de classe de desserte (`NA` hors desserte).}
#'     \item{`desserte_sf`}{la desserte vectorielle, conservée pour le least-cost (Lot 2).}
#'     \item{`obstacles_complets_mask`, `obstacles_partiels_mask`}{1 où obstacle, 0 sinon.}
#'     \item{`exclusion_mask`}{1 là où la pente dépasse le seuil d'abattage manuel.}
#'     \item{`volume`}{raster de volume aligné, ou `NULL`.}
#'     \item{`parcellaire`}{objet `sf`, ou `NULL`.}
#'     \item{`grid`}{métadonnées de grille (emprise, résolution, dimensions, CRS).}
#'     \item{`config`}{la configuration utilisée.}
#'     \item{`fichiers`}{chemins écrits si `write_dir`, sinon `NULL`.}
#'   }
#'
#' @section Bordures:
#' `slope_pct`, `aspect_deg` et donc `exclusion_mask` valent `NA` sur la première
#' couronne de cellules : le calcul de pente exige les 8 voisins.
#'
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(
#'   mnt = file.path(toy, "mnt.tif"),
#'   desserte = file.path(toy, "desserte.gpkg"),
#'   foret = file.path(toy, "foret.gpkg")
#' )
#' pre$grid$res
preprocess <- function(mnt,
                       desserte,
                       foret,
                       obstacles_complets = NULL,
                       obstacles_partiels = NULL,
                       volume = NULL,
                       parcellaire = NULL,
                       config = foretaccess_config(),
                       write_dir = NULL) {
  validate_config(config)

  # 1. Chargement (chemin ou objet déjà chargé).
  mnt <- .as_raster(mnt, "mnt")
  desserte <- .as_vector(desserte, "desserte")
  foret <- .as_vector(foret, "foret")
  obstacles_complets <- .as_vector_opt(obstacles_complets, "obstacles_complets")
  obstacles_partiels <- .as_vector_opt(obstacles_partiels, "obstacles_partiels")
  parcellaire <- .as_vector_opt(parcellaire, "parcellaire")
  volume <- if (is.null(volume)) NULL else .as_raster(volume, "volume")

  # 2. Validation stricte (CRS, grille, attributs, géométries).
  valider_entrees(
    mnt = mnt, desserte = desserte, foret = foret,
    obstacles_complets = obstacles_complets,
    obstacles_partiels = obstacles_partiels,
    volume = volume, parcellaire = parcellaire
  )

  # 3. Pente & exposition.
  terr <- calculer_terrain(mnt, methode = config$general$methode_pente)

  # 4. Rasterisation des vecteurs sur la grille du MNT.
  foret_mask <- .masque_vecteur(foret, mnt, "foret_mask")
  obstacles_complets_mask <- .masque_vecteur(
    obstacles_complets, mnt, "obstacles_complets_mask"
  )
  obstacles_partiels_mask <- .masque_vecteur(
    obstacles_partiels, mnt, "obstacles_partiels_mask"
  )
  desserte_rast <- .rasteriser_desserte(desserte, mnt)

  # 5. Masque d'exclusion : pente au-delà du seuil d'abattage manuel (ADR-003).
  seuil <- config$skidder$pente_abattage_max_pct
  exclusion_mask <- terra::ifel(terr$slope_pct > seuil, 1, 0)
  names(exclusion_mask) <- "exclusion_mask"

  # 6. Volume : déjà contrôlé aligné par valider_entrees(), on le nomme seulement.
  if (!is.null(volume)) names(volume) <- "volume"

  # 7. Assemblage.
  pre <- structure(
    list(
      slope_pct               = terr$slope_pct,
      aspect_deg              = terr$aspect_deg,
      foret_mask              = foret_mask,
      desserte                = desserte_rast,
      desserte_sf             = desserte,
      obstacles_complets_mask = obstacles_complets_mask,
      obstacles_partiels_mask = obstacles_partiels_mask,
      exclusion_mask          = exclusion_mask,
      volume                  = volume,
      parcellaire             = parcellaire,
      grid                    = .grille(mnt),
      config                  = config,
      fichiers                = NULL
    ),
    class = "foretaccess_preprocessing"
  )

  if (!is.null(write_dir)) {
    pre$fichiers <- .ecrire_rasters(pre, write_dir)
  }
  pre
}

# Variante tolérant NULL pour les couches vectorielles facultatives.
.as_vector_opt <- function(x, arg) {
  if (is.null(x)) NULL else .as_vector(x, arg)
}

# Métadonnées de la grille de référence.
.grille <- function(mnt) {
  em <- as.vector(terra::ext(mnt))
  list(
    crs  = terra::crs(mnt),
    ext  = c(xmin = em[["xmin"]], xmax = em[["xmax"]], ymin = em[["ymin"]], ymax = em[["ymax"]]),
    res  = terra::res(mnt),
    nrow = terra::nrow(mnt),
    ncol = terra::ncol(mnt)
  )
}

# Masque binaire (1 dans les géométries, 0 ailleurs) ; raster nul si couche absente.
.masque_vecteur <- function(x, mnt, nom) {
  if (is.null(x)) {
    m <- terra::rast(mnt)
    terra::values(m) <- 0
  } else {
    m <- terra::rasterize(terra::vect(x), mnt, field = 1, background = 0)
  }
  names(m) <- nom
  m
}

# Raster catégoriel de la desserte, codes stables : route = 1, piste = 2, dfci = 3.
.rasteriser_desserte <- function(desserte, mnt) {
  classes <- .classes_desserte()
  v <- terra::vect(desserte)
  v$code_classe <- match(as.character(desserte$classe), classes)

  r <- terra::rasterize(v, mnt, field = "code_classe")
  levels(r) <- data.frame(value = seq_along(classes), classe = classes)
  names(r) <- "desserte"
  r
}

# Couches raster écrites sur disque par write_dir.
.couches_rasters <- function() {
  c(
    "slope_pct", "aspect_deg", "foret_mask", "desserte",
    "obstacles_complets_mask", "obstacles_partiels_mask",
    "exclusion_mask", "volume"
  )
}

# Écriture GeoTIFF/COG des rasters ; renvoie les chemins nommés.
.ecrire_rasters <- function(pre, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)

  couches <- .couches_rasters()
  couches <- couches[!vapply(pre[couches], is.null, logical(1))]

  chemins <- vapply(couches, function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    # Le pilote COG passe par un raster MEM intermédiaire, qui n'accepte pas
    # d'option de création : on laisse la compression par défaut du pilote.
    terra::writeRaster(pre[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))

  as.list(chemins)
}

#' Relit un prétraitement écrit sur disque
#'
#' Recharge les rasters écrits par `preprocess(write_dir = ...)`. Les couches
#' vectorielles (`desserte_sf`, `parcellaire`) ne sont pas relues : elles ne sont
#' pas écrites par `write_dir` (ADR-002, les vecteurs vont en base).
#'
#' @param write_dir Répertoire contenant les GeoTIFF/COG écrits.
#' @return Une liste nommée de `SpatRaster`.
#' @export
lire_rasters <- function(write_dir) {
  checkmate::assert_directory_exists(write_dir, access = "r")
  fichiers <- file.path(write_dir, paste0(.couches_rasters(), ".tif"))
  fichiers <- fichiers[file.exists(fichiers)]
  if (!length(fichiers)) {
    cli::cli_abort("Aucun raster de prétraitement trouvé dans {.path {write_dir}}.")
  }
  stats::setNames(lapply(fichiers, terra::rast), tools::file_path_sans_ext(basename(fichiers)))
}

#' @export
print.foretaccess_preprocessing <- function(x, ...) {
  g <- x$grid
  facultatives <- c("volume", "parcellaire")
  presentes <- facultatives[!vapply(x[facultatives], is.null, logical(1))]

  cli::cli_inform(c(
    "Pretraitement ForetAccess",
    "*" = "grille : {g$nrow} x {g$ncol} cellules, resolution {paste(g$res, collapse = ' x ')} m",
    "*" = "emprise : [{g$ext[['xmin']]}, {g$ext[['xmax']]}] x [{g$ext[['ymin']]}, {g$ext[['ymax']]}]",
    "*" = "couches facultatives : {if (length(presentes)) toString(presentes) else 'aucune'}",
    "*" = "seuil d'exclusion (pente abattage) : {x$config$skidder$pente_abattage_max_pct} %"
  ))
  invisible(x)
}
