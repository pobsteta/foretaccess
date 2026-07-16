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
  graine = 1,
  skidding_m = 0,
  volume_champ = NULL,
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

  Optimisation strategy: `"multistart"` (default).

- heuristique:

  Base ordering of parcels (trial 0), see
  [`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md).

- n_start:

  Number of insertion orders to try (multi-start).

- graine:

  Integer seed for the reproducible order permutations.

- skidding_m:

  Skidding distance (m): a parcel cell within it of a road is served
  without building a road.

- volume_champ:

  Optional name of the parcel volume column (for the
  `"plus_gros_volume"` base ordering).

- config:

  A `foretaccess_config`; the solver settings live in
  `config$desserte$trace`.

## Value

A `foretaccess_reseau` object (same as Lot 16) for the best network
found, enriched with `strategie` and `journal` (total cost per trial).
