# Trajet optimal d'une cellule vers sa source

Remonte le raster de prédécesseurs produit par
[`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md)
pour reconstituer le chemin de moindre coût, de `depuis` jusqu'à la
source qui lui a été allouée.

## Usage

``` r
chemin_optimal(propagation, depuis)
```

## Arguments

- propagation:

  Objet `foretaccess_propagation` issu de
  [`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md).

- depuis:

  Cellule de départ : indice de cellule (entier), ou objet `sf` de
  points (chaque point donne un trajet).

## Value

Un objet `sf` de `LINESTRING` dans le CRS de la propagation, avec les
colonnes `cellule` (cellule de départ), `source` (identifiant alloué) et
`cout` (coût cumulé). Les cellules non atteintes sont ignorées, avec un
avertissement.
