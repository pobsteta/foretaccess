# Acquisition des couches IGN Geoplateforme via happign (Lot 10).
#
# Les appels reseau reels sont isoles dans de minces wrappers internes
# (.fetch_wms_raster / .fetch_wfs) : les tests unitaires les remplacent par des
# fixtures (local_mocked_bindings), sans reseau ni dependance installee.

# Garde de dependance optionnelle (happign/osmdata sont en Suggests).
.require_pkg <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    cli::cli_abort(c(
      "Le paquet {.pkg {pkg}} est requis pour cette acquisition.",
      "i" = "Installez-le : {.code install.packages(\"{pkg}\")}."
    ))
  }
  invisible(TRUE)
}

# --- Wrappers reseau (points de mock) ---------------------------------------

.fetch_wms_raster <- function(aoi, layer, res, crs, filename) {
  .require_pkg("happign")
  happign::get_wms_raster(
    x = aoi, layer = layer, res = res, crs = crs,
    rgb = FALSE, filename = filename, overwrite = TRUE, verbose = FALSE
  )
}

.fetch_wfs <- function(aoi, typename) {
  .require_pkg("happign")
  happign::get_wfs(x = aoi, layer = typename)
}

# --- Utilitaires communs ----------------------------------------------------

# Chemin de cache d'une couche : cache_dir/layers/<couche>/<couche>.<ext>.
.chemin_cache <- function(cache_dir, couche, ext) {
  d <- file.path(cache_dir, "layers", couche)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  file.path(d, paste0(couche, ".", ext))
}

# Reprojette un sf vers le CRS cible puis le decoupe sur l'AOI (polygone deja
# dans le CRS cible). Les WFS ne filtrent que par bbox : le clip est necessaire.
.reprojeter_clip <- function(x, aoi_cible, crs) {
  x <- sf::st_transform(x, crs)
  x <- sf::st_make_valid(x)
  inter <- suppressWarnings(sf::st_intersection(x, sf::st_geometry(aoi_cible)))
  inter[!sf::st_is_empty(inter), , drop = FALSE]
}

# Mapping de la classe de desserte depuis l'attribut `nature` de BD TOPO
# (troncon_de_route). Route par defaut ; piste pour les natures non carrossables
# en dur. La classe `dfci` reste vide en phase 1 (peu distinguable dans BD TOPO,
# a alimenter via une source dediee) -- spec 010 Q2. Comparaison en ASCII replie
# (les valeurs BD TOPO sont accentuees ; les litteraux R restent ASCII).
.mapper_classe_desserte <- function(x) {
  nat <- if ("nature" %in% names(x)) as.character(x$nature) else rep(NA_character_, nrow(x))
  nat_ascii <- tolower(iconv(nat, to = "ASCII//TRANSLIT"))
  motifs_piste <- c("chemin", "sentier", "empierree", "escalier", "piste cyclable")
  est_piste <- Reduce(`|`, lapply(motifs_piste, function(p) {
    r <- grepl(p, nat_ascii, fixed = TRUE)
    r[is.na(r)] <- FALSE
    r
  }))
  classe <- rep("route", length(nat_ascii))
  classe[est_piste] <- "piste"
  classe
}

# --- Acquisition par source -------------------------------------------------

#' Acquiert le MNT depuis RGE ALTI (IGN WMS)
#'
#' @param aoi Objet `sf`/`sfc` d'emprise, dans le CRS cible.
#' @param res_m Résolution du raster (m). Défaut 5.
#' @param crs Code EPSG de sortie. Défaut 2154.
#' @param cache_dir Répertoire de cache.
#' @param overwrite Re-télécharger même si le cache existe. Défaut `FALSE`.
#' @param country Code pays ISO. Défaut `"FR"`.
#' @return Le chemin du raster `mnt.tif` écrit en cache.
#' @export
acquire_mnt <- function(aoi, res_m = 5, crs = 2154, cache_dir = tempdir(),
                        overwrite = FALSE, country = "FR") {
  chemin <- .chemin_cache(cache_dir, "mnt", "tif")
  if (file.exists(chemin) && !overwrite) {
    return(chemin)
  }
  info <- get_layer_service("dem", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val dem} introuvable pour le pays {.val {country}}.")
  }
  .fetch_wms_raster(aoi, layer = info$layer, res = res_m, crs = crs, filename = chemin)
  chemin
}

#' Acquiert la desserte depuis BD TOPO (IGN WFS)
#'
#' Récupère `troncon_de_route`, reprojette, découpe sur l'AOI et dérive le champ
#' `classe` (`route`/`piste`) attendu par [preprocess()].
#'
#' @inheritParams acquire_mnt
#' @return Un objet `sf` de lignes avec un champ `classe`.
#' @export
acquire_desserte <- function(aoi, crs = 2154, cache_dir = tempdir(),
                             overwrite = FALSE, country = "FR") {
  chemin <- .chemin_cache(cache_dir, "desserte", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  info <- get_layer_service("roads", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val roads} introuvable pour le pays {.val {country}}.")
  }
  brut <- .fetch_wfs(aoi, info$typename)
  d <- .reprojeter_clip(brut, aoi, crs)
  d$classe <- .mapper_classe_desserte(d)
  d <- d[, "classe", drop = FALSE]
  sf::st_write(d, chemin, delete_dsn = TRUE, quiet = TRUE)
  d
}

#' Acquiert la forêt depuis BD Forêt v2 (IGN WFS)
#'
#' @inheritParams acquire_mnt
#' @return Un objet `sf` de polygones de forêt.
#' @export
acquire_foret <- function(aoi, crs = 2154, cache_dir = tempdir(),
                          overwrite = FALSE, country = "FR") {
  chemin <- .chemin_cache(cache_dir, "foret", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  info <- get_layer_service("bdforet_v2", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val bdforet_v2} introuvable pour le pays {.val {country}}.")
  }
  brut <- .fetch_wfs(aoi, info$typename)
  f <- .reprojeter_clip(brut, aoi, crs)
  sf::st_write(f, chemin, delete_dsn = TRUE, quiet = TRUE)
  f
}

#' Acquiert le parcellaire cadastral (IGN WFS, optionnel)
#'
#' @inheritParams acquire_mnt
#' @return Un objet `sf` de polygones de parcelles.
#' @export
acquire_cadastre <- function(aoi, crs = 2154, cache_dir = tempdir(),
                             overwrite = FALSE, country = "FR") {
  chemin <- .chemin_cache(cache_dir, "cadastre", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  info <- get_layer_service("cadastre", country)
  if (is.null(info)) {
    cli::cli_abort("Couche {.val cadastre} introuvable pour le pays {.val {country}}.")
  }
  brut <- .fetch_wfs(aoi, info$typename)
  p <- .reprojeter_clip(brut, aoi, crs)
  sf::st_write(p, chemin, delete_dsn = TRUE, quiet = TRUE)
  p
}
