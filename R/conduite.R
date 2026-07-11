#' Balayage radial de conduite du porteur
#'
#' Reproduit `fwd_azimuts_forest_roadnet` de Sylvaccess v3.6 : depuis chaque cellule du
#' réseau de desserte, un balayage **360° au pas de 1°**, en ligne droite, jusqu'à
#' `distance_pente_forte_max_m`. Une cellule est conduisible si l'engin peut l'atteindre
#' sous trois contraintes de pente, distinctes de celles du skidder (spec 003 §4.2).
#'
#' @details
#' Contrairement au treuillage — dont ce balayage partage la géométrie ([.rayons()]) —
#' les filtres portent sur la **pente du terrain** à la cellule, en **degrés**, et non sur
#' le gradient du rayon. À chaque cellule `j` d'un rayon d'azimut `az`, le rayon s'arrête
#' (`break`) au premier filtre violé :
#'
#' 1. **Pente en long, signée par l'altitude.** Le porteur ramène le bois vers la route,
#'    chargé : si `alt_j > alt_route` le trajet est une descente
#'    (`pente_j ≤ pente_descente_max`), sinon une montée (`pente_j ≤ pente_montee_max`).
#' 2. **Dévers**, dépendant de l'azimut :
#'    \deqn{p_{lat,max} = \left| \theta_{lat} / \cos((90 - \Delta)\pi/180) \right|,
#'          \quad \Delta = (az - aspect_j) \bmod 180.}
#'    Nul dans le sens de la pente (`Δ → 0`, `cos(90°) = 0`, seuil infini), maximal en
#'    travers (`Δ → 90`, seuil `= θ_lat`). C'est le basculement latéral de la machine.
#' 3. **Distance cumulée en pente forte.** Un accumulateur croît de la longueur du pas là
#'    où `pente_j > θ_lat` ; le rayon casse si le cumul dépasse `distance_pente_forte_max_m`.
#'
#' La distance retenue est **3D** : `√(Hdist² + (alt_j − alt_route)²)`. Chaque cellule
#' garde la desserte la plus proche à ce sens.
#'
#' @param pre Objet `foretaccess_preprocessing` (Lot 1).
#' @param config Objet [foretaccess_config()].
#' @param zone `SpatRaster` logique des cellules candidates à la conduite (forêt roulable).
#'
#' @return Une liste de deux `SpatRaster` : `distance` (3D, m) et `allocation`.
#' @seealso [treuiller()], [.rayons()]
#' @export
conduire <- function(pre, config, zone) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  po <- config$porteur

  res <- terra::res(pre$mnt)[1]
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)

  alt <- as.numeric(terra::values(pre$mnt))
  # Pente et exposition en degres : Sylvaccess compare en angles, pas en pourcents.
  pente_deg <- .pct_en_deg(as.numeric(terra::values(pre$slope_pct)))
  aspect <- as.numeric(terra::values(pre$aspect_deg))
  zv <- as.numeric(terra::values(zone))
  conduisible <- !is.na(zv) & zv != 0

  routes <- which(!is.na(terra::values(pre$desserte)))
  if (!length(routes)) {
    cli::cli_abort("{.arg pre$desserte} ne contient aucune cellule.")
  }

  # Seuils en degres.
  s_up <- .pct_en_deg(po$pente_montee_max_pct)
  s_down <- .pct_en_deg(po$pente_descente_max_pct)
  s_lat <- .pct_en_deg(po$pente_travers_max_pct)
  lmax <- po$distance_pente_forte_max_m

  dist <- rep(Inf, nr * nc)
  alloc <- rep(NA_real_, nr * nc)

  rl <- ((routes - 1L) %/% nc) + 1L
  rc <- ((routes - 1L) %% nc) + 1L
  alt_r <- alt[routes]

  rayons <- .rayons(res, lmax)

  for (az in seq_along(rayons)) {
    ray <- rayons[[az]]
    az_deg <- az - 1L

    # Rayons vivants, compactes a chaque pas (cf. treuiller() : la plupart meurent vite).
    act <- routes
    rl_a <- rl
    rc_a <- rc
    alt_a <- alt_r
    # Distance deja parcourue en pente forte, par rayon.
    dpt <- rep(0, length(routes))

    for (i in seq_len(nrow(ray))) {
      lv <- rl_a + ray$dl[i]
      cv <- rc_a + ray$dc[i]
      dans <- lv >= 1L & lv <= nr & cv >= 1L & cv <= nc
      if (!any(dans)) break

      cel <- rep(NA_integer_, length(act))
      cel[dans] <- (lv[dans] - 1L) * nc + cv[dans]
      ok <- dans
      ok[dans] <- conduisible[cel[dans]]
      if (!any(ok)) break

      p_j <- pente_deg[cel]
      asp_j <- aspect[cel]

      # 1. Pente en long, signee par l'altitude. Le porteur ramene le bois charge vers la
      #    route : une cellule plus haute que la route -> trajet charge en descente (seuil
      #    descente) ; plus basse -> montee (seuil montee).
      charge_descend <- alt[cel] > alt_a
      seuil_long <- ifelse(charge_descend, s_down, s_up)
      ok <- ok & !is.na(p_j) & p_j <= seuil_long

      # 2. Devers, dependant de l'azimut. `aspect_j` peut etre NA (replat) : sans
      #    direction de pente, il n'y a pas de devers, la contrainte ne s'applique pas.
      delta <- (az_deg - asp_j) %% 180
      cos_t <- cos((90 - delta) / 180 * pi)
      p_lat_max <- ifelse(is.na(asp_j) | cos_t == 0, Inf, abs(s_lat / cos_t))
      ok <- ok & (is.na(asp_j) | p_j <= p_lat_max)

      # 3. Accumulateur de pente forte : croit la ou p_j > s_lat, plafonne a lmax.
      pas_i <- if (i == 1L) ray$hdist[i] else ray$hdist[i] - ray$hdist[i - 1L]
      dpt_j <- dpt + ifelse(!is.na(p_j) & p_j > s_lat, pas_i, 0)
      ok <- ok & (dpt_j <= lmax)

      ok[is.na(ok)] <- FALSE
      garde <- which(ok)
      if (!length(garde)) break

      hd <- ray$hdist[i]
      dz <- alt[cel[garde]] - alt_a[garde]
      d3 <- sqrt(hd^2 + dz^2)

      idx <- cel[garde]
      rr <- act[garde]
      o <- order(d3, decreasing = TRUE)
      idx <- idx[o]
      d3 <- d3[o]
      rr <- rr[o]

      mieux <- d3 < dist[idx]
      dist[idx[mieux]] <- d3[mieux]
      alloc[idx[mieux]] <- rr[mieux]

      # Compactage sur les survivants, en propageant leur accumulateur.
      dpt <- dpt_j[garde]
      act <- act[garde]
      rl_a <- rl_a[garde]
      rc_a <- rc_a[garde]
      alt_a <- alt_a[garde]
    }
  }

  dist[routes] <- 0
  alloc[routes] <- routes
  dist[!is.finite(dist)] <- NA_real_

  faire <- function(v, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }
  list(distance = faire(dist, "distance_conduite"), allocation = faire(alloc, "allocation"))
}

# Pente en pourcentage vers pente en degres : theta = atan(p / 100). Vectorise, `NA`-sur.
.pct_en_deg <- function(pct) {
  atan(pct / 100) * 180 / pi
}
