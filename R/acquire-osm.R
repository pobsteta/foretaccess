# Acquisition des obstacles depuis OpenStreetMap via osmdata (Lot 10).
#
# L'appel reseau reel est isole dans .fetch_osm (point de mock). Les obstacles
# par defaut (spec 010 Q3) : bati, surfaces d'eau, voies ferrees, falaises.

# Requetes OSM par type d'obstacle : (cle, valeur) OpenStreetMap. `NULL` en
# valeur = toute valeur de la cle.
.OBSTACLES_OSM <- list(
  building = list(list(key = "building", value = NULL)),
  water    = list(list(key = "natural", value = "water"),
                  list(key = "waterway", value = NULL)),
  railway  = list(list(key = "railway", value = NULL)),
  cliff    = list(list(key = "natural", value = "cliff"))
)

# Wrapper reseau (point de mock) : renvoie l'objet osmdata_sf pour une (cle,
# valeur) sur une bbox WGS84.
# Instances Overpass, essayees dans l'ordre. L'instance principale limite
# agressivement le debit : une session un peu active se fait refuser jusqu'au
# `status` (HTTP 504 puis echec de overpass_status), et osmdata boucle alors en
# backoff 60 s sans jamais aboutir. Les miroirs n'ont pas les memes quotas.
# Mesure du 2026-07-30 : apres une journee de requetes, l'instance par defaut
# refusait toute requete tandis qu'un miroir repondait immediatement.
.SERVEURS_OVERPASS <- c(
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
  "https://overpass.osm.ch/api/interpreter",
  "https://overpass.private.coffee/api/interpreter"
)

