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

  # Comme pour le skidder, le reseau public est une barriere et non une
  # destination : Sylvaccess le verse aux obstacles du porteur
  # (`Obstacles_forwarder[Res_pub==1]=1`). Cf. .classes_desserte().
  desserte_cel <- .cellules_livraison(pre)
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

# Zone traversable par le balayage du porteur, fidele a `Zone_OK` de Sylvaccess :
#
#   Zone_OK = (foret ∪ saut hors foret) ∩ pente <= max(travers, montee, descente) ∩ hors obstacles
#
# Deux points que la premiere version manquait :
#   * la borne de pente est le **maximum** des trois seuils (30 % par defaut), pas le
#     minimum. Le balayage raffine ensuite par le sens et le devers (spec 003 §4.2) ; borner
#     a `min` (15 %) excluait a tort les cellules roulables en montee dans le sens de la pente ;
#   * un **saut hors foret** de `distance_hors_desserte_max_m` (200 m), pondere par la pente,
#     depuis le contour de la foret : le porteur peut couper par un terrain recoltable non
#     forestier pour rejoindre un massif isole. C'est `Pente_ok_forwarder`, l'analogue de
#     `zone_roulable_connectee()` du skidder.
.zone_conduite <- function(pre, config) {
  po <- config$porteur
  seuil <- max(po$pente_travers_max_pct, po$pente_montee_max_pct, po$pente_descente_max_pct)
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)

  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  pente <- as.numeric(terra::values(pre$slope_pct))
  # Le reseau public rejoint les obstacles du porteur, exactement comme dans
  # Sylvaccess (`Obstacles_forwarder[Res_pub==1]=1`).
  obst <- as.numeric(terra::values(pre$obstacles_complets_mask)) == 1 |
    as.numeric(terra::values(pre$reseau_public_mask)) == 1

  atteint <- .saut_hors_foret(pre, config, foret, pente, obst, nr, nc)

  z <- (foret | atteint) & !is.na(pente) & (pente <= seuil) & !obst
  r <- terra::rast(pre$mnt)
  terra::values(r) <- as.numeric(z)
  names(r) <- "zone_conduite"
  r
}

# Cellules non forestieres atteintes par le saut de `distance_hors_desserte_max_m` depuis
# le contour de la foret, sur du terrain recoltable (pente <= abattage). `FALSE` partout si
# la couche est sans foret ou sans contour.
.saut_hors_foret <- function(pre, config, foret, pente, obst, nr, nc) {
  po <- config$porteur
  n <- length(foret)
  if (!any(foret)) {
    return(rep(FALSE, n))
  }

  recoltable_hf <- !foret & !obst & !is.na(pente) & (pente <= po$pente_abattage_max_pct)
  contour <- .contour(foret, nr, nc)
  if (!any(contour) || !any(recoltable_hf)) {
    return(rep(FALSE, n))
  }

  cout <- surface_cout_skidder(pre, config)
  src <- terra::rast(pre$mnt)
  v <- rep(NA_real_, n)
  v[which(contour)] <- which(contour)
  terra::values(src) <- v

  zone <- terra::rast(pre$mnt)
  terra::values(zone) <- as.numeric(recoltable_hf)

  prop <- propager_cout(cout, src, zone = zone, cout_max = po$distance_hors_desserte_max_m)
  !is.na(terra::values(prop$cout_cumule)) & recoltable_hf
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

# Sous tuilage, tous les mecanismes du porteur ont une portee *bornee*, donc un halo
# assez large rend la tuile exacte partout, sans certificat par cellule. La portee a
# couvrir cumule les trois : le saut hors foret (`distance_hors_desserte_max_m`) etend la
# zone, le balayage la parcourt sur `distance_pente_forte_max_m`, et le grappin ajoute
# `portee_grue_m`. `NULL` hors tuilage.
.certifier_porteur <- function(pre, config, bord, accessible) {
  if (is.null(bord)) {
    return(NULL)
  }
  if (length(bord) == 0L) {
    return(rep(TRUE, terra::ncell(pre$mnt)))
  }
  po <- config$porteur
  res <- terra::res(pre$mnt)[1]
  portee <- po$distance_hors_desserte_max_m + po$distance_pente_forte_max_m +
    po$portee_grue_m + 1.5 * res
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
