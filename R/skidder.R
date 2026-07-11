#' Moteur d'accessibilité skidder (débusqueur)
#'
#' Applique les règles Sylvaccess v3.6 au jeu de rasters produit par
#' [preprocess()] : circulation libre sous le seuil de pente, treuillage
#' au-delà, et distances de débardage. Aucune I/O : le moteur consomme l'objet du
#' Lot 1 (ADR-004) et tous ses seuils viennent de `config` (ADR-003).
#'
#' @details
#' Deux mécanismes coexistent, et ils n'ont pas la même nature :
#' * le **traînage** est un plus court chemin sur la surface de coût
#'   ([propager_cout()], [surface_cout_skidder()]) ;
#' * le **treuillage** est un balayage radial en ligne droite ([treuiller()]).
#'
#' L'option de modélisation `1` (défaut v3.6, « limiter l'impact sur le sol »)
#' **privilégie le treuillage** : une cellule treuillable l'est, même si l'engin
#' pourrait y rouler. L'option `2` n'est pas implémentée.
#'
#' @section Écarts assumés avec Sylvaccess v3.6:
#' La hiérarchie route / piste est réduite à deux niveaux (`route` et `dfci`
#' comptent comme routes), et l'option de modélisation 2 n'est pas implémentée.
#' Voir `specs/002-skidder.md`.
#'
#' @param pre Objet `foretaccess_preprocessing` issu de [preprocess()].
#' @param config Objet [foretaccess_config()].
#' @param trajets_depuis Cellules (indices ou points `sf`) pour lesquelles
#'   reconstruire le trajet de traînage vers la desserte. `NULL` (défaut) : aucun.
#' @param write_dir Répertoire d'écriture des rasters en GeoTIFF/COG, ou `NULL`.
#' @param bord Côtés ouverts de la fenêtre, quand `pre` n'est qu'une **tuile** d'un
#'   territoire plus vaste (voir [certifier_propagation()]). `NULL` (défaut) : `pre`
#'   couvre tout le territoire, le résultat est exact partout. Sinon, la sortie porte
#'   une couche `certifie` (spec 007 §4.3).
#'
#' @return Un objet de classe `foretaccess_skidder` :
#'   \describe{
#'     \item{`accessibilite`}{`SpatRaster` catégoriel : `parcourable`,
#'       `accessible`, `non_accessible`, `hors_foret`. `NA` = indéterminé.}
#'     \item{`distance_treuillage`}{distance **3D** de treuillage (m), 0 sinon.}
#'     \item{`distance_trainage_foret`}{distance de traînage en forêt (m).}
#'     \item{`distance_trainage_piste`}{distance sur piste jusqu'à une route (m).}
#'     \item{`distance_debardage`}{somme des trois précédentes.}
#'     \item{`allocation`}{cellule de desserte de rattachement.}
#'     \item{`trajet`}{`sf` de `LINESTRING`, ou `NULL`.}
#'     \item{`certifie`}{`SpatRaster` logique, ou `NULL` si `bord` l'est.}
#'     \item{`recap`}{`data.frame` des surfaces et volumes par classe.}
#'     \item{`grid`, `config`, `fichiers`}{comme au Lot 1.}
#'   }
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' sk <- skidder(pre)
#' sk$recap
skidder <- function(pre,
                    config = foretaccess_config(),
                    trajets_depuis = NULL,
                    write_dir = NULL,
                    bord = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  if (as.integer(config$skidder$option_modelisation) != 1L) {
    cli::cli_abort(c(
      "Seule l'option de modelisation 1 est implementee.",
      "i" = "L'option 2 (privilegier le debusquage) est reportee (spec 002, section 10.8)."
    ))
  }

  desserte_cel <- which(!is.na(terra::values(pre$desserte)))
  if (!length(desserte_cel)) {
    cli::cli_abort("Aucune cellule de desserte : le skidder n'a pas de point de depart.")
  }

  # --- Treuillage : balayage radial, hors cellules de desserte. ---------------
  zone_tr <- zone_treuillable(pre, config)
  zone_tr[desserte_cel] <- 0
  treuil <- treuiller(pre$mnt, pre$desserte, zone_tr, config)

  # --- Trainage en foret : plus court chemin depuis la desserte. --------------
  # La zone roulable inclut le saut de `distance_hors_desserte_max_m` hors foret.
  sources <- .sources_desserte(pre, desserte_cel)
  cout <- surface_cout_skidder(pre, config)
  zone_rl <- zone_roulable_connectee(pre, config)

  if (is.null(bord)) {
    roulage <- propager_cout(cout, sources, zone = zone_rl)
    cert_r <- NULL
  } else {
    # `zone_rl` est *monotone* : calculee sur une fenetre, elle ne peut que
    # sous-estimer la zone globale. Certifier le trainage suffit donc a certifier
    # aussi la zone -- a condition de minorer `d_bord` sur une sur-approximation.
    cert_r <- certifier_propagation(
      cout, sources,
      zone = zone_rl, zone_majorante = .zone_majorante(pre, config), bord = bord
    )
    roulage <- cert_r$propagation
  }

  # --- Trainage sur piste : distance le long des pistes jusqu'a une route. ----
  # Si le pretraitement la porte deja (tuilage), elle est globale, donc exacte : le
  # reseau est unidimensionnel et creux, on le propage une fois pour toute l'emprise
  # plutot que de faire grandir le halo jusqu'a sa plus longue piste (spec 007 §4.3.1).
  piste <- if (is.null(pre$distance_piste)) {
    .distance_sur_piste(pre, cout, bord)
  } else {
    list(distance = as.numeric(terra::values(pre$distance_piste)), certifie = NULL)
  }
  d_piste <- piste$distance

  # --- Combinaison (option 1 : le treuillage prime). --------------------------
  d_tr <- as.numeric(terra::values(treuil$distance))
  a_tr <- as.numeric(terra::values(treuil$allocation))
  d_rl <- as.numeric(terra::values(roulage$cout_cumule))
  a_rl <- as.numeric(terra::values(roulage$allocation))
  # Pour le classement, `parcourable` decrit la praticabilite du terrain forestier,
  # pas la zone de propagation (qui deborde de 50 m hors foret).
  roulable <- as.numeric(terra::values(zone_roulage(pre, config))) == 1
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  pente_na <- is.na(terra::values(pre$slope_pct))

  est_desserte <- rep(FALSE, length(d_tr))
  est_desserte[desserte_cel] <- TRUE

  treuille <- !is.na(d_tr) & !est_desserte
  roule <- !is.na(d_rl) & !est_desserte

  allocation <- ifelse(treuille, a_tr, ifelse(roule, a_rl, NA_real_))
  allocation[est_desserte] <- desserte_cel

  dist_treuil <- ifelse(treuille, d_tr, 0)
  dist_foret <- ifelse(!treuille & roule, d_rl, 0)
  dist_piste <- .piste_allouee(d_piste, allocation)

  # `parcourable` decrit la praticabilite du terrain (pente sous le seuil), pas le
  # mecanisme d'extraction : une cellule treuillee peut etre parcourable.
  accessible <- treuille | roule | est_desserte
  parcourable <- accessible & roulable

  codes <- rep(3, length(d_tr)) # non_accessible
  codes[accessible] <- 2 # accessible (par treuillage)
  codes[parcourable | est_desserte] <- 1 # parcourable par l'engin
  codes[!foret & !est_desserte] <- 4 # hors_foret
  codes[pente_na] <- NA_real_

  # Une cellule non certifiee est `indetermine` (`NA`), jamais rangee dans
  # `non_accessible` : le doute se declare, il ne se range pas (spec 007 §4.4).
  certifie <- .certifier_skidder(cert_r, piste$certifie, treuille, roule, allocation, pre, config, bord)
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

  dist_total <- dist_treuil + dist_foret + dist_piste
  dist_total[is.na(codes)] <- NA_real_

  sk <- structure(
    list(
      accessibilite           = acc,
      distance_treuillage     = faire(dist_treuil, "distance_treuillage"),
      distance_trainage_foret = faire(dist_foret, "distance_trainage_foret"),
      distance_trainage_piste = faire(dist_piste, "distance_trainage_piste"),
      distance_debardage      = faire(dist_total, "distance_debardage"),
      allocation              = faire(allocation, "allocation"),
      trajet                  = NULL,
      certifie                = if (is.null(certifie)) NULL else faire(certifie, "certifie"),
      recap                   = recapituler(acc, pre$volume),
      grid                    = pre$grid,
      config                  = config,
      fichiers                = NULL
    ),
    class = "foretaccess_skidder"
  )

  if (!is.null(trajets_depuis)) {
    sk$trajet <- chemin_optimal(roulage, trajets_depuis)
  }
  if (!is.null(write_dir)) {
    sk$fichiers <- .ecrire_rasters_skidder(sk, write_dir)
  }
  sk
}

