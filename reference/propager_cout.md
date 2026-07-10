# Propagation de coût cumulé depuis des sources (service partagé)

Service de plus court chemin sur grille, **sans aucune règle métier** :
il est mutualisé entre le skidder (Lot 2), le porteur (Lot 3) et le
camion DFCI (Lot 6). Reproduit `calcul_distance_de_cout()` de Sylvaccess
v3.6.

## Usage

``` r
propager_cout(surface_cout, sources, zone = NULL, cout_max = Inf)
```

## Arguments

- surface_cout:

  `SpatRaster` de coût par cellule (`NA` = infranchissable).

- sources:

  Sources de la propagation : `SpatRaster` (toute cellule non `NA` et
  non nulle est une source, sa valeur servant d'identifiant), ou objet
  `sf` qui sera rasterisé sur la grille de `surface_cout`.

- zone:

  `SpatRaster` logique délimitant les cellules traversables, ou `NULL`
  (défaut) pour n'exclure que les cellules de coût `NA`.

- cout_max:

  Coût cumulé maximal. Défaut `Inf` (aucun plafond).

## Value

Un objet de classe `foretaccess_propagation` : une liste de trois
`SpatRaster` sur la grille de `surface_cout`.

- `cout_cumule`:

  coût cumulé depuis la source la moins coûteuse.

- `allocation`:

  identifiant de cette source (`Out_alloc` du `.pyx`).

- `predecesseur`:

  indice de la cellule précédente sur le chemin optimal, qui permet de
  reconstruire le trajet avec
  [`chemin_optimal()`](https://pobsteta.github.io/foretaccess/reference/chemin_optimal.md).

Les cellules non atteintes valent `NA` dans les trois couches.

## Details

Sémantique, fidèle au code source Sylvaccess (spec 002 §4.1) :

- **8-connexité** ; le pas vaut la résolution, ou `résolution × sqrt(2)`
  en diagonale ;

- le coût d'un pas est `surface_cout[cellule d'arrivée] × pas`. C'est le
  coût de la **cellule d'arrivée**, et non la moyenne des deux cellules
  — ce qui distingue Sylvaccess de
  [`terra::costDist()`](https://rspatial.github.io/terra/reference/costDist.html)
  et interdit de s'en servir tel quel ;

- une cellule de coût `NA`, ou hors de `zone`, est **infranchissable** ;

- `cout_max` plafonne la propagation : au-delà, la sortie vaut `NA`.

L'algorithme est un Dijkstra à tas binaire. C'est le candidat naturel à
un portage Rust si la performance l'exige (ADR-001).

## See also

[`chemin_optimal()`](https://pobsteta.github.io/foretaccess/reference/chemin_optimal.md)

## Examples

``` r
cout <- terra::rast(nrows = 11, ncols = 11, xmin = 0, xmax = 11,
                    ymin = 0, ymax = 11, crs = "EPSG:2154")
terra::values(cout) <- 1
src <- terra::rast(cout)
src[6, 6] <- 1
prop <- propager_cout(cout, src)
prop$cout_cumule[6, 1]
#>   cout_cumule
#> 1           5
```
