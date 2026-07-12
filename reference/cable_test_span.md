# Teste un segment de câble entre les points `pg` et `posi` du profil, portant des supports de hauteurs `hg` et `hd` : pré-filtre, pente dans `[slope_min, slope_max]`, contrainte d'angle au support intermédiaire (`angle_intsup`) vis-à-vis du segment précédent (`slope_prev`, `-9999` si aucun), puis `find_lomin`. Renvoie un vecteur `c(faisable, D, H, diag, slope, fact, Xup, Zup, Lo, Th, Tv, Tcalc, F)`.

Teste un segment de câble entre les points `pg` et `posi` du profil,
portant des supports de hauteurs `hg` et `hd` : pré-filtre, pente dans
`[slope_min, slope_max]`, contrainte d'angle au support intermédiaire
(`angle_intsup`) vis-à-vis du segment précédent (`slope_prev`, `-9999`
si aucun), puis `find_lomin`. Renvoie un vecteur
`c(faisable, D, H, diag, slope, fact, Xup, Zup, Lo, Th, Tv, Tcalc, F)`.

## Usage

``` r
cable_test_span(
  line_x,
  line_z,
  pg,
  posi,
  hg,
  hd,
  hline_min,
  hline_max,
  slope_min,
  slope_max,
  alts,
  f_o,
  tmax,
  q1,
  q2,
  q3,
  eao,
  csize,
  angle_intsup,
  dsupdep,
  slope_prev
)
```

## Arguments

- line_x:

  Horizontal positions along the terrain profile (m).

- line_z:

  Terrain altitudes along the profile (m).

- pg:

  Index of the near support in the profile.

- posi:

  Index of the far support in the profile.

- hg:

  Height of the near support (m).

- hd:

  Height of the far support (m).

- hline_min:

  Minimum ground clearance of the cable (m).

- hline_max:

  Maximum height of the cable (m).

- slope_min:

  Minimum admissible slope of the span (rad).

- slope_max:

  Maximum admissible slope of the span (rad).

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

- csize:

  Sweep step of the load position (m).

- angle_intsup:

  Maximum slope change allowed at an intermediate support (rad).

- dsupdep:

  Extra cable length on the departure side (m).

- slope_prev:

  Slope of the previous span (rad), or -9999 if none.

## Value

A length-13 numeric vector (see the description for the fields).
