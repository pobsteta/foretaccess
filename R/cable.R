#' Potentiel d'accessibilite par cable-mat (Lot 4d)
#'
#' Reproduit le balayage 360 deg / pixel de Sylvaccess v3.6 (moteur cable) :
#' depuis chaque cellule de desserte (depart de ligne), un rayon est lance dans
#' chacune des 360 directions ; le profil d'altitude sous le rayon est extrait du
#' MNT, echantillonne au demi-metre, et la faisabilite d'une ligne de cable
#' (travee simple, **sans support intermediaire**) est evaluee par le noyau Rust
#' [cable_test_span()] jusqu'a `longueur_max_m`. Les cellules forestieres
#' traversees par une ligne faisable sont marquees accessibles au cable.
#'
#' Le placement de supports intermediaires (`OptPyl_Up`) et le pechage lateral
#' (`distance_laterale_max_m`) sont des extensions futures (voir `specs/004`) :
#' ce lot livre le potentiel **0 support**, colonne vertebrale testable.
#'
#' @param pre Objet `foretaccess_preprocessing` (voir [preprocess()]).
#' @param config Objet `foretaccess_config`. Les parametres cable (garde au sol,
#'   materiel, geometrie) vivent dans `config$cable`.
#' @param write_dir Repertoire d'ecriture des rasters (COG), ou `NULL`.
#' @param bord Reserve au tuilage (Lot 7) ; ignore ici (pas de propagation
#'   longue portee a certifier au-dela du halo).
#'
#' @return Un objet de classe `foretaccess_cable` : `accessibilite` (raster de
#'   classes : accessible_cable / non_accessible / hors_foret), `longueur_ligne`
#'   (m, meilleure ligne couvrant la cellule), `azimut_ligne` (deg),
#'   `nb_supports` (0 dans ce lot), `recap`, `grid`, `config`, `fichiers`.
#' @export
potentiel_cable <- function(pre, config = foretaccess_config(), write_dir = NULL, bord = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  ct <- .constantes_cable(config$cable)
  res <- terra::res(pre$mnt)[1]
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)
  n <- nr * nc

  alt <- as.numeric(terra::values(pre$mnt))
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  routes <- which(!is.na(terra::values(pre$desserte)))
  if (!length(routes)) {
    cli::cli_abort("Aucune cellule de desserte : le cable n'a pas de point de depart.")
  }

  couvert <- rep(FALSE, n)
  longueur <- rep(0, n)
  azimut <- rep(NA_real_, n)

  rayons <- .rayons(res, ct$lmax)

  for (dep in routes) {
    dl0 <- (dep - 1L) %/% nc + 1L
    dc0 <- (dep - 1L) %% nc + 1L
    for (az in seq_along(rayons)) {
      ligne <- .ligne_cable(rayons[[az]], dl0, dc0, dep, alt, nr, nc, ct, res)
      if (is.null(ligne)) next
      couv <- ligne$cel[ligne$hdist <= ligne$longueur]
      if (!length(couv)) next
      couvert[couv] <- TRUE
      idx <- couv[ligne$longueur > longueur[couv]]
      longueur[idx] <- ligne$longueur
      azimut[idx] <- az - 1L
    }
  }

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

# Pour un rayon (offsets dl/dc + hdist) depuis le depart, construit le profil
# d'altitude echantillonne au demi-metre et cherche la plus longue ligne de
# cable faisable (0 support), du plus long au plus court. Renvoie les cellules du
# rayon, leur hdist, et la longueur faisable retenue -- ou NULL si aucune.
.ligne_cable <- function(ray, dl0, dc0, dep, alt, nr, nc, ct, pas) {
  lig <- dl0 + ray$dl
  col <- dc0 + ray$dc
  dans <- lig >= 1L & lig <= nr & col >= 1L & col <= nc
  if (!any(dans)) return(NULL)
  ray <- ray[dans, , drop = FALSE]
  cel <- (lig[dans] - 1L) * nc + col[dans]

  smax <- max(ray$hdist)
  if (smax < ct$lmin) return(NULL) # trop court pour une ligne (< longueur_min)

  # Profil au demi-metre : depart (hdist 0) puis cellules du rayon.
  hd <- c(0, ray$hdist)
  za <- c(alt[dep], alt[cel])
  xs <- seq(0, smax, by = 0.5)
  zs <- stats::approx(hd, za, xout = xs)$y

  # Candidats de longueur, du plus long au plus court (pas = resolution) :
  # premiere travee faisable = la plus longue. La granularite de la couverture
  # etant la cellule, un pas plus fin serait inutile (et couteux).
  hi <- min(smax, ct$lmax)
  if (hi < ct$lmin) return(NULL)
  for (l_cand in seq(hi, ct$lmin, by = -pas)) {
    posi <- as.integer(round(l_cand * 2)) # indice 0.5 m
    if (posi >= length(xs)) next
    r <- cable_test_span(
      xs, zs, 0L, posi, ct$htower, ct$h_end, ct$hline_min, ct$hline_max,
      ct$slope_min, ct$slope_max, zs, ct$f_o, ct$tmax, ct$q1, ct$q2, ct$q3,
      ct$eao, 0.5, ct$angle_intsup, 0, -9999
    )
    if (r[1] == 1) {
      return(list(cel = cel, hdist = ray$hdist, longueur = xs[posi + 1L]))
    }
  }
  NULL
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
