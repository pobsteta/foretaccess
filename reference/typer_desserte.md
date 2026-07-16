# Type a road network by wood flux

Ports ForestRoadNetwork's "Road Type Determination": each tronçon is
placed in a road class by flux thresholds (high flux -\> primary, ... ,
low -\> tertiary). Optionally, a share of a class's length is converted
to temporary/winter roads, preferentially inside dedicated zones.

## Usage

``` r
typer_desserte(graphe, seuils_flux, conversion_temporaire = NULL)
```

## Arguments

- graphe:

  A `foretaccess_reseau_graphe` carrying a `flux` column on its
  `troncons` (run
  [`calculer_flux()`](https://pobsteta.github.io/foretaccess/reference/calculer_flux.md)
  first).

- seuils_flux:

  A named, ascending numeric vector of class lower bounds, e.g.
  `c(tertiaire = 0, secondaire = 100, primaire = 500)`. Each tronçon is
  assigned the highest class whose bound it reaches.

- conversion_temporaire:

  Optional list to convert part of a class into temporary roads: `type`
  (source class), `proportion` (0..1 of that class's length), `cible`
  (target label, default `"temporaire"`) and optional `zones` (an `sf`
  of preferential areas).

## Value

A `foretaccess_desserte_typee` object: `troncons` (`sf` with a `type`
column), `noeuds`, `sources` (if any), `recap` (length per type) and the
recall of `seuils_flux`.
