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
  f_o,
  tmax,
  q1,
  q2,
  q3,
  eao,
  angle_intsup,
  lmax,
  lmin
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

  Minimum line slope (rad).

- slope_max:

  Maximum line slope (rad).

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

## Value

A list: `couvert`, `longueur`, `azimut` (per cell) and the candidate
line vectors `li_dep`, `li_az`, `li_lg`, `li_surf`, `li_sens`, `li_vol`,
`li_ipc`.
