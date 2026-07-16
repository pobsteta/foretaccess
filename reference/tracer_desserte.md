# Design the optimal route of a new forest road

Traces the least-cost road from a start point to an end point (through
optional mandatory waypoints) over the construction-cost surface (Lot
14), honouring road geometry constraints — bounded longitudinal grade,
smooth turns, minimum turning radius, controlled hairpins,
terrain-compatible profile. Thin R wrapper around the Rust A\\ solver
(`desserte_trace`, spec 015): R flattens the DEM, crossability and
terrain slope, calls the solver and rebuilds the polyline.

## Usage

``` r
tracer_desserte(pre, cout, waypoints, config = foretaccess_config())
```

## Arguments

- pre:

  A `foretaccess_preprocessing` object (DEM, terrain slope).

- cout:

  A `foretaccess_cout_construction` object (Lot 14): supplies the
  crossability mask (`franchissable`).

- waypoints:

  Ordered points the road must visit (start first, end last; at least
  two). An `sf`/`SpatVector` of points, a two-column matrix of
  coordinates, or a vector of raster cell numbers (1-based).

- config:

  A `foretaccess_config`; the solver settings live in
  `config$desserte$trace`.

## Value

A `foretaccess_trace` object: a list with `ligne` (an `sf` LINESTRING of
the route), `cout` (total cost), `faisable` (did every segment reach its
target), `waypoints` (the cell numbers) and the `config`.
