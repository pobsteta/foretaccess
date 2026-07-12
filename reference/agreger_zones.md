# Agrégation zonale des surfaces et volumes (Lot 8)

Agrège un raster catégoriel d'accessibilité (issu d'un moteur —
[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md),
[`porteur()`](https://pobsteta.github.io/foretaccess/reference/porteur.md),
[`camion_dfci()`](https://pobsteta.github.io/foretaccess/reference/camion_dfci.md)
— ou d'une couverture câble) en **surfaces** (ha) et, si un raster de
volume est fourni, en **volumes** (m³), **par zone** et par classe. Les
zones sont des polygones quelconques : massif, parcelle, commune
(US-8.2, EF-9/EF-12). C'est le pendant zonal de
[`recapituler()`](https://pobsteta.github.io/foretaccess/reference/recapituler.md),
qui agrège sur l'emprise entière.

## Usage

``` r
agreger_zones(classes, zones, volume = NULL, id = NULL)
```

## Arguments

- classes:

  `SpatRaster` catégoriel (facteur) — la sortie `accessibilite` d'un
  moteur.

- zones:

  Objet `sf` de polygones (les entités d'agrégation).

- volume:

  `SpatRaster` de volume aligné sur `classes`, ou `NULL`.

- id:

  Nom de la colonne de `zones` identifiant chaque zone. `NULL` (défaut)
  : un identifiant `1..n` est ajouté sous la colonne `zone_id`.

## Value

Un objet `sf` (classe `foretaccess_agregation`) : `zones` augmenté des
colonnes d'agrégation. Les zones sans aucune cellule ont des surfaces
nulles.

## Details

L'agrégation est un simple **croisement raster** : les zones sont
rasterisées sur la grille du raster de classes (par leur identifiant),
puis on compte les cellules de chaque classe dans chaque zone. La
surface d'une cellule vaut `prod(res)/10000` ha. Une cellule non
couverte par une zone est ignorée ; une cellule de classe `NA`
(indéterminée) compte dans la colonne `indetermine`.

Le résultat est un objet `sf` : **une ligne par zone**, la géométrie
d'origine conservée, augmentée de colonnes **larges** par classe —
`surface_<classe>_ha` (et `volume_<classe>_m3` si `volume`), plus
`surface_totale_ha`. Cette forme est directement **persistable et
requêtable** en base
([`sb_write_layer()`](https://pobsteta.github.io/foretaccess/reference/sb_write_layer.md)).

## See also

[`recapituler()`](https://pobsteta.github.io/foretaccess/reference/recapituler.md),
[`sb_write_layer()`](https://pobsteta.github.io/foretaccess/reference/sb_write_layer.md)

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
                  file.path(toy, "foret.gpkg"))
sk <- skidder(pre)
# Deux zones : moitie ouest / moitie est de l'emprise.
e <- terra::ext(pre$mnt)
xm <- (e[1] + e[2]) / 2
za <- sf::st_as_sf(terra::as.polygons(terra::ext(e[1], xm, e[3], e[4]),
                   crs = terra::crs(pre$mnt)))
zb <- sf::st_as_sf(terra::as.polygons(terra::ext(xm, e[2], e[3], e[4]),
                   crs = terra::crs(pre$mnt)))
zones <- rbind(za, zb)
agreger_zones(sk$accessibilite, zones)
#> Agregation zonale ForetAccess
#> • zones : 2
#> • colonnes de surface : surface_parcourable_ha, surface_accessible_ha,
#>   surface_non_accessible_ha, surface_hors_foret_ha, surface_indetermine_ha,
#>   surface_totale_ha
#> • surface totale : 6.25 ha
#> Simple feature collection with 2 features and 7 fields
#> Geometry type: POLYGON
#> Dimension:     XY
#> Bounding box:  xmin: 0 ymin: 0 xmax: 250 ymax: 250
#> Projected CRS: RGF93 v1 / Lambert-93
#>                         geometry zone_id surface_parcourable_ha
#> 1 POLYGON ((0 0, 0 250, 125 2...       1                   2.02
#> 2 POLYGON ((125 0, 125 250, 2...       2                   2.04
#>   surface_accessible_ha surface_non_accessible_ha surface_hors_foret_ha
#> 1                     0                         0                  0.86
#> 2                     0                         0                  0.84
#>   surface_indetermine_ha surface_totale_ha
#> 1                  0.245             3.125
#> 2                  0.245             3.125
```
