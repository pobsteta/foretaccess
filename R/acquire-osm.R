# Acquisition des obstacles depuis OpenStreetMap (Lot 10).
#
# Le transport passe par le client canonique `osm_overpass()` (ADR-010) depuis le
# 2026-08-13 ; `osmdata` a ete retire des Suggests, plus aucun appel ne subsistant.
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

# Wrapper reseau (POINT DE MOCK des tests). Depuis l'ADR-010 il n'est plus qu'un
# ADAPTATEUR au-dessus d'`osm_overpass()` : il rend la forme attendue par les
# appelants historiques (`osm_lines`/`osm_polygons`/`osm_multipolygons`) pour ne
# rien casser, mais tout le transport -- borne libcurl, rotation d'instances sans
# appel reseau, distinction refus/vide -- vit desormais dans le client canonique.
#
# `cle` accepte une LISTE de filtres : les regrouper en une union Overpass est
# l'optimisation qui fait passer `acquire_obstacles()` de 5 requetes a 1 et
# `acquire_dfci()` de 3 a 1. Overpass plafonne le nombre de requetes, pas la
# surface -- multiplier les appels est exactement ce qui declenche le 429.
.fetch_osm <- function(bbox_wgs, key, value = NULL, timeout = 90,
                       serveurs = OSM_SERVEURS_OVERPASS) {
  d <- .osm_bissecter(bbox_wgs, key, value, timeout, serveurs)
  g <- if (nrow(d)) sf::st_geometry(d) else NULL
  est <- function(types) {
    if (is.null(g)) return(NULL)
    k <- as.character(sf::st_geometry_type(d)) %in% types
    if (!any(k)) NULL else d[k, , drop = FALSE]
  }
  list(
    osm_lines = est(c("LINESTRING", "MULTILINESTRING")),
    osm_polygons = est("POLYGON"),
    osm_multipolygons = est("MULTIPOLYGON")
  )
}

