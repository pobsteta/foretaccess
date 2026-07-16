#' Potentiel d'accessibilite par cable-mat (Lot 4d)
#'
#' Reproduit le balayage 360 deg / pixel de Sylvaccess v3.6 (moteur cable) :
#' depuis chaque **place de depot** (depart de ligne), un rayon est lance dans
#' chaque direction ; le profil d'altitude sous le rayon est extrait du MNT, et le
#' noyau Rust place jusqu'a `nb_supports_max` **supports intermediaires**
#' (`OptPyl_Up_NoH`), coupant la ligne au point le plus lointain atteint quand il ne
#' peut pas la porter entiere. Les cellules forestieres traversees par une ligne
#' faisable sont marquees accessibles au cable.
#'
#' Le profil sert sous deux formes, comme dans la source : **au pixel** pour poser les
#' supports, **au demi-metre** pour la garde au sol.
#'
#' @section Validite de la ligne:
#' Avant meme de savoir si le cable TIENT, il faut savoir jusqu'ou la ligne a un SENS.
#' `check_line` la coupe sur trois criteres geometriques : elle **finit en foret** (on
#' n'installe pas un cable pour desservir un pre), elle ne traverse pas plus de
#' `min(0,1 x longueur_max_m, longueur_min_m)` metres de non-foret d'affilee, et elle ne
#' **court pas en travers d'un versant raide** (`angle_transversal_deg`,
#' `pente_transversale_max_pct`, `distance_transversale_max_m`,
#' `proportion_transversale_max`). Sans ce filtre, les lignes filent jusqu'a
#' `longueur_max_m` a travers n'importe quel terrain : sur le jeu ColduPre, cela declare
#' accessible a tort **10 %** de la foret.
#'
#' @section Sens de debardage:
#' Une ligne se resout dans l'un ou l'autre sens selon que la machine, posee sur la
#' desserte, **domine** ou non le profil (mat au depart + `hauteur_mat_m` contre point
#' haut de la ligne + `hauteur_ancrage_m`). « Machine en haut » : le cable descend, les
#' bornes de pente sont `bornes_pente_cable()$amont_*`. « Machine en bas » : le cable
#' monte, la ligne se resout sur le profil **retourne** (l'ancrage ouvre, le mat ferme)
#' avec les bornes `aval_*` niees, et elle ne peut pas etre coupee du cote machine --
#' seulement raccourcie par le haut.
#'
#' @section Ecarts assumes avec Sylvaccess v3.6:
#' L'optimisation de la **hauteur de fixation** sur chaque support (`c_option_h`,
#' `cable$optimiser_hauteur_fixation`) est **experimentale** et desactivee par defaut
#' (variante `_NoH`, le defaut de v3.6). Le portage des variantes a hauteur balayee
#' (`OptPyl_Up` / `OptPyl_Up2`) existe mais **ne reproduit pas encore l'oracle** : sur
#' ColduPre il *reduit* la couverture (net -999 cellules) la ou Sylvaccess l'*augmente*
#' (net +470), signe d'un defaut restant dans la passe machine-en-bas ; et il est
#' **~20x plus lent** (46 min pour 2 departs). A n'activer que pour experimenter. Cf.
#' `PLAN.md` (dette assumee du cable) et `specs/004-cable.md`.
#'
#' Le **pechage lateral** (`distance_laterale_max_m`, `c_l_hor`) est pris en compte :
#' la couverture d'une ligne faisable n'est pas son seul axe mais le rectangle de
#' demi-largeur `c_l_hor` autour du segment, comme `create_rast_couv` chez Sylvaccess.
#'
#' @section Places de depot:
#' Une ligne de cable ne part pas de n'importe ou : installer un cable-mat exige
#' une aire de depot, une plateforme et un acces camion. Sylvaccess en fait une
#' **entree a part** (`c_file_departure`), dont il ne retient que les troncons
#' portant l'attribut `CABLE` -- sur son jeu de test officiel, **2 troncons sur
#' 125**. Passer `departs` reproduit ce comportement.
#'
#' Sans `departs`, on retombe sur *toute* la desserte : la couverture est alors
#' tres **optimiste** (on desservirait de la foret depuis des pistes incapables
#' d'accueillir un cable) et le balayage, proportionnel au nombre de departs,
#' devient tres long. Ce repli n'existe que pour les cas ou l'on ne dispose
#' d'aucune couche de places de depot.
#'
#' @param pre Objet `foretaccess_preprocessing` (voir [preprocess()]).
#' @param config Objet `foretaccess_config`. Les parametres cable (garde au sol,
#'   materiel, geometrie) vivent dans `config$cable`.
#' @param departs Places de depot d'ou une ligne de cable peut partir : chemin de
#'   vecteur ou objet `sf` (lignes, polygones ou points). Si la couche porte un
#'   champ `cable`, seules les entites dont `cable` est non nul sont retenues
#'   (equivalent de l'attribut `CABLE` de Sylvaccess). `NULL` (defaut) : repli sur
#'   toute la desserte -- voir la section *Places de depot*.
#' @param write_dir Repertoire d'ecriture des rasters (COG), ou `NULL`.
#' @param bord Reserve au tuilage (Lot 7) ; ignore ici (pas de propagation
#'   longue portee a certifier au-dela du halo).
#'
#' @return Un objet de classe `foretaccess_cable` : `accessibilite` (raster de
#'   classes : accessible_cable / non_accessible / hors_foret), `longueur_ligne`
#'   (m, meilleure ligne couvrant la cellule), `azimut_ligne` (deg),
#'   `nb_supports` (0 dans ce lot), `lignes` (data.frame des lignes candidates :
#'   `depart`, `azimut`, `longueur_m`, `surface_ha`, `sens`, `supports`,
#'   `volume_m3`, `ipc` -- une par (depart, azimut) faisable, pour la selection
#'   du Lot 5), `recap`, `grid`, `config`, `fichiers`.
#' @export
potentiel_cable <- function(pre, config = foretaccess_config(), departs = NULL,
                            write_dir = NULL, bord = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  ct <- .constantes_cable(config$cable)
  if (isTRUE(ct$optim_h)) {
    cli::cli_warn(c(
      "Optimisation de hauteur de fixation ({.code optimiser_hauteur_fixation}) EXPERIMENTALE.",
      "!" = "Elle ne reproduit pas l'oracle Sylvaccess (reduit la couverture) et est ~20x plus lente.",
      "i" = "Defaut recommande : {.code FALSE}. Voir {.file PLAN.md} (dette cable)."
    ))
  }
  res <- terra::res(pre$mnt)[1]
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)
  n <- nr * nc

  alt <- as.numeric(terra::values(pre$mnt))
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  routes <- .cellules_depart_cable(pre, departs)

  # Balayage 360 deg / pixel porte en Rust (crate cablehelp, parallele `rayon`).
  # L'orchestration -- extraction du profil, recherche de la travee faisable,
  # accumulation couverture/lignes -- vit desormais dans le noyau ; R prepare les
  # entrees et reassemble les sorties SIG. Voir src/rust/src/cable/scan.rs.
  vol <- if (!is.null(pre$volume)) as.numeric(terra::values(pre$volume)) else NULL
  sc <- cable_scan(
    alt = alt, nr = nr, nc = nc, res = res,
    foret = as.integer(foret), routes = as.integer(routes),
    vol = if (is.null(vol)) numeric(0) else vol, has_vol = !is.null(vol),
    htower = ct$htower, h_end = ct$h_end,
    hline_min = ct$hline_min, hline_max = ct$hline_max,
    # Les deux jeux de bornes : le noyau choisit le sens ligne par ligne, selon que
    # la machine domine ou non le profil (cf. `potentiel_cable()`, Sens de debardage).
    slope_min = ct$bornes$amont_min, slope_max = ct$bornes$amont_max,
    slope_min_aval = ct$bornes$aval_min, slope_max_aval = ct$bornes$aval_max,
    f_o = ct$f_o, tmax = ct$tmax, q1 = ct$q1, q2 = ct$q2, q3 = ct$q3,
    eao = ct$eao, angle_intsup = ct$angle_intsup, lmax = ct$lmax, lmin = ct$lmin,
    hintsup = ct$hintsup, sup_max = ct$sup_max, lmin_span = ct$lmin_span,
    nbconfig = ct$prec$largeur_faisceau,
    pas_azimut = ct$prec$pas_azimut_deg, pas_depart = ct$prec$pas_depart,
    aspect = as.numeric(terra::values(pre$aspect_deg)),
    pente = as.numeric(terra::values(pre$slope_pct)),
    lsans_foret = ct$lsans_foret, angle_transv = ct$angle_transv,
    slope_trans = ct$slope_trans, l_slope = ct$l_slope, prop_slope = ct$prop_slope,
    l_hor = ct$l_hor,
    optim_h = ct$optim_h
  )

  couvert <- sc$couvert == 1L
  longueur <- sc$longueur
  azimut <- sc$azimut

  k <- length(sc$li_dep)
  lignes <- data.frame(
    depart     = sc$li_dep,
    azimut     = sc$li_az,
    longueur_m = sc$li_lg,
    surface_ha = sc$li_surf,
    sens       = sc$li_sens,
    supports   = sc$li_nsup,
    volume_m3  = sc$li_vol,
    ipc        = sc$li_ipc
  )

  accessible <- couvert & foret
  codes <- rep(3L, n) # non_accessible
  codes[accessible] <- 1L # accessible_cable
  codes[!foret] <- 4L # hors_foret

  faire <- function(v, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }
  acc <- faire(codes, "accessibilite")
  levels(acc) <- data.frame(
    value = c(1L, 3L, 4L),
    classe = c("accessible_cable", "non_accessible", "hors_foret")
  )
  longueur[!accessible] <- NA_real_
  azimut[!accessible] <- NA_real_

  ca <- structure(
    list(
      accessibilite  = acc,
      longueur_ligne = faire(longueur, "longueur_ligne"),
      azimut_ligne   = faire(azimut, "azimut_ligne"),
      nb_supports    = faire(ifelse(accessible, 0L, NA_integer_), "nb_supports"),
      lignes         = lignes,
      recap          = recapituler(acc, pre$volume),
      grid           = pre$grid,
      config         = config,
      fichiers       = NULL
    ),
    class = "foretaccess_cable"
  )
  if (!is.null(write_dir)) ca$fichiers <- .ecrire_rasters_cable(ca, write_dir)
  ca
}

