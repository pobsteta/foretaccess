# Classify skidding distance into Sylvaccess distance bands

Turns the continuous skidding distance (`sk$distance_debardage`) into
the categorical **"skidding distance classes"** raster that Sylvaccess
exports: distance bands (`config$skidder$classes_distance_m`, e.g.
0-250, 250-500, 500-1000, 1000-1500, 1500-2000, \>2000 m), plus
`inaccessible`, `inexploitable` (harvest slope exceeded) and
`hors_foret`. The
[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)
engine already computes the distance; this is the display-ready product.

## Usage

``` r
classes_debardage(sk, pre = NULL, config = sk$config)
```

## Arguments

- sk:

  A `foretaccess_skidder` **or** `foretaccess_porteur` object (output of
  [`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)
  /
  [`porteur()`](https://pobsteta.github.io/foretaccess/reference/porteur.md)).
  Both carry the same `accessibilite` levels and a `distance_debardage`,
  so the banding is identical; only the underlying distance model
  differs.

- pre:

  The `foretaccess_preprocessing` object used to run the engine.
  Optional; supplies the harvest-slope exclusion needed for the
  `inexploitable` class.

- config:

  A `foretaccess_config`; the distance bands live in
  `config$skidder$classes_distance_m`. Defaults to `sk$config`.

## Value

A categorical `SpatRaster` (`classe_debardage`) with an attached colour
table, directly plottable and compatible with
[`recapituler()`](https://pobsteta.github.io/foretaccess/reference/recapituler.md).

## Details

Precedence per cell: `hors_foret` (not forest) \< distance band
(reachable) \< `inaccessible` (forest, not reached) \< `inexploitable`
(forest, local slope above the harvest threshold — overrides). The
`inexploitable` class requires `pre` (its `exclusion_mask`); without it
those cells stay in their accessibility class.

## See also

[`accessfor_correspondance()`](https://pobsteta.github.io/foretaccess/reference/accessfor_correspondance.md)
maps these classes onto the IGN ACCESSFOR reference layer.
