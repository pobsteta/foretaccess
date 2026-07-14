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

  est_desserte <- rep(FALSE, n)
  est_desserte[desserte_cel] <- TRUE

  # --- Roulage sur terrain plat : plus court chemin depuis la desserte. -------
  # C'est la passe principale de Sylvaccess (`Dfwd_flat_forest_tracks` /
  # `Dfwd_flat_forest_road`), et elle seule sait CONTOURNER : le balayage radial
  # va tout droit, il ne franchit ni un ravin ni un rocher.
  cout_terrain <- surface_cout_skidder(pre, config)
  plat <- propager_cout(
    cout_terrain, .sources_desserte(pre, desserte_cel),
    zone = zone_plate_connectee(pre, config)
  )
  d_plat <- as.numeric(terra::values(plat$cout_cumule))
  a_plat <- as.numeric(terra::values(plat$allocation))
  roule <- !is.na(d_plat) & !est_desserte

  # --- Conduite : balayage radial depuis le reseau, sur la foret roulable. ----
  # Il ETEND la zone plate vers les pentes que l'engin prend encore, selon le sens
  # et le devers (spec 003 §4.2).
  zone_cond <- .zone_conduite(pre, config)
  cond <- conduire(pre, config, zone_cond)
  d_cond <- as.numeric(terra::values(cond$distance))
  a_cond <- as.numeric(terra::values(cond$allocation))
  balaye <- !is.na(d_cond) & !est_desserte & !roule

  conduit <- roule | balaye

  # --- Distance sur piste : precalculee globalement, ou locale. ---------------
  # Comme pour le skidder, la propagation LE LONG du reseau se fait sur la pente
  # seule : une desserte n'est pas un obstacle a la circulation sur elle-meme.
  piste <- if (is.null(pre$distance_piste)) {
    .distance_sur_piste(pre, ponderation_pente(pre$slope_pct), bord)
  } else {
    list(distance = as.numeric(terra::values(pre$distance_piste)), certifie = NULL)
  }

  # --- Balayage depuis le CONTOUR de la zone conduite (`fwd_azimuts_contour`). -
  # Meme mecanique que la troisieme passe du skidder : l'engin repart du bord de ce
  # qu'il a deja parcouru, en emportant sa distance. Le critere porte sur le total
  # `dist + 0,1 x d_piste + d_foret` -- la piste compte pour un dixieme, on la
  # parcourt dix fois plus volontiers que la foret.
  d_deja <- ifelse(roule, d_plat, ifelse(balaye, d_cond, 0))
  a_deja <- ifelse(roule, a_plat, ifelse(balaye, a_cond, NA_real_))
  ct <- .conduite_contour(pre, config, zone_cond, conduit, d_deja, a_deja, piste$distance)
  if (!is.null(ct)) {
    neuf <- !is.na(ct$distance) & !conduit & !est_desserte
    d_cond[neuf] <- ct$distance[neuf] + ct$distance_conduite[neuf]
    a_cond[neuf] <- ct$allocation[neuf]
    balaye <- balaye | neuf
    conduit <- roule | balaye
  }

  # --- Grappin : extension bornee depuis les cellules conduites. --------------
  # Les rampes sont les cellules de FORET ou l'engin s'est effectivement rendu, pas
  # les cellules de desserte : `fwd_filter_hoist()` ne retient que `Dforet > 0`, et
  # une cellule de desserte est a `Dforet == 0`. Grappiller depuis la route elle-meme
  # entourerait chaque voie d'un halo de foret « accessible » -- y compris sur un
  # versant a 90 %, ou le porteur ne peut pas se tenir. C'est de la que venaient
  # 7 345 des 7 847 cellules en trop sur ColduPre.
  grap <- .grappiller(pre, config, conduit)
  d_grap <- as.numeric(terra::values(grap$cout_cumule))
  a_grap <- as.numeric(terra::values(grap$allocation))
  grappe <- !is.na(d_grap) & !conduit & !est_desserte

  # --- Combinaison. -----------------------------------------------------------
  allocation <- ifelse(roule, a_plat, ifelse(balaye, a_cond, ifelse(grappe, a_grap, NA_real_)))
  allocation[est_desserte] <- desserte_cel

  dist_cond <- ifelse(roule, d_plat, ifelse(balaye, d_cond, 0))
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

# Zone traversable par le balayage du porteur, fidele a `Zone_OK` de Sylvaccess
# (`Sylvaccess_3_forwarder.py:432-450`) :
#
#   Zone_OK = (foret ∪ saut hors foret) ∩ Pente_ok_buch ∩ hors obstacles
#   zone    = Zone_OK ∩ pente <= max(travers, montee, descente)
#
# Trois points que les versions precedentes manquaient :
#   * la borne de pente est le **maximum** des trois seuils (30 % par defaut), pas le
#     minimum. Le balayage raffine ensuite par le sens et le devers (spec 003 §4.2) ; borner
#     a `min` (15 %) excluait a tort les cellules roulables en montee dans le sens de la pente ;
#   * un **saut hors foret** de `distance_hors_desserte_max_m` (200 m), pondere par la pente,
#     depuis le contour de la foret : le porteur peut couper par un terrain recoltable non
#     forestier pour rejoindre un massif isole. C'est `Pente_ok_forwarder`, l'analogue de
#     `zone_roulable_connectee()` du skidder ;
#   * le critere d'**abattage** (`Pente_ok_buch`) s'applique AUSSI EN FORET, et il porte sur
#     le **maximum local 3x3** de la pente, pas sur la pente de la cellule (`slopes_skid()`,
#     cf. `pre$slope_max_local`). Sylvaccess l'impose en dernier :
#     `zone_rast[Foret==1]=1` puis `zone_rast[Pente_ok_buch==0]=0`. On ne va pas chercher du
#     bois la ou l'on ne peut pas l'abattre, fut-ce en foret.
.zone_conduite <- function(pre, config) {
  po <- config$porteur
  seuil <- max(po$pente_travers_max_pct, po$pente_montee_max_pct, po$pente_descente_max_pct)
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)

  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  pente <- as.numeric(terra::values(pre$slope_pct))
  abattable <- .abattable(pre, po$pente_abattage_max_pct)
  # Le reseau public rejoint les obstacles du porteur, exactement comme dans
  # Sylvaccess (`Obstacles_forwarder[Res_pub==1]=1`).
  obst <- as.numeric(terra::values(pre$obstacles_complets_mask)) == 1 |
    as.numeric(terra::values(pre$reseau_public_mask)) == 1

  atteint <- .saut_hors_foret(pre, config, foret, abattable, obst, nr, nc)

  z <- (foret | atteint) & abattable & !is.na(pente) & (pente <= seuil) & !obst
  r <- terra::rast(pre$mnt)
  terra::values(r) <- as.numeric(z)
  names(r) <- "zone_conduite"
  r
}