#' Échantillonnage du balayage câble, dérivé de la précision
#'
#' Reproduit `get_dep_config()` de Sylvaccess v3.6. Un seul réglage, `precision`,
#' gouverne **trois** choses à la fois : le pas angulaire du balayage, le pas entre
#' cellules de départ, et la largeur du faisceau de placement des supports.
#'
#' @param precision `1` (fine), `2` (moyenne) ou `3` (grossière, défaut v3.6).
#' @return Une liste : `pas_azimut_deg`, `pas_depart` (n'échantillonner qu'une cellule
#'   de départ sur `pas_depart`), `largeur_faisceau`.
#' @export
precision_cable <- function(precision = 3L) {
  p <- as.integer(precision)
  checkmate::assert_int(p, lower = 1, upper = 3)
  list(
    pas_azimut_deg   = if (p > 1L) 2L else 1L,
    pas_depart       = if (p == 3L) 2L else 1L,
    largeur_faisceau = if (p == 3L) 1L else 5L
  )
}

#' Bornes de pente admissibles d'une ligne de câble
#'
#' Reproduit `get_cable_configs()` de Sylvaccess v3.6. Ces bornes ne sont **pas** des
#' paramètres : elles se **déduisent** du type de chariot, du type de câble et du sens
#' de débardage autorisé. C'est une contrainte de la machine, pas un réglage.
#'
#' @details
#' Pour un **chariot classique** sur mât-câble (`type_chariot = 0`, `type_cable < 3`),
#' débardage dans les deux sens : la ligne « machine en haut » est bornée à
#' \eqn{[-1{,}4\;;\;+0{,}1]} rad — elle **doit descendre**, avec 0,1 rad de tolérance —
#' et la ligne « machine en bas » à \eqn{[-0{,}1\;;\;+1{,}4]}. Débardage à l'amont seul
#' (`sens_debardage = 1`), la borne haute devient \eqn{-\arctan(p_{grav}/100)} : le
#' chariot descend **par gravité**, il lui faut donc une pente minimale.
#'
#' Pour un **winch-liner** (`type_chariot = 1`), les bornes viennent de
#' `pente_winchliner_amont_pct` / `_aval_pct` : le chariot est tracté, il ne dépend plus
#' de la gravité.
#'
#' @param ca La liste `config$cable`.
#' @return Une liste de quatre bornes en radians : `amont_min`, `amont_max`,
#'   `aval_min`, `aval_max`.
#' @export
bornes_pente_cable <- function(ca) {
  ang <- function(pct) atan(pct / 100)
  grav <- ang(ca$pente_gravite_pct)
  wl_up <- ang(ca$pente_winchliner_amont_pct)
  wl_dn <- ang(ca$pente_winchliner_aval_pct)
  sens <- as.integer(ca$sens_debardage)

  b <- function(amont_min, amont_max, aval_min, aval_max) {
    list(amont_min = amont_min, amont_max = amont_max, aval_min = aval_min, aval_max = aval_max)
  }

  if (as.integer(ca$type_chariot) == 1L) {
    # Winch-liner : le chariot est tracte, la pente vient du materiel.
    return(switch(as.character(sens),
      "0" = b(-wl_up, 0.1, -0.1, wl_dn),
      "1" = b(-wl_up, 0.1, 0, 0),
      b(0, 0, -0.1, wl_dn)
    ))
  }
  if (as.integer(ca$type_cable) < 3L) {
    # Chariot classique sur mat-cable.
    return(switch(as.character(sens),
      "0" = b(-1.4, 0.1, -0.1, 1.4),
      "1" = b(-1.4, -grav, 0, 0),
      b(0, 0, -0.1, 1.4)
    ))
  }
  # Cable long classique : la descente par gravite est requise dans les deux sens.
  switch(as.character(sens),
    "0" = b(-1.4, -grav, grav, 1.4),
    "1" = b(-1.4, -grav, 0, 0),
    b(0, 0, grav, 1.4)
  )
}

