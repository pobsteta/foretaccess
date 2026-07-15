#' Moteur camion DFCI — zone de défendabilité (balayage radial)
#'
#' Cartographie la **zone défendable** contre l'incendie depuis le réseau DFCI
#' (défense de la forêt contre les incendies). Transcription du moteur
#' `debusq_dfci` de Sylvaccess v3.6 : depuis chaque pixel du réseau DFCI, une
#' **lance** est déroulée en ligne droite dans les 360 azimuts (pas de 1°). La
#' lance **épouse le relief** (longueur 3D cumulée cellule à cellule), elle est
#' plafonnée à `config$dfci$distance_defense_max_m` (`dfci_lmax`) et **arrêtée**
#' par une pente supérieure à `config$dfci$pente_defense_max_pct` (`dfci_slope_max`),
#' par un obstacle, ou par le bord.
#'
#' @details
#' Ce n'est **pas** un plus court chemin pondéré (le chemin `calc_dist_dfci` de
#' Sylvaccess est désactivé) mais un **lancer de rayons radial** : la charge est
#' défendue en ligne droite depuis la desserte, tant que le terrain se laisse
#' franchir. La longueur de lance minimale atteignant chaque cellule de forêt donne
#' sa **classe de défendabilité** (bandes `config$dfci$classes_distance_m`).
#'
#' Les sources sont les cellules portant le flag **`CL_DFCI`** (attribut orthogonal
#' aux classes route/piste/réseau public : une desserte peut être route classique
#' *et* réseau de défense). Elles sont portées par [preprocess()] dans
#' `pre$dfci_source_mask`.
#'
#' @section Écart assumé avec Sylvaccess:
#' Le **bug de masquage** du dénivelé (`sylvaccess_cython3.pyx:4807`, qui écrit aux
#' coordonnées de la dernière source au lieu de la cellule courante) est **corrigé** :
#' `denivele` est bien remis à `NA` sur toute cellule non défendable. L'accord à
#' l'oracle sur `Denivele_sur_piste` s'en trouve très légèrement dégradé, au profit
#' de la justesse.
#'
#' @param pre Objet `foretaccess_preprocessing` issu de [preprocess()].
#' @param config Objet [foretaccess_config()].
#' @param write_dir Répertoire d'écriture des rasters en GeoTIFF/COG, ou `NULL`.
#' @param bord Côtés ouverts de la fenêtre quand `pre` est une **tuile**. `NULL`
#'   (défaut) : `pre` couvre tout le territoire.
#'
#' @return Un objet de classe `foretaccess_dfci` :
#'   \describe{
#'     \item{`accessibilite`}{`SpatRaster` catégoriel à 6 classes : `inaccessible`,
#'       `non_defendable_pente`, `defendable_c1`/`c2`/`c3` (bandes de lance),
#'       `hors_foret`.}
#'     \item{`longueur_lance`}{longueur de lance (m) atteignant la cellule ; `NA`
#'       hors portée / hors forêt.}
#'     \item{`denivele`}{dénivelé cellule − desserte-source (m) ; `NA` idem.}
#'     \item{`lien_reseau`}{cellule de desserte DFCI de rattachement (index 1-based).}
#'     \item{`pente_ok`}{`SpatRaster` logique : pente ≤ seuil pompier.}
#'     \item{`certifie`}{`SpatRaster` logique (tuilage), ou `NULL`.}
#'     \item{`recap`}{`data.frame` des surfaces et volumes par classe.}
#'     \item{`grid`, `config`, `fichiers`}{comme au Lot 1.}
#'   }
#' @seealso [skidder()], [porteur()], [potentiel_cable()]
#' @export
#' @examples
#' toy <- system.file("extdata/toy", package = "foretaccess")
#' pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
#'                   file.path(toy, "foret.gpkg"))
#' df <- camion_dfci(pre)
#' df$recap
camion_dfci <- function(pre, config = foretaccess_config(), write_dir = NULL, bord = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  validate_config(config)

  n <- terra::ncell(pre$mnt)
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)
  res <- terra::res(pre$mnt)[1]

  source_cel <- .sources_dfci(pre, config)
  if (!length(source_cel)) {
    if (is.null(bord)) {
      cli::cli_abort(c(
        "Aucune desserte-source DFCI : le camion n'a pas de point de depart.",
        "i" = "Attendu : des troncons portant le flag {.field CL_DFCI} \\
               (voir {.fun preprocess}, couche {.field dfci_source_mask})."
      ))
    }
    return(.dfci_indetermine(pre, config))
  }

  alt <- as.numeric(terra::values(pre$mnt))
  slope <- as.numeric(terra::values(pre$slope_pct))
  foret <- as.numeric(terra::values(pre$foret_mask)) == 1
  foret[is.na(foret)] <- FALSE

  # Pente franchissable par les pompiers (`Pente_ok_fire`) : seuil simple par
  # cellule (Sylvaccess jette la version max-local 3x3, cf. swap de `slopes_skid`).
  pente_ok <- !is.na(slope) & slope <= config$dfci$pente_defense_max_pct

  # Zone traversable par la lance (`Zone_ok`) : pente OK, hors trou de MNT. Les
  # obstacles DFCI viennent d'une couche dediee (`dfci_fold_obs`), vide par defaut
  # chez Sylvaccess -- on ne bloque donc pas sur les obstacles des engins.
  zone_ok <- pente_ok & !is.na(alt)

  lmax <- config$dfci$distance_defense_max_m
  sc <- dfci_scan(
    alt = alt, nr = nr, nc = nc, res = res,
    foret = as.integer(foret),
    sources = as.integer(source_cel),
    zone_ok = as.integer(zone_ok),
    lmax = lmax
  )

  dist <- sc$dist
  deniv <- sc$deniv
  lien <- sc$lien
  acc <- sc$acc == 1L

  # --- Certificat de tuilage. -------------------------------------------------
  # Portee bornee par `lmax` : une cellule a plus de `lmax` de tout bord ouvert ne
  # peut etre atteinte par aucune source exterieure a la fenetre -- son resultat est
  # donc global. Les cellules a moins de `lmax` d'un bord ouvert restent indeterminees.
  certifie <- NULL
  if (!is.null(bord)) {
    certifie <- .certifier_dfci(pre, bord, lmax)
  }

  # --- Classement en zone de defendabilite (5 classes + hors foret). ----------
  bornes <- config$dfci$classes_distance_m
  codes <- rep(6L, n) # hors_foret par defaut
  en_foret <- foret
  codes[en_foret] <- 1L # foret inaccessible
  # Bandes de defendabilite (derniere borne inclusive, comme Sylvaccess).
  bande <- .bande_defendabilite(dist, bornes)
  # Bande 0-based -> code : bande 0 (0-120 m) = defendable_c1 (code 3), etc.
  defendable <- en_foret & acc & !is.na(bande)
  codes[defendable] <- 3L + bande[defendable]
  # La pente trop elevee ecrase tout (overwrite final chez Sylvaccess).
  codes[en_foret & !pente_ok] <- 2L # non_defendable (pente)

  if (!is.null(certifie)) codes[!certifie] <- NA_integer_
  distance <- dist
  distance[is.na(codes) | codes %in% c(1L, 2L, 6L)] <- NA_real_
  deniv[is.na(codes) | codes %in% c(1L, 2L, 6L)] <- NA_real_
  lien[is.na(codes)] <- 0L

  faire <- function(vv, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- vv
    names(r) <- nom
    r
  }

  acc_r <- faire(codes, "accessibilite")
  levels(acc_r) <- .niveaux_dfci()

  df <- structure(
    list(
      accessibilite  = acc_r,
      longueur_lance = faire(distance, "longueur_lance"),
      denivele       = faire(deniv, "denivele"),
      lien_reseau    = faire(ifelse(lien == 0L, NA_real_, lien), "lien_reseau"),
      pente_ok       = faire(as.numeric(pente_ok), "pente_ok"),
      certifie       = if (is.null(certifie)) NULL else faire(certifie, "certifie"),
      recap          = recapituler(acc_r, pre$volume),
      grid           = pre$grid,
      config         = config,
      fichiers       = NULL
    ),
    class = "foretaccess_dfci"
  )

  if (!is.null(write_dir)) df$fichiers <- .ecrire_rasters_dfci(df, write_dir)
  df
}

