# Pondération de pente (facteur d'allongement 3D)

`sqrt(1 + (pente_pct / 100)^2)`. Vaut 1 à pente nulle, `sqrt(2)` à 100
%. Fonction de la pente **absolue** : le coût est isotrope.

## Usage

``` r
ponderation_pente(pente_pct)
```

## Arguments

- pente_pct:

  `SpatRaster` ou vecteur numérique de pentes en pourcentage.

## Value

Objet de même forme que `pente_pct`.

## Examples

``` r
ponderation_pente(c(0, 100))
#> [1] 1.000000 1.414214
```
