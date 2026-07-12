#' Selection multicritere des lignes cable (Lot 5)
#'
#' Reproduit `select_best_lines` / `create_best_table` de Sylvaccess v3.6 : parmi
#' les lignes candidates du balayage cable ([potentiel_cable()]), en selectionne
#' un sous-ensemble non redondant maximisant la couverture selon des criteres
#' ponderes. Enchaine : filtrage par limites, score pondere normalise,
#' classement, selection **gloutonne** (une ligne n'est retenue que si elle
#' apporte assez de surface **nouvelle**).
#'
#' Six criteres (EF-7) : surface (max), supports (min), sens (amont/aval),
#' longueur (min/max), volume (max), IPC (max). Chacun a un **poids** (0 = ignore)
#' et une **limite**, dans `config$cable$selection`. Sans donnee de volume, les
#' criteres volume/IPC sont neutralises.
#'
#' @param cable Objet `foretaccess_cable` (voir [potentiel_cable()]), dont la
#'   table `$lignes` porte les candidates.
#' @param config Objet `foretaccess_config` ; les poids/limites vivent dans
#'   `config$cable$selection`. Par defaut, celui du `cable`.
#'
#' @return Un objet `foretaccess_selection` : `lignes` (objet `sf` LINESTRING des
#'   lignes retenues, avec attributs), `couverture` (`SpatRaster` de la zone
#'   couverte), `config`.
#' @export
selectionner_lignes <- function(cable, config = cable$config) {
  checkmate::assert_class(cable, "foretaccess_cable")
  sel <- config$cable$selection
  lignes <- cable$lignes
  gabarit <- cable$accessibilite
  res <- terra::res(gabarit)[1]
  nr <- terra::nrow(gabarit)
  nc <- terra::ncol(gabarit)

  # Volume disponible ? Sinon on neutralise les criteres volume/IPC.
  vol_dispo <- any(!is.na(lignes$volume_m3)) && any(lignes$volume_m3 > 0, na.rm = TRUE)
  poids <- sel$poids
  lim <- sel$limites
  if (!vol_dispo) {
    poids$volume <- 0
    poids$ipc <- 0
  }

  # 1. Filtrage par limites.
  garde <- lignes$surface_ha >= lim$surface_min &
    lignes$supports <= lim$supports_max &
    lignes$longueur_m >= lim$longueur_min &
    lignes$longueur_m <= lim$longueur_max
  if (vol_dispo) {
    garde <- garde & lignes$volume_m3 >= lim$volume_min & lignes$ipc >= lim$ipc_min
  }
  lignes <- lignes[garde, , drop = FALSE]
  if (!nrow(lignes)) {
    return(.selection_vide(gabarit, config))
  }

  # 2. Score pondere normalise, puis 3. classement (sens prefere d'abord).
  score <- .score_lignes(lignes, poids)
  ordre <- .ordre_selection(lignes, score, sel$sens_prefere)
  lignes <- lignes[ordre, , drop = FALSE]

  # 4. Selection gloutonne : contribution de surface nouvelle >= seuil.
  rayons <- .rayons(res, max(lignes$longueur_m))
  couvert <- rep(FALSE, nr * nc)
  retenue <- logical(nrow(lignes))
  for (i in seq_len(nrow(lignes))) {
    cel <- .cellules_ligne(lignes$depart[i], lignes$azimut[i], lignes$longueur_m[i],
      rayons, nr, nc)
    if (!length(cel)) next
    if (sum(!couvert[cel]) / length(cel) >= sel$contribution_min) {
      retenue[i] <- TRUE
      couvert[cel] <- TRUE
    }
  }
  lignes <- lignes[retenue, , drop = FALSE]

  # 5. Sorties : sf des lignes + raster de couverture.
  couv_r <- terra::rast(gabarit)
  terra::values(couv_r) <- as.integer(couvert)
  names(couv_r) <- "couverture_cable"

  structure(
    list(
      lignes     = .lignes_sf(lignes, gabarit),
      couverture = couv_r,
      config     = config
    ),
    class = "foretaccess_selection"
  )
}

