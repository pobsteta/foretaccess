# Compare une desserte OSM à la BD TOPO (spec 028)

Mesure le linéaire de part et d'autre d'un **corridor** autour de la
référence, par type OSM et par classe BD TOPO. C'est un **diagnostic**,
pas un résultat : un linéaire hors corridor n'est pas une desserte
manquante prouvée.

## Usage

``` r
comparer_desserte_osm(bdtopo, osm, corridor_m = 15)
```

## Arguments

- bdtopo:

  Desserte de référence (sortie
  d'[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)).

- osm:

  Desserte candidate (sortie
  d'[`acquire_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_osm.md)).

- corridor_m:

  Demi-largeur du corridor (m). Défaut 15, la valeur de `dsr_detecter()`
  pour exclure le réseau de référence.

## Value

Une liste : `osm` (linéaire OSM total et hors corridor, par type),
`bdtopo` (linéaire BD TOPO hors corridor OSM, par classe), et `resume`.

## Details

Un tronçon OSM hors corridor peut être un décalage de saisie sur une
voie déjà présente, une trace erronée, ou un chemin non carrossable. Le
chiffre à en retenir est un **gisement à instruire**, et le CA-28.5
exige de le confronter d'abord aux objets BD TOPO connus, puis à une
annotation.

## See also

[`acquire_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_osm.md),
`specs/028`.
