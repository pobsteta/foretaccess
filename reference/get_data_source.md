# Résout une source de données par sa clé

Renvoie la configuration d'une couche déclarée dans le JSON du pays.

## Usage

``` r
get_data_source(source_key, country = "FR")
```

## Arguments

- source_key:

  Clé de la source (p. ex. `"dem"`, `"roads"`).

- country:

  Code pays ISO. Défaut `"FR"`.

## Value

Une liste (config de la source), ou `NULL` si absente.

## Examples

``` r
get_data_source("dem", "FR")$layer
#> [1] "IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93"
```
