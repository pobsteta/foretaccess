#' Moteur d'accessibilité porteur (forwarder)
#'
#' Applique les règles Sylvaccess v3.6 au jeu de rasters produit par [preprocess()].
#' Le porteur diffère profondément du skidder : sa conduite est un **balayage radial**
#' depuis le réseau ([conduire()]), non un plus court chemin, et il n'a **pas de treuil**
#' mais un **grappin** de portée fixe. Voir `specs/003-porteur.md`.
#'
#' @details
#' Trois mécanismes, dans l'ordre de priorité :
#' * la **conduite** ([conduire()]) : l'engin roule, sous ses contraintes de pente en
#'   long, de dévers et de distance en pente forte. Ces cellules sont `parcourable` ;
#' * le **grappin** : depuis le contour de la zone conduite, une extension de
#'   `portee_grue_m` (défaut 8 m) sur le terrain récoltable. Ces cellules sont
#'   `accessible` sans être `parcourable` ;
#' * la **distance sur piste**, mutualisée avec le skidder (Lot 2).
#'
#' @param pre Objet `foretaccess_preprocessing` issu de [preprocess()].
#' @param config Objet [foretaccess_config()].
#' @param write_dir Répertoire d'écriture des rasters, ou `NULL`.
#' @param bord Côtés ouverts de la fenêtre quand `pre` est une **tuile** (voir
#'   [certifier_propagation()]). `NULL` (défaut) : `pre` couvre tout le territoire.
#'
#' @return Un objet de classe `foretaccess_porteur`, de structure parallèle à
#'   [skidder()] mais sans `distance_treuillage` : `accessibilite`,
#'   `distance_conduite`, `distance_grappin`, `distance_trainage_piste`,
#'   `distance_debardage`, `allocation`, `certifie`, `recap`, `grid`, `config`.
#' @seealso [skidder()], [conduire()], [traiter_par_tuiles()]
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' po <- porteur(pre)
#' po$recap
porteur <- function(pre, config = foretaccess_config(), write_dir = NULL, bord = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  desserte_cel <- which(!is.na(terra::values(pre$desserte)))
  if (!length(desserte_cel)) {
    cli::cli_abort("Aucune cellule de desserte : le porteur n'a pas de point de depart.")
  }

  n <- terra::ncell(pre$mnt)
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  pente_na <- is.na(terra::values(pre$slope_pct))

  # --- Conduite : balayage radial depuis le reseau, sur la foret roulable. ----
  zone_cond <- .zone_conduite(pre, config)
  cond <- conduire(pre, config, zone_cond)
  d_cond <- as.numeric(terra::values(cond$distance))
  a_cond <- as.numeric(terra::values(cond$allocation))

  est_desserte <- rep(FALSE, n)
  est_desserte[desserte_cel] <- TRUE
  conduit <- !is.na(d_cond) & !est_desserte

  # --- Grappin : extension bornee depuis les cellules conduites. --------------
  grap <- .grappiller(pre, config, conduit | est_desserte)
  d_grap <- as.numeric(terra::values(grap$cout_cumule))
  a_grap <- as.numeric(terra::values(grap$allocation))
  grappe <- !is.na(d_grap) & !conduit & !est_desserte

  # --- Distance sur piste : precalculee globalement, ou locale. ---------------
  cout <- surface_cout_skidder(pre, config)
  piste <- if (is.null(pre$distance_piste)) {
    .distance_sur_piste(pre, cout, bord)
  } else {
    list(distance = as.numeric(terra::values(pre$distance_piste)), certifie = NULL)
  }

  # --- Combinaison. -----------------------------------------------------------
  allocation <- ifelse(conduit, a_cond, ifelse(grappe, a_grap, NA_real_))
  allocation[est_desserte] <- desserte_cel

  dist_cond <- ifelse(conduit, d_cond, 0)
  dist_grap <- ifelse(grappe, d_grap, 0)
  dist_piste <- .piste_allouee(piste$distance, allocation)

  accessible <- conduit | grappe | est_desserte
  # `parcourable` : l'engin y roule. Le grappin, lui, atteint sans rouler.
  parcourable <- conduit | est_desserte

  codes <- rep(3, n) # non_accessible
  codes[accessible] <- 2 # accessible (au grappin)
  codes[parcourable] <- 1 # parcourable (l'engin roule)
  codes[!foret & !est_desserte] <- 4 # hors_foret
  codes[pente_na] <- NA_real_

  certifie <- .certifier_porteur(pre, config, bord, accessible)
  if (!is.null(certifie)) codes[!certifie] <- NA_real_

  faire <- function(v, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }

  acc <- faire(codes, "accessibilite")
  levels(acc) <- data.frame(
    value = 1:4,
    classe = c("parcourable", "accessible", "non_accessible", "hors_foret")
  )

  dist_total <- dist_cond + dist_grap + dist_piste
  dist_total[is.na(codes)] <- NA_real_

  po <- structure(
    list(
      accessibilite           = acc,
      distance_conduite       = faire(dist_cond, "distance_conduite"),
      distance_grappin        = faire(dist_grap, "distance_grappin"),
      distance_trainage_piste = faire(dist_piste, "distance_trainage_piste"),
      distance_debardage      = faire(dist_total, "distance_debardage"),
      allocation              = faire(allocation, "allocation"),
      certifie                = if (is.null(certifie)) NULL else faire(certifie, "certifie"),
      recap                   = recapituler(acc, pre$volume),
      grid                    = pre$grid,
      config                  = config,
      fichiers                = NULL
    ),
    class = "foretaccess_porteur"
  )

  if (!is.null(write_dir)) po$fichiers <- .ecrire_rasters_porteur(po, write_dir)
  po
}

