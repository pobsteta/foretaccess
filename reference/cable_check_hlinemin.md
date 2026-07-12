# Faisabilité complète d'une travée : la charge balaie la longueur, on résout les tensions à chaque position et on mesure la garde au sol. Renvoie la garde minimale rencontrée (m), ou `-1` si la travée est infaisable (garde hors `[hline_min, hline_max]` ou tension au-delà de `tmax + 1000`). Sans supports intermédiaires (Lot 4b).

Faisabilité complète d'une travée : la charge balaie la longueur, on
résout les tensions à chaque position et on mesure la garde au sol.
Renvoie la garde minimale rencontrée (m), ou `-1` si la travée est
infaisable (garde hors `[hline_min, hline_max]` ou tension au-delà de
`tmax + 1000`). Sans supports intermédiaires (Lot 4b).

## Usage

``` r
cable_check_hlinemin(
  alts,
  h_alt,
  d,
  lo,
  fact,
  tho,
  tvo,
  xup,
  zup,
  f_o,
  tmax,
  hline_min,
  hline_max,
  q1,
  q2,
  q3,
  csize,
  eao
)
```

## Arguments

- alts:

  Terrain altitudes under the line, sampled every 0.5 m (m).

- h_alt:

  Altitude difference between supports (m).

- d:

  Horizontal span between supports (m).

- lo:

  Unstretched cable length over the span (m).

- fact:

  Direction of the line (+1 or -1).

- tho:

  Horizontal tension with the load centred (N).

- tvo:

  Vertical tension with the load centred (N).

- xup:

  Horizontal position of the upper support (m).

- zup:

  Altitude of the upper support (m).

- f_o:

  Gravity force of the load and carriage (N).

- tmax:

  Admissible cable tension (N).

- hline_min:

  Minimum ground clearance of the cable (m).

- hline_max:

  Maximum height of the cable (m).

- q1:

  Linear mass of the skyline (kg/m).

- q2:

  Linear mass of the mainline / traction cable (kg/m).

- q3:

  Linear mass of the return cable (kg/m).

- csize:

  Sweep step of the load position (m).

- eao:

  Young's modulus times the cable section (N).

## Value

The minimum ground clearance (m), or `-1` if infeasible.
