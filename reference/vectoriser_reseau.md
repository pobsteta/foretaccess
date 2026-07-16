# Vectorise a forest-road network into a topological graph

Turns the raster/polyline network of a `foretaccess_reseau` (Lot 16)
into a clean node/edge graph: raster cells are canonical node ids
(shared cells -\> shared nodes), fine segments are contracted along
degree-2 chains into `troncons` (edges) between the remarkable nodes
(outlets, junctions of degree= 3, leaves of degree 1). This is the graph
the wood-flux (Lot 17b) and roadtyping (Lot 17c) operate on.

## Usage

``` r
vectoriser_reseau(reseau)
```

## Arguments

- reseau:

  A `foretaccess_reseau` object (Lot 16).

## Value

A `foretaccess_reseau_graphe` object: `noeuds` (an `sf` POINT with `id`,
`cell`, `degre`, `type` in outlet/junction/leaf), `troncons` (an `sf`
LINESTRING with `id`, `de`, `vers` node ids and `longueur` in m),
`exutoires` (outlet node ids) and the recall of the grid.
