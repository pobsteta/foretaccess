# Optimise a road network by rip-up & reroute local search (Lot 18c).

Starts from the greedy network, then repeatedly removes each road and
reroutes its source against the rest of the network; a move is kept only
if it lowers the total cost and leaves every source connected. Never
worse than the greedy start (CA-18.1); the `journal` (total cost per
pass) is monotone decreasing (CA-18.4).

## Usage

``` r
desserte_reseau_riprute(
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
  max_pass,
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
  modhair,
  cost
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

- max_pass:

  Maximum number of improvement passes.

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

- cost:

  Construction cost per metre (euros/m) per cell (row-major); `1.0`
  everywhere = neutral (pure geometry).

## Value

A list: `paths` (1-based cell-index vectors of the improved network),
`costs` (per-road costs) and `journal` (total cost after each pass).
