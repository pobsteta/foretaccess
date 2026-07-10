# Moteur d'accessibilité skidder (débusqueur)

Applique les règles Sylvaccess v3.6 au jeu de rasters produit par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
: circulation libre sous le seuil de pente, treuillage au-delà, et
distances de débardage. Aucune I/O : le moteur consomme l'objet du Lot 1
(ADR-004) et tous ses seuils viennent de `config` (ADR-003).

## Usage

``` r
skidder(
  pre,
  config = foretaccess_config(),
  trajets_depuis = NULL,
  write_dir = NULL
)
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` issu de
  [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

- trajets_depuis:

  Cellules (indices ou points `sf`) pour lesquelles reconstruire le
  trajet de traînage vers la desserte. `NULL` (défaut) : aucun.

- write_dir:

  Répertoire d'écriture des rasters en GeoTIFF/COG, ou `NULL`.

## Value

Un objet de classe `foretaccess_skidder` :

- `accessibilite`:

  `SpatRaster` catégoriel : `parcourable`, `accessible`,
  `non_accessible`, `hors_foret`. `NA` = indéterminé.

- `distance_treuillage`:

  distance **3D** de treuillage (m), 0 sinon.

- `distance_trainage_foret`:

  distance de traînage en forêt (m).

- `distance_trainage_piste`:

  distance sur piste jusqu'à une route (m).

- `distance_debardage`:

  somme des trois précédentes.

- `allocation`:

  cellule de desserte de rattachement.

- `trajet`:

  `sf` de `LINESTRING`, ou `NULL`.

- `recap`:

  `data.frame` des surfaces et volumes par classe.

- `grid`, `config`, `fichiers`:

  comme au Lot 1.

## Details

Deux mécanismes coexistent, et ils n'ont pas la même nature :

- le **traînage** est un plus court chemin sur la surface de coût
  ([`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md),
  [`surface_cout_skidder()`](https://pobsteta.github.io/foretaccess/reference/surface_cout_skidder.md))
  ;

- le **treuillage** est un balayage radial en ligne droite
  ([`treuiller()`](https://pobsteta.github.io/foretaccess/reference/treuiller.md)).

L'option de modélisation `1` (défaut v3.6, « limiter l'impact sur le sol
») **privilégie le treuillage** : une cellule treuillable l'est, même si
l'engin pourrait y rouler. L'option `2` n'est pas implémentée.

## Écarts assumés avec Sylvaccess v3.6

La hiérarchie route / piste est réduite à deux niveaux (`route` et
`dfci` comptent comme routes), et l'option de modélisation 2 n'est pas
implémentée. Voir `specs/002-skidder.md`.

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
                  file.path(toy, "foret.gpkg"))
sk <- skidder(pre)
sk$recap
#>           classe cellules surface_ha
#> 1    parcourable     1624       4.06
#> 2     accessible        0       0.00
#> 3 non_accessible        0       0.00
#> 4     hors_foret      680       1.70
#> 5    indetermine      196       0.49
```
