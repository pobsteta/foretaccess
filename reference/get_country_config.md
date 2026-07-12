# Charge la configuration des sources d'un pays

Lit et met en cache le JSON de configuration d'un pays.

## Usage

``` r
get_country_config(country = "FR")
```

## Arguments

- country:

  Code pays ISO 3166-1 alpha-2 (défaut `"FR"`).

## Value

Une liste (la configuration du pays).

## Examples

``` r
cfg <- get_country_config("FR")
cfg$crs_national
#> [1] 2154
```