.fetch_osm <- function(bbox_wgs, key, value = NULL, timeout = 120,
                       serveurs = .SERVEURS_OVERPASS) {
  .require_pkg("osmdata")
  urls <- unique(c(osmdata::get_overpass_url(), serveurs))
  initial <- osmdata::get_overpass_url()
  # PIEGE : `set_overpass_url()` appelle `overpass_status()`, donc il TAPE le
  # reseau. Quand l'instance est saturee, c'est le CHANGEMENT d'instance qui
  # echoue, pas la requete -- et une rotation naive meurt avant d'avoir essaye
  # le moindre miroir. On l'enveloppe donc, restauration finale comprise.
  basculer <- function(u) {
    isTRUE(tryCatch({
      osmdata::set_overpass_url(u)
      TRUE
    }, error = function(e) FALSE, warning = function(w) TRUE))
  }
  on.exit(basculer(initial), add = TRUE)
  derniere <- NULL
  for (u in urls) {
    if (!basculer(u)) {
      next
    }
    q <- osmdata::opq(bbox = bbox_wgs, timeout = timeout)
    q <- osmdata::add_osm_feature(q, key = key, value = value)
    res <- tryCatch(osmdata::osmdata_sf(q), error = function(e) e)
    if (!inherits(res, "error")) {
      if (!identical(u, initial)) {
        cli::cli_inform("OSM : instance {.val {initial}} indisponible, repli sur
                         {.val {u}}.")
      }
      return(res)
    }
    derniere <- res
  }
  # Toutes les instances ont echoue : on relaie l'erreur plutot que de rendre un
  # resultat vide, qu'un appelant confondrait avec « rien a cet endroit ».
  stop(derniere) # nocov
}

# Geometries pertinentes d'un objet osmdata_sf : polygones, multipolygones et
# lignes, en une seule sfc (types mixtes admis).
.geoms_osm <- function(od) {
  parts <- list(od$osm_polygons, od$osm_multipolygons, od$osm_lines)
  geoms <- list()
  for (p in parts) {
    if (!is.null(p) && nrow(p) > 0) {
      geoms[[length(geoms) + 1L]] <- sf::st_geometry(p)
    }
  }
  if (!length(geoms)) {
    return(NULL)
  }
  do.call(c, geoms)
}

#' Acquiert les obstacles depuis OpenStreetMap
#'
#' Télécharge les obstacles au sein de l'emprise : bâti, surfaces d'eau, voies
#' ferrées, falaises (jeu configurable). Chaque type est requêté sur la bbox
#' WGS84 de l'AOI, puis reprojeté et découpé sur l'AOI (spec 010 Q3).
#'
#' @param aoi Objet `sf`/`sfc` d'emprise, dans le CRS cible.
#' @param features Types d'obstacles à récupérer (sous-ensemble de `building`,
#'   `water`, `railway`, `cliff`).
#' @param crs Code EPSG de sortie. Défaut 2154.
#' @param cache_dir Répertoire de cache.
#' @param overwrite Re-télécharger même si le cache existe. Défaut `FALSE`.
#' @return Un objet `sf` d'obstacles avec un champ `type`, ou un `sf` vide si
#'   aucun obstacle n'est trouvé.
#' @export
acquire_obstacles <- function(aoi, features = c("building", "water", "railway", "cliff"),
                              crs = 2154, cache_dir = tempdir(), overwrite = FALSE) {
  chemin <- .chemin_cache(cache_dir, "obstacles", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  features <- match.arg(features, names(.OBSTACLES_OSM), several.ok = TRUE)

  aoi_wgs <- sf::st_transform(aoi, 4326)
  bbox_wgs <- sf::st_bbox(aoi_wgs)

  types <- character(0)
  geoms <- NULL
  for (feat in features) {
    for (req in .OBSTACLES_OSM[[feat]]) {
      od <- .fetch_osm(bbox_wgs, key = req$key, value = req$value)
      g <- .geoms_osm(od)
      if (!is.null(g)) {
        geoms <- if (is.null(geoms)) g else do.call(c, list(geoms, g))
        types <- c(types, rep(feat, length(g)))
      }
    }
  }

  crs_obj <- sf::st_crs(crs)
  if (is.null(geoms)) {
    vide <- sf::st_sf(type = character(0), geometry = sf::st_sfc(crs = crs_obj))
    sf::st_write(vide, chemin, delete_dsn = TRUE, quiet = TRUE)
    return(vide)
  }

  obs <- sf::st_sf(type = types, geometry = geoms)
  obs <- .reprojeter_clip(obs, aoi, crs)
  sf::st_write(obs, chemin, delete_dsn = TRUE, quiet = TRUE)
  obs
}

# Cles OSM identifiant une piste DFCI (wiki OSM FR:France/DFCI_et_DECI). La cle
# canonique `ref:FR:DFCI` porte la reference du panneau terrain (format "AL 04") ;
# les deux autres sont des alias historiques a migrer.
.CLES_DFCI_OSM <- c("ref:FR:DFCI", "ref:dfci", "dfci_ref")

# Valeurs OSM d'aires de retournement (highway=turning_circle / turning_loop) :
# points ou un camion peut faire demi-tour au bout d'une impasse DFCI (repli).
.CLES_RETOURNEMENT_OSM <- c("turning_circle", "turning_loop")

#' Acquiert le réseau DFCI depuis OpenStreetMap
#'
#' Récupère les pistes de défense des forêts contre l'incendie (DFCI) portant une
#' référence OSM `ref:FR:DFCI` (ou les alias `ref:dfci` / `dfci_ref`) au sein de
#' l'emprise. Ces lignes servent à poser le flag `dfci` (`CL_DFCI`) sur la
#' desserte via [flag_dfci()] — la source du camion DFCI (spec 006). C'est la
#' « source dédiée » laissée ouverte en phase 1 (spec 010 §10.2).
#'
#' @inheritParams acquire_obstacles
#' @return Un objet `sf` de lignes DFCI avec un champ `ref`, ou un `sf` vide si
#'   aucune piste DFCI n'est trouvée.
#' @seealso [flag_dfci()], [acquire_desserte()]
#' @export
acquire_dfci <- function(aoi, crs = 2154, cache_dir = tempdir(), overwrite = FALSE) {
  chemin <- .chemin_cache(cache_dir, "dfci", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  aoi_wgs <- sf::st_transform(aoi, 4326)
  bbox_wgs <- sf::st_bbox(aoi_wgs)

  refs <- character(0)
  geoms <- NULL
  for (cle in .CLES_DFCI_OSM) {
    od <- .fetch_osm(bbox_wgs, key = cle, value = NULL)
    lignes <- od$osm_lines
    if (!is.null(lignes) && nrow(lignes) > 0) {
      g <- sf::st_geometry(lignes)
      r <- if (cle %in% names(lignes)) as.character(lignes[[cle]]) else rep(NA_character_, length(g))
      geoms <- if (is.null(geoms)) g else do.call(c, list(geoms, g))
      refs <- c(refs, r)
    }
  }

  crs_obj <- sf::st_crs(crs)
  if (is.null(geoms)) {
    vide <- sf::st_sf(ref = character(0), geometry = sf::st_sfc(crs = crs_obj))
    sf::st_write(vide, chemin, delete_dsn = TRUE, quiet = TRUE)
    return(vide)
  }

  dfci <- sf::st_sf(ref = refs, geometry = geoms)
  dfci <- .reprojeter_clip(dfci, aoi, crs)
  sf::st_write(dfci, chemin, delete_dsn = TRUE, quiet = TRUE)
  dfci
}

# Aires de retournement OSM (points), pour le repli geometrique de flag_dfci.
# Non exporte : detail d'acquisition, mocke via .fetch_osm dans les tests.
#
# MISE EN CACHE (`cache_dir` non NULL) : cette fonction est appelee des que le
# DFCI est vide ou injoignable -- c'est-a-dire SYSTEMATIQUEMENT sur une emprise
# sans piste `ref:FR:DFCI`, le cas courant. Sans cache elle re-interrogeait
# Overpass a chaque execution, jusqu'au throttling (backoff 60 s a repetition
# qui bloquait `data-raw/oracle_aoi.R`). Le resultat VIDE est mis en cache comme
# les autres : une emprise sans aire de retournement n'a pas a etre redemandee.
.acquire_retournements <- function(aoi, crs = 2154, cache_dir = NULL,
                                   overwrite = FALSE) {
  chemin <- if (!is.null(cache_dir)) {
    .chemin_cache(cache_dir, "retournements", "gpkg")
  } else {
    NULL
  }
  if (!is.null(chemin) && file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  aoi_wgs <- sf::st_transform(aoi, 4326)
  bbox_wgs <- sf::st_bbox(aoi_wgs)
  geoms <- NULL
  for (val in .CLES_RETOURNEMENT_OSM) {
    od <- .fetch_osm(bbox_wgs, key = "highway", value = val)
    pts <- od$osm_points
    if (!is.null(pts) && nrow(pts) > 0) {
      g <- sf::st_geometry(pts)
      geoms <- if (is.null(geoms)) g else do.call(c, list(geoms, g))
    }
  }
  crs_obj <- sf::st_crs(crs)
  pts <- if (is.null(geoms)) {
    sf::st_sf(geometry = sf::st_sfc(crs = crs_obj))
  } else {
    sf::st_transform(sf::st_sf(geometry = geoms), crs)
  }
  if (!is.null(chemin)) {
    sf::st_write(pts, chemin, delete_dsn = TRUE, quiet = TRUE)
  }
  pts
}
