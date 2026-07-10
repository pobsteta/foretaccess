# Terrain roulable, indépendamment de la forêt

Cellules dont la pente est sous le seuil skidder et qui ne portent pas
d'obstacle. Reproduit `Pente_ok_skid` de Sylvaccess : à la différence de
[`zone_roulage()`](https://pobsteta.github.io/foretaccess/reference/zone_roulage.md),
la forêt n'entre **pas** dans le critère — le skidder peut traverser du
non-forestier (voir
[`zone_roulable_connectee()`](https://pobsteta.github.io/foretaccess/reference/zone_roulable_connectee.md)).

## Usage

``` r
terrain_roulable(pre, config = foretaccess_config())
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un `SpatRaster` logique (1 = terrain roulable).
