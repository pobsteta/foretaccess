# Liste les couches disponibles

Liste les couches disponibles

## Usage

``` r
sb_list_layers(backend, ...)
```

## Arguments

- backend:

  Objet de stockage
  ([`storage_gpkg()`](https://pobsteta.github.io/foretaccess/reference/storage_gpkg.md)
  ou
  [`storage_postgis()`](https://pobsteta.github.io/foretaccess/reference/storage_postgis.md)).

- ...:

  Arguments spécifiques au backend.

## Value

Un vecteur de caractères (noms de couches).