# Niveaux du raster de defendabilite. Ordre : inaccessible, non defendable (pente),
# trois bandes de lance croissantes, hors foret.
.niveaux_dfci <- function() {
  data.frame(
    value  = 1:6,
    classe = c("inaccessible", "non_defendable_pente",
               "defendable_c1", "defendable_c2", "defendable_c3", "hors_foret")
  )
}

# Bande de defendabilite (0-based : 0, 1, 2) d'une longueur de lance selon les
# bornes `classes_distance_m` (ex. 0;120;280;440). Derniere borne INCLUSIVE ; hors
# bornes -> NA. `dist` en metres, `NA` hors portee.
.bande_defendabilite <- function(dist, bornes) {
  k <- length(bornes) - 1L # nombre de bandes finies
  bande <- rep(NA_integer_, length(dist))
  vu <- !is.na(dist)
  for (b in seq_len(k)) {
    lo <- bornes[b]
    hi <- bornes[b + 1L]
    dedans <- vu & dist >= lo & (if (b == k) dist <= hi else dist < hi)
    bande[dedans] <- b - 1L
  }
  bande
}

# Cellules-source du camion : celles portant le flag CL_DFCI (dfci_source_mask),
# en ordre row-major (croissant) -- l'ordre de balayage de Sylvaccess, qui fixe le
# depart des egalites de longueur de lance.
.sources_dfci <- function(pre, config) {
  m <- pre$dfci_source_mask
  if (is.null(m)) {
    return(integer(0))
  }
  vals <- as.numeric(terra::values(m))
  which(!is.na(vals) & vals == 1)
}

