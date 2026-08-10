#' Validation des entrées du prétraitement
#'
#' Politique **stricte** (spec 001 §10, décision 1) : toutes les couches doivent
#' partager le CRS du MNT, et les rasters son alignement de grille. Aucune
#' reprojection ni rééchantillonnage silencieux — l'utilisateur prépare ses
#' données en amont. Chaque manquement lève une erreur ciblée.
#'
#' @param mnt `SpatRaster` du modèle numérique de terrain (grille de référence).
#' @param desserte Objet `sf` de lignes, avec un champ `classe`.
#' @param foret Objet `sf` de polygones.
#' @param obstacles_complets,obstacles_partiels Objets `sf` ou `NULL`.
#' @param volume `SpatRaster` ou `NULL`, aligné sur la grille du MNT.
#' @param parcellaire Objet `sf` ou `NULL`.
#'
#' @return `TRUE` de façon invisible si tout est valide ; sinon une erreur.
#' @export
valider_entrees <- function(mnt,
                            desserte,
                            foret,
                            obstacles_complets = NULL,
                            obstacles_partiels = NULL,
                            volume = NULL,
                            parcellaire = NULL) {
  checkmate::assert_class(mnt, "SpatRaster")
  if (terra::nlyr(mnt) != 1L) {
    cli::cli_abort(c(
      "{.arg mnt} doit avoir une seule couche.",
      "x" = "Recu : {terra::nlyr(mnt)} couches."
    ))
  }
  if (is.na(.crs_sf(mnt))) {
    cli::cli_abort("{.arg mnt} n'a pas de CRS defini ; il sert de reference.")
  }

  .valider_desserte(desserte)

  vecteurs <- list(
    desserte           = desserte,
    foret              = foret,
    obstacles_complets = obstacles_complets,
    obstacles_partiels = obstacles_partiels,
    parcellaire        = parcellaire
  )
  for (nm in names(vecteurs)) {
    x <- vecteurs[[nm]]
    if (is.null(x)) next
    .valider_geometries(x, nm)
    .valider_crs(x, mnt, nm)
    .valider_recouvrement(x, mnt, nm)
  }

  if (!is.null(volume)) {
    checkmate::assert_class(volume, "SpatRaster")
    .valider_crs(volume, mnt, "volume")
    .valider_grille(volume, mnt, "volume")
  }

  invisible(TRUE)
}

# Classes de desserte reconnues (spec 001 §3).
#
# `reseau_public` (CL_SVAC = 3 chez Sylvaccess) n'est PAS une desserte forestiere :
# c'est le point de chargement du camion, et pour les engins de debardage une
# BARRIERE (on ne debarde ni sur ni au travers d'une route ouverte a la
# circulation). Sylvaccess l'exclut explicitement des sources et de la zone
# roulable (`from_rast[Res_pub==1]=0`, `zone_rast[Res_pub==1]=0`,
# `Obstacles_forwarder[Res_pub==1]=1`). L'omettre coute 6,8 % de la carte
# skidder, entierement dans le sens optimiste (mesure sur le jeu ColduPre).
.classes_desserte <- function() c("route", "piste", "dfci", "reseau_public")

# Classes ACCEPTEES EN ENTREE. A distinguer de `.classes_desserte()`, qui est le
# vocabulaire de DEBARDAGE : `hors_desserte` (CL_SVAC = 0) est une valeur connue
# et legitime, conservee par `acquire_desserte()` depuis le 2026-07-30 parce
# qu'elle porte la CONNECTIVITE du reseau (rond-points, liaisons), exploitee par
# `verifier_integrite_desserte()`. Elle n'entre PAS dans les couches
# d'exploitation : chaque rasterisation la retire explicitement en amont.
#
# Ne JAMAIS l'ajouter a `.classes_desserte()` : les classes y sont codees par
# leur RANG et `.rasteriser_desserte()` prend le `max` (la barriere l'emporte) --
# une 5e classe passerait devant `reseau_public`.
.classes_desserte_connues <- function() c(.classes_desserte(), "hors_desserte")