# Sur-approximation locale de la zone traversable globale : tout terrain roulable, plus
# la desserte elle-meme, qu'une pente forte pourrait exclure. `d_bord` doit s'y propager
# librement, sans quoi il cesserait de minorer le cout d'entree (spec 007 §4.3).
.zone_majorante <- function(pre, config) {
  z <- terrain_roulable(pre, config)
  z[!is.na(terra::values(pre$desserte))] <- 1
  z
}

# Portee maximale du treuil : au-dela, aucun rayon ne survit. Le halo doit la couvrir,
# sinon une desserte hors fenetre treuillerait dans la tuile sans qu'on le sache.
.portee_treuil <- function(config, res) {
  sk <- config$skidder
  max(sk$debardage_amont_max_m, sk$debardage_aval_max_m) + 1.5 * res
}

# Certificat composite du moteur (spec 007 §4.3). `NULL` hors tuilage.
#
# Le treuillage, l'abattage et la pente sont *locaux* : exacts des lors que le halo
# couvre la portee du treuil. Restent le trainage, dont le certificat porte a la fois
# le cout et la zone, et la distance sur piste, qu'il faut certifier **a la cellule de
# desserte allouee** -- c'est elle qui la porte.
.certifier_skidder <- function(cert_r, cert_piste, treuille, roule, allocation,
                               pre, config, bord) {
  if (is.null(cert_r)) {
    return(NULL)
  }
  res <- terra::res(pre$mnt)[1]
  halo_suffisant <- length(bord) == 0L ||
    .halo_cellules(pre) * res >= .portee_treuil(config, res)
  if (!halo_suffisant) {
    return(rep(FALSE, terra::ncell(pre$mnt)))
  }

  ok <- as.logical(terra::values(cert_r$certifie))
  # L'allocation du trainage n'importe que pour les cellules qu'il dessert vraiment.
  alloc_r <- roule & !treuille
  ok[alloc_r] <- ok[alloc_r] & as.logical(terra::values(cert_r$certifie_allocation))[alloc_r]

  if (!is.null(cert_piste)) {
    cp <- as.logical(terra::values(cert_piste))
    a <- !is.na(allocation)
    ok[a] <- ok[a] & cp[allocation[a]]
  }
  ok
}

