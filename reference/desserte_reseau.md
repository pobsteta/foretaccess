# Build a forest-road network serving ordered parcel cells (greedy MTAP, Lot 16a).

Ports ForestRoadNetwork's greedy MTAP-\>STAP loop: each source cell (in
the caller-provided heuristic order) is connected to the current network
with the Lot 15 constrained solver, and the created road grows the
network for later sources (reuse -\> tree). A source already within
`skidding` metres of a road is skipped. The neighbourhood table is built
once. All grids are row-major and flattened; cell indices are 0-based on
input, 1-based on output.

## Usage

``` r
desserte_reseau(
  alt,
  obs,
  obs2,
  local_slope,
  zone,
  nr,
  nc,
  sources,
  network0,
  skidding,
  csize,
  min_slope,
  max_slope,
  penalty_xy,
  penalty_z,
  max_diff_z,
  d_neighborhood,
  angle_hairpin,
  lmax_ab_sl,
  radius,
  prop_sl_max,
  max_slope_hairpin,
  tal,
  modhair
)
```

## Arguments

- alt:

  Elevation values (row-major, m).

- obs:

  Obstacle mask (1 = blocked), row-major.

- obs2:

  Excess cross-slope mask, row-major.

- local_slope:

  Fraction (0..1) of the neighbourhood with steep cross-slope.

- zone:

  Passable mask (1 = passable), row-major.

- nr:

  Number of raster rows.

- nc:

  Number of raster columns.

- sources:

  Parcel cells to serve, 0-based flattened, in heuristic order.

- network0:

  Existing-road cells, 0-based flattened.

- skidding:

  Skidding distance (m): a source within it of a road is skipped.

- csize:

  Cell size (m).

- min_slope:

  Minimum road grade (percent).

- max_slope:

  Maximum road grade (percent).

- penalty_xy:

  Turn penalty.

- penalty_z:

  Slope-change penalty.

- max_diff_z:

  Max elevation gap road/terrain (m).

- d_neighborhood:

  Neighbourhood radius (m).

- angle_hairpin:

  Hairpin angle threshold (deg).

- lmax_ab_sl:

  Max road length with excess cross-slope (m).

- radius:

  Turning radius (m).

- prop_sl_max:

  Max local steep-cross-slope fraction at a hairpin.

- max_slope_hairpin:

  Hairpin limit-angle parameter.

- tal:

  Hairpin limit-angle parameter.

- modhair:

  Hairpin spacing parameter.

## Value

A list: `paths` (a list of 1-based cell-index vectors, one per built
road) and `costs` (one cost per built road).
