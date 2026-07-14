# Échantillonnage du balayage câble, dérivé de la précision

Reproduit `get_dep_config()` de Sylvaccess v3.6. Un seul réglage,
`precision`, gouverne **trois** choses à la fois : le pas angulaire du
balayage, le pas entre cellules de départ, et la largeur du faisceau de
placement des supports.

## Usage

``` r
precision_cable(precision = 3L)
```

## Arguments

- precision:

  `1` (fine), `2` (moyenne) ou `3` (grossière, défaut v3.6).

## Value

Une liste : `pas_azimut_deg`, `pas_depart` (n'échantillonner qu'une
cellule de départ sur `pas_depart`), `largeur_faisceau`.
