# Compare une sortie à un oracle de non-régression

Cœur du harnais de non-régression (brief §7, ADR-006). Compare une
valeur *actuelle* à un *oracle* de référence (sorties Sylvaccess v3.6
figées, ou oracle synthétique au Lot 0) avec des tolérances absolue et
relative.

## Usage

``` r
compare_to_oracle(actual, oracle, tol_abs = 0, tol_rel = 1e-06)
```

## Arguments

- actual:

  Valeur produite (numérique ou `SpatRaster`).

- oracle:

  Valeur de référence, de même forme que `actual`.

- tol_abs:

  Tolérance absolue (défaut `0`).

- tol_rel:

  Tolérance relative (défaut `1e-6`), rapportée à `abs(oracle)`.

## Value

Une liste de classe `foretaccess_nonreg` : `ok` (logique), `max_abs`,
`max_rel`, `n`, `tol_abs`, `tol_rel`.

## Details

Types supportés : vecteurs/matrices numériques et rasters
[`terra::SpatRaster`](https://rspatial.github.io/terra/reference/SpatRaster-class.html).
Les `NA` doivent apparaître aux mêmes positions dans les deux objets.

## Examples

``` r
compare_to_oracle(c(1, 2, 3), c(1, 2, 3.0000001), tol_rel = 1e-3)
#> Non-regression : OK
#> • n = 3 ; max_abs = 1e-07 ; max_rel = 3.333e-08
#> • tolerances : abs = 0 ; rel = 0.001
```
