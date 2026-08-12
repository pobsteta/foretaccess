# Lot 15c : orchestration R du solveur de trace (noyau Rust `desserte_trace`,
# Lot 15b). R prepare les grilles aplaties, appelle le solveur, reconstruit la
# polyligne SIG. Frontiere minimale et typee (ADR-001).

#' Design the optimal route of a new forest road
#'
#' Traces the least-cost road from a start point to an end point (through optional
#' mandatory waypoints) over the construction-cost surface (Lot 14), honouring
#' road geometry constraints — bounded longitudinal grade, smooth turns, minimum
#' turning radius, controlled hairpins, terrain-compatible profile. Thin R wrapper
#' around the Rust A\* solver (`desserte_trace`, spec 015): R flattens the DEM,
#' crossability and terrain slope, calls the solver and rebuilds the polyline.
#'
#' @section Performance:
#' Un seul trace A\* entre les waypoints, **borne au corridor** qu'ils
#' definissent (cf. [reseau_desserte()] *Performance*) : de quelques dizaines de
#' millisecondes a quelques secondes pour deux points proches, et d'autant plus
#' cher qu'ils sont eloignes -- la fenetre grandit avec leur distance. Sans
#' commune mesure avec [reseau_desserte()], qui enchaine un trace PAR CELLULE de
#' parcelle.
#' @param pre A `foretaccess_preprocessing` object (DEM, terrain slope).
#' @param cout A `foretaccess_cout_construction` object (Lot 14): supplies the
#'   crossability mask (`franchissable`) and, if `pondere_cout = TRUE`, the
#'   construction cost surface (`cout`, euros/m).
#' @param waypoints Ordered points the road must visit (start first, end last;
#'   at least two). An `sf`/`SpatVector` of points, a two-column matrix of
#'   coordinates, or a vector of raster cell numbers (1-based).
#' @param pondere_cout If `TRUE`, weights the trace by the construction cost
#'   surface (`cout$cout`, euros/m) instead of pure geometric distance, so the
#'   road minimises monetary cost. Default `FALSE` (SylvaRoad behaviour).
#' @param config A `foretaccess_config`; the solver settings live in
#'   `config$desserte$trace`.
#' @return A `foretaccess_trace` object: a list with `ligne` (an `sf` LINESTRING
#'   of the route), `cout` (total cost), `faisable` (did every segment reach its
#'   target), `waypoints` (the cell numbers) and the `config`.
#' @export
tracer_desserte <- function(pre, cout, waypoints, pondere_cout = FALSE,
                            config = foretaccess_config()) {
  checkmate::assert_class(pre, "foretaccess_preprocessing")
  checkmate::assert_class(cout, "foretaccess_cout_construction")
  validate_config(config)
  .avertir_cout_ignore(cout, pondere_cout, !missing(pondere_cout))
  tr <- config$desserte$trace

  grille <- pre$mnt
  nr <- terra::nrow(grille)
  nc <- terra::ncol(grille)
  csize <- terra::res(grille)[1]

  # Grilles aplaties ligne par ligne (ordre des cellules terra = row-major).
  alt <- as.numeric(terra::values(grille))
  slope <- as.numeric(terra::values(pre$slope_pct))
  fr <- as.numeric(terra::values(cout$franchissable))

  # Obstacle = cellule non franchissable (Lot 14 : cout NA, obstacle, interdit,
  # pente non constructible). `zone` = complement, pour l'heuristique inverse.
  bloque <- is.na(fr) | fr <= 0
  obs <- as.integer(bloque)
  zone <- as.integer(!bloque)

  # Devers excessif (obs2) et fraction locale de fort devers (local_slope), tous
  # deux derives de la pente du terrain (proxy du devers de la plateforme).
  obs2 <- as.integer(!is.na(slope) & slope > tr$trans_slope_all)
  local_slope <- .desserte_local_slope(pre$slope_pct, tr$trans_slope_hairpin,
                                       tr$rayon_braquage_m, csize)

  # Points de passage -> cellules terra (1-based) -> indices 0-based du solveur.
  cells1 <- if (is.matrix(waypoints) && ncol(waypoints) == 2) {
    terra::cellFromXY(grille, waypoints)
  } else {
    .cellules_depuis(waypoints, grille)
  }
  if (length(cells1) < 2) {
    cli::cli_abort("{.arg waypoints} doit contenir au moins 2 points (depart, arrivee).")
  }
  wp0 <- as.integer(cells1 - 1L)

  # Grille de coût €/m (Lot 14) si ponderation demandee, sinon neutre (1.0).
  cost <- if (isTRUE(pondere_cout)) as.numeric(terra::values(cout$cout)) else rep(1, nr * nc)

  res <- desserte_trace(
    alt = alt, obs = obs, obs2 = obs2, local_slope = local_slope, zone = zone,
    nr = nr, nc = nc, waypoints = wp0, bufgoal = tr$buffer_arrivee_m,
    csize = csize, min_slope = tr$pente_long_min, max_slope = tr$pente_long_max,
    penalty_xy = tr$penalty_xy, penalty_z = tr$penalty_z,
    max_diff_z = tr$max_diff_z_m, d_neighborhood = tr$d_neighborhood_m,
    angle_hairpin = tr$angle_epingle, lmax_ab_sl = tr$lmax_devers_m,
    radius = tr$rayon_braquage_m, prop_sl_max = tr$prop_devers_max,
    max_slope_hairpin = tr$max_slope_hairpin, tal = tr$tal, modhair = tr$modhair,
    cost = cost
  )

  if (!res$feasible) {
    cli::cli_warn("Trace incomplet : un segment n'a pas atteint sa cible.")
  }

  # Reconstruction de la polyligne : cellules 1-based -> centres -> LINESTRING.
  crs_grille <- sf::st_crs(terra::crs(grille))
  geom <- if (length(res$path) >= 2) {
    xy <- terra::xyFromCell(grille, res$path)
    sf::st_sfc(sf::st_linestring(xy), crs = crs_grille)
  } else {
    sf::st_sfc(sf::st_linestring(matrix(numeric(0), ncol = 2)), crs = crs_grille)
  }
  ligne <- sf::st_sf(cout = res$cost, faisable = res$feasible, geometry = geom)

  structure(
    list(
      ligne = ligne,
      cout = res$cost,
      faisable = isTRUE(res$feasible),
      waypoints = cells1,
      config = config
    ),
    class = "foretaccess_trace"
  )
}

# Fraction locale (0..1) de cellules a fort devers dans un disque de rayon
# `rayon` autour de chaque cellule (portage de `calc_local_slope`). Si le disque
# ne couvre pas plus d'une cellule, la fraction se reduit a la cellule elle-meme.
.desserte_local_slope <- function(slope_r, seuil, rayon, csize) {
  raide <- terra::ifel(!is.na(slope_r) & slope_r > seuil, 1, 0)
  frac <- if (rayon >= csize) {
    w <- terra::focalMat(raide, rayon, type = "circle")
    terra::focal(raide, w = w, fun = "sum", na.rm = TRUE)
  } else {
    raide
  }
  v <- as.numeric(terra::values(frac))
  v[is.na(v)] <- 0
  v
}

#' @export
print.foretaccess_trace <- function(x, ...) {
  n_pts <- if (nrow(x$ligne) > 0) nrow(sf::st_coordinates(x$ligne)) else 0
  cli::cli_h1("Trace de desserte")
  cli::cli_text("Faisable : {.val {x$faisable}}")
  cli::cli_text("Cout total : {round(x$cout, 1)}")
  cli::cli_text("Points de passage : {length(x$waypoints)} | sommets du trace : {n_pts}")
  invisible(x)
}
