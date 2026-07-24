# Obstacles conformes ACCESSFOR (spec 022 volet B). ACCESSFOR (rapport final 2025,
# sec.2.3.4) integre comme obstacles a la circulation des engins : cours d'eau,
# surfaces hydro, voies ferrees, batis, routes principales -- extraits de la BD
# TOPO IGN -- ET des zonages reglementaires (reserve integrale de PN, reserves
# biologiques, APB, reserves naturelles) issus de l'INPN (famille Patrinat de la
# Geoplateforme). Cette acquisition les assemble en UNE couche `obstacles_complets`
# pour preprocess(). Distincte d'acquire_obstacles() (source OSM). Effet mesure sur
# Chastel-Nouvel : accord agrege ACCESSFOR +1,6 pt (les zonages y sont vides ;
# l'apport vient des cours d'eau/batis -- bien plus fort sur un massif a reserves).

# Couches BD TOPO obstacles (WFS IGN data.geopf.fr). Lignes tamponnees en surface
# au rasterisation ; polygones tels quels.
.OBSTACLES_BDTOPO <- c(
  cours_d_eau            = "BDTOPO_V3:cours_d_eau",
  surface_hydrographique = "BDTOPO_V3:surface_hydrographique",
  voie_ferree            = "BDTOPO_V3:troncon_de_voie_ferree",
  batiment               = "BDTOPO_V3:batiment"
)

# Zonages reglementaires INPN/MNHN (famille Patrinat). Correspondance exacte aux
# exclusions ACCESSFOR (rapport sec.2.3.4). Les couches "tout" excluent le polygone
# entier ; le parc national est FILTRE sur la reserve integrale (zone), SURTOUT PAS
# le parc entier. Ne PAS inclure PNR / ZNIEFF / Natura 2000 / RNCFS (hors liste).
.ZONAGES_PATRINAT <- c(
  apb = "patrinat_apb:apb",             # arrete de protection de biotope
  rnn = "patrinat_rnn:rnn",             # reserve naturelle nationale
  rnr = "patrinat_rnr:rnr",             # reserve naturelle regionale
  rb  = "patrinat_rb:reserve_biologique" # reserves biologiques (integrales + dirigees)
)
.ZONAGE_PN <- "patrinat_pn:parc_national" # filtre zone == reserve integrale

