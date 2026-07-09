# Backend de stockage GeoPackage

Implémentation de l'interface
[storage](https://pobsteta.github.io/foretaccess/reference/storage.md)
au-dessus d'un fichier GeoPackage (via sf).

## Usage

``` r
storage_gpkg(path)
```

## Arguments

- path:

  Chemin du fichier `.gpkg` (créé à la première écriture).

## Value

Un objet de classe `foretaccess_storage_gpkg`.

## See also

[`storage_postgis()`](https://pobsteta.github.io/foretaccess/reference/storage_postgis.md),
[storage](https://pobsteta.github.io/foretaccess/reference/storage.md)

## Examples

``` r
if (FALSE) { # \dontrun{
sb <- storage_gpkg(tempfile(fileext = ".gpkg"))
sb_write_layer(sb, "essai", sf::st_sf(id = 1, geometry = sf::st_sfc(sf::st_point(c(0, 0)))))
sb_list_layers(sb)
} # }
```
