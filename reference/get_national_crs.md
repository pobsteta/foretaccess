# CRS national d'un pays

CRS national d'un pays

## Usage

``` r
get_national_crs(country = "FR")
```

## Arguments

- country:

  Code pays ISO. Défaut `"FR"`.

## Value

Un entier (code EPSG ; 2154 pour la France).

## Examples

``` r
get_national_crs("FR")
#> [1] 2154
```