# Constantes physiques et parametres derives de config$cable (v3.6).
.constantes_cable <- function(ca) {
  g <- 9.80665
  list(
    g = g,
    f_o = g * (ca$charge_max_kg + ca$poids_chariot_kg), # Fo
    eao = ca$module_young_n_mm2 * 0.25 * pi * ca$diametre_mm^2, # E * Ao
    tmax = ca$tension_rupture_kgf * g / ca$coeff_securite, # c_rupt * g / c_safe
    q1 = ca$masse_lineaire_porteur_kg_m,
    q2 = ca$masse_lineaire_traction_kg_m,
    q3 = ca$masse_lineaire_retour_kg_m,
    hline_min = ca$hauteur_cable_min_m,
    hline_max = ca$hauteur_cable_max_m,
    htower = ca$hauteur_mat_m,
    h_end = ca$hauteur_support_terminal_m,
    lmax = ca$longueur_max_m,
    lmin = ca$longueur_min_m,
    hintsup = ca$hauteur_support_inter_m,
    sup_max = as.integer(ca$nb_supports_max),
    lmin_span = ca$longueur_min_travee_m,
    prec = precision_cable(ca$precision),
    angle_transv = ca$angle_transversal_deg,
    slope_trans = ca$pente_transversale_max_pct,
    l_slope = ca$distance_transversale_max_m,
    prop_slope = ca$proportion_transversale_max,
    l_hor = ca$distance_laterale_max_m,
    optim_h = isTRUE(ca$optimiser_hauteur_fixation), # c_option_h
    # `Lsans_foret = min(c_lmax * 0,1, c_lmin)` chez Sylvaccess, sauf surcharge.
    lsans_foret = if (is.na(ca$longueur_sans_foret_max_m)) {
      min(ca$longueur_max_m * 0.1, ca$longueur_min_m)
    } else {
      ca$longueur_sans_foret_max_m
    },
    angle_intsup = ca$angle_intersupport_deg * pi / 180,
    bornes = bornes_pente_cable(ca)
  )
}

