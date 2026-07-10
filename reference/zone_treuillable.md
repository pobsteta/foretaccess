# Zone treuillable

Cellules atteignables au treuil : forêt, hors obstacles complets, et
pente sous le seuil d'abattage manuel. Reproduit `Zone_OK` de
Sylvaccess. Les obstacles **partiels** n'y figurent pas (voir
[`zone_roulage()`](https://pobsteta.github.io/foretaccess/reference/zone_roulage.md)).

## Usage

``` r
zone_treuillable(pre, config = foretaccess_config())
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un `SpatRaster` logique (1 = treuillable).
