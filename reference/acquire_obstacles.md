# Acquiert les obstacles depuis OpenStreetMap

Télécharge les obstacles au sein de l'emprise : bâti, surfaces d'eau,
voies ferrées, falaises (jeu configurable). Chaque type est requêté sur
la bbox WGS84 de l'AOI, puis reprojeté et découpé sur l'AOI (spec 010
Q3).

## Usage

``` r
acquire_obstacles(
  aoi,
  features = c("building", "water", "railway", "cliff"),
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE
)
```

## Arguments

- aoi:

  Objet `sf`/`sfc` d'emprise, dans le CRS cible.

- features:

  Types d'obstacles à récupérer (sous-ensemble de `building`, `water`,
  `railway`, `cliff`).

- crs:

  Code EPSG de sortie. Défaut 2154.

- cache_dir:

  Répertoire de cache.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

## Value

Un objet `sf` d'obstacles avec un champ `type`, ou un `sf` vide si aucun
obstacle n'est trouvé.
