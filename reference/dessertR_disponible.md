# Is the optional dessertR backend available?

`dessertR` is an optional, non-CRAN backend. Four functions need it –
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md),
[`verifier_integrite_desserte()`](https://pobsteta.github.io/foretaccess/reference/verifier_integrite_desserte.md),
[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md)
and
[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)
– and they degrade or fail without it. Call this **before** offering
those actions, so a caller can say *"not available"* instead of showing
an empty result that reads like a clean bill of health.

## Usage

``` r
dessertR_disponible()
```

## Value

A single `logical`. `TRUE` if `dessertR` can be loaded.

## Details

**Why it is not declared in `Suggests`.** `dessertR` depends on `rlas`,
which is **archived on CRAN**: declaring it (with a `Remotes:` entry)
makes `pak` resolve the chain and stop at *"rlas: Can't find package
called rlas"*, which breaks installation of `foretaccess` **for
everyone**, including users who never touch `dessertR`. Verified on CI,
2026-08-12: four jobs failed in 90 seconds. It will be declared the day
`rlas` returns to CRAN.

Installing it therefore takes two steps – `rlas` from the CRAN archive
(or from source), then `remotes::install_github("pobsteta/dessertR")`.

## See also

[`verifier_integrite_desserte()`](https://pobsteta.github.io/foretaccess/reference/verifier_integrite_desserte.md),
whose `disponible` field reports the same thing for a diagnostic that
has already run.

## Examples

``` r
if (dessertR_disponible()) {
  message("Diagnostic d'integrite disponible.")
}
```
