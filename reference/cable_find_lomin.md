# Cherche la longueur à vide minimale `Lo` telle que la tension du câble, la charge au milieu, atteigne `tmax`, puis vérifie la garde au sol sur toute la travée. Renvoie un vecteur `c(faisable, Lo, Th, Tv, Tcalc, F)` ; `faisable` vaut 1 ou 0. Sans supports intermédiaires (Lot 4c).

Amorçage substitué aux tables Sylvaccess
(`(Th, Tv) = (0.9*tmax, 0.1*tmax)`, `Lo = corde + réserve`) : choix de
performance, pas de correction.

## Usage

``` r
cable_find_lomin(
  d,
  h,
  xup,
  zup,
  fact,
  alts,
  f_o,
  tmax,
  q1,
  q2,
  q3,
  eao,
  hline_min,
  hline_max,
  csize
)
```

## Arguments

- d:

  Horizontal span between supports (m).

- h:

  Altitude difference between supports (m).

- xup:

  Horizontal position of the upper support (m).

- zup:

  Altitude of the upper support (m).

- fact:

  Direction of the line (+1 or -1).

- alts:

  Terrain altitudes under the line, sampled every 0.5 m (m).

- f_o:

  Gravity force of the load and carriage (N).

- tmax:

  Admissible cable tension (N).

- q1:

  Linear mass of the skyline (kg/m).

- q2:

  Linear mass of the mainline / traction cable (kg/m).

- q3:

  Linear mass of the return cable (kg/m).

- eao:

  Young's modulus times the cable section (N).

- hline_min:

  Minimum ground clearance of the cable (m).

- hline_max:

  Maximum height of the cable (m).

- csize:

  Sweep step of the load position (m).

## Value

A length-6 numeric vector `c(faisable, Lo, Th, Tv, Tcalc, F)`.