# Zone roulable du porteur : foret, pente sous le seuil de la contrainte la plus stricte
# (la conduite affine ensuite par le sens et le devers), hors obstacles complets. Sylvaccess
# borne d'abord par `min(travers, montee, descente)`, puis raffine dans le balayage.
.zone_conduite <- function(pre, config) {
  po <- config$porteur
  seuil <- min(po$pente_travers_max_pct, po$pente_montee_max_pct, po$pente_descente_max_pct)
  z <- (pre$foret_mask == 1) &
    (pre$slope_pct <= seuil) &
    (pre$obstacles_complets_mask == 0)
  z <- terra::ifel(is.na(z), 0, z)
  names(z) <- "zone_conduite"
  z
}

# Grappin : front d'onde borne a `portee_grue_m` depuis les cellules conduites, sur le
# terrain recoltable (foret, pente sous abattage, hors obstacles complets). Reproduit
# `fwd_add_hoist`. `propager_cout` a cout uniforme donne exactement cette distance.
.grappiller <- function(pre, config, atteintes) {
  po <- config$porteur
  n <- terra::ncell(pre$mnt)

  recoltable <- (pre$foret_mask == 1) &
    (pre$slope_pct <= po$pente_abattage_max_pct) &
    (pre$obstacles_complets_mask == 0)
  recoltable <- terra::ifel(is.na(recoltable), 0, recoltable)

  cout <- terra::rast(pre$mnt)
  terra::values(cout) <- 1

  src <- terra::rast(pre$mnt)
  v <- rep(NA_real_, n)
  v[atteintes] <- which(atteintes)
  terra::values(src) <- v

  propager_cout(cout, src, zone = recoltable, cout_max = po$portee_grue_m)
}

# Sous tuilage, la conduite et le grappin sont des balayages a portee *bornee* : un halo
# qui couvre `distance_pente_forte_max_m + portee_grue_m` rend la tuile exacte partout.
# Nul besoin d'un certificat par cellule -- la portee suffit. `NULL` hors tuilage.
.certifier_porteur <- function(pre, config, bord, accessible) {
  if (is.null(bord)) {
    return(NULL)
  }
  if (length(bord) == 0L) {
    return(rep(TRUE, terra::ncell(pre$mnt)))
  }
  po <- config$porteur
  res <- terra::res(pre$mnt)[1]
  portee <- po$distance_pente_forte_max_m + po$portee_grue_m + 1.5 * res
  halo_ok <- !is.null(pre$halo_cel) && pre$halo_cel * res >= portee
  rep(halo_ok, terra::ncell(pre$mnt))
}

# Couches raster ecrites par write_dir.
.couches_porteur <- function() {
  c(
    "accessibilite", "distance_conduite", "distance_grappin",
    "distance_trainage_piste", "distance_debardage", "allocation"
  )
}

.ecrire_rasters_porteur <- function(po, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)
  chemins <- vapply(.couches_porteur(), function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    terra::writeRaster(po[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))
  as.list(chemins)
}

#' @export
print.foretaccess_porteur <- function(x, ...) {
  r <- x$recap
  cli::cli_inform(c(
    "Moteur porteur ForetAccess",
    "*" = "grille : {x$grid$nrow} x {x$grid$ncol} cellules",
    "*" = "surfaces (ha) : {paste0(r$classe, ' = ', signif(r$surface_ha, 4), collapse = ' ; ')}",
    "*" = "distance de debardage max : \\
           {signif(max(terra::values(x$distance_debardage), na.rm = TRUE), 5)} m"
  ))
  invisible(x)
}
