#' Distance maximale de treuillage admissible
#'
#' La « loi de bascule » de Sylvaccess v3.6. Contrairement à ce que suggère la
#' documentation, ce **n'est pas** une fonction affine de la pente : c'est une
#' fonction affine du **dénivelé**, calibrée sur deux points d'ancrage. Exprimée
#' en fonction de la pente signée `s` du rayon desserte → pixel, elle devient :
#'
#' \deqn{D_{max}(s) = \frac{orig}{1 - coeff \cdot s / \sqrt{1 + s^2}}}
#'
#' bornée par `debardage_aval_max_m` en aval et `debardage_amont_max_m` en amont.
#'
#' @details
#' Avec les défauts v3.6 (50 m amont, 100 m aval, bascules 75 % et 20 %) :
#' `coeff = -1,007829` et `orig = 80,2349 m`. **À plat, la distance admissible
#' vaut donc 80,23 m** — ni 50, ni 100. Une interpolation linéaire en pente,
#' l'hypothèse naturelle, donnerait 50 m à 30 % au lieu de 62 m.
#'
#' Source : `Sylvaccess_1_skidder.py:336-370` et `sylvaccess_cython3.pyx:3164`.
#'
#' @param pente Pente **signée** du rayon (rapport, non pourcentage) : positive
#'   en amont (le pixel est plus haut que la desserte), négative en aval.
#' @param config Objet [foretaccess_config()].
#'
#' @return Un vecteur de distances maximales admissibles, en mètres.
#' @export
#' @examples
#' distance_treuillage_max(c(-0.5, 0, 0.3, 1))
distance_treuillage_max <- function(pente, config = foretaccess_config()) {
  checkmate::assert_numeric(pente)
  .dmax(pente, coefficients_bascule(config))
}

# Loi de bascule, coefficients deja calcules. Appelee dans la boucle de rayons :
# elle ne revalide pas la configuration.
.dmax <- function(pente, cf) {
  # Forme fermee : Dmax est affine en denivele, or denivele = dist * sin(theta).
  interp <- cf$orig / (1 - cf$coeff * pente / sqrt(1 + pente^2))

  d <- ifelse(pente <= cf$p_down, cf$daval,
    ifelse(pente > cf$p_up, cf$damont, interp)
  )
  as.numeric(d)
}

#' Coefficients de la loi de bascule
#'
#' Calcule `coeff` et `orig` à partir des quatre paramètres skidder, en
#' reproduisant les cas particuliers de Sylvaccess (`Sylvaccess_1_skidder.py`).
#'
#' @inheritParams distance_treuillage_max
#' @return Une liste : `coeff`, `orig`, `p_up`, `p_down`, `damont`, `daval`,
#'   `dmin` (en deçà de laquelle aucun plafond n'est appliqué).
#' @export
coefficients_bascule <- function(config = foretaccess_config()) {
  validate_config(config)
  sk <- config$skidder

  damont <- sk$debardage_amont_max_m
  daval <- sk$debardage_aval_max_m
  p_up <- abs(sk$pente_bascule_amont_pct) / 100
  p_down <- -abs(sk$pente_bascule_aval_pct) / 100

  if (damont == daval) {
    coeff <- 0
    orig <- damont
  } else if (damont == 0 && daval > 0) {
    coeff <- 0
    orig <- daval
    p_up <- 1e-6
    p_down <- 0
  } else if (daval == 0 && damont > 0) {
    coeff <- 0
    orig <- damont
    p_up <- 0
    p_down <- -1e-6
  } else {
    # Denivele d'un segment de longueur `d` a la pente `p` : d * p / sqrt(1 + p^2).
    deniv_up <- if (p_up > 0) sqrt(damont^2 / (1 + 1 / p_up^2)) else 0
    deniv_down <- if (p_down < 0) -sqrt(daval^2 / (1 + 1 / p_down^2)) else 0

    if (deniv_up - deniv_down != 0) {
      coeff <- (damont - daval) / (deniv_up - deniv_down)
      orig <- damont - coeff * deniv_up
    } else {
      coeff <- 0
      orig <- 0.5 * (damont + daval)
    }
  }

  list(
    coeff = coeff, orig = orig, p_up = p_up, p_down = p_down,
    damont = damont, daval = daval, dmin = min(damont, daval)
  )
}

