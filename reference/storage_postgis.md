# Backend de stockage PostGIS

Implémentation de l'interface
[storage](https://pobsteta.github.io/foretaccess/reference/storage.md)
au-dessus d'une base PostGIS. Suivant l'ADR-002, le modèle cible est une
**base dédiée** avec **un schéma par run/massif** ; le schéma est un
paramètre explicite du backend.

## Usage

``` r
storage_postgis(conn, schema = "public", ensure_schema = TRUE)
```

## Arguments

- conn:

  Connexion `DBI` active (p. ex.
  `DBI::dbConnect(RPostgres::Postgres(), ...)`). Le cycle de vie de la
  connexion est géré par l'appelant.

- schema:

  Nom du schéma PostgreSQL cible (défaut `"public"`).

- ensure_schema:

  Créer le schéma s'il n'existe pas (défaut `TRUE`).

## Value

Un objet de classe `foretaccess_storage_postgis`.

## See also

[`storage_gpkg()`](https://pobsteta.github.io/foretaccess/reference/storage_gpkg.md),
[storage](https://pobsteta.github.io/foretaccess/reference/storage.md)