# Largeur du halo effectivement disponible autour de la fenetre, en cellules. Sans
# information de tuilage, la fenetre est le territoire : la portee est toujours couverte.
.halo_cellules <- function(pre) {
  if (is.null(pre$halo_cel)) Inf else pre$halo_cel
}

# Raster de sources : chaque cellule de desserte porte son propre indice.
.sources_desserte <- function(pre, desserte_cel) {
  s <- terra::rast(pre$mnt)
  v <- rep(NA_real_, terra::ncell(s))
  v[desserte_cel] <- desserte_cel
  terra::values(s) <- v
  s
}

# Distance, le long des pistes, jusqu'a la route la plus proche. Les cellules de
# route valent 0 ; les cellules hors reseau valent 0 (elles ne trainent pas sur piste).
#
# Le cout est la surface ponderee par la pente (`Pond_pente`), comme dans
# `Dfwd_flat_forest_tracks()` : une piste en devers coute plus qu'une piste plate.
#
# Le reseau est une donnee locale : sa restriction a la fenetre est exacte, et sert donc
# aussi de zone majorante. Seule la *distance* le long du reseau deborde de la fenetre.
.distance_sur_piste <- function(pre, cout, bord = NULL) {
  n <- terra::ncell(pre$mnt)

  # Sans table de categories, la desserte ne distingue pas piste et route : il n'y a
  # donc pas de trainage sur piste (cas des dessertes-points de test, ou d'un reseau
  # non categorise). On rend une distance nulle plutot que de planter.
  cl <- terra::levels(pre$desserte)[[1]]
  if (!is.data.frame(cl) || ncol(cl) < 2L) {
    return(list(distance = rep(0, n), certifie = NULL))
  }
  code_piste <- cl[[1]][as.character(cl[[2]]) == "piste"]
  codes <- as.numeric(terra::values(pre$desserte))

  est_piste <- !is.na(codes) & codes %in% code_piste
  est_route <- !is.na(codes) & !est_piste

  if (!any(est_route) || !any(est_piste)) {
    return(list(distance = rep(0, n), certifie = NULL))
  }

  zone <- terra::rast(pre$mnt)
  terra::values(zone) <- as.numeric(est_piste | est_route)

  src <- terra::rast(pre$mnt)
  v <- rep(NA_real_, n)
  v[est_route] <- 1
  terra::values(src) <- v

  if (is.null(bord)) {
    prop <- propager_cout(cout, src, zone = zone)
    certifie <- NULL
  } else {
    cert <- certifier_propagation(cout, src, zone = zone, bord = bord)
    prop <- cert$propagation
    certifie <- cert$certifie
  }

  d <- as.numeric(terra::values(prop$cout_cumule))
  d[is.na(d)] <- 0
  list(distance = d, certifie = certifie)
}

# Reporte la distance sur piste de la cellule de desserte allouee a chaque pixel.
.piste_allouee <- function(d_piste, allocation) {
  out <- rep(0, length(allocation))
  ok <- !is.na(allocation)
  out[ok] <- d_piste[allocation[ok]]
  out
}

# Couches raster ecrites par write_dir.
.couches_skidder <- function() {
  c(
    "accessibilite", "distance_treuillage", "distance_trainage_foret",
    "distance_trainage_piste", "distance_debardage", "allocation"
  )
}

.ecrire_rasters_skidder <- function(sk, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)

  chemins <- vapply(.couches_skidder(), function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    terra::writeRaster(sk[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))
  as.list(chemins)
}

#' @export
print.foretaccess_skidder <- function(x, ...) {
  r <- x$recap
  cli::cli_inform(c(
    "Moteur skidder ForetAccess",
    "*" = "grille : {x$grid$nrow} x {x$grid$ncol} cellules",
    "*" = "surfaces (ha) : {paste0(r$classe, ' = ', signif(r$surface_ha, 4), collapse = ' ; ')}",
    "*" = "distance de debardage max : \\
           {signif(max(terra::values(x$distance_debardage), na.rm = TRUE), 5)} m"
  ))
  invisible(x)
}
