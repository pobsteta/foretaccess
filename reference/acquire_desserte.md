# Acquiert la desserte depuis BD TOPO (IGN WFS)

Récupère `troncon_de_route`, reprojette, découpe sur l'AOI et dérive le
champ `classe` (`route`/`piste`) attendu par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).

## Usage

``` r
acquire_desserte(
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

Un objet `sf` de lignes avec un champ `classe`.
