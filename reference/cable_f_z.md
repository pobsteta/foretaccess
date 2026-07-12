# Equation verticale de la caténaire élastique `f_z(Th, Tv)`, nulle à la solution.

Equation verticale de la caténaire élastique `f_z(Th, Tv)`, nulle à la
solution.

## Usage

``` r
cable_f_z(th, tv, lo, eao, w, f, s1, h)
```

## Arguments

- th:

  Horizontal tension component at the upper support (N).

- tv:

  Vertical tension component at the upper support (N).

- lo:

  Unstretched cable length over the span (m).

- eao:

  Young's modulus times the cable section (N).

- w:

  Weight of the cable over its whole length (N).

- f:

  Gravity force of the load (N).

- s1:

  Arc-length position of the load (m).

- h:

  Altitude difference between supports (m).

## Value

The vertical residual (m); zero at the solution.
