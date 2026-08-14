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

Une liste de classe `foretaccess_osm_compare` :

- `osm`:

  linéaire OSM total et hors corridor, par type.

- `bdtopo`:

  linéaire BD TOPO hors corridor OSM, par classe.

- `resume`:

  les cinq totaux (`osm_km`, `osm_hors_km`, `osm_couvert_pct`,
  `bdtopo_km`, `bdtopo_hors_km`).

- `corridor_m`:

  la demi-largeur employée.

- `osm_hors_corridor`:

  `sf` des tronçons OSM **amputés** de leur part dans le corridor BD
  TOPO : attributs d'origine plus `hors_m` (m). Géométrie homogène en
  `MULTILINESTRING`, CRS de l'entrée, `sf` à 0 ligne si rien ne sort du
  corridor (jamais `NULL`).

- `bdtopo_hors_corridor`:

  le symétrique, BD TOPO hors corridor OSM.

## Details

Un tronçon OSM hors corridor peut être un décalage de saisie sur une
voie déjà présente, une trace erronée, ou un chemin non carrossable. Le
chiffre à en retenir est un **gisement à instruire**, et le CA-28.5
exige de le confronter d'abord aux objets BD TOPO connus, puis à une
annotation.

Les **géométries** hors corridor sont rendues telles quelles, clippées :
un tronçon à moitié dans le corridor n'est renvoyé que pour sa moitié
hors corridor, sans quoi on présenterait comme « absent de la BD TOPO »
un linéaire qui y figure. Elles ne coûtent rien de plus : la différence
géométrique est déjà calculée pour mesurer le linéaire.

## Performance

Recoupement geometrique de deux couches, tempere par l'index spatial de
`sf`. **104 s** pour 3 122 x 544 troncons (mesure nemetonshiny,
2026-08-12). Purement local : aucun acces reseau, aucune surprise de
debit.

## See also

[`acquire_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_osm.md),
`specs/028`.
