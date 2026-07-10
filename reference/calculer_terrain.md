# Pente et exposition depuis un MNT

Dérive la **pente en pourcentage** et l'**exposition en degrés** (0–360
depuis le nord, sens horaire) d'un modèle numérique de terrain, via
[`terra::terrain()`](https://rspatial.github.io/terra/reference/terrain.html).

## Usage

``` r
calculer_terrain(mnt, methode = "Horn")
```

## Arguments

- mnt:

  `SpatRaster` mono-couche, ou chemin de fichier.

- methode:

  Méthode de calcul : `"Horn"` (8 voisins) ou `"Evans"` (4 voisins).

## Value

Une liste de deux `SpatRaster` : `slope_pct` et `aspect_deg`, sur la
grille du MNT.

## Details

La méthode par défaut est **Horn** (8 voisins), celle de `terra`. Elle
reste configurable (`config$general$methode_pente`) pour permettre une
réconciliation ultérieure avec l'oracle Sylvaccess v3.6 sans refonte
(spec 001 §10, décision 2).

Conventions de sortie :

- `slope_pct` = `tan(pente_radians) * 100`.

- `aspect_deg` vaut `NA` sur les cellules **plates** (pente nulle), là
  où `terra` renvoie conventionnellement 90.

- Les cellules de **bordure** valent `NA` dans les deux couches : le
  calcul exige les 8 voisins. C'est un effet de bord documenté (spec 001
  §8) ; les comparaisons à l'oracle portent sur l'intérieur du raster.

## Examples

``` r
mnt <- terra::rast(system.file("extdata/toy/mnt.tif", package = "foretaccess"))
terr <- calculer_terrain(mnt)
terra::global(terr$slope_pct, "mean", na.rm = TRUE)
#>           mean
#> slope_pct   20
```
