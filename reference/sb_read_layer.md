# Relit une couche vectorielle

Relit une couche vectorielle

## Usage

``` r
sb_read_layer(backend, layer, ...)
```

## Arguments

- backend:

  Objet de stockage
  ([`storage_gpkg()`](https://pobsteta.github.io/foretaccess/reference/storage_gpkg.md)
  ou
  [`storage_postgis()`](https://pobsteta.github.io/foretaccess/reference/storage_postgis.md)).

- layer:

  Nom de la couche (chaîne).

- ...:

  Arguments spécifiques au backend.

## Value

Un objet `sf`.
