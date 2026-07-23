# Contract a designed network's grid polylines into clean tronçons

[`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md)'s
`$lignes` follow the raster grid step by step (thousands of tiny
segments), which is heavy and staircase-like to display. This applies
the **same topological contraction** as
[`vectoriser_reseau()`](https://pobsteta.github.io/foretaccess/reference/vectoriser_reseau.md)
– degree-2 chains merged into `troncons` between junctions (degree \>=
3), leaves and outlets – returning a **tidy vector** of the created
network, without building the full flux graph. The result is ready to
feed
[`vectoriser_reseau()`](https://pobsteta.github.io/foretaccess/reference/vectoriser_reseau.md)
/
[`typer_desserte()`](https://pobsteta.github.io/foretaccess/reference/typer_desserte.md)
or to display directly instead of the `$reseau` raster.

## Usage

``` r
contracter_lignes(reseau)
```

## Arguments

- reseau:

  A `foretaccess_reseau` object (Lot 16).

## Value

An `sf` LINESTRING, one feature per contracted tronçon, with `id`, `de`
/ `vers` (node cell ids) and `longueur` (m). Empty roads abort.

## See also

[`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md)
(produces the fine `$lignes`),
[`vectoriser_reseau()`](https://pobsteta.github.io/foretaccess/reference/vectoriser_reseau.md)
(the typing entry point that contracts likewise).

## Examples

``` r
if (FALSE) { # \dontrun{
res <- reseau_desserte(pre, cout, parcelles, desserte_existante)
lignes_propres <- contracter_lignes(res) # affichage vecteur net
} # }
```
