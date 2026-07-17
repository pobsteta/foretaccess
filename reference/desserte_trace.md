# Trace a forest road through mandatory waypoints (road-design A\\ solver, Lot 15b).

Ports SylvaRoad's `Astar_force_wp`: A\\ on the disc-neighbourhood graph,
with geometric transition cost plus parabolic direction/slope penalties,
hairpin handling (turning `radius`, limit angle), longitudinal-profile
control (`check_profile`) and self-intersection avoidance (spec 015 Sec.
4). The neighbourhood table is (re)built internally from the DEM and
obstacle mask.

## Usage

``` r
desserte_trace(
  alt,
  obs,
  obs2,
  local_slope,
  zone,
  nr,
  nc,
  waypoints,
  bufgoal,
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

  Obstacle mask (1 = blocked / non-crossable), row-major.

- obs2:

  Excess cross-slope mask (1 = terrain slope over `trans_slope_all`).

- local_slope:

  Fraction (0..1) of the neighbourhood with steep cross-slope.

- zone:

  Passable mask (1 = passable) for the inverse-distance heuristic.

- nr:

  Number of raster rows.

- nc:

  Number of raster columns.

- waypoints:

  0-based flattened cell indices to visit, in order.

- bufgoal:

  Finish tolerance around the final goal (m).

- csize:

  Cell size (m).

- min_slope:

  Minimum road grade (percent).

- max_slope:

  Maximum road grade (percent).

- penalty_xy:

  Turn (direction-change) penalty (m per 180 deg).

- penalty_z:

  Slope-change ("wave") penalty.

- max_diff_z:

  Max elevation gap between road and terrain (m).

- d_neighborhood:

  Neighbourhood radius (m).

- angle_hairpin:

  Angle above which a turn is a hairpin (deg).

- lmax_ab_sl:

  Max road length with excess cross-slope (m).

- radius:

  Turning radius for trucks (m).

- prop_sl_max:

  Max local steep-cross-slope fraction at a hairpin.

- max_slope_hairpin:

  Slope tolerance parameter for the hairpin limit angle.

- tal:

  Hairpin limit-angle tuning parameter.

- modhair:

  Minimum-spacing-between-hairpins parameter.

- cost:

  Construction cost per metre (euros/m) per cell (row-major); `1.0`
  everywhere = neutral (pure geometry).

## Value

A list: `path` (1-based flattened cell indices), `cost`, `feasible`.

## Details

All grids are row-major and flattened; `waypoints` are 0-based flattened
cell indices (\>= 2), the first the origin and the last the final goal.
