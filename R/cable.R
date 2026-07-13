#' Potentiel d'accessibilite par cable-mat (Lot 4d)
#'
#' Reproduit le balayage 360 deg / pixel de Sylvaccess v3.6 (moteur cable) :
#' depuis chaque **place de depot** (depart de ligne), un rayon est lance dans
#' chacune des 360 directions ; le profil d'altitude sous le rayon est extrait du
#' MNT, echantillonne au demi-metre, et la faisabilite d'une ligne de cable
#' (travee simple, **sans support intermediaire**) est evaluee par le noyau Rust
#' [cable_test_span()] jusqu'a `longueur_max_m`. Les cellules forestieres
#' traversees par une ligne faisable sont marquees accessibles au cable.
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
#' Le placement de supports intermediaires (`OptPyl_Up`) et le pechage lateral
#' (`distance_laterale_max_m`) sont des extensions futures (voir `specs/004`) :
#' ce lot livre le potentiel **0 support**, colonne vertebrale testable.
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
    slope_min = ct$slope_min, slope_max = ct$slope_max,
    f_o = ct$f_o, tmax = ct$tmax, q1 = ct$q1, q2 = ct$q2, q3 = ct$q3,
    eao = ct$eao, angle_intsup = ct$angle_intsup, lmax = ct$lmax, lmin = ct$lmin
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
    supports   = rep(0L, k),
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
    angle_intsup = ca$angle_intersupport_deg * pi / 180,
    slope_min = ca$pente_min_rad,
    slope_max = ca$pente_max_rad
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
