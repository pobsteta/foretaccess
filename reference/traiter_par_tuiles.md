# Traiter une emprise par tuiles

Découpe l'emprise, applique un moteur à chaque tuile sur une fenêtre
élargie d'un halo, **certifie** le résultat cellule par cellule (spec
007 §4.3) et recompose une mosaïque. Le résultat est **identique** à
celui du moteur appliqué d'un seul bloc, partout où il est certifié.

## Usage

``` r
traiter_par_tuiles(
  pre,
  config = foretaccess_config(),
  moteur = skidder,
  write_dir = NULL,
  quiet = FALSE,
  couches = NULL
)
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` couvrant toute l'emprise.

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).
  Les paramètres de tuilage vivent dans `config$general` : `tuile_m`,
  `halo_initial_m`, `halo_max_m`.

- moteur:

  Fonction moteur, de signature `(pre, config, bord)`. Défaut
  [`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md).

- write_dir:

  Répertoire d'écriture des COG recomposés, ou `NULL`.

- quiet:

  Supprime la progression.

- couches:

  Noms des couches de sortie du `moteur` à recomposer. `NULL` (défaut) :
  celles du skidder. Pour le porteur, passer `.couches_porteur()`.

## Value

Un objet de classe `foretaccess_mosaique` :

- `accessibilite`, `distance_*`, `allocation`:

  les couches du moteur, recomposées sur toute l'emprise.

- `certifie`:

  `SpatRaster` logique. Gardé en mémoire, **pas écrit** : les cellules
  non certifiées se lisent déjà comme `NA` dans les couches.

- `recap`:

  `data.frame` agrégé, `indetermine` compris.

- `tuiles`:

  `data.frame` : halo final et cellules non certifiées, par tuile.

- `indetermine_ha`:

  surface non certifiée, toujours reportée.

- `grid`, `config`, `fichiers`:

  comme au Lot 1.

## Details

Le halo **double** tant que des cellules de la tuile restent non
certifiées, jusqu'à `halo_max_m`. Au-delà, ces cellules sortent en
`indetermine` — la classe que
[`recapituler()`](https://pobsteta.github.io/foretaccess/reference/recapituler.md)
produit déjà pour les bordures de pente — et un avertissement le dit.
Elles ne sont **jamais** rangées dans `non_accessible` : le doute se
déclare.

`pre` doit couvrir toute l'emprise. Ses rasters peuvent être **adossés à
des fichiers** (`preprocess(write_dir = …)`) : `terra` n'en charge alors
que la fenêtre de chaque tuile, ce qui rend le traitement possible là où
le mono-bloc ne tiendrait pas en mémoire — le véritable obstacle du
passage à l'échelle, avant le temps de calcul.

L'`allocation` porte un indice de cellule dans la grille **globale**,
jamais celle de la tuile : sans cette remise à l'échelle, deux tuiles
alloueraient le même identifiant à deux dessertes différentes.

## See also

[`decouper_emprise()`](https://pobsteta.github.io/foretaccess/reference/decouper_emprise.md),
[`certifier_propagation()`](https://pobsteta.github.io/foretaccess/reference/certifier_propagation.md),
[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
                  file.path(toy, "foret.gpkg"))
cfg <- foretaccess_config(general = list(tuile_m = 150, halo_initial_m = 50))
mo <- traiter_par_tuiles(pre, cfg, quiet = TRUE)
mo$recap
#>           classe cellules surface_ha
#> 1    parcourable     1632       4.08
#> 2     accessible        0       0.00
#> 3 non_accessible        0       0.00
#> 4     hors_foret      672       1.68
#> 5    indetermine      196       0.49
```
