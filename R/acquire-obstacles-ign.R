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
# a la rasterisation ; polygones tels quels.
#
# Liste TRANSCRITE du tableau de l'annexe p.51-52 du rapport ACCESSFOR : quatre
# thematiques (TRANSPORT / HYDROGRAPHIE / BATI / ZONES_REGLEMENTEES). Les couches
# cimetiere, reservoir, terrain_de_sport et piste_d_aerodrome manquaient jusqu'a
# la v1.27.1 -- soit 4 des 9 classes d'obstacles BD TOPO d'ACCESSFOR.
.OBSTACLES_BDTOPO <- c(
  # HYDROGRAPHIE -- filtrees sur persistance permanente (cf. .filtre_obstacle).
  cours_d_eau            = "BDTOPO_V3:troncon_hydrographique",
  surface_hydrographique = "BDTOPO_V3:surface_hydrographique",
  # TRANSPORT -- voie ferree filtree (nature, position au sol) ; routes a part.
  voie_ferree            = "BDTOPO_V3:troncon_de_voie_ferree",
  piste_d_aerodrome      = "BDTOPO_V3:piste_d_aerodrome",
  # BATI -- « Tout » chez ACCESSFOR, aucun filtre attributaire.
  batiment               = "BDTOPO_V3:batiment",
  cimetiere              = "BDTOPO_V3:cimetiere",
  reservoir              = "BDTOPO_V3:reservoir",
  terrain_de_sport       = "BDTOPO_V3:terrain_de_sport"
)

# Classements administratifs retenus par ACCESSFOR pour les « routes principales »
# (annexe p.52, filtre sur `cpx_classement_administratif`). Remplace le filtre
# `importance <= 3` de la v1.21.0, qui ne retrouvait PAS la meme selection : sur
# l'AOI oracle il retenait 0 troncon la ou le classement en retient 11.
.CLASSEMENTS_ROUTES_ACCESSFOR <- c(
  "Autoroute", "Departementale", "Nationale", "Route europeenne",
  "Route intercommunale"
)