# Balayage depuis le contour de la zone conduite (`fwd_azimuts_contour`).
#
# Les rampes sont les cellules du bord de la zone conduite QUI SONT SUR TERRAIN PLAT
# (`contour = (Dforet>=0) * (Pente_ok_forw==1)`) : on ne relance pas une machine depuis
# un point ou elle ne tient deja plus. Elles sont purgees des obstacles, du reseau
# public et des dessertes. Chaque rampe emporte sa distance deja parcourue, ponderee
# comme chez Sylvaccess : `0,1 x d_piste + d_foret`.
#
# Les cibles excluent les cellules deja conduites (`Temp = (Dforet>=0)*(contour==0)`),
# et le remplissage est additif (`fwd_fill_contour`). Rend `NULL` si le contour est vide.
.conduite_contour <- function(pre, config, zone_cond, conduit, d_deja, a_deja, d_piste) {
  n <- terra::ncell(pre$mnt)
  plat <- as.numeric(terra::values(terrain_plat(pre, config))) == 1

  zc <- terra::rast(pre$mnt)
  terra::values(zc) <- as.numeric(conduit)
  voisins <- terra::focal(zc, w = 3, fun = "sum", na.rm = TRUE)
  contour <- conduit & plat & (as.numeric(terra::values(voisins)) < 9)

  contour <- contour &
    as.numeric(terra::values(pre$obstacles_complets_mask)) == 0 &
    as.numeric(terra::values(pre$reseau_public_mask)) == 0 &
    is.na(terra::values(pre$desserte))
  contour[is.na(contour)] <- FALSE
  if (!any(contour)) {
    return(NULL)
  }

  # Cout emporte : la piste compte pour un dixieme de la foret.
  d_pis <- .piste_allouee(d_piste, a_deja)
  cout <- rep(0, n)
  cout[contour] <- d_deja[contour] + 0.1 * d_pis[contour]

  # Cibles : la zone de conduite, moins ce qui est deja conduit (sauf les rampes).
  zone <- terra::deepcopy(zone_cond)
  zone[which(conduit & !contour)] <- 0

  cd <- conduire(pre, config, zone, sources = which(contour), depart_cout = cout)
  d <- as.numeric(terra::values(cd$distance))
  a <- as.numeric(terra::values(cd$allocation))
  d[contour] <- NA_real_

  atteint <- !is.na(d) & !is.na(a)
  dc <- rep(NA_real_, n)
  alloc <- rep(NA_real_, n)
  # On herite de la rampe : sa distance deja parcourue, et sa desserte.
  dc[atteint] <- d_deja[a[atteint]]
  alloc[atteint] <- a_deja[a[atteint]]
  d[!atteint] <- NA_real_

  list(distance = d, distance_conduite = dc, allocation = alloc)
}

# `Pente_ok_buch` : maximum local 3x3 de la pente sous le seuil d'abattage. C'est le seul
# critere dilate de Sylvaccess (`slopes_skid()`) -- une cellule est ecartee des qu'une seule
# de ses huit voisines depasse le seuil.
.abattable <- function(pre, seuil) {
  m <- as.numeric(terra::values(pre$slope_max_local))
  !is.na(m) & m <= seuil
}

# Cellules non forestieres atteintes par le saut de `distance_hors_desserte_max_m` depuis
# le contour de la foret, sur du terrain recoltable (`Pente_ok_buch`, hors obstacles).
# `FALSE` partout si la couche est sans foret ou sans contour.
.saut_hors_foret <- function(pre, config, foret, abattable, obst, nr, nc) {
  po <- config$porteur
  n <- length(foret)
  if (!any(foret)) {
    return(rep(FALSE, n))
  }

  recoltable_hf <- !foret & !obst & abattable
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
# terrain recoltable. Reproduit `fwd_add_hoist` et sa zone
# (`Sylvaccess_3_forwarder.py:550-554`) : `Pente_ok_buch` (maximum local, cf. `.abattable()`),
# en foret, hors obstacles et hors reseau public. `propager_cout` a cout uniforme donne
# exactement cette distance.
.grappiller <- function(pre, config, atteintes) {
  po <- config$porteur
  n <- terra::ncell(pre$mnt)

  recoltable <- (pre$foret_mask == 1) &
    (pre$slope_max_local <= po$pente_abattage_max_pct) &
    (pre$obstacles_complets_mask == 0) &
    (pre$reseau_public_mask == 0)
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
