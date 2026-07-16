# Optimise a road network by multi-start over insertion orders (Lot 18a).

Runs the greedy MTAP builder under `n_start` insertion orders and keeps
the cheapest network. Trial 0 is the caller-provided base order, so the
result is never worse than the plain greedy of Lot 16 (CA-18.1). Trials
1.. are reproducible Fisher-Yates permutations seeded by `seed`
(CA-18.2). The neighbourhood table is built once and shared; trials run
in parallel (`rayon`).

## Usage

``` r
desserte_reseau_multistart(
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
  n_start,
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

- n_start:

  Number of insertion orders to try (\>= 1).

- seed:

  Seed for the reproducible order permutations.

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
`costs` (per-road costs of the best network), `best` (1-based index of
the best trial) and `journal` (total cost of every trial).
