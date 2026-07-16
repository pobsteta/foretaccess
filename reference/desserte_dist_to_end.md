# Inverse cost-distance from a target cell (road-design A\\ heuristic, Lot 15a).

Ports SylvaRoad's `calcul_distance_de_cout`: geometric 8-neighbour
distance (step = resolution, or `resolution * sqrt(2)` on the diagonal)
propagated from the target over the passable zone (`zone == 1`). The
step cost is unit (distance only), so the result is a lower bound of the
remaining road cost — an admissible A\\ heuristic (spec 015, CA-15.8).

## Usage

``` r
desserte_dist_to_end(zone, nr, nc, csize, y_end, x_end, max_distance)
```

## Arguments

- zone:

  Passable mask (1 = passable, 0 = blocked), row-major.

- nr:

  Number of raster rows.

- nc:

  Number of raster columns.

- csize:

  Cell size (m); square cells assumed.

- y_end:

  Target row (0-based).

- x_end:

  Target column (0-based).

- max_distance:

  Propagation ceiling (m); cells beyond it stay `NA`.

## Value

A row-major numeric vector: 0 at the target, cumulated distance
elsewhere, `NA` for unreached cells.
