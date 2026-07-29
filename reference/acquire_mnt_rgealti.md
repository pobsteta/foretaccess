# Acquiert un MNT RGE ALTI depuis les **dalles départementales** (Géoservices)

Alternative saine au RGE ALTI servi par WMS, qui rend un MNT **blocky**
(blocs plats à marches) dont la pente est fausse. C'est le produit que
prescrit la notice ACCESSFOR (rapport février 2025, annexe p. 50) : *«
Livraison d'un MNT provenant du RGE Alti 5m converti en 32bit »*,
téléchargé par département.

## Usage

``` r
acquire_mnt_rgealti(
  aoi,
  dep,
  res_m = 5,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE
)
```

## Arguments

- aoi:

  Objet `sf`/`sfc` d'emprise, dans le CRS cible.

- dep:

  Code du département sur deux caractères (ex. `"48"`).

- res_m:

  Résolution du produit RGE ALTI : 5 ou 1. Défaut 5.

- crs:

  Code EPSG de sortie. Défaut 2154.

- cache_dir:

  Répertoire de cache.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

## Value

Le chemin du raster `mnt_rgealti.tif` écrit en cache.

## Details

L'archive départementale (~450 Mo en `.7z` pour le 5 m) est téléchargée
une fois et mise en cache ; seules les **dalles couvrant l'AOI** en sont
extraites, puis mosaïquées et découpées. L'extraction requiert `py7zr`
(Python) ou un binaire `7z` sur le `PATH` – l'archive Géoservices n'est
pas lisible autrement.

Sur la même AOI, ce produit donne une distribution de pente quasi
identique au MNT LiDAR HD (médiane 39,96 % contre 40,99 %), là où la
variante WMS donnait une médiane de 18,89 % et un maximum de 382 %.

## See also

[`acquire_mnt()`](https://pobsteta.github.io/foretaccess/reference/acquire_mnt.md)
(LIDAR HD, source par défaut).