# Filtres attributaires de l'annexe p.51-52, appliques couche par couche.
#   * hydrographie : PERSISTANC = « Permanent » -- sans quoi les cours d'eau
#     intermittents (secs une partie de l'annee) bloquent a tort ;
#   * voie ferree  : NATURE != « sans objet » ;
#   * transport    : POS_SOL >= 0 -- un TUNNEL n'est pas un obstacle de surface.
.filtre_obstacle <- function(x, couche) {
  if (is.null(x) || nrow(x) == 0) {
    return(x)
  }
  garder <- rep(TRUE, nrow(x))
  if (couche %in% c("cours_d_eau", "surface_hydrographique") &&
      "persistance" %in% names(x)) {
    garder <- garder & grepl("permanent", .ascii(x$persistance))
  }
  if (couche == "voie_ferree" && "nature" %in% names(x)) {
    garder <- garder & !grepl("sans objet", .ascii(x$nature))
  }
  if (couche %in% c("voie_ferree", "routes_principales") &&
      "position_par_rapport_au_sol" %in% names(x)) {
    pos <- suppressWarnings(as.integer(as.character(x$position_par_rapport_au_sol)))
    garder <- garder & (is.na(pos) | pos >= 0L)
  }
  garder[is.na(garder)] <- FALSE
  x[garder, , drop = FALSE]
}

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
#' @param routes_importance_max Fallback selection of main roads by BD TOPO
#'   `importance` (at most this value), used **only** when
#'   `cpx_classement_administratif` is absent from the WFS feed. Default `NA`
#'   (no fallback) -- ACCESSFOR selects on the administrative class, not on
#'   `importance`, and the two do not coincide.
#' @param classements_routes Values of BD TOPO `cpx_classement_administratif`
#'   making a road an obstacle. Default: the ACCESSFOR list (annexe p. 52) --
#'   motorway, département, national, European and intercommunal roads. `NULL`
#'   disables the classement filter (then `routes_importance_max` applies).
#' @param tampon_m Buffer (m) applied to line obstacles. Default 5.
#' @param zonages Include the INPN/Patrinat regulatory exclusions? Default `TRUE`.
#' @return An `sf` of `MULTIPOLYGON` obstacles in `crs`, clipped to `aoi`. Empty
#'   layers are skipped; if nothing is found the result has zero rows.
#' @seealso [acquire_obstacles()] (OSM), [preprocess()] (consumes
#'   `obstacles_complets`), `specs/022`.
#' @export
acquire_obstacles_bdtopo <- function(aoi, crs = 2154, cache_dir = tempdir(),
                                     overwrite = FALSE, country = "FR",
                                     routes_importance_max = NA_integer_,
                                     classements_routes = .CLASSEMENTS_ROUTES_ACCESSFOR,
                                     tampon_m = 5, zonages = TRUE,
                                     politique_cache = "reacquerir") {
  chemin <- .chemin_cache(cache_dir, "obstacles_bdtopo", "gpkg")
  prov <- list(crs = crs, tampon_m = tampon_m, zonages = zonages,
               classements = paste(classements_routes, collapse = ","),
               routes_importance_max = routes_importance_max)
  if (file.exists(chemin) && !overwrite &&
      cache_utilisable(chemin, "obstacles_bdtopo", NULL, prov, politique_cache)) {
    return(sf::st_read(chemin, quiet = TRUE))
  }
  aoi_cible <- sf::st_transform(sf::st_geometry(sf::st_as_sf(aoi)), crs)

  polys <- list()
  # --- Obstacles BD TOPO ---------------------------------------------------
  for (nom in names(.OBSTACLES_BDTOPO)) {
    x <- tryCatch(.fetch_wfs(aoi, .OBSTACLES_BDTOPO[[nom]]), error = function(e) NULL)
    x <- .filtre_obstacle(x, nom)
    g <- .obstacle_polygones(x, crs, aoi_cible, tampon_m)
    if (!is.null(g)) polys[[nom]] <- g
  }
  # Routes principales : filtre ACCESSFOR sur `cpx_classement_administratif`
  # (annexe p.52), repli sur `importance` si la colonne manque du flux.
  if (!is.null(classements_routes) || !is.na(routes_importance_max)) {
    rt <- tryCatch(.fetch_wfs(aoi, .OBSTACLES_BDTOPO_ROUTE()), error = function(e) NULL)
    rt <- .filtre_routes_principales(rt, classements_routes, routes_importance_max)
    rt <- .filtre_obstacle(rt, "routes_principales")
    g <- .obstacle_polygones(rt, crs, aoi_cible, tampon_m)
    if (!is.null(g)) polys[["routes_principales"]] <- g
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
  .provenance_ecrire(chemin, "obstacles_bdtopo", NULL, prov)
  out
}

# Selection des « routes principales » : classement administratif ACCESSFOR en
# premier, repli `importance` si la colonne manque. Les deux ne coincident PAS --
# sur l'AOI oracle, `importance <= 3` retenait 0 troncon quand le classement en
# retient 11 (des departementales d'importance 4).
.filtre_routes_principales <- function(rt, classements, importance_max) {
  if (is.null(rt) || nrow(rt) == 0) {
    return(rt)
  }
  if (!is.null(classements) && "cpx_classement_administratif" %in% names(rt)) {
    cl <- .ascii(rt$cpx_classement_administratif)
    garder <- cl %in% .ascii(classements)
    garder[is.na(garder)] <- FALSE
    return(rt[garder, , drop = FALSE])
  }
  if (!is.na(importance_max) && "importance" %in% names(rt)) {
    imp <- suppressWarnings(as.integer(as.character(rt$importance)))
    return(rt[!is.na(imp) & imp <= importance_max, , drop = FALSE])
  }
  rt[0, , drop = FALSE]
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
