# Accumulate wood flux over a road-network graph

Ports ForestRoadNetwork's "Wood Flux Determination": source points are
seeded in each harvested parcel (at least one per parcel, whatever the
density), each injects its share of the parcel volume, and the volume
flows down the network along the least-cost path to the nearest outlet,
accumulating on every tronçon it crosses. As the network is a tree
rooted on the existing roads, that path is unique and the accumulation
is a subtree sum.

## Usage

``` r
calculer_flux(graphe, parcelles, volume_champ = "volume", densite_sources = 5)
```

## Arguments

- graphe:

  A `foretaccess_reseau_graphe` (Lot 17a).

- parcelles:

  An `sf` POLYGON of the harvested parcels, carrying a volume.

- volume_champ:

  Name of the parcel volume column (default `"volume"`).

- densite_sources:

  Source points per hectare (default 5); at least one point is seeded
  per parcel regardless.

## Value

The `graphe` with a `flux` column added to `troncons` (accumulated
volume) and a `sources` `sf` POINT (seeded points with their `volume`).