#' Acquire ACCESSFOR-conformant obstacles from BD TOPO and INPN (spec 022 volet B)
#'
#' Assembles the **obstacle layer ACCESSFOR uses** (report Feb. 2025, sec. 2.3.4)
#' into a single `sf` of polygons ready for `preprocess(obstacles_complets = )`:
#' BD TOPO obstacles (watercourses, water surfaces, railways, buildings, main
#' roads) **plus** the INPN/MNHN regulatory exclusions (biotope-protection orders,
#' national and regional nature reserves, biological reserves, and the **integral
#' reserve** of national parks -- not the whole park). Distinct from
#' [acquire_obstacles()] (OpenStreetMap source).
#'
#' @details
#' Line features (watercourses, railways, main roads) are buffered by half a
#' `tampon_m` so they rasterise to a continuous barrier; polygons are kept as is.
#' National parks are filtered on their `zone` attribute to the **integral
#' reserve** only -- excluding the whole park would over-block massively. `PNR`,
#' `ZNIEFF`, Natura 2000 and hunting reserves are **not** ACCESSFOR exclusions and
#' are never included. On a massif without reserves the effect comes from the BD
#' TOPO obstacles alone.
#'
#' @inheritParams acquire_desserte
#' @param routes_importance_max Main roads with BD TOPO `importance` at most this
#'   are added as obstacles (autoroutes/nationales/départementales structurantes).
#'   Default 3. `NA` disables road obstacles.
#' @param tampon_m Buffer (m) applied to line obstacles. Default 5.
#' @param zonages Include the INPN/Patrinat regulatory exclusions? Default `TRUE`.
#' @return An `sf` of `MULTIPOLYGON` obstacles in `crs`, clipped to `aoi`. Empty
#'   layers are skipped; if nothing is found the result has zero rows.
#' @seealso [acquire_obstacles()] (OSM), [preprocess()] (consumes
#'   `obstacles_complets`), `specs/022`.
#' @export
acquire_obstacles_bdtopo <- function(aoi, crs = 2154, cache_dir = tempdir(),
                                     overwrite = FALSE, country = "FR",
                                     routes_importance_max = 3L, tampon_m = 5,
                                     zonages = TRUE) {
  chemin <- .chemin_cache(cache_dir, "obstacles_bdtopo", "gpkg")
  if (file.exists(chemin) && !overwrite) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  aoi_cible <- sf::st_transform(sf::st_geometry(sf::st_as_sf(aoi)), crs)

  polys <- list()
  # --- Obstacles BD TOPO ---------------------------------------------------
  for (typ in .OBSTACLES_BDTOPO) {
    x <- tryCatch(.fetch_wfs(aoi, typ), error = function(e) NULL)
    g <- .obstacle_polygones(x, crs, aoi_cible, tampon_m)
    if (!is.null(g)) polys[[typ]] <- g
  }
  # Routes principales (grands axes) : depuis troncon_de_route, filtre importance.
  if (!is.na(routes_importance_max)) {
    rt <- tryCatch(.fetch_wfs(aoi, .OBSTACLES_BDTOPO_ROUTE()), error = function(e) NULL)
    if (!is.null(rt) && "importance" %in% names(rt)) {
      imp <- suppressWarnings(as.integer(as.character(rt$importance)))
      rt <- rt[!is.na(imp) & imp <= routes_importance_max, ]
      g <- .obstacle_polygones(rt, crs, aoi_cible, tampon_m)
      if (!is.null(g)) polys[["routes_principales"]] <- g
    }
  }
  # --- Zonages reglementaires (INPN / Patrinat) ----------------------------
  if (isTRUE(zonages)) {
    for (typ in .ZONAGES_PATRINAT) {
      x <- tryCatch(.fetch_wfs(aoi, typ), error = function(e) NULL)
      g <- .obstacle_polygones(x, crs, aoi_cible, tampon_m)
      if (!is.null(g)) polys[[typ]] <- g
    }
    # Parc national : SEULEMENT la reserve integrale (filtre `zone`).
    pn <- tryCatch(.fetch_wfs(aoi, .ZONAGE_PN), error = function(e) NULL)
    if (!is.null(pn) && "zone" %in% names(pn)) {
      pn <- pn[grepl("integrale", .ascii(pn$zone)), ]
      g <- .obstacle_polygones(pn, crs, aoi_cible, tampon_m)
      if (!is.null(g)) polys[["pn_reserve_integrale"]] <- g
    }
  }

  out <- if (length(polys)) {
    sf::st_sf(obstacle = names(polys), geometry = do.call(c, unname(polys)))
  } else {
    sf::st_sf(obstacle = character(0), geometry = sf::st_sfc(crs = crs))
  }
  sf::st_write(out, chemin, delete_dsn = TRUE, quiet = TRUE)
  out
}

# Typename BD TOPO des routes (reutilise la config desserte).
.OBSTACLES_BDTOPO_ROUTE <- function(country = "FR") {
  info <- get_layer_service("roads", country)
  if (is.null(info)) "BDTOPO_V3:troncon_de_route" else info$typename
}

# Translitteration ASCII (pour filtrer `zone` accentue).
.ascii <- function(x) tolower(iconv(as.character(x), to = "ASCII//TRANSLIT"))

# Normalise une couche fetchee en une geometrie MULTIPOLYGON unique, reprojetee,
# clippee sur l'AOI. Lignes tamponnees. NULL si vide/absente.
.obstacle_polygones <- function(x, crs, aoi_cible, tampon_m) {
  if (is.null(x) || nrow(x) == 0) {
    return(NULL)
  }
  g <- sf::st_geometry(sf::st_transform(sf::st_make_valid(x), crs))
  types <- as.character(sf::st_geometry_type(g))
  if (any(grepl("LINE|POINT", types))) {
    g <- sf::st_buffer(g, tampon_m / 2)
  }
  g <- suppressWarnings(sf::st_intersection(sf::st_make_valid(g), aoi_cible))
  g <- g[!sf::st_is_empty(g)]
  if (length(g) == 0) {
    return(NULL)
  }
  sf::st_union(sf::st_cast(sf::st_make_valid(g), "MULTIPOLYGON"))
}
