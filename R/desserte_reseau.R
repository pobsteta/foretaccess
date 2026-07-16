# Lot 16 : reseau de desserte multi-cibles (MTAP). Coiffe le solveur de trace du
# Lot 15 d'une couche reseau (portage de ForestRoadNetwork, Klemet, GPL v3).
# 16a : orchestration glouton (ordre heuristique + reutilisation), noyau Rust
# `desserte_reseau` (boucle MTAP->STAP, table de voisinage batie une fois).

#' Design a forest-road network serving several parcels
#'
#' Builds a road network connecting N parcels to an existing road network, at
#' minimum cumulated construction cost, by the greedy MTAP heuristic: parcels are
#' ordered, then each is connected to the current network with the Lot 15
#' constrained solver, the new road growing the network for later parcels (reuse
#' -> tree). A parcel cell already within `skidding_m` of a road needs no road.
#'
#' @param pre A `foretaccess_preprocessing` object (DEM, terrain slope).
#' @param cout A `foretaccess_cout_construction` object (Lot 14): crossability.
#' @param parcelles An `sf` POLYGON of the areas to serve.
#' @param desserte_existante An `sf` LINESTRING of the network to connect to.
#' @param heuristique Ordering of parcels: `"plus_proche"` (closest first),
#'   `"plus_gros_volume"` (largest volume first) or `"aleatoire"` (random).
#' @param skidding_m Skidding distance (m): a parcel cell within it of a road is
#'   served without building a road.
#' @param volume_champ Optional name of the parcel volume column (for
#'   `"plus_gros_volume"`); each cell inherits its parcel volume.
#' @param config A `foretaccess_config`; the solver settings live in
#'   `config$desserte$trace`.
#' @param graine Optional integer seed for the `"aleatoire"` ordering.
#' @return A `foretaccess_reseau` object: `lignes` (an `sf` LINESTRING of the
#'   created roads, one feature per road, with creation order and cost), `reseau`
#'   (a `SpatRaster` of the whole network, for Lot 17), `cout` (total) and the
#'   recall of the heuristic.
#' @export
reseau_desserte <- function(pre, cout, parcelles, desserte_existante,
                            heuristique = c("plus_proche", "plus_gros_volume", "aleatoire"),
                            skidding_m = 0, volume_champ = NULL,
                            config = foretaccess_config(), graine = NULL) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  checkmate::assert_class(cout, "foretaccess_cout_construction")
  heuristique <- match.arg(heuristique)
  validate_config(config)
  tr <- config$desserte$trace

  grille <- pre$mnt
  nr <- terra::nrow(grille)
  nc <- terra::ncol(grille)
  csize <- terra::res(grille)[1]

  g <- .desserte_grilles(pre, cout, tr)

  # Reseau existant rasterise -> cellules (1-based).
  road_r <- terra::rasterize(terra::vect(desserte_existante), grille, field = 1, background = NA)
  net_cells1 <- which(!is.na(terra::values(road_r)))
  if (length(net_cells1) == 0) {
    cli::cli_abort("{.arg desserte_existante} ne couvre aucune cellule de la grille.")
  }

  # Cellules des parcelles (1-based) et leur ordre heuristique.
  parc_ids <- .desserte_cellules_parcelles(parcelles, grille, volume_champ)
  if (length(parc_ids$cells) == 0) {
    cli::cli_abort("{.arg parcelles} ne couvre aucune cellule de la grille.")
  }
  ordre <- .desserte_ordre(parc_ids, road_r, heuristique, graine)
  sources0 <- as.integer(parc_ids$cells[ordre] - 1L)

  res <- desserte_reseau(
    alt = g$alt, obs = g$obs, obs2 = g$obs2, local_slope = g$local_slope, zone = g$zone,
    nr = nr, nc = nc, sources = sources0, network0 = as.integer(net_cells1 - 1L),
    skidding = skidding_m, csize = csize,
    min_slope = tr$pente_long_min, max_slope = tr$pente_long_max,
    penalty_xy = tr$penalty_xy, penalty_z = tr$penalty_z,
    max_diff_z = tr$max_diff_z_m, d_neighborhood = tr$d_neighborhood_m,
    angle_hairpin = tr$angle_epingle, lmax_ab_sl = tr$lmax_devers_m,
    radius = tr$rayon_braquage_m, prop_sl_max = tr$prop_devers_max,
    max_slope_hairpin = tr$max_slope_hairpin, tal = tr$tal, modhair = tr$modhair
  )

  # Polylignes des routes creees (une feature par tronçon).
  crs_grille <- sf::st_crs(terra::crs(grille))
  lignes <- .desserte_paths_en_sf(res$paths, res$costs, grille, crs_grille)

  # Raster du reseau complet (existant + routes creees), pour le Lot 17.
  cells_reseau <- unique(c(net_cells1, unlist(res$paths)))
  reseau_r <- terra::rast(grille)
  terra::values(reseau_r) <- 0
  reseau_r[cells_reseau] <- 1
  names(reseau_r) <- "reseau"

  structure(
    list(
      lignes = lignes,
      reseau = reseau_r,
      cout = sum(res$costs),
      heuristique = heuristique,
      config = config
    ),
    class = "foretaccess_reseau"
  )
}

