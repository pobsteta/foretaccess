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
    (pre$obstacles_partiels_mask == 0) &
    (pre$reseau_public_mask == 0)

  z <- terra::ifel(is.na(z), 0, z)
  names(z) <- "zone_roulage"
  z
}

#' Terrain roulable, indépendamment de la forêt
#'
#' Cellules dont la pente est sous le seuil skidder et qui ne portent pas
#' d'obstacle. Reproduit `Pente_ok_skid` de Sylvaccess : à la différence de
#' [zone_roulage()], la forêt n'entre **pas** dans le critère — le skidder peut
#' traverser du non-forestier (voir [zone_roulable_connectee()]).
#'
#' @inheritParams surface_cout_skidder
#' @return Un `SpatRaster` logique (1 = terrain roulable).
#' @export
terrain_roulable <- function(pre, config = foretaccess_config()) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  z <- (pre$slope_pct <= config$skidder$pente_skidder_max_pct) &
    (pre$obstacles_complets_mask == 0) &
    (pre$obstacles_partiels_mask == 0) &
    (pre$reseau_public_mask == 0)

  z <- terra::ifel(is.na(z), 0, z)
  names(z) <- "terrain_roulable"
  z
}

#' Zone effectivement roulable, connectée à la desserte
#'
#' Reproduit la construction de `Pente_ok_skidder` (`Sylvaccess_1_skidder.py`,
#' §« Calculation of skidding distance inside the forest stands »), en trois temps :
#'
#' 1. la **forêt roulable** atteinte depuis la desserte, sans limite de distance ;
#' 2. une extension de `distance_hors_desserte_max_m` (défaut 50 m) **hors forêt**,
#'    sur du terrain roulable — le skidder peut couper par une prairie ;
#' 3. le **recollement** de la forêt roulable ainsi rendue accessible.
#'
#' `distance_hors_desserte_max_m` n'est donc **pas** un plafond sur la distance de
#' débardage : c'est la distance maximale parcourable hors forêt et hors desserte.
#'
#' Les sources de chaque étape sont la zone entière atteinte à l'étape précédente,
#' et non son seul contour : les cellules intérieures, à coût nul, sont dominées —
#' le résultat est identique, sans calcul de contour.
#'
#' @inheritParams surface_cout_skidder
#' @return Un `SpatRaster` logique (1 = roulable et connecté à la desserte).
#' @export
zone_roulable_connectee <- function(pre, config = foretaccess_config()) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  # Reseau public exclu : ce n'est pas une desserte forestiere mais une BARRIERE.
  # Le forcer dans la zone roulable (ci-dessous) ferait rouler le skidder le long
  # de la route publique en payant le surcout d'obstacle -- d'ou des distances de
  # 1 646 km sur ColduPre. Sylvaccess l'exclut explicitement, trois fois :
  # `zone_rast[Res_pub==1] = 0`. Cf. `.classes_desserte()`.
  desserte_cel <- .cellules_livraison(pre)
  if (!length(desserte_cel)) {
    cli::cli_abort("Aucune cellule de desserte : rien n'est connecte.")
  }

  cout <- surface_cout_skidder(pre, config)
  roulable <- as.logical(terra::values(terrain_roulable(pre, config)))
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)

  sources <- function(cellules) {
    s <- terra::rast(pre$mnt)
    v <- rep(NA_real_, terra::ncell(s))
    v[cellules] <- cellules
    terra::values(s) <- v
    s
  }
  zone <- function(masque) {
    z <- terra::rast(pre$mnt)
    terra::values(z) <- as.numeric(masque)
    z
  }
  atteint <- function(prop) !is.na(terra::values(prop$cout_cumule))

  # Les etapes 1 et 3 ne demandent que de la *connectivite*, pas des couts : un
  # etiquetage de composantes connexes (en C++) suffit, et evite deux Dijkstra.
  # Seule l'etape 2, bornee par un cout, en exige un.

  # 1. Foret roulable atteinte depuis la desserte, sans limite.
  z1 <- (roulable & foret)
  z1[desserte_cel] <- TRUE
  a1 <- .composantes_atteintes(pre$mnt, z1, desserte_cel)

  # 2. Saut hors foret, plafonne, sur terrain roulable. Deux economies, sans effet
  # sur le resultat : seules les cellules du *contour* de la zone atteinte servent
  # de sources (les interieures, a cout nul, sont dominees), et la propagation
  # n'explore pas l'interieur de cette zone (tout chemin qui la traverse repart de
  # son contour, deja source). L'exploration se limite ainsi a la bande de 50 m.
  z2 <- roulable & !a1
  a2 <- a1 | atteint(propager_cout(
    cout, sources(which(.contour(a1, nr, nc))), zone = zone(z2),
    cout_max = config$skidder$distance_hors_desserte_max_m
  ))

  # 3. Recollement de la foret roulable rendue accessible.
  z3 <- (roulable & foret) | a2
  a3 <- .composantes_atteintes(pre$mnt, z3, which(a2))

  a3[desserte_cel] <- TRUE
  z <- terra::rast(pre$mnt)
  terra::values(z) <- as.numeric(a3)
  names(z) <- "zone_roulable_connectee"
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

  # Le seuil d'abattage porte sur le maximum LOCAL de la pente (fenetre 3 x 3),
  # pas sur la pente de la cellule : c'est le `Pente_ok_buch` de Sylvaccess, et
  # la zone d'exclusion s'en trouve dilatee d'une cellule. Cf. preprocess().
  z <- (pre$foret_mask == 1) &
    (pre$obstacles_complets_mask == 0) &
    (pre$slope_max_local <= config$skidder$pente_abattage_max_pct)

  z <- terra::ifel(is.na(z), 0, z)
  names(z) <- "zone_treuillable"
  z
}

# Cellules du masque appartenant a une composante connexe (8-connexite) qui
# contient au moins une cellule source. Sert la ou seule la connectivite compte :
# `terra::patches()` etiquette en C++, la ou un Dijkstra serait du gaspillage.
.composantes_atteintes <- function(gabarit, masque, sources) {
  r <- terra::rast(gabarit)
  v <- rep(NA_real_, terra::ncell(r))
  v[masque] <- 1
  terra::values(r) <- v

  etiquettes <- terra::patches(r, directions = 8, zeroAsNA = TRUE)
  lab <- as.numeric(terra::values(etiquettes))

  gardees <- unique(lab[sources])
  gardees <- gardees[!is.na(gardees)]
  !is.na(lab) & lab %in% gardees
}

# Contour interieur d'un masque : les cellules du masque ayant au moins un voisin
# (8-connexite) hors du masque, bord de grille compris. Calcule par decalages de
# matrice, sans boucle.
.contour <- function(masque, nr, nc) {
  m <- matrix(masque, nrow = nr, ncol = nc, byrow = TRUE)
  entoure <- matrix(TRUE, nr, nc)

  decale <- function(x, dl, dc) {
    y <- matrix(FALSE, nr, nc)
    li <- max(1L, 1L - dl):min(nr, nr - dl)
    ci <- max(1L, 1L - dc):min(nc, nc - dc)
    y[li, ci] <- x[li + dl, ci + dc]
    y
  }
  for (dl in -1:1) {
    for (dc in -1:1) {
      if (dl == 0L && dc == 0L) next
      entoure <- entoure & decale(m, dl, dc)
    }
  }
  as.vector(t(m & !entoure))
}
