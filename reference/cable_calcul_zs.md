# Position verticale (chute depuis le support haut) à l'abscisse curviligne `s` : c'est elle qui fournit la garde au sol du câble.

Position verticale (chute depuis le support haut) à l'abscisse
curviligne `s` : c'est elle qui fournit la garde au sol du câble.

## Usage

``` r
cable_calcul_zs(th, tv, lo, eao, w, f, s1, s)
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

- s:

  Arc-length position at which the cable is evaluated (m).

## Value

The vertical drop of the cable below the upper support at `s` (m).
