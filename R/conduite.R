#' Balayage radial de conduite du porteur
#'
#' Reproduit `fwd_azimuts_forest_roadnet` de Sylvaccess v3.6 : depuis chaque cellule du
#' réseau de desserte, un balayage **360° au pas de 1°**, en ligne droite, jusqu'à
#' `distance_pente_forte_max_m`. Une cellule est conduisible si l'engin peut l'atteindre
#' sous trois contraintes de pente, distinctes de celles du skidder (spec 003 §4.2).
#'
#' @details
#' Contrairement au treuillage — dont ce balayage partage la géométrie interne —
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
#' @param sources Indices des cellules de départ. `NULL` (défaut) : les cellules de
#'   livraison de la desserte. La passe contour (`fwd_azimuts_contour`) y passe les
#'   cellules du bord de la zone déjà conduite.
#' @param depart_cout Vecteur de longueur `ncell(pre$mnt)` : distance **déjà parcourue**
#'   pour atteindre chaque source. `NULL` (défaut) : nulle. Sinon le critère
#'   d'amélioration porte sur le **total** `depart_cout + distance parcourue`.
#'
#' @return Une liste de deux `SpatRaster` : `distance` (3D, m) et `allocation`.
#' @seealso [treuiller()]
#' @export
conduire <- function(pre, config, zone, sources = NULL, depart_cout = NULL) {
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

  # Cellules de LIVRAISON seulement : le porteur ne depose pas son bois sur une
  # route ouverte a la circulation, qui est pour lui une barriere
  # (`Obstacles_forwarder[Res_pub==1]=1` chez Sylvaccess). Cf. .classes_desserte().
  routes <- if (is.null(sources)) .cellules_livraison(pre) else sources
  if (!length(routes)) {
    cli::cli_abort("{.arg pre$desserte} ne contient aucune cellule.")
  }
  if (is.null(depart_cout)) {
    cout_r <- rep(0, length(routes))
  } else {
    checkmate::assert_numeric(depart_cout, len = nr * nc, any.missing = FALSE)
    cout_r <- depart_cout[routes]
  }

  # Seuils en degres.
  s_up <- .pct_en_deg(po$pente_montee_max_pct)
  s_down <- .pct_en_deg(po$pente_descente_max_pct)
  s_lat <- .pct_en_deg(po$pente_travers_max_pct)
  lmax <- po$distance_pente_forte_max_m

  dist <- rep(Inf, nr * nc)
  alloc <- rep(NA_real_, nr * nc)
  # Total minimal connu. Sans cout de depart il vaut `dist` : les deux criteres
  # coincident, et le comportement est celui de `fwd_azimuts_forest_roadnet()`.
  total <- rep(Inf, nr * nc)

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
    # Distance deja parcourue en pente forte, par rayon, et distance 3D du pas
    # precedent : l'accumulateur croit de l'increment de distance **3D**
    # (`dpt += dist - dist2` dans `fwd_azimuts_forest_roadnet`), pas de l'increment
    # horizontal. Sur un versant raide les deux different d'autant plus que la pente
    # est forte -- et c'est justement la que l'accumulateur decide.
    dpt <- rep(0, length(routes))
    d_prec <- rep(0, length(routes))
    cout_a <- cout_r

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

      hd <- ray$hdist[i]
      dz <- alt[cel] - alt_a
      d3 <- sqrt(hd^2 + dz^2)

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

      # 3. Accumulateur de pente forte : croit de l'increment de distance 3D la ou
      #    p_j > s_lat, plafonne a lmax.
      pas_i <- d3 - d_prec
      dpt_j <- dpt + ifelse(!is.na(p_j) & p_j > s_lat, pas_i, 0)
      ok <- ok & (dpt_j <= lmax)

      ok[is.na(ok)] <- FALSE
      garde <- which(ok)
      if (!length(garde)) break

      idx <- cel[garde]
      dd <- d3[garde]
      rr <- act[garde]
      tt <- cout_a[garde] + dd
      o <- order(tt, decreasing = TRUE)
      idx <- idx[o]
      dd <- dd[o]
      rr <- rr[o]
      tt <- tt[o]

      mieux <- tt < total[idx]
      total[idx[mieux]] <- tt[mieux]
      dist[idx[mieux]] <- dd[mieux]
      alloc[idx[mieux]] <- rr[mieux]

      # Compactage sur les survivants, en propageant leurs accumulateurs.
      dpt <- dpt_j[garde]
      d_prec <- d3[garde]
      act <- act[garde]
      rl_a <- rl_a[garde]
      rc_a <- rc_a[garde]
      alt_a <- alt_a[garde]
      cout_a <- cout_a[garde]
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
