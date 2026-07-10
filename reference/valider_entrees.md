# Validation des entrées du prétraitement

Politique **stricte** (spec 001 §10, décision 1) : toutes les couches
doivent partager le CRS du MNT, et les rasters son alignement de grille.
Aucune reprojection ni rééchantillonnage silencieux — l'utilisateur
prépare ses données en amont. Chaque manquement lève une erreur ciblée.

## Usage

``` r
valider_entrees(
  mnt,
  desserte,
  foret,
  obstacles_complets = NULL,
  obstacles_partiels = NULL,
  volume = NULL,
  parcellaire = NULL
)
```

## Arguments

- mnt:

  `SpatRaster` du modèle numérique de terrain (grille de référence).

- desserte:

  Objet `sf` de lignes, avec un champ `classe`.

- foret:

  Objet `sf` de polygones.

- obstacles_complets, obstacles_partiels:

  Objets `sf` ou `NULL`.

- volume:

  `SpatRaster` ou `NULL`, aligné sur la grille du MNT.

- parcellaire:

  Objet `sf` ou `NULL`.

## Value

`TRUE` de façon invisible si tout est valide ; sinon une erreur.