# Cellules d'ou une ligne de cable peut partir.
#
# Sylvaccess prend une couche de depart dediee (`c_file_departure`) et n'en retient
# que les troncons portant l'attribut `CABLE` (`Cable_start > 0`) : sur son jeu de
# test officiel, 2 troncons sur 125. Une place de depot de cable-mat exige une aire
# de retournement et un acces camion -- ca n'existe pas sur n'importe quelle piste.
#
# Sans couche de depart, on retombe sur toute la desserte : couverture tres
# optimiste et balayage tres long. On le dit, plutot que de le laisser croire.
.cellules_depart_cable <- function(pre, departs) {
  if (is.null(departs)) {
    cel <- which(!is.na(terra::values(pre$desserte)))
    if (!length(cel)) {
      cli::cli_abort("Aucune cellule de desserte : le cable n'a pas de point de depart.")
    }
    cli::cli_inform(c(
      "!" = "Aucune couche de places de depot ({.arg departs}) : le balayage part
             des {length(cel)} cellules de desserte.",
      "i" = "La couverture cable sera optimiste -- une piste n'accueille pas un
             cable-mat. Voir la section {.emph Places de depot} de {.fn potentiel_cable}."
    ))
    return(cel)
  }

  dep <- .as_vector(departs, "departs")
  if (is.na(sf::st_crs(dep))) {
    cli::cli_abort("La couche {.arg departs} n'a pas de CRS.")
  }
  if (sf::st_crs(dep) != sf::st_crs(pre$mnt)) {
    cli::cli_abort(c(
      "Le CRS de {.arg departs} differe de celui du MNT.",
      "i" = "Aucune reprojection implicite : reprojeter en amont (ADR-004)."
    ))
  }

  # Attribut `cable` : equivalent du champ `CABLE` de Sylvaccess. Absent, toute la
  # couche est reputee cable-apte -- c'est deja une couche de places de depot.
  if ("cable" %in% names(dep)) {
    v <- dep[["cable"]]
    dep <- dep[!is.na(v) & v != 0, ]
    if (!nrow(dep)) {
      cli::cli_abort(c(
        "Aucune entite cable-apte dans {.arg departs}.",
        "i" = "Le champ {.field cable} vaut 0 ou {.val NA} partout."
      ))
    }
  }

  m <- .masque_vecteur(dep, pre$mnt, "departs_cable")
  cel <- which(as.numeric(terra::values(m)) == 1)
  if (!length(cel)) {
    cli::cli_abort(c(
      "La couche {.arg departs} ne couvre aucune cellule de la grille.",
      "i" = "Emprise disjointe du MNT ?"
    ))
  }
  cel
}

.couches_cable <- function() {
  c("accessibilite", "longueur_ligne", "azimut_ligne", "nb_supports")
}

.ecrire_rasters_cable <- function(ca, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)
  chemins <- vapply(.couches_cable(), function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    terra::writeRaster(ca[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))
  as.list(chemins)
}

#' @export
print.foretaccess_cable <- function(x, ...) {
  r <- x$recap
  cli::cli_inform(c(
    "Moteur cable ForetAccess (0 support)",
    "*" = "grille : {x$grid$nrow} x {x$grid$ncol} cellules",
    "*" = "surfaces (ha) : {paste0(r$classe, ' = ', signif(r$surface_ha, 4), collapse = ' ; ')}"
  ))
  invisible(x)
}
