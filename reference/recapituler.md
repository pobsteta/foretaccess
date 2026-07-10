# Tableau récapitulatif surfaces / volumes par classe

Agrège un raster catégoriel d'accessibilité en surfaces (ha) et, si un
raster de volume est fourni, en volumes (m³). Réutilisé par le porteur
(Lot 3).

## Usage

``` r
recapituler(classes, volume = NULL)
```

## Arguments

- classes:

  `SpatRaster` catégoriel (facteur).

- volume:

  `SpatRaster` de volume aligné, ou `NULL`.

## Value

Un `data.frame` : `classe`, `cellules`, `surface_ha`, et `volume_m3` si
`volume` est fourni.

## Details

Les cellules `NA` du raster de classes forment une ligne
**`indetermine`** explicite : elles ne sont jamais rangées
silencieusement dans une classe métier. Sur le jeu jouet elles
correspondent aux bordures du calcul de pente (Lot 1). La somme des
surfaces égale donc toujours celle du raster entier.
