# Surface de coût du skidder (pondération de pente)

Reproduit `Pond_pente` de Sylvaccess v3.6
(`Sylvaccess_1_skidder.py:121`) :

## Usage

``` r
surface_cout_skidder(pre, config = foretaccess_config())
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un `SpatRaster` de coût, sur la grille du MNT.

## Details

\$\$c = \sqrt{1 + (p / 100)^2}\$\$

C'est le **facteur d'allongement 3D** de la traversée d'une cellule : la
distance de moindre coût qui en résulte est la longueur réelle du chemin
épousant le terrain. Le coût ne dépend que de la **valeur absolue** de
la pente — la propagation est donc **isotrope**. Il n'y a aucune
fonction de Tobler dans Sylvaccess (spec 002 §4.2).

Les **obstacles complets** reçoivent un surcoût **additif**
(`config$skidder$surcout_obstacle_complet`, défaut 1000) : prohibitif,
mais fini — ils ne sont pas infranchissables. Les **obstacles partiels**
n'interviennent pas ici : ils restreignent la zone de roulage, pas le
coût (voir
[`zone_roulage()`](https://pobsteta.github.io/foretaccess/reference/zone_roulage.md)).

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
                  file.path(toy, "foret.gpkg"))
terra::global(surface_cout_skidder(pre), "max", na.rm = TRUE)
#>                   max
#> surface_cout 1.019804
```
