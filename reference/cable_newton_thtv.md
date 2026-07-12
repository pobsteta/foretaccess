# Résout `f_x = f_z = 0` (tensions `Th, Tv` au support haut) par Newton-Raphson à Jacobien analytique, repli sur grille. Renvoie un vecteur `c(Th, Tv)`.

Résout `f_x = f_z = 0` (tensions `Th, Tv` au support haut) par
Newton-Raphson à Jacobien analytique, repli sur grille. Renvoie un
vecteur `c(Th, Tv)`.

## Usage

``` r
cable_newton_thtv(th, tv, h_alt, d, lo, w, s1, f, eao, tmax, err)
```

## Arguments

- th:

  Initial guess for the horizontal tension component (N).

- tv:

  Initial guess for the vertical tension component (N).

- h_alt:

  Altitude difference between supports (m).

- d:

  Horizontal span between supports (m).

- lo:

  Unstretched cable length over the span (m).

- w:

  Weight of the cable over its whole length (N).

- s1:

  Arc-length position of the load (m).

- f:

  Gravity force of the load (N).

- eao:

  Young's modulus times the cable section (N).

- tmax:

  Admissible cable tension (N), bounding the grid fallback.

- err:

  Tolerance on the Newton step (N).

## Value

A length-2 numeric vector `c(Th, Tv)`.
