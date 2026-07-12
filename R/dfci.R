#' Moteur camion DFCI — zone défendable (beta)
#'
#' Cartographie la **zone défendable** contre l'incendie depuis les dessertes
#' DFCI (défense de la forêt contre les incendies), en réponse à EF-8. Sortie
#' **beta** au sens du brief (§4.5) : le modèle est volontairement simple et ses
#' limites sont explicites (voir *Section limites*).
#'
#' @details
#' Le camion stationne sur une desserte carrossable et défend le terrain
#' avoisinant, dans une **portée latérale** limitée. On modélise cette portée par
#' un **plus court chemin pondéré par la pente** ([propager_cout()],
#' [surface_cout_skidder()]) depuis les cellules de desserte-source, plafonné à
#' `config$dfci$distance_defense_max_m` et interdit au-delà de la pente
#' d'intervention `config$dfci$pente_defense_max_pct`. C'est donc un **tampon au
#' terrain** : la distance de défense épouse le relief, et le terrain trop raide
#' est réputé indéfendable.
#'
#' Les dessertes-source sont les classes listées dans `config$dfci$classes_source`
#' (défaut : `"dfci"` seul). Une cellule de forêt atteinte est `defendable` ; une
#' cellule de forêt non atteinte, `non_defendable` ; le reste, `hors_foret`.
#'
#' @section Section limites (beta):
#' Le modèle **ne représente pas** : le combustible (type de peuplement, charge),
#' le vent, ni la physique de la lance (portée du jet, débit, pression). La portée
#' de défense est un **paramètre unique**, non dérivé des caractéristiques du
#' matériel. Les dessertes sont prises telles quelles : leur carrossabilité réelle
#' par un camion (projet QUALIROAD) n'est pas qualifiée. La coupure de pente est
#' un proxy grossier d'atteignabilité. Ces sorties valent pour une **première
#' hiérarchisation**, pas pour du dimensionnement opérationnel.
#'
#' @param pre Objet `foretaccess_preprocessing` issu de [preprocess()].
#' @param config Objet [foretaccess_config()].
#' @param write_dir Répertoire d'écriture des rasters en GeoTIFF/COG, ou `NULL`.
#' @param bord Côtés ouverts de la fenêtre quand `pre` est une **tuile** (voir
#'   [certifier_propagation()]). `NULL` (défaut) : `pre` couvre tout le territoire.
#'
#' @return Un objet de classe `foretaccess_dfci` :
#'   \describe{
#'     \item{`accessibilite`}{`SpatRaster` catégoriel : `defendable`,
#'       `non_defendable`, `hors_foret`. `NA` = indéterminé.}
#'     \item{`distance_defense`}{distance de défense au terrain (m) depuis la
#'       desserte-source la plus proche ; 0 sur la desserte, `NA` hors portée.}
#'     \item{`allocation`}{cellule de desserte de rattachement.}
#'     \item{`certifie`}{`SpatRaster` logique, ou `NULL` si `bord` l'est.}
#'     \item{`recap`}{`data.frame` des surfaces et volumes par classe.}
#'     \item{`grid`, `config`, `fichiers`}{comme au Lot 1.}
#'   }
#' @seealso [skidder()], [porteur()], [propager_cout()]
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' df <- camion_dfci(pre)
#' df$recap
camion_dfci <- function(pre, config = foretaccess_config(), write_dir = NULL, bord = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  source_cel <- .sources_dfci(pre, config)
  if (!length(source_cel)) {
    if (is.null(bord)) {
      cli::cli_abort(c(
        "Aucune desserte-source DFCI : le camion n'a pas de point de depart.",
        "i" = "Classes attendues : {.val {config$dfci$classes_source}} \\
               (voir {.field config$dfci$classes_source})."
      ))
    }
    # Sous tuilage, une tuile sans source DFCI dans sa fenetre n'est pas
    # calculable : une desserte hors fenetre peut la defendre. On ne certifie
    # rien, le halo grandit (meme convention que .tuile_indeterminee).
    return(.dfci_indetermine(pre, config))
  }

  n <- terra::ncell(pre$mnt)
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  pente_na <- is.na(terra::values(pre$slope_pct))

  # --- Zone defendable : plus court chemin pondere par la pente, borne. --------
  cout <- surface_cout_skidder(pre, config)
  zone <- .zone_defendable(pre, config)

  src <- terra::rast(pre$mnt)
  v <- rep(NA_real_, n)
  v[source_cel] <- source_cel
  terra::values(src) <- v

  dmax <- config$dfci$distance_defense_max_m
  if (is.null(bord)) {
    prop <- propager_cout(cout, src, zone = zone, cout_max = dmax)
    certifie <- NULL
  } else {
    cert <- certifier_propagation(
      cout, src,
      zone = zone, zone_majorante = .zone_majorante_dfci(pre, config),
      bord = bord, cout_max = dmax
    )
    prop <- cert$propagation
    certifie <- as.logical(terra::values(cert$certifie))
  }

  d_def <- as.numeric(terra::values(prop$cout_cumule))
  a_def <- as.numeric(terra::values(prop$allocation))
  atteint <- !is.na(d_def)

  # --- Classement. ------------------------------------------------------------
  codes <- rep(2, n) # non_defendable
  codes[atteint & foret] <- 1 # defendable
  codes[!foret] <- 3 # hors_foret
  codes[pente_na] <- NA_real_
  if (!is.null(certifie)) codes[!certifie] <- NA_real_

  distance <- ifelse(atteint, d_def, 0)
  distance[is.na(codes)] <- NA_real_
  allocation <- ifelse(atteint, a_def, NA_real_)

  faire <- function(vv, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- vv
    names(r) <- nom
    r
  }

  acc <- faire(codes, "accessibilite")
  levels(acc) <- data.frame(
    value = 1:3,
    classe = c("defendable", "non_defendable", "hors_foret")
  )

  df <- structure(
    list(
      accessibilite    = acc,
      distance_defense = faire(distance, "distance_defense"),
      allocation       = faire(allocation, "allocation"),
      certifie         = if (is.null(certifie)) NULL else faire(certifie, "certifie"),
      recap            = recapituler(acc, pre$volume),
      grid             = pre$grid,
      config           = config,
      fichiers         = NULL
    ),
    class = "foretaccess_dfci"
  )

  if (!is.null(write_dir)) df$fichiers <- .ecrire_rasters_dfci(df, write_dir)
  df
}

