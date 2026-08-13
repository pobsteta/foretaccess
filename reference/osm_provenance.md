# Provenance of an Overpass response

Provenance of an Overpass response

## Usage

``` r
osm_provenance(x)
```

## Arguments

- x:

  An `sf` returned by
  [`osm_overpass()`](https://pobsteta.github.io/foretaccess/reference/osm_overpass.md).

## Value

A named list: `instance`, `requete`, `date_requete`, `nb_entites`. Two
runs a month apart otherwise differ with **no trace at all** – on data
feeding a network design, that is a substantive problem, not
bookkeeping.

## See also

[`osm_overpass()`](https://pobsteta.github.io/foretaccess/reference/osm_overpass.md).