# UNE requete par AOI ; la bissection n'est qu'un REPLI (brief §3).
#
# Le tuilage systematique -- 1 km chez `dsr_osm()` -- transforme une AOI de
# 10 x 10 km en 100 requetes plus 100 s de pause, soit precisement le
# comportement qui declenche le 429 que le reste du code s'efforce d'eviter. Il
# induit en prime une redondance : `(._;>;)` rapatrie tous les noeuds de chaque
# way a chaque dalle traversee.
#
# On bissecte donc en quadrants SEULEMENT sur un refus de VOLUME ou de TIMEOUT --
# jamais sur un 429, qui appelle une rotation d'instance et non un decoupage.
.osm_bissecter <- function(bbox_wgs, key, value = NULL, timeout = 90,
                           serveurs = OSM_SERVEURS_OVERPASS, profondeur = 0L) {
  out <- tryCatch(
    osm_overpass(bbox_wgs, key, value, timeout = timeout, serveurs = serveurs),
    error = function(e) e
  )
  if (!inherits(out, "error")) {
    return(out)
  }
  msg <- conditionMessage(out)
  volume <- grepl("timeout|tronque|504|memoire|memory", msg, ignore.case = TRUE)
  if (!volume || profondeur >= .OSM_PROFONDEUR_MAX) {
    stop(out)
  }
  cli::cli_inform("OSM : requete trop lourde, bissection en quadrants
                   (profondeur {profondeur + 1L}).")
  parts <- lapply(.osm_quadrants(bbox_wgs), function(q) {
    .osm_bissecter(q, key, value, timeout, serveurs, profondeur + 1L)
  })
  parts <- parts[vapply(parts, nrow, integer(1)) > 0]
  if (!length(parts)) {
    return(sf::st_sf(osm_id = character(0), geometry = sf::st_sfc(crs = 4326)))
  }
  cols <- Reduce(union, lapply(parts, names))
  parts <- lapply(parts, function(d) {
    for (n in setdiff(cols, names(d))) d[[n]] <- NA
    d[, cols]
  })
  fus <- do.call(rbind, parts)
  # Dedoublonnage a la fusion : un way traversant deux quadrants revient deux fois.
  if ("osm_id" %in% names(fus)) fus <- fus[!duplicated(fus$osm_id), ]
  fus
}

# Profondeur 3 = 64 sous-emprises au pire ; au-dela, l'erreur est plus honnete
# qu'un decoupage qui n'aboutira pas.
.OSM_PROFONDEUR_MAX <- 3L

.osm_quadrants <- function(b) {
  mx <- (b[["xmin"]] + b[["xmax"]]) / 2
  my <- (b[["ymin"]] + b[["ymax"]]) / 2
  f <- function(x1, y1, x2, y2) {
    c(xmin = x1, ymin = y1, xmax = x2, ymax = y2)
  }
  list(f(b[["xmin"]], b[["ymin"]], mx, my), f(mx, b[["ymin"]], b[["xmax"]], my),
       f(b[["xmin"]], my, mx, b[["ymax"]]), f(mx, my, b[["xmax"]], b[["ymax"]]))
}


# Dispatch LOCAL du type d'obstacle : la requete groupee rapatrie tout en un
# appel, c'est ici qu'on retrouve quel filtre a matche. Premier filtre satisfait
# gagne, dans l'ordre de `.OBSTACLES_OSM`.
.osm_type_obstacle <- function(d, filtres) {
  t <- rep(NA_character_, nrow(d))
  for (f in filtres) {
    if (!f$cle %in% names(d)) next
    v <- as.character(d[[f$cle]])
    ok <- if (is.null(f$valeur)) !is.na(v) else !is.na(v) & v == f$valeur[1]
    t[is.na(t) & ok] <- f$type
  }
  t
}

# Geometries pertinentes d'une reponse OSM : polygones, multipolygones et
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
#' @param politique_cache Que faire d'un cache produit avec **d'autres
#'   paramètres** ? Défaut `"reacquerir"`. Voir [cache_utilisable()] et
#'   `specs/027`.
#' @return Un objet `sf` d'obstacles avec un champ `type`, ou un `sf` vide si
#'   aucun obstacle n'est trouvé.
#' @export
acquire_obstacles <- function(aoi, features = c("building", "water", "railway", "cliff"),
                              crs = 2154, cache_dir = tempdir(), overwrite = FALSE,
                              politique_cache = "reacquerir") {
  chemin <- .chemin_cache(cache_dir, "obstacles", "gpkg")
  prov <- list(crs = crs, features = paste(sort(features), collapse = ","))
  if (file.exists(chemin) && !overwrite &&
      cache_utilisable(chemin, "obstacles", "osm", prov, politique_cache)) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  features <- match.arg(features, names(.OBSTACLES_OSM), several.ok = TRUE)

  aoi_wgs <- sf::st_transform(aoi, 4326)
  bbox_wgs <- sf::st_bbox(aoi_wgs)

  # UNE SEULE requete pour tous les types : union de filtres Overpass, puis
  # dispatch LOCAL par tag. Auparavant une requete par couple (cle, valeur), soit
  # 5 appels pour les 4 types par defaut -- et Overpass plafonne le nombre de
  # requetes, pas la surface. Gain direct : 5 -> 1.
  filtres <- list()
  for (feat in features) {
    for (req in .OBSTACLES_OSM[[feat]]) {
      filtres[[length(filtres) + 1L]] <- list(cle = req$key, valeur = req$value,
                                              type = feat)
    }
  }
  od <- .fetch_osm(bbox_wgs, key = lapply(filtres, function(f) {
    list(cle = f$cle, valeur = f$valeur)
  }))
  types <- character(0)
  geoms <- NULL
  for (p in list(od$osm_polygons, od$osm_multipolygons, od$osm_lines)) {
    if (is.null(p) || nrow(p) == 0) next
    t <- .osm_type_obstacle(p, filtres)
    garde <- !is.na(t)
    if (!any(garde)) next
    g <- sf::st_geometry(p)[garde]
    geoms <- if (is.null(geoms)) g else do.call(c, list(geoms, g))
    types <- c(types, t[garde])
  }

  crs_obj <- sf::st_crs(crs)
  if (is.null(geoms)) {
    vide <- sf::st_sf(type = character(0), geometry = sf::st_sfc(crs = crs_obj))
    sf::st_write(vide, chemin, delete_dsn = TRUE, quiet = TRUE)
    .provenance_ecrire(chemin, "obstacles", "osm", prov)
    return(vide)
  }

  obs <- sf::st_sf(type = types, geometry = geoms)
  obs <- .reprojeter_clip(obs, aoi, crs)
  sf::st_write(obs, chemin, delete_dsn = TRUE, quiet = TRUE)
  .provenance_ecrire(chemin, "obstacles", "osm", prov)
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
#' @param politique_cache Que faire d'un cache produit avec **d'autres
#'   paramètres** ? Défaut `"reacquerir"`. Voir [cache_utilisable()] et
#'   `specs/027`.
#' @return Un objet `sf` de lignes DFCI avec un champ `ref`, ou un `sf` vide si
#'   aucune piste DFCI n'est trouvée.
#' @seealso [flag_dfci()], [acquire_desserte()]
#' @export
acquire_dfci <- function(aoi, crs = 2154, cache_dir = tempdir(), overwrite = FALSE,
                         politique_cache = "reacquerir") {
  chemin <- .chemin_cache(cache_dir, "dfci", "gpkg")
  prov <- list(crs = crs)
  if (file.exists(chemin) && !overwrite &&
      cache_utilisable(chemin, "dfci", "osm", prov, politique_cache)) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  aoi_wgs <- sf::st_transform(aoi, 4326)
  bbox_wgs <- sf::st_bbox(aoi_wgs)

  # UNE requete pour les trois cles de reference DFCI (union de filtres), au lieu
  # de trois appels successifs. Gain : 3 -> 1.
  od <- .fetch_osm(bbox_wgs, key = lapply(.CLES_DFCI_OSM, function(k) {
    list(cle = k, valeur = NULL)
  }))
  refs <- character(0)
  geoms <- NULL
  lignes <- od$osm_lines
  if (!is.null(lignes) && nrow(lignes) > 0) {
    # La reference peut venir de n'importe laquelle des trois cles : on prend la
    # premiere renseignee, dans l'ordre de `.CLES_DFCI_OSM`.
    r <- rep(NA_character_, nrow(lignes))
    for (k in .CLES_DFCI_OSM) {
      if (k %in% names(lignes)) {
        v <- as.character(lignes[[k]])
        r[is.na(r)] <- v[is.na(r)]
      }
    }
    garde <- !is.na(r)
    if (any(garde)) {
      geoms <- sf::st_geometry(lignes)[garde]
      refs <- r[garde]
    }
  }

  crs_obj <- sf::st_crs(crs)
  if (is.null(geoms)) {
    vide <- sf::st_sf(ref = character(0), geometry = sf::st_sfc(crs = crs_obj))
    sf::st_write(vide, chemin, delete_dsn = TRUE, quiet = TRUE)
    .provenance_ecrire(chemin, "dfci", "osm", prov)
    return(vide)
  }

  dfci <- sf::st_sf(ref = refs, geometry = geoms)
  dfci <- .reprojeter_clip(dfci, aoi, crs)
  sf::st_write(dfci, chemin, delete_dsn = TRUE, quiet = TRUE)
  .provenance_ecrire(chemin, "dfci", "osm", prov)
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
                                   overwrite = FALSE,
                                   politique_cache = "reacquerir") {
  chemin <- if (!is.null(cache_dir)) {
    .chemin_cache(cache_dir, "retournements", "gpkg")
  } else {
    NULL
  }
  if (!is.null(chemin) && file.exists(chemin) && !overwrite &&
      cache_utilisable(chemin, "retournements", "osm", list(crs = crs),
        politique_cache)) {
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
    .provenance_ecrire(chemin, "retournements", "osm", list(crs = crs))
  }
  pts
}
