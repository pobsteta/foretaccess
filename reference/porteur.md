# Moteur d'accessibilité porteur (forwarder)

Applique les règles Sylvaccess v3.6 au jeu de rasters produit par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).
Le porteur diffère profondément du skidder : sa conduite est un
**balayage radial** depuis le réseau
([`conduire()`](https://pobsteta.github.io/foretaccess/reference/conduire.md)),
non un plus court chemin, et il n'a **pas de treuil** mais un
**grappin** de portée fixe. Voir `specs/003-porteur.md`.

## Usage

``` r
porteur(pre, config = foretaccess_config(), write_dir = NULL, bord = NULL)
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` issu de
  [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

- write_dir:

  Répertoire d'écriture des rasters, ou `NULL`.

- bord:

  Côtés ouverts de la fenêtre quand `pre` est une **tuile** (voir
  [`certifier_propagation()`](https://pobsteta.github.io/foretaccess/reference/certifier_propagation.md)).
  `NULL` (défaut) : `pre` couvre tout le territoire.

## Value

Un objet de classe `foretaccess_porteur`, de structure parallèle à
[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)
mais sans `distance_treuillage` : `accessibilite`, `distance_conduite`,
`distance_grappin`, `distance_trainage_piste`, `distance_debardage`,
`allocation`, `certifie`, `recap`, `grid`, `config`.

## Details

Trois mécanismes, dans l'ordre de priorité :

- la **conduite**
  ([`conduire()`](https://pobsteta.github.io/foretaccess/reference/conduire.md))
  : l'engin roule, sous ses contraintes de pente en long, de dévers et
  de distance en pente forte. Ces cellules sont `parcourable` ;

- le **grappin** : depuis le contour de la zone conduite, une extension
  de `portee_grue_m` (défaut 8 m) sur le terrain récoltable. Ces
  cellules sont `accessible` sans être `parcourable` ;

- la **distance sur piste**, mutualisée avec le skidder (Lot 2).

## See also

[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md),
[`conduire()`](https://pobsteta.github.io/foretaccess/reference/conduire.md),
[`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md)

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
                  file.path(toy, "foret.gpkg"))
po <- porteur(pre)
po$recap
#>           classe cellules surface_ha
#> 1    parcourable      141     0.3525
#> 2     accessible      286     0.7150
#> 3 non_accessible     1197     2.9925
#> 4     hors_foret      680     1.7000
#> 5    indetermine      196     0.4900
```