# --- Helpers -----------------------------------------------------------------

# Grilles aplaties du solveur (MNT, obstacles, devers, fraction locale, zone).
# Partage la meme logique que `tracer_desserte` (Lot 15c).
.desserte_grilles <- function(pre, cout, tr) {
  grille <- pre$mnt
  csize <- terra::res(grille)[1]
  slope <- as.numeric(terra::values(pre$slope_pct))
  fr <- as.numeric(terra::values(cout$franchissable))
  bloque <- is.na(fr) | fr <= 0
  list(
    alt = as.numeric(terra::values(grille)),
    obs = as.integer(bloque),
    zone = as.integer(!bloque),
    obs2 = as.integer(!is.na(slope) & slope > tr$trans_slope_all),
    local_slope = .desserte_local_slope(pre$slope_pct, tr$trans_slope_hairpin,
                                        tr$rayon_braquage_m, csize)
  )
}

# Cellules (1-based) couvertes par les parcelles + volume par cellule.
.desserte_cellules_parcelles <- function(parcelles, grille, volume_champ) {
  v <- terra::vect(parcelles)
  parc_r <- terra::rasterize(v, grille, field = 1, background = NA)
  cells <- which(!is.na(terra::values(parc_r)))
  vol <- rep(1, length(cells))
  if (!is.null(volume_champ)) {
    checkmate::assert_choice(volume_champ, names(parcelles))
    vol_r <- terra::rasterize(v, grille, field = volume_champ, background = NA)
    vol <- as.numeric(terra::values(vol_r))[cells]
    vol[is.na(vol)] <- 0
  }
  list(cells = cells, volume = vol)
}

# Ordre d'insertion des cellules de parcelle selon l'heuristique.
.desserte_ordre <- function(parc_ids, road_r, heuristique, graine) {
  cells <- parc_ids$cells
  n <- length(cells)
  if (heuristique == "aleatoire") {
    if (is.null(graine)) {
      return(sample.int(n))
    }
    # Tirage reproductible sans polluer le RNG global.
    if (exists(".Random.seed", envir = globalenv())) {
      old <- get(".Random.seed", envir = globalenv())
      on.exit(assign(".Random.seed", old, envir = globalenv()), add = TRUE)
    }
    set.seed(graine)
    return(sample.int(n))
  }
  # Distance de chaque cellule au reseau existant (tie-break / critere principal).
  dist_r <- terra::distance(road_r)
  d <- as.numeric(terra::values(dist_r))[cells]
  if (heuristique == "plus_gros_volume") {
    order(-parc_ids$volume, d) # plus gros volume d'abord, puis plus proche
  } else {
    order(d) # plus proche d'abord
  }
}

# Liste de chemins (cellules 1-based) -> sf LINESTRING (une feature par route).
.desserte_paths_en_sf <- function(paths, costs, grille, crs_grille) {
  if (length(paths) == 0) {
    return(sf::st_sf(
      ordre = integer(0), cout = numeric(0),
      geometry = sf::st_sfc(crs = crs_grille)
    ))
  }
  geoms <- lapply(paths, function(cells) {
    xy <- terra::xyFromCell(grille, cells)
    if (nrow(xy) == 1L) xy <- rbind(xy, xy)
    sf::st_linestring(xy)
  })
  sf::st_sf(
    ordre = seq_along(paths),
    cout = costs,
    geometry = sf::st_sfc(geoms, crs = crs_grille)
  )
}

#' @export
print.foretaccess_reseau <- function(x, ...) {
  cli::cli_h1("Reseau de desserte")
  cli::cli_text("Heuristique : {.val {x$heuristique}}")
  cli::cli_text("Routes creees : {nrow(x$lignes)}")
  cli::cli_text("Cout total : {round(x$cout, 1)}")
  invisible(x)
}