#' Distance de treuillage depuis la desserte (balayage radial)
#'
#' Reproduit `skid_debusq_RF()` de Sylvaccess (`sylvaccess_cython3.pyx:3116`).
#' Le treuillage n'est **pas** un plus court chemin : depuis chaque cellule de
#' desserte, on balaie 360 azimuts au pas de 1°, en **ligne droite**.
#'
#' @details
#' Le long de chaque rayon, un pixel est treuillable si :
#' * la **distance 3D** `sqrt(Hdist^2 + dz^2)` ne dépasse pas
#'   [distance_treuillage_max()] pour la pente signée du rayon (test appliqué
#'   seulement au-delà de `min(amont, aval)`) ;
#' * la **corde du câble**, tendue depuis la desserte à
#'   `hauteur_attache_treuil_m`, reste au-dessus du sol et sous
#'   `hauteur_degagement_max_m` **en tout point intermédiaire** ;
#' * le pixel est dans la zone treuillable.
#'
#' Dès qu'une de ces conditions échoue, le rayon est **interrompu** : rien n'est
#' atteignable au-delà par cet azimut. Chaque pixel retient la plus petite
#' distance, tous azimuts et toutes cellules de desserte confondus.
#'
#' Écart assumé avec la source : dans le `.pyx`, le test de dégagement n'est
#' évalué que si le pixel serait amélioré, ce qui rend l'interruption du rayon
#' dépendante de l'ordre de parcours des cellules de desserte. Ici il est
#' toujours évalué — c'est la sémantique visée, et elle est déterministe.
#'
#' @param mnt `SpatRaster` du MNT.
#' @param desserte `SpatRaster` des cellules de desserte (non `NA` = desserte).
#' @param zone `SpatRaster` logique des cellules treuillables.
#' @param config Objet [foretaccess_config()].
#'
#' @return Une liste de deux `SpatRaster` : `distance` (m, distance 3D ; `NA` si
#'   non treuillable) et `allocation` (indice de la cellule de desserte).
#' @export
treuiller <- function(mnt, desserte, zone, config = foretaccess_config()) {
  mnt <- .as_raster(mnt, "mnt")
  cf <- coefficients_bascule(config)
  sk <- config$skidder

  res <- terra::res(mnt)[1]
  nr <- terra::nrow(mnt)
  nc <- terra::ncol(mnt)

  alt <- as.numeric(terra::values(mnt))
  zv <- as.numeric(terra::values(zone))
  treuillable <- !is.na(zv) & zv != 0

  routes <- which(!is.na(terra::values(desserte)))
  dist <- rep(Inf, nr * nc)
  alloc <- rep(NA_real_, nr * nc)
  if (!length(routes)) {
    cli::cli_abort("{.arg desserte} ne contient aucune cellule.")
  }

  rl <- ((routes - 1L) %/% nc) + 1L
  rc <- ((routes - 1L) %% nc) + 1L
  alt_r <- alt[routes]

  rayons <- .rayons(res, max(cf$damont, cf$daval))
  h <- sk$hauteur_attache_treuil_m
  degagement <- sk$hauteur_degagement_max_m

  for (az in seq_along(rayons)) {
    ray <- rayons[[az]]
    vivant <- rep(TRUE, length(routes))
    # Bornes cumulees de la pente admissible, imposees par les pixels deja
    # traverses : la corde doit rester dans [sol, sol + degagement].
    lo <- rep(-Inf, length(routes))
    hi <- rep(Inf, length(routes))

    for (i in seq_len(nrow(ray))) {
      lv <- rl + ray$dl[i]
      cv <- rc + ray$dc[i]
      vivant <- vivant & lv >= 1L & lv <= nr & cv >= 1L & cv <= nc

      cel <- rep(NA_integer_, length(routes))
      cel[vivant] <- (lv[vivant] - 1L) * nc + cv[vivant]
      vivant[vivant] <- treuillable[cel[vivant]]
      if (!any(vivant)) break

      hd <- ray$hdist[i]
      dz <- alt[cel] - alt_r
      s <- dz / hd
      d3 <- sqrt(hd^2 + dz^2)

      # Degagement : verifie sur les pixels strictement anterieurs (bornes cumulees).
      vivant <- vivant & !is.na(s) & s >= lo & s <= hi
      # Plafond de distance : applique seulement au-dela de min(amont, aval).
      vivant <- vivant & (d3 <= cf$dmin | d3 <= .dmax(s, cf))
      vivant[is.na(vivant)] <- FALSE
      if (!any(vivant)) break

      # Ecriture du minimum : on ordonne par distance decroissante pour que la
      # plus petite valeur soit ecrite en dernier sur les cellules dupliquees.
      idx <- cel[vivant]
      dd <- d3[vivant]
      rr <- routes[vivant]
      o <- order(dd, decreasing = TRUE)
      idx <- idx[o]
      dd <- dd[o]
      rr <- rr[o]

      mieux <- dd < dist[idx]
      dist[idx[mieux]] <- dd[mieux]
      alloc[idx[mieux]] <- rr[mieux]

      # Mise a jour des bornes pour les pixels suivants du rayon.
      lo <- pmax(lo, (dz - h) / hd)
      hi <- pmin(hi, (dz - h + degagement) / hd)
    }
  }

  dist[routes] <- 0
  alloc[routes] <- routes
  dist[!is.finite(dist)] <- NA_real_

  faire <- function(v, nom) {
    r <- terra::rast(mnt)
    terra::values(r) <- v
    names(r) <- nom
    r
  }
  list(distance = faire(dist, "distance_treuillage"), allocation = faire(alloc, "allocation"))
}

# Rayons pre-calcules : pour chaque azimut, la suite ordonnee des cellules
# traversees (decalages ligne/colonne) et leur distance horizontale au centre.
# Reproduit `create_buffer_skidder()` de Sylvaccess.
.rayons <- function(res, portee_m) {
  lmax <- portee_m + 1.5 * res
  pas <- res / 3
  ts <- seq(pas, lmax, by = pas)

  lapply(0:359, function(az) {
    rad <- az * pi / 180
    # Azimut depuis le nord, sens horaire.
    dx <- sin(rad)
    dy <- cos(rad)
    dc <- round(ts * dx / res)
    dl <- round(-ts * dy / res)

    garde <- !(dc == 0 & dl == 0)
    dc <- dc[garde]
    dl <- dl[garde]

    doublon <- c(FALSE, dc[-1] == dc[-length(dc)] & dl[-1] == dl[-length(dl)])
    dc <- dc[!doublon]
    dl <- dl[!doublon]

    hdist <- res * sqrt(dl^2 + dc^2)
    garde <- hdist <= lmax
    data.frame(dl = as.integer(dl[garde]), dc = as.integer(dc[garde]), hdist = hdist[garde])
  })
}