# Tuile sans source DFCI : rien de calcule, rien de certifie. Toutes les couches
# sont NA et `certifie` est faux partout, de sorte que le halo grandit.
.dfci_indetermine <- function(pre, config) {
  n <- terra::ncell(pre$mnt)
  faire <- function(vv, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- vv
    names(r) <- nom
    r
  }
  acc <- faire(rep(NA_real_, n), "accessibilite")
  levels(acc) <- data.frame(
    value = 1:3,
    classe = c("defendable", "non_defendable", "hors_foret")
  )
  structure(
    list(
      accessibilite    = acc,
      distance_defense = faire(rep(NA_real_, n), "distance_defense"),
      allocation       = faire(rep(NA_real_, n), "allocation"),
      certifie         = faire(rep(FALSE, n), "certifie"),
      recap            = recapituler(acc, pre$volume),
      grid             = pre$grid,
      config           = config,
      fichiers         = NULL
    ),
    class = "foretaccess_dfci"
  )
}

# Cellules de desserte servant de base au camion : celles dont la classe figure
# dans config$dfci$classes_source. Codes du raster desserte : route=1, piste=2,
# dfci=3 (voir .rasteriser_desserte).
.sources_dfci <- function(pre, config) {
  codes <- match(config$dfci$classes_source, .classes_desserte())
  vals <- as.numeric(terra::values(pre$desserte))
  which(!is.na(vals) & vals %in% codes)
}

# Terrain defendable : pente sous le seuil d'intervention et hors obstacle
# complet. La pente NA est infranchissable (1 = defendable, 0 sinon).
.zone_defendable <- function(pre, config) {
  z <- (pre$slope_pct <= config$dfci$pente_defense_max_pct) &
    (pre$obstacles_complets_mask == 0)
  z <- terra::ifel(is.na(z), 0, z)
  names(z) <- "zone_defendable"
  z
}

# Sur-approximation de la zone traversable pour le certificat de tuilage : le
# terrain defendable, sans autre restriction. Minore ainsi le cout de bord.
.zone_majorante_dfci <- function(pre, config) {
  .zone_defendable(pre, config)
}

# Couches raster ecrites par write_dir.
.couches_dfci <- function() {
  c("accessibilite", "distance_defense", "allocation")
}

.ecrire_rasters_dfci <- function(df, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)
  chemins <- vapply(.couches_dfci(), function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    terra::writeRaster(df[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))
  as.list(chemins)
}

#' @export
print.foretaccess_dfci <- function(x, ...) {
  r <- x$recap
  cli::cli_inform(c(
    "Moteur camion DFCI ForetAccess (beta)",
    "*" = "grille : {x$grid$nrow} x {x$grid$ncol} cellules",
    "*" = "surfaces (ha) : {paste0(r$classe, ' = ', signif(r$surface_ha, 4), collapse = ' ; ')}",
    "*" = "portee de defense max : \\
           {signif(max(terra::values(x$distance_defense), na.rm = TRUE), 5)} m"
  ))
  invisible(x)
}
