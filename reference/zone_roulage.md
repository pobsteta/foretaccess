# Zone de roulage du skidder

Cellules où l'engin peut circuler : forêt, pente sous le seuil skidder,
hors obstacles complets **et** hors obstacles partiels. Reproduit
`zone_rast[Partial_Obstacles_skidder == 1] <- 0` de Sylvaccess.

## Usage

``` r
zone_roulage(pre, config = foretaccess_config())
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un `SpatRaster` logique (1 = roulable).

## Details

Les obstacles **partiels** bloquent le roulage mais **pas** le
treuillage : on peut treuiller par-dessus, pas rouler dessus (spec 002
§10.4).
