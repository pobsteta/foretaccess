# Amorçage `(Th, Tv, faisable)` par recherche sur grille sous la tension admissible. Renvoie un vecteur de longueur 3 ; `faisable` vaut 1 si `sqrt(Th^2 + Tv^2) <= tmax`, 0 sinon.

Amorçage `(Th, Tv, faisable)` par recherche sur grille sous la tension
admissible. Renvoie un vecteur de longueur 3 ; `faisable` vaut 1 si
`sqrt(Th^2 + Tv^2) <= tmax`, 0 sinon.

## Usage

``` r
cable_find_thtv_tmax(tmax, w, eao, f, pas, d, h, lo, step)
```

## Arguments

- tmax:

  Admissible cable tension (N).

- w:

  Weight of the cable over its whole length (N).

- eao:

  Young's modulus times the cable section (N).

- f:

  Gravity force of the load (N).

- pas:

  Arc-length position of the load used for the grid seed (m).

- d:

  Horizontal span between supports (m).

- h:

  Altitude difference between supports (m).

- lo:

  Unstretched cable length over the span (m).

- step:

  Grid step in tension (N).

## Value

A length-3 numeric vector `c(Th, Tv, faisable)`.
