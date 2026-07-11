# Emprise d'une tuile

Emprise d'une tuile

## Usage

``` r
fenetre_tuile(tuiles, id, quoi = c("halo", "tuile"))
```

## Arguments

- tuiles:

  Objet `foretaccess_tuiles` issu de
  [`decouper_emprise()`](https://pobsteta.github.io/foretaccess/reference/decouper_emprise.md).

- id:

  Identifiant de la tuile.

- quoi:

  `"halo"` (fenêtre de calcul, défaut) ou `"tuile"` (fenêtre
  d'écriture).

## Value

Un `SpatExtent`.

## Examples

``` r
r <- terra::rast(nrows = 10, ncols = 10, xmin = 0, xmax = 100,
                 ymin = 0, ymax = 100, crs = "EPSG:2154")
tu <- decouper_emprise(r, tuile_m = 50, halo_m = 10)
fenetre_tuile(tu, 1)
#> SpatExtent : 0, 60, 40, 100 (xmin, xmax, ymin, ymax)
```
