# Balayage 360 deg / pixel du potentiel câble (0 support), porté en Rust.

Pour chaque cellule de desserte et chacun des 360 azimuts, extrait le
profil d'altitude, cherche la plus longue travée faisable
([`cable_test_span()`](https://pobsteta.github.io/foretaccess/reference/cable_test_span.md))
et accumule couverture et lignes candidates. Parallèle (`rayon`) sur les
départs ; réduction fidèle au balayage R (mêmes départ/azimut/longueur).

## Usage

``` r
cable_scan(
  alt,
  nr,
  nc,
  res,
  foret,
  routes,
  vol,
  has_vol,
  htower,
  h_end,
  hline_min,
  hline_max,
  slope_min,
  slope_max,
  slope_min_aval,
  slope_max_aval,
  f_o,
  tmax,
  q1,
  q2,
  q3,
  eao,
  angle_intsup,
  lmax,
  lmin,
  hintsup,
  sup_max,
  lmin_span,
  nbconfig,
  pas_azimut,
  pas_depart,
  aspect,
  pente,
  lsans_foret,
  angle_transv,
  slope_trans,
  l_slope,
  prop_slope,
  l_hor,
  optim_h,
  methode_seilaplan,
  hm_min,
  hm_max,
  hm_delta,
  min_dist_mast,
  n_sk
)
```

## Arguments

- alt:

  Elevation values (row-major, NA as NaN).

- nr:

  Number of raster rows.

- nc:

  Number of raster columns.

- res:

  Cell size (m); square cells assumed.

- foret:

  Forest mask (1 = forest), row-major.

- routes:

  Desserte cell indices (1-based) used as line starts.

- vol:

  Volume per cell (row-major); ignored when `has_vol` is false.

- has_vol:

  Whether `vol` carries usable volume data.

- htower:

  Start-support height (m).

- h_end:

  Terminal-support height (m).

- hline_min:

  Minimum ground clearance of the carrying cable (m).

- hline_max:

  Maximum ground clearance of the carrying cable (m).

- slope_min:

  Minimum line slope, uphill yarding (rad).

- slope_max:

  Maximum line slope, uphill yarding (rad).

- slope_min_aval:

  Minimum line slope, downhill yarding (rad).

- slope_max_aval:

  Maximum line slope, downhill yarding (rad).

- f_o:

  Gravity force of load plus carriage (N).

- tmax:

  Maximum allowable tension (N).

- q1:

  Linear mass of the carrying cable (kg/m).

- q2:

  Linear mass of the hauling cable (kg/m).

- q3:

  Linear mass of the return cable (kg/m).

- eao:

  Young's modulus times cable section (N).

- angle_intsup:

  Inter-support angle constraint (rad).

- lmax:

  Maximum line length (m).

- lmin:

  Minimum line length (m).

- hintsup:

  Attachment height on an intermediate support (m).

- sup_max:

  Maximum number of intermediate supports.

- lmin_span:

  Minimum distance between two supports (m).

- nbconfig:

  Beam width of the support-placement search.

- pas_azimut:

  Azimuth step of the sweep (degrees).

- pas_depart:

  Sample every `pas_depart`-th departure cell.

- aspect:

  Terrain aspect (degrees, NaN on flats), row-major.

- pente:

  Terrain slope (percent), row-major.

- lsans_foret:

  Longest stretch a line may cross outside the forest (m).

- angle_transv:

  Minimum angle to the contour line (degrees).

- slope_trans:

  Terrain slope above which a cross-slope stretch counts (percent).

- l_slope:

  Maximum cumulated length on a steep cross-slope (m).

- prop_slope:

  Maximum share of the line on a steep cross-slope.

- l_hor:

  Lateral yarding half-width buffered around each line (m).

- optim_h:

  Optimise the attachment height on each support (`c_option_h`).

- methode_seilaplan:

  Place supports with the SEILAPLAN graph (Bont & Heinimann 2012)
  instead of Sylvaccess `OptPyl_NoH` (spec 013). Optimises both support
  position and height.

- hm_min:

  Lowest intermediate-support height level (m), SEILAPLAN only.

- hm_max:

  Highest intermediate-support height level (m), SEILAPLAN only.

- hm_delta:

  Height step between levels (m), SEILAPLAN only.

- min_dist_mast:

  Minimum horizontal spacing between supports (m), SEILAPLAN only.

- n_sk:

  Number of pre-tension steps swept by the graph, SEILAPLAN only.

## Value

A list: `couvert`, `longueur`, `azimut` (per cell) and the candidate
line vectors `li_dep`, `li_az`, `li_lg`, `li_surf`, `li_sens`, `li_vol`,
`li_ipc`, `li_nsup`.