# Score pondere : chaque critere est normalise dans [0, ~1] puis pondere.
# Maximiser (surface, volume, IPC) : v / p98 (robuste). Minimiser (supports,
# longueur) : 1 - v / max. Le score est la somme.
.score_lignes <- function(lignes, poids) {
  maxi <- function(v, w) {
    if (w <= 0) {
      return(rep(0, length(v)))
    }
    p <- stats::quantile(v, 0.98, names = FALSE, na.rm = TRUE)
    if (is.na(p) || p <= 0) rep(0, length(v)) else (v / p) * w
  }
  mini <- function(v, w) {
    if (w <= 0) {
      return(rep(0, length(v)))
    }
    m <- max(v, na.rm = TRUE)
    if (is.na(m) || m <= 0) rep(0, length(v)) else (1 - v / m) * w
  }
  maxi(lignes$surface_ha, poids$surface) +
    mini(lignes$supports, poids$supports) +
    mini(lignes$longueur_m, poids$longueur) +
    maxi(lignes$volume_m3, poids$volume) +
    maxi(lignes$ipc, poids$ipc)
}

# Ordre de selection : score decroissant, ties casses par (depart, azimut) pour
# le determinisme (CA-5.8). Si un sens est prefere, ses lignes passent d'abord.
.ordre_selection <- function(lignes, score, sens_prefere) {
  cle <- function(idx) idx[order(-score[idx], lignes$depart[idx], lignes$azimut[idx])]
  if (sens_prefere != 0) {
    pref <- which(lignes$sens == sens_prefere)
    autre <- which(lignes$sens != sens_prefere)
    c(cle(pref), cle(autre))
  } else {
    cle(seq_len(nrow(lignes)))
  }
}

# Cellules couvertes par une ligne (depart, azimut, longueur), sans recalcul de
# faisabilite : simple parcours du rayon jusqu'a la longueur.
.cellules_ligne <- function(depart, az, longueur, rayons, nr, nc) {
  ray <- rayons[[az + 1L]]
  ray <- ray[ray$hdist <= longueur, , drop = FALSE]
  if (!nrow(ray)) {
    return(integer(0))
  }
  dl0 <- (depart - 1L) %/% nc + 1L
  dc0 <- (depart - 1L) %% nc + 1L
  lig <- dl0 + ray$dl
  col <- dc0 + ray$dc
  dans <- lig >= 1L & lig <= nr & col >= 1L & col <= nc
  (lig[dans] - 1L) * nc + col[dans]
}

# Lignes retenues -> objet sf LINESTRING (depart -> extremite via azimut/longueur).
.lignes_sf <- function(lignes, gabarit) {
  crs <- sf::st_crs(terra::crs(gabarit))
  if (!nrow(lignes)) {
    return(sf::st_sf(lignes, geometry = sf::st_sfc(crs = crs)))
  }
  xy0 <- terra::xyFromCell(gabarit, lignes$depart)
  rad <- lignes$azimut * pi / 180
  x1 <- xy0[, 1] + lignes$longueur_m * sin(rad)
  y1 <- xy0[, 2] + lignes$longueur_m * cos(rad)
  geoms <- lapply(seq_len(nrow(lignes)), function(i) {
    sf::st_linestring(rbind(c(xy0[i, 1], xy0[i, 2]), c(x1[i], y1[i])))
  })
  sf::st_sf(lignes, geometry = sf::st_sfc(geoms, crs = crs))
}

.selection_vide <- function(gabarit, config) {
  couv_r <- terra::rast(gabarit)
  terra::values(couv_r) <- 0L
  names(couv_r) <- "couverture_cable"
  vide <- data.frame(
    depart = integer(0), azimut = numeric(0), longueur_m = numeric(0),
    surface_ha = numeric(0), sens = integer(0), supports = integer(0),
    volume_m3 = numeric(0), ipc = numeric(0)
  )
  structure(
    list(
      lignes = sf::st_sf(vide, geometry = sf::st_sfc(crs = sf::st_crs(terra::crs(gabarit)))),
      couverture = couv_r,
      config = config
    ),
    class = "foretaccess_selection"
  )
}

#' @export
print.foretaccess_selection <- function(x, ...) {
  cli::cli_inform(c(
    "Selection de lignes cable ForetAccess",
    "*" = "lignes retenues : {nrow(x$lignes)}",
    "*" = "surface cable couverte : \\
           {signif(sum(terra::values(x$couverture), na.rm = TRUE) * prod(terra::res(x$couverture)) / 10000, 4)} ha"
  ))
  invisible(x)
}
