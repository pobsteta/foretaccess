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
  res_lidar_m = 1
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

## Value

Le chemin du raster `mnt.tif` écrit en cache.
