#' Surface de coût du skidder (pondération de pente)
#'
#' Reproduit `Pond_pente` de Sylvaccess v3.6 (`Sylvaccess_1_skidder.py:121`) :
#'
#' \deqn{c = \sqrt{1 + (p / 100)^2}}
#'
#' C'est le **facteur d'allongement 3D** de la traversée d'une cellule : la
#' distance de moindre coût qui en résulte est la longueur réelle du chemin
#' épousant le terrain. Le coût ne dépend que de la **valeur absolue** de la
#' pente — la propagation est donc **isotrope**. Il n'y a aucune fonction de
#' Tobler dans Sylvaccess (spec 002 §4.2).
#'
#' Les **obstacles complets** reçoivent un surcoût **additif**
#' (`config$skidder$surcout_obstacle_complet`, défaut 1000) : prohibitif, mais
#' fini — ils ne sont pas infranchissables. Les **obstacles partiels**
#' n'interviennent pas ici : ils restreignent la zone de roulage, pas le coût
#' (voir [zone_roulage()]).
#'
#' @param pre Objet `foretaccess_preprocessing` (Lot 1).
#' @param config Objet [foretaccess_config()].
#'
#' @return Un `SpatRaster` de coût, sur la grille du MNT.
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' terra::global(surface_cout_skidder(pre), "max", na.rm = TRUE)
surface_cout_skidder <- function(pre, config = foretaccess_config()) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  cout <- ponderation_pente(pre$slope_pct)
  cout <- cout + config$skidder$surcout_obstacle_complet * pre$obstacles_complets_mask

  names(cout) <- "surface_cout"
  cout
}

#' Pondération de pente (facteur d'allongement 3D)
#'
#' `sqrt(1 + (pente_pct / 100)^2)`. Vaut 1 à pente nulle, `sqrt(2)` à 100 %.
#' Fonction de la pente **absolue** : le coût est isotrope.
#'
#' @param pente_pct `SpatRaster` ou vecteur numérique de pentes en pourcentage.
#' @return Objet de même forme que `pente_pct`.
#' @export
#' @examples
#' ponderation_pente(c(0, 100))
ponderation_pente <- function(pente_pct) {
  sqrt(1 + (pente_pct / 100)^2)
}

#' Zone de roulage du skidder
#'
#' Cellules où l'engin peut circuler : forêt, pente sous le seuil skidder, hors
#' obstacles complets **et** hors obstacles partiels. Reproduit
#' `zone_rast[Partial_Obstacles_skidder == 1] <- 0` de Sylvaccess.
#'
#' Les obstacles **partiels** bloquent le roulage mais **pas** le treuillage : on
#' peut treuiller par-dessus, pas rouler dessus (spec 002 §10.4).
#'
#' @inheritParams surface_cout_skidder
#' @return Un `SpatRaster` logique (1 = roulable).
#' @export
zone_roulage <- function(pre, config = foretaccess_config()) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  z <- (pre$foret_mask == 1) &
    (pre$slope_pct <= config$skidder$pente_skidder_max_pct) &
    (pre$obstacles_complets_mask == 0) &
    (pre$obstacles_partiels_mask == 0)

  z <- terra::ifel(is.na(z), 0, z)
  names(z) <- "zone_roulage"
  z
}

#' Zone treuillable
#'
#' Cellules atteignables au treuil : forêt, hors obstacles complets, et pente
#' sous le seuil d'abattage manuel. Reproduit `Zone_OK` de Sylvaccess. Les
#' obstacles **partiels** n'y figurent pas (voir [zone_roulage()]).
#'
#' @inheritParams surface_cout_skidder
#' @return Un `SpatRaster` logique (1 = treuillable).
#' @export
zone_treuillable <- function(pre, config = foretaccess_config()) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  z <- (pre$foret_mask == 1) &
    (pre$obstacles_complets_mask == 0) &
    (pre$slope_pct <= config$skidder$pente_abattage_max_pct)

  z <- terra::ifel(is.na(z), 0, z)
  names(z) <- "zone_treuillable"
  z
}
