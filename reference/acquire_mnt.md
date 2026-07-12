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
  country = "FR"
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

## Value

Le chemin du raster `mnt.tif` écrit en cache.