# Retire les troncons hors debardage. A appeler AVANT toute rasterisation.
#
# Indispensable, et pas seulement cosmetique : `terra::rasterize(field = ...)`
# grave la sentinelle entiere -2147483648 dans les cellules atteintes par une
# geometrie dont le champ vaut `NA`, au lieu de les laisser vides -- et cette
# sentinelle ECRASE la classe valide d'une cellule partagee, MALGRE `fun = "max"`.
# Se reposer sur le `NA` de `match()` amputerait donc le reseau a ses JONCTIONS
# (mesure DABO, grille 5 m : 440 cellules sur 24 259, soit 1,8 %), exactement la
# ou un sentier rejoint une route.
.sans_hors_desserte <- function(desserte) {
  if (is.null(desserte[["classe"]])) {
    return(desserte)
  }
  garde <- as.character(desserte$classe) %in% .classes_desserte()
  desserte[garde, , drop = FALSE]
}

# Classes qui accueillent effectivement le bois debarde : le reseau public
# (barriere, cf. ci-dessus) n'en fait pas partie.
.classes_livraison <- function() c("route", "piste", "dfci")

# Raster de desserte restreint aux cellules de livraison (reseau public en NA).
# Les balayages radiaux (treuiller(), conduire()) consomment un raster, pas des
# indices : ils doivent voir la MEME desserte que le roulage.
.desserte_livraison <- function(pre) {
  r <- terra::rast(pre$desserte)
  v <- rep(NA_real_, terra::ncell(r))
  cel <- .cellules_livraison(pre)
  v[cel] <- as.numeric(terra::values(pre$desserte))[cel]
  terra::values(r) <- v
  names(r) <- "desserte"
  r
}

# Indices des cellules de desserte ou le bois peut etre livre (reseau public exclu).
#
# Sans table de categories -- desserte non categorisee, ou raster de marqueurs des
# fixtures --, il n'y a pas de reseau public a distinguer : toute cellule livre.
.cellules_livraison <- function(pre) {
  v <- as.numeric(terra::values(pre$desserte))
  cl <- terra::levels(pre$desserte)[[1]]
  if (!is.data.frame(cl) || ncol(cl) < 2L) {
    return(which(!is.na(v)))
  }
  codes <- cl[[1]][as.character(cl[[2]]) %in% .classes_livraison()]
  which(!is.na(v) & v %in% codes)
}

# Le champ `classe` existe et ne contient que des valeurs reconnues.
.valider_desserte <- function(desserte) {
  checkmate::assert_class(desserte, "sf", .var.name = "desserte")

  if (!"classe" %in% names(desserte)) {
    cli::cli_abort(c(
      "La desserte doit posseder un champ {.field classe}.",
      "x" = "Champs presents : {.field {setdiff(names(desserte), attr(desserte, 'sf_column'))}}."
    ))
  }

  valeurs <- as.character(desserte$classe)
  if (anyNA(valeurs)) {
    cli::cli_abort("Le champ {.field classe} de la desserte contient des {.val NA}.")
  }

  # `hors_desserte` est ACCEPTE (il porte la topologie) mais ne sera pas
  # rasterise ; toute autre valeur reste une erreur.
  attendues <- .classes_desserte_connues()
  inconnues <- setdiff(unique(valeurs), attendues)
  if (length(inconnues)) {
    cli::cli_abort(c(
      "Valeur{?s} de {.field classe} inconnue{?s} dans la desserte : {.val {inconnues}}.",
      "i" = "Valeurs attendues : {.val {attendues}}."
    ))
  }

  invisible(TRUE)
}

