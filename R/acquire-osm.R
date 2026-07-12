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
.fetch_osm <- function(bbox_wgs, key, value = NULL) {
  .require_pkg("osmdata")
  q <- osmdata::opq(bbox = bbox_wgs)
  q <- osmdata::add_osm_feature(q, key = key, value = value)
  osmdata::osmdata_sf(q)
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
