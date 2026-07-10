# Zone effectivement roulable, connectée à la desserte

Reproduit la construction de `Pente_ok_skidder`
(`Sylvaccess_1_skidder.py`, §« Calculation of skidding distance inside
the forest stands »), en trois temps :

## Usage

``` r
zone_roulable_connectee(pre, config = foretaccess_config())
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un `SpatRaster` logique (1 = roulable et connecté à la desserte).

## Details

1.  la **forêt roulable** atteinte depuis la desserte, sans limite de
    distance ;

2.  une extension de `distance_hors_desserte_max_m` (défaut 50 m) **hors
    forêt**, sur du terrain roulable — le skidder peut couper par une
    prairie ;

3.  le **recollement** de la forêt roulable ainsi rendue accessible.

`distance_hors_desserte_max_m` n'est donc **pas** un plafond sur la
distance de débardage : c'est la distance maximale parcourable hors
forêt et hors desserte.

Les sources de chaque étape sont la zone entière atteinte à l'étape
précédente, et non son seul contour : les cellules intérieures, à coût
nul, sont dominées — le résultat est identique, sans calcul de contour.
