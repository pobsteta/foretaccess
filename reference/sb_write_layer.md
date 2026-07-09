# Écrit une couche vectorielle

Écrit une couche vectorielle

## Usage

``` r
sb_write_layer(backend, layer, data, ...)
```

## Arguments

- backend:

  Objet de stockage
  ([`storage_gpkg()`](https://pobsteta.github.io/foretaccess/reference/storage_gpkg.md)
  ou
  [`storage_postgis()`](https://pobsteta.github.io/foretaccess/reference/storage_postgis.md)).

- layer:

  Nom de la couche (chaîne).

- data:

  Objet `sf`.

- ...:

  Arguments spécifiques au backend.

## Value

`backend` de façon invisible.
