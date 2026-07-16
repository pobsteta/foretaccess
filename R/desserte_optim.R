# Lot 18 : optimisation du reseau de desserte (multi-start & amelioration locale).
# Couche au-dessus du Lot 16 : le glouton reste la baseline, cette couche explore
# l'espace des ordres d'insertion pour faire mieux. Metaheuristiques standard du
# domaine (Akay 2004 -- recuit ; Contreras/Chung -- ACO), calcul parallele (rayon).
# 18a : multi-start parallele (noyau Rust `desserte_reseau_multistart`).

#' Optimise a forest-road network over insertion orders
#'
#' Wraps the Lot 16 greedy builder in an optimisation layer that explores the
#' space of parcel insertion orders and keeps the cheapest network. The greedy
#' order is always trial 0, so the result is never worse than the plain greedy of
#' [reseau_desserte()] (CA-18.1). Currently the `"multistart"` strategy is
#' available (parallel over K perturbed orders, `rayon`); `"recuit"` (simulated
#' annealing) and `"riprute"` (rip-up & reroute) are planned (Lot 18b/18c).
#'
#' @param pre A `foretaccess_preprocessing` object (DEM, terrain slope).
#' @param cout A `foretaccess_cout_construction` object (Lot 14).
#' @param parcelles An `sf` POLYGON of the areas to serve.
#' @param desserte_existante An `sf` LINESTRING of the network to connect to.
#' @param strategie Optimisation strategy: `"multistart"` (default) or `"recuit"`
#'   (simulated annealing on the insertion order).
#' @param heuristique Base ordering of parcels (trial 0), see [reseau_desserte()].
#' @param n_start Number of insertion orders to try (`"multistart"`).
#' @param n_iter Number of annealing iterations (`"recuit"`).
#' @param temp0 Initial annealing temperature (`"recuit"`); `<= 0` derives it from
#'   the base network cost.
#' @param refroidissement Geometric cooling factor in `(0, 1)` (`"recuit"`).
#' @param graine Integer seed for the reproducible order permutations / moves.
#' @param skidding_m Skidding distance (m): a parcel cell within it of a road is
#'   served without building a road.
#' @param volume_champ Optional name of the parcel volume column (for the
#'   `"plus_gros_volume"` base ordering).
#' @param config A `foretaccess_config`; the solver settings live in
#'   `config$desserte$trace`.
#' @return A `foretaccess_reseau` object (same as Lot 16) for the best network
#'   found, enriched with `strategie` and `journal` (total cost per trial).
#' @export
optimiser_reseau <- function(pre, cout, parcelles, desserte_existante,
                             strategie = c("multistart", "recuit", "riprute"),
                             heuristique = c("plus_proche", "plus_gros_volume", "aleatoire"),
                             n_start = 16, n_iter = 200, temp0 = 0,
                             refroidissement = 0.95, graine = 1, skidding_m = 0,
                             volume_champ = NULL, config = foretaccess_config()) {
  strategie <- match.arg(strategie)
  heuristique <- match.arg(heuristique)
  checkmate::assert_count(n_start, positive = TRUE)
  checkmate::assert_count(n_iter, positive = TRUE)
  checkmate::assert_number(refroidissement, lower = 0, upper = 1)
  checkmate::assert_count(graine)
  validate_config(config)

  ctx <- .reseau_preparer(pre, cout, parcelles, desserte_existante, config)

  # Ordre de base (essai 0) selon l'heuristique, comme le glouton du Lot 16.
  parc_ids <- .desserte_cellules_parcelles(parcelles, ctx$grille, volume_champ)
  if (length(parc_ids$cells) == 0) {
    cli::cli_abort("{.arg parcelles} ne couvre aucune cellule de la grille.")
  }
  ordre <- .desserte_ordre(parc_ids, ctx$road_r, heuristique, graine)
  sources0 <- as.integer(parc_ids$cells[ordre] - 1L)

  res <- switch(strategie,
    multistart = .optim_multistart(ctx, sources0, skidding_m, n_start, graine),
    recuit = .optim_recuit(ctx, sources0, skidding_m, n_iter, temp0,
                           refroidissement, graine),
    cli::cli_abort(c(
      "La strategie {.val {strategie}} n'est pas encore disponible.",
      i = "Prevue au Lot 18c ; utiliser {.val multistart} ou {.val recuit}."
    ))
  )

  net <- .reseau_assembler(res$paths, res$costs, ctx, desserte_existante,
                           parcelles, skidding_m, heuristique, "glouton", config)
  net$strategie <- strategie
  net$journal <- res$journal
  net
}

# Multi-start parallele : delegue au noyau Rust (table batie une fois, rayon).
.optim_multistart <- function(ctx, sources0, skidding_m, n_start, graine) {
  r <- do.call(desserte_reseau_multistart, c(
    list(alt = ctx$g$alt, obs = ctx$g$obs, obs2 = ctx$g$obs2,
         local_slope = ctx$g$local_slope, zone = ctx$g$zone,
         nr = ctx$nr, nc = ctx$nc, sources = sources0,
         network0 = as.integer(ctx$net_cells1 - 1L), skidding = skidding_m,
         n_start = as.integer(n_start), seed = graine),
    .desserte_solver_params(ctx$tr, ctx$csize)
  ))
  list(paths = r$paths, costs = r$costs, journal = r$journal, best = r$best)
}

# Recuit simule sur l'ordre : delegue au noyau Rust (table batie une fois).
.optim_recuit <- function(ctx, sources0, skidding_m, n_iter, temp0, cooling, graine) {
  r <- do.call(desserte_reseau_recuit, c(
    list(alt = ctx$g$alt, obs = ctx$g$obs, obs2 = ctx$g$obs2,
         local_slope = ctx$g$local_slope, zone = ctx$g$zone,
         nr = ctx$nr, nc = ctx$nc, sources = sources0,
         network0 = as.integer(ctx$net_cells1 - 1L), skidding = skidding_m,
         n_iter = as.integer(n_iter), t0 = temp0, cooling = cooling, seed = graine),
    .desserte_solver_params(ctx$tr, ctx$csize)
  ))
  list(paths = r$paths, costs = r$costs, journal = r$journal, best = 1L)
}
