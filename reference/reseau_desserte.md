# Design a forest-road network serving several parcels

Builds a road network connecting N parcels to an existing road network,
at minimum cumulated construction cost, by the greedy MTAP heuristic:
parcels are ordered, then each is connected to the current network with
the Lot 15 constrained solver, the new road growing the network for
later parcels (reuse -\> tree). A parcel cell already within
`skidding_m` of a road needs no road.

## Usage

``` r
reseau_desserte(
  pre,
  cout,
  parcelles,
  desserte_existante,
  heuristique = c("plus_proche", "plus_gros_volume", "aleatoire"),
  mode = c("glouton", "steiner"),
  skidding_m = 0,
  volume_champ = NULL,
  config = foretaccess_config(),
  graine = NULL
)
```

## Arguments

- pre:

  A `foretaccess_preprocessing` object (DEM, terrain slope).

- cout:

  A `foretaccess_cout_construction` object (Lot 14): crossability.

- parcelles:

  An `sf` POLYGON of the areas to serve.

- desserte_existante:

  An `sf` LINESTRING of the network to connect to.

- heuristique:

  Ordering of parcels: `"plus_proche"` (closest first),
  `"plus_gros_volume"` (largest volume first) or `"aleatoire"` (random).

- mode:

  Construction mode: `"glouton"` (greedy MTAP-\>STAP, default) or
  `"steiner"` (minimum-spanning-tree approximation over the terminals, a
  quality alternative at the cost of N^2 traces).

- skidding_m:

  Skidding distance (m): a parcel cell within it of a road is served
  without building a road.

- volume_champ:

  Optional name of the parcel volume column (for `"plus_gros_volume"`);
  each cell inherits its parcel volume.

- config:

  A `foretaccess_config`; the solver settings live in
  `config$desserte$trace`.

- graine:

  Optional integer seed for the `"aleatoire"` ordering.

## Value

A `foretaccess_reseau` object: `lignes` (an `sf` LINESTRING of the
created roads, one feature per road, with creation `ordre`, `cout` and
planimetric `longueur` in m), `reseau` (a `SpatRaster` of the whole
network, for Lot 17), `desserte` (the existing network, kept for the Lot
17 graph), `cout` (total), `connexe` (a single connected component,
CA-16.5), `desservies` (a logical, one per parcel, CA-16.1) and the
recall of the `mode` and `heuristique`.
