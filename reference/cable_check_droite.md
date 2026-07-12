# Pré-filtre géométrique : le câble est approximé par la corde entre supports moins une flèche analytique. Renvoie 1 si le profil `(line_x, line_z)` reste dans les gardes entre les indices `pg+1` et `pd-1`, 0 sinon. Sans supports intermédiaires (Lot 4b).

Pré-filtre géométrique : le câble est approximé par la corde entre
supports moins une flèche analytique. Renvoie 1 si le profil
`(line_x, line_z)` reste dans les gardes entre les indices `pg+1` et
`pd-1`, 0 sinon. Sans supports intermédiaires (Lot 4b).

## Usage

``` r
cable_check_droite(
  fact,
  h_alt,
  d,
  xup,
  zup,
  line_x,
  line_z,
  hline_min,
  hline_max,
  tmax,
  q1,
  q2,
  q3,
  f_o,
  pg,
  pd
)
```

## Arguments

- fact:

  Direction of the line (+1 or -1).

- h_alt:

  Altitude difference between supports (m).

- d:

  Horizontal span between supports (m).

- xup:

  Horizontal position of the upper support (m).

- zup:

  Altitude of the upper support (m).

- line_x:

  Horizontal positions along the terrain profile (m).

- line_z:

  Altitudes of the terrain profile (m).

- hline_min:

  Minimum ground clearance of the cable (m).

- hline_max:

  Maximum height of the cable (m).

- tmax:

  Admissible cable tension (N).

- q1:

  Linear mass of the skyline (kg/m).

- q2:

  Linear mass of the mainline / traction cable (kg/m).

- q3:

  Linear mass of the return cable (kg/m).

- f_o:

  Gravity force of the load and carriage (N).

- pg:

  Index of the near support in the profile.

- pd:

  Index of the far support in the profile.

## Value

1 if the span passes the pre-filter, 0 otherwise.
