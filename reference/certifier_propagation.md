# Certificat d'exactitude d'une propagation sur une fenêtre

Propage un coût sur une fenêtre de calcul, et **prouve**, cellule par
cellule, que le résultat est celui qu'aurait donné la même propagation
sur le territoire entier. Sans cela, un plus court chemin — qui n'a
**aucune portée bornée** — produit des artefacts de bordure
indiscernables d'un résultat correct (spec 007 §4.2).

## Usage

``` r
certifier_propagation(
  surface_cout,
  sources,
  zone = NULL,
  zone_majorante = zone,
  bord = NULL,
  cout_max = Inf
)
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

- zone_majorante:

  `SpatRaster` logique **contenant** la zone traversable globale,
  restreinte à la fenêtre. Défaut : `zone`, correct quand `zone` est
  purement locale. Quand `zone` dépend d'une connexité globale (donc
  sous-estimée sur la fenêtre), passer ici une sur-approximation locale,
  sans quoi `d_∂` ne minorerait plus rien.

- bord:

  Cellules d'entrée : un vecteur de côtés ouverts parmi `"haut"`,
  `"bas"`, `"gauche"`, `"droite"` ; un `SpatRaster` logique ; ou `NULL`
  (défaut) pour les quatre côtés. `character(0)` : aucune entrée, tout
  est certifié.

- cout_max:

  Coût cumulé maximal. Défaut `Inf` (aucun plafond).

## Value

Un objet de classe `foretaccess_certificat` :

- `propagation`:

  l'objet `foretaccess_propagation` de
  [`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md).

- `certifie`:

  `SpatRaster` logique : le coût cumulé y est exact.

- `certifie_allocation`:

  `SpatRaster` logique : l'allocation y est exacte.

- `n_non_certifie`:

  nombre de cellules non certifiées.

## Details

Soit `R` la fenêtre de calcul, `d_R` le coût cumulé depuis les sources
présentes dans `R`, et `d_∂` le coût cumulé depuis le **bord ouvert** de
`R`, pris à coût nul.

**Certificat.** Si `d_R(v) ≤ d_∂(v)`, alors `d_R(v)` est le coût global.

*Preuve.* Soit `P` un chemin global optimal aboutissant en `v`. Si `P`
reste dans `R`, sa source y est aussi, donc `d_R(v) ≤ coût(P)`. Sinon
`P` entre dans `R` par une cellule `b` du bord ouvert ; le suffixe de
`P` depuis `b` reste dans `R` et coûte au plus `coût(P)`. Comme `d_∂`
part de `b` à coût nul et que les coûts sont positifs,
`d_∂(v) ≤ coût(P)`. Sous l'hypothèse, `d_R(v) ≤ d_∂(v) ≤ coût(P)`, qui
est le coût global. Or `d_R(v) ≥` ce coût, puisque `R` offre moins de
chemins. Égalité. ∎

Trois conséquences :

- **Allocation.** Si l'inégalité est **stricte**, aucun chemin extérieur
  n'atteint le coût optimal : la source allouée est exacte elle aussi. À
  égalité, la distance est exacte mais l'allocation peut différer.

- **Inaccessibilité.** `d_R(v) = ∞` et `d_∂(v) = ∞` vérifient `∞ ≤ ∞` :
  la cellule est certifiée **inaccessible**, rien ne pouvant entrer
  jusqu'à elle.

- **Connexité.** Le cas `coût ≡ 0` certifie l'appartenance à une
  composante connexe.

Le bord **fermé** (un côté qui coïncide avec le bord de l'emprise) n'est
pas une entrée : rien n'existe au-delà. L'ignorer rendrait le certificat
inutilement pessimiste sur les tuiles de bordure.

`cout_max` s'applique aux **deux** propagations. C'est ce qui rend le
certificat correct pour un coût plafonné : une cellule que le bord
n'atteint pas sous le plafond ne peut pas non plus être atteinte de
l'extérieur sous ce plafond.

## See also

[`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md),
[`decouper_emprise()`](https://pobsteta.github.io/foretaccess/reference/decouper_emprise.md)

## Examples

``` r
cout <- terra::rast(nrows = 5, ncols = 5, xmin = 0, xmax = 5,
                    ymin = 0, ymax = 5, crs = "EPSG:2154")
terra::values(cout) <- 1
src <- terra::rast(cout)
src[1, 1] <- 1
# Aucune entree possible : la fenetre est le territoire entier.
cert <- certifier_propagation(cout, src, bord = character(0))
cert$n_non_certifie
#> [1] 0
```
