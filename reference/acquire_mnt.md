# Acquiert le MNT depuis RGE ALTI (IGN WMS)

Acquiert le MNT depuis RGE ALTI (IGN WMS)

## Usage

``` r
acquire_mnt(
  aoi,
  res_m = 5,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  country = "FR",
  res_lidar_m = 1,
  politique_cache = "reacquerir"
)
```

## Arguments

- aoi:

  Objet `sf`/`sfc` d'emprise, dans le CRS cible.

- res_m:

  Résolution du raster (m). Défaut 5.

- crs:

  Code EPSG de sortie. Défaut 2154.

- cache_dir:

  Répertoire de cache.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

- country:

  Code pays ISO. Défaut `"FR"`.

- res_lidar_m:

  Résolution fine (m) de téléchargement du **MNT LIDAR HD** (couche
  primaire) sur l'emprise, agrégée ensuite à `res_m`. Défaut 1. Doit
  diviser `res_m` (ex. 1 → 5). Passer `res_lidar_m >= res_m` désactive
  l'agrégation (téléchargement direct à `res_m`).

- politique_cache:

  Que faire d'un cache produit avec **d'autres paramètres** ?
  `"reacquerir"` (défaut) refait l'acquisition, `"avertir"` sert le
  cache en nommant ce qui diverge, `"echouer"` interrompt, `"ignorer"`
  désactive le contrôle. Un cache **sans provenance** (antérieur à la
  v1.29.0) compte comme divergent. Cf.
  [`cache_utilisable()`](https://pobsteta.github.io/foretaccess/reference/cache_utilisable.md)
  et `specs/027`.

## Value

Le chemin du raster `mnt.tif` écrit en cache.