# Certificat de tuilage : cellules a plus de `lmax` de tout bord OUVERT de la
# fenetre. Aucune source exterieure ne peut y derouler une lance <= lmax, leur
# resultat est donc identique au mono-bloc. `bord` : cotes ouverts, sous-ensemble
# de c("haut", "bas", "gauche", "droite").
.certifier_dfci <- function(pre, bord, lmax) {
  nr <- terra::nrow(pre$mnt)
  nc <- terra::ncol(pre$mnt)
  res <- terra::res(pre$mnt)[1]
  marge <- ceiling(lmax / res)
  lignes <- matrix(rep(seq_len(nr), nc), nrow = nr)
  colonnes <- matrix(rep(seq_len(nc), each = nr), nrow = nr)
  loin <- matrix(TRUE, nr, nc)
  if ("haut" %in% bord) loin <- loin & (lignes > marge)
  if ("bas" %in% bord) loin <- loin & (lignes <= nr - marge)
  if ("gauche" %in% bord) loin <- loin & (colonnes > marge)
  if ("droite" %in% bord) loin <- loin & (colonnes <= nc - marge)
  as.logical(t(loin)) # row-major
}

# Tuile sans source DFCI : rien de calcule, rien de certifie (le halo grandit).
.dfci_indetermine <- function(pre, config) {
  n <- terra::ncell(pre$mnt)
  faire <- function(vv, nom) {
    r <- terra::rast(pre$mnt)
    terra::values(r) <- vv
    names(r) <- nom
    r
  }
  acc <- faire(rep(NA_real_, n), "accessibilite")
  levels(acc) <- .niveaux_dfci()
  structure(
    list(
      accessibilite  = acc,
      longueur_lance = faire(rep(NA_real_, n), "longueur_lance"),
      denivele       = faire(rep(NA_real_, n), "denivele"),
      lien_reseau    = faire(rep(NA_real_, n), "lien_reseau"),
      pente_ok       = faire(rep(NA_real_, n), "pente_ok"),
      certifie       = faire(rep(FALSE, n), "certifie"),
      recap          = recapituler(acc, pre$volume),
      grid           = pre$grid,
      config         = config,
      fichiers       = NULL
    ),
    class = "foretaccess_dfci"
  )
}

# Couches raster ecrites par write_dir.
.couches_dfci <- function() {
  c("accessibilite", "longueur_lance", "denivele", "lien_reseau", "pente_ok")
}

.ecrire_rasters_dfci <- function(df, write_dir) {
  checkmate::assert_string(write_dir)
  dir.create(write_dir, recursive = TRUE, showWarnings = FALSE)
  chemins <- vapply(.couches_dfci(), function(nm) {
    f <- file.path(write_dir, paste0(nm, ".tif"))
    terra::writeRaster(df[[nm]], f, filetype = "COG", overwrite = TRUE)
    f
  }, character(1))
  as.list(chemins)
}

#' @export
print.foretaccess_dfci <- function(x, ...) {
  r <- x$recap
  lmax <- signif(suppressWarnings(max(terra::values(x$longueur_lance), na.rm = TRUE)), 5)
  if (!is.finite(lmax)) lmax <- NA
  cli::cli_inform(c(
    "Moteur camion DFCI ForetAccess (balayage radial)",
    "*" = "grille : {x$grid$nrow} x {x$grid$ncol} cellules",
    "*" = "surfaces (ha) : {paste0(r$classe, ' = ', signif(r$surface_ha, 4), collapse = ' ; ')}",
    "*" = "longueur de lance max atteinte : {lmax} m"
  ))
  invisible(x)
}