# CRS d'une couche, en `crs` sf. Un CRS absent vaut NA (terra renvoie "").
.crs_sf <- function(x) {
  if (!inherits(x, "SpatRaster")) {
    return(sf::st_crs(x))
  }
  wkt <- terra::crs(x)
  if (!nzchar(wkt)) sf::NA_crs_ else sf::st_crs(wkt)
}

# CRS strictement identique à celui du MNT.
.valider_crs <- function(x, mnt, arg) {
  crs_x <- .crs_sf(x)
  crs_mnt <- .crs_sf(mnt)

  if (is.na(crs_x)) {
    cli::cli_abort("{.arg {arg}} n'a pas de CRS defini (attendu : celui du MNT).")
  }
  if (crs_x != crs_mnt) {
    cli::cli_abort(c(
      "CRS divergent pour {.arg {arg}}.",
      "x" = "{.arg {arg}} : {crs_x$input %||% 'inconnu'} ; MNT : {crs_mnt$input %||% 'inconnu'}.",
      "i" = "Reprojetez la couche sur le CRS du MNT avant l'appel (politique stricte)."
    ))
  }
  invisible(TRUE)
}

# Grille raster strictement identique à celle du MNT (dimensions, résolution, emprise).
.valider_grille <- function(r, mnt, arg) {
  if (!identical(dim(r)[1:2], dim(mnt)[1:2])) {
    cli::cli_abort(c(
      "Grille non alignee pour {.arg {arg}}.",
      "x" = "Dimensions {paste(dim(r)[1:2], collapse = 'x')} ; MNT : \\
             {paste(dim(mnt)[1:2], collapse = 'x')}."
    ))
  }
  if (!isTRUE(all.equal(terra::res(r), terra::res(mnt)))) {
    cli::cli_abort(c(
      "Grille non alignee pour {.arg {arg}}.",
      "x" = "Resolution {paste(terra::res(r), collapse = 'x')} ; MNT : \\
             {paste(terra::res(mnt), collapse = 'x')}."
    ))
  }
  if (!isTRUE(all.equal(as.vector(terra::ext(r)), as.vector(terra::ext(mnt))))) {
    cli::cli_abort(c(
      "Grille non alignee pour {.arg {arg}}.",
      "x" = "L'emprise differe de celle du MNT.",
      "i" = "Aucun reechantillonnage silencieux n'est effectue (politique stricte)."
    ))
  }
  invisible(TRUE)
}

# Géométries présentes, non vides et valides.
.valider_geometries <- function(x, arg) {
  checkmate::assert_class(x, "sf", .var.name = arg)

  if (nrow(x) == 0L) {
    cli::cli_abort("{.arg {arg}} ne contient aucune geometrie.")
  }
  vides <- sf::st_is_empty(x)
  if (any(vides)) {
    cli::cli_abort(c(
      "{.arg {arg}} contient {sum(vides)} geometrie{?s} vide{?s}.",
      "x" = "Ligne{?s} concernee{?s} : {which(vides)}."
    ))
  }
  invalides <- !sf::st_is_valid(x)
  if (any(invalides, na.rm = TRUE)) {
    cli::cli_abort(c(
      "{.arg {arg}} contient {sum(invalides, na.rm = TRUE)} geometrie{?s} invalide{?s}.",
      "i" = "Corrigez avec {.fn sf::st_make_valid} avant l'appel."
    ))
  }
  invisible(TRUE)
}

# L'emprise de la couche recoupe celle du MNT.
.valider_recouvrement <- function(x, mnt, arg) {
  bb <- sf::st_bbox(x)
  em <- terra::ext(mnt)
  disjoint <- bb[["xmax"]] < em$xmin || bb[["xmin"]] > em$xmax ||
    bb[["ymax"]] < em$ymin || bb[["ymin"]] > em$ymax
  if (disjoint) {
    cli::cli_abort(c(
      "{.arg {arg}} ne recoupe pas l'emprise du MNT.",
      "x" = "Emprises disjointes."
    ))
  }
  invisible(TRUE)
}
