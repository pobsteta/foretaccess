# Acquiert la desserte depuis BD TOPO (IGN WFS)

Récupère `troncon_de_route`, reprojette, découpe sur l'AOI et dérive le
champ `classe` attendu par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).

## Usage

``` r
acquire_desserte(
  aoi,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  country = "FR",
  classification = c("clsvac", "heuristique")
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

- classification:

  Comment classer la BD TOPO en desserte Sylvaccess. `"clsvac"` (défaut,
  spec 022) : trois classes `piste` / `route` (forestière, terminus du
  traînage) / `reseau_public` (grands axes, barrière), aligné sur
  ACCESSFOR — les routes empierrées carrossables deviennent `route`, pas
  `piste`. `"heuristique"` : ancien mapping deux classes `route`/`piste`
  (bit-pour-bit ; la route empierrée y tombe en `piste`).

## Value

Un objet `sf` de lignes avec un champ `classe`.
