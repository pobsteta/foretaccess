# Zone plate effectivement conduisible, connectée à la desserte

Analogue porteur de
[`zone_roulable_connectee()`](https://pobsteta.github.io/foretaccess/reference/zone_roulable_connectee.md),
et fidèle à la construction de `Pente_ok_forwarder`
(`Sylvaccess_3_forwarder.py`, §« Calculation of skidding distance inside
the forest stands ») : mêmes trois temps, sur le
[`terrain_plat()`](https://pobsteta.github.io/foretaccess/reference/terrain_plat.md)
et avec le saut hors forêt du porteur (`f_dmax_outfor`, défaut 200 m).

## Usage

``` r
zone_plate_connectee(pre, config = foretaccess_config())
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un `SpatRaster` logique (1 = plat et connecté à la desserte).

## Details

C'est la zone sur laquelle le porteur **roule** en plus court chemin, et
donc celle qui contourne obstacles et ravins. Sans elle, la zone
conduite se réduit aux rayons du balayage : une étoile, au périmètre
démesuré — que le grappin gonfle ensuite d'un halo tout autour (mesuré
sur ColduPre : 11 119 cellules de grappin pour 14 000 conduites, ratio
impossible pour une région compacte).
