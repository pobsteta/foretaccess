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
  pondere_cout = FALSE,
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

- pondere_cout:

  If `TRUE`, weights the trace by the Lot 14 construction cost surface
  (`cout$cout`, euros/m) instead of pure geometric distance; the trace
  then minimises monetary cost. Default `FALSE` (SylvaRoad behaviour).

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
17 graph), `cout` (total), `connexe` and `raccorde` (two connectivity
flags, see *Connectivity* below), `desservies` (a logical, one per
parcel, CA-16.1) and the recall of the `mode` and `heuristique`.

## Connectivity

Two booleans, with **different** meanings – read the right one:

- **`connexe`** – does the *whole* raster network (existing roads +
  created roads) form a **single** 8-connected component (CA-16.5)? This
  is dominated by the **existing** network's own fragmentation: a real
  reference network is thousands of segments that do not touch at grid
  resolution, so `connexe` is almost always `FALSE` on real data. **A
  `FALSE` here does *not* mean a created road dangles** – it usually
  just reflects a fragmented input.

- **`raccorde`** – do the created roads add **no new** connected
  component relative to the existing network alone? `TRUE` iff every
  created road attaches to the existing network (directly or through
  another created road); a road left dangling would raise the component
  count. This is the flag that answers *"is every road I built actually
  connected?"* – the one to surface as a quality badge, not `connexe`.
