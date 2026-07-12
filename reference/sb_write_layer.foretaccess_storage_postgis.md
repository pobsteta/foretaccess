# Écrit une couche en PostGIS (idempotent, index spatial)

Écrase la couche si elle existe (`delete_layer = TRUE`) puis crée un
**index spatial GiST** sur sa colonne de géométrie (US-8.1). L'index
accélère les requêtes zonales et les jointures spatiales.

## Usage

``` r
# S3 method for class 'foretaccess_storage_postgis'
sb_write_layer(backend, layer, data, ..., spatial_index = TRUE)
```

## Arguments

- backend:

  Objet `foretaccess_storage_postgis`.

- layer:

  Nom de la couche.

- data:

  Objet `sf`.

- ...:

  Passé à
  [`sf::st_write()`](https://r-spatial.github.io/sf/reference/st_write.html).

- spatial_index:

  Créer l'index spatial GiST après l'écriture (défaut `TRUE`).

## Value

`backend` de façon invisible.
