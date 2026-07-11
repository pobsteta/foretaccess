# Découper une emprise en tuiles avec halo

Découpe la grille d'un raster gabarit en **fenêtres d'écriture
disjointes** (les tuiles), chacune assortie d'une **fenêtre de calcul**
élargie d'un halo. Le halo n'est pas un chevauchement à fusionner : il
ne sert qu'au calcul, et n'est jamais écrit. La recomposition est donc
une mosaïque, sans règle de fusion (spec 007 §4.5).

## Usage

``` r
decouper_emprise(gabarit, tuile_m, halo_m = 0)
```

## Arguments

- gabarit:

  `SpatRaster` (ou chemin) dont la grille sert de référence.

- tuile_m:

  Côté d'une tuile, en unités du CRS. Arrondi au nombre entier de
  cellules supérieur.

- halo_m:

  Largeur du halo, en unités du CRS. Défaut `0`.

## Value

Un objet de classe `foretaccess_tuiles` :

- `tuiles`:

  `data.frame`, une ligne par tuile : `id`, les lignes/colonnes de la
  fenêtre d'écriture (`l1`, `l2`, `c1`, `c2`), celles de la fenêtre de
  calcul (`hl1`, `hl2`, `hc1`, `hc2`), et les côtés ouverts
  (`ouvert_haut`, `ouvert_bas`, `ouvert_gauche`, `ouvert_droite`).

- `nrow`, `ncol`, `res`:

  la grille du gabarit.

- `tuile_cel`, `halo_cel`:

  tuile et halo, en cellules.

## Details

Le découpage travaille en **indices de lignes et de colonnes**, jamais
en coordonnées : deux tuiles adjacentes partagent une frontière exacte,
sans risque d'arrondi sur les emprises.

Chaque tuile porte les **côtés ouverts** de sa fenêtre de calcul : ceux
par lesquels un chemin venu du reste du territoire peut entrer. Un côté
qui coïncide avec le bord de l'emprise est **fermé** — rien n'existe
au-delà. Cette distinction évite au certificat (spec 007 §4.3) d'être
inutilement pessimiste sur les tuiles de bordure.

## See also

[`fenetre_tuile()`](https://pobsteta.github.io/foretaccess/reference/fenetre_tuile.md),
[`certifier_propagation()`](https://pobsteta.github.io/foretaccess/reference/certifier_propagation.md)

## Examples

``` r
r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
decouper_emprise(r, tuile_m = 50, halo_m = 10)
#> Decoupage ForetAccess
#> • grille : 10 x 10 cellules a 10 m
#> • 4 tuiles de 5 cellules, halo de 1 cellule
#> • surcout surfacique moyen : 1.44x
```
