# Optimise a road network by simulated annealing on the insertion order (Lot 18b).

Energy is the total network cost; a neighbour swaps two positions in the
order; acceptance is Metropolis (`exp(-delta/T)`) with geometric
cooling. Starts from the base order and returns the best network met, so
never worse than the plain greedy (CA-18.1); reproducible for a fixed
`seed` (CA-18.2). The `journal` is the best-so-far cost per iteration
(monotone decreasing, CA-18.4).

## Usage

``` r
desserte_reseau_recuit(
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
  n_iter,
  t0,
  cooling,
  seed,
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

  Parcel cells to serve, 0-based flattened, in the base order.

- network0:

  Existing-road cells, 0-based flattened.

- skidding:

  Skidding distance (m): a source within it of a road is skipped.

- n_iter:

  Number of annealing iterations.

- t0:

  Initial temperature; if `<= 0`, derived from the base energy.

- cooling:

  Geometric cooling factor (0..1).

- seed:

  Seed for the reproducible neighbour moves and acceptance draws.

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

A list: `paths` (1-based cell-index vectors of the best network),
`costs` (per-road costs of the best network) and `journal` (best-so-far
cost per iteration).
