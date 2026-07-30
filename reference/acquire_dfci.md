# Acquiert le réseau DFCI depuis OpenStreetMap

Récupère les pistes de défense des forêts contre l'incendie (DFCI)
portant une référence OSM `ref:FR:DFCI` (ou les alias `ref:dfci` /
`dfci_ref`) au sein de l'emprise. Ces lignes servent à poser le flag
`dfci` (`CL_DFCI`) sur la desserte via
[`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md)
— la source du camion DFCI (spec 006). C'est la « source dédiée »
laissée ouverte en phase 1 (spec 010 §10.2).

## Usage

``` r
acquire_dfci(
  aoi,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  politique_cache = "reacquerir"
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

- politique_cache:

  Que faire d'un cache produit avec **d'autres paramètres** ? Défaut
  `"reacquerir"`. Voir
  [`cache_utilisable()`](https://pobsteta.github.io/foretaccess/reference/cache_utilisable.md)
  et `specs/027`.

## Value

Un objet `sf` de lignes DFCI avec un champ `ref`, ou un `sf` vide si
aucune piste DFCI n'est trouvée.

## See also

[`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md),
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
