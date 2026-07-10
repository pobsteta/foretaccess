# Distance maximale de treuillage admissible

La « loi de bascule » de Sylvaccess v3.6. Contrairement à ce que suggère
la documentation, ce **n'est pas** une fonction affine de la pente :
c'est une fonction affine du **dénivelé**, calibrée sur deux points
d'ancrage. Exprimée en fonction de la pente signée `s` du rayon desserte
→ pixel, elle devient :

## Usage

``` r
distance_treuillage_max(pente, config = foretaccess_config())
```

## Arguments

- pente:

  Pente **signée** du rayon (rapport, non pourcentage) : positive en
  amont (le pixel est plus haut que la desserte), négative en aval.

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un vecteur de distances maximales admissibles, en mètres.

## Details

\$\$D\_{max}(s) = \frac{orig}{1 - coeff \cdot s / \sqrt{1 + s^2}}\$\$

bornée par `debardage_aval_max_m` en aval et `debardage_amont_max_m` en
amont.

Avec les défauts v3.6 (50 m amont, 100 m aval, bascules 75 % et 20 %) :
`coeff = -1,007829` et `orig = 80,2349 m`. **À plat, la distance
admissible vaut donc 80,23 m** — ni 50, ni 100. Une interpolation
linéaire en pente, l'hypothèse naturelle, donnerait 50 m à 30 % au lieu
de 62 m.

Source : `Sylvaccess_1_skidder.py:336-370` et
`sylvaccess_cython3.pyx:3164`.

## Examples

``` r
distance_treuillage_max(c(-0.5, 0, 0.3, 1))
#> [1] 100.00000  80.23486  62.21698  50.00000
```
