# Acquiert le parcellaire cadastral (IGN WFS, optionnel)

Acquiert le parcellaire cadastral (IGN WFS, optionnel)

## Usage

``` r
acquire_cadastre(
  aoi,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  country = "FR"
)
```

## Arguments

- aoi:

  Objet `sf`/`sfc` d'emprise, dans le CRS cible.

- crs:

  Code EPSG de sortie. Défaut 2154.

- cache_dir:

  Répertoire de cache.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

- country:

  Code pays ISO. Défaut `"FR"`.

## Value

Un objet `sf` de polygones de parcelles.
