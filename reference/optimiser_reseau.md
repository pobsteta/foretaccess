# Optimise a forest-road network over insertion orders

Wraps the Lot 16 greedy builder in an optimisation layer that explores
the space of parcel insertion orders and keeps the cheapest network. The
greedy order is always trial 0, so the result is never worse than the
plain greedy of
[`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md)
(CA-18.1). Currently the `"multistart"` strategy is available (parallel
over K perturbed orders, `rayon`); `"recuit"` (simulated annealing) and
`"riprute"` (rip-up & reroute) are planned (Lot 18b/18c).

## Usage

``` r
optimiser_reseau(
  pre,
  cout,
  parcelles,
  desserte_existante,
  strategie = c("multistart", "recuit", "riprute"),
  heuristique = c("plus_proche", "plus_gros_volume", "aleatoire"),
  n_start = 16,
  n_iter = 200,
  temp0 = 0,
  refroidissement = 0.95,
  max_passes = 6,
  graine = 1,
  skidding_m = 0,
  volume_champ = NULL,
  pondere_cout = FALSE,
  config = foretaccess_config()
)
```

## Arguments

- pre:

  A `foretaccess_preprocessing` object (DEM, terrain slope).

- cout:

  A `foretaccess_cout_construction` object (Lot 14).

- parcelles:

  An `sf` POLYGON of the areas to serve.

- desserte_existante:

  An `sf` LINESTRING of the network to connect to.

- strategie:

  Optimisation strategy: `"multistart"` (default), `"recuit"` (simulated
  annealing on the insertion order) or `"riprute"` (rip-up & reroute
  local search).

- heuristique:

  Base ordering of parcels (trial 0), see
  [`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md).

- n_start:

  Number of insertion orders to try (`"multistart"`).

- n_iter:

  Number of annealing iterations (`"recuit"`).

- temp0:

  Initial annealing temperature (`"recuit"`); `<= 0` derives it from the
  base network cost.

- refroidissement:

  Geometric cooling factor in `(0, 1)` (`"recuit"`).

- max_passes:

  Maximum improvement passes (`"riprute"`).

- graine:

  Integer seed for the reproducible order permutations / moves.

- skidding_m:

  Skidding distance (m): a parcel cell within it of a road is served
  without building a road.

- volume_champ:

  Optional name of the parcel volume column (for the
  `"plus_gros_volume"` base ordering).

- pondere_cout:

  If `TRUE`, weights the trace by the Lot 14 construction cost surface
  (`cout$cout`, euros/m) instead of geometric distance.

- config:

  A `foretaccess_config`; the solver settings live in
  `config$desserte$trace`.

## Value

A `foretaccess_reseau` object (same as Lot 16) for the best network
found, enriched with `strategie` and `journal` (total cost per trial).

## Performance

Each trial is a full greedy build reusing a **single** neighbourhood
table and running the trials in **parallel** (`rayon`). Since the greedy
trace was made corridor-bounded (see
[`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md)
*Performance*), the optimisers are now tractable at interactive scale:
on a departmental run, `n_start = 16` costs about the same wall-clock as
one greedy build. Reasonable exposable defaults: `n_start` 8-32,
`n_iter` 100-300 – no hard cap is needed below those. The dominant lever
remains **`skidding_m`** (set it to the real skidding distance; see
[`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md)),
which governs the number of traces per build.
