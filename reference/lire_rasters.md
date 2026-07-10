# Relit un prétraitement écrit sur disque

Recharge les rasters écrits par `preprocess(write_dir = ...)`. Les
couches vectorielles (`desserte_sf`, `parcellaire`) ne sont pas relues :
elles ne sont pas écrites par `write_dir` (ADR-002, les vecteurs vont en
base).

## Usage

``` r
lire_rasters(write_dir)
```

## Arguments

- write_dir:

  Répertoire contenant les GeoTIFF/COG écrits.

## Value

Une liste nommée de `SpatRaster`.
