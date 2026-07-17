# Résout l'URL de service d'une couche

Combine la couche et le service qu'elle référence pour renvoyer l'URL
complète du service, sa version, et l'identifiant de couche (`layer`
pour un WMS, `typename` pour un WFS).

## Usage

``` r
get_layer_service(layer_key, country = "FR")
```

## Arguments

- layer_key:

  Clé de la couche (p. ex. `"dem"`, `"roads"`).

- country:

  Code pays ISO. Défaut `"FR"`.

## Value

Une liste (`url`, `version`, et `layer`/`typename`), ou `NULL`.

## Examples

``` r
info <- get_layer_service("dem", "FR")
info$url
#> [1] "https://data.geopf.fr/wms-r/wms"
info$layer
#> [1] "IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93"
```
