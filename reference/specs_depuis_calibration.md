# Turn a dessertR calibration into detection specs

`dessertR::dsr_calibrer_specs()` returns bounds calibrated **on your own
data**, and advises using them when the frozen ones saturate. Its
`$specs` is a **flat** list of channels;
[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md)
expects the **nested** shape of
[`specs_desserte_calibrees()`](https://pobsteta.github.io/foretaccess/reference/specs_desserte_calibrees.md)
(`geomorpho` / `surface` / `c_vessel`). Two contracts for one word –
this bridges them.

## Usage

``` r
specs_depuis_calibration(
  calibration,
  surface = specs_desserte_calibrees()$surface,
  c_vessel = specs_desserte_calibrees()$c_vessel
)
```

## Arguments

- calibration:

  Either the full `dsr_calibrer_specs()` result or its `$specs` element
  directly. Both are accepted.

- surface:

  Bounds for the point-cloud channels. Defaults to the frozen ones;
  `NULL` leaves them to dessertR.

- c_vessel:

  Frangi anchor. Defaults to the frozen one; `NULL` makes the vesselness
  extent-relative.

## Value

A list shaped like
[`specs_desserte_calibrees()`](https://pobsteta.github.io/foretaccess/reference/specs_desserte_calibrees.md),
usable as the `specs` argument of
[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md).

## Details

The flat calibration *is* the `geomorpho` group: `$specs` is documented
as "directement utilisable" by `dsr_conductivite()`, which is exactly
what
[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md)
feeds with `specs$geomorpho`.

**What a calibration cannot give you**, and why the other two groups
keep their frozen defaults:

- `surface` – those channels (`taux_penetration`, `densite_sol`,
  `h_couvert`) come from the **point cloud**, not from the DEM stack
  that was calibrated. `dsr_calibrer_specs()` never sees them.

- `c_vessel` – the Frangi anchor, produced by
  `dessertR::dsr_c_vessel()`, not by the calibration. Without it the
  vesselness channel is rescaled on whatever extent you pass, and
  `seuil` stops being comparable between sites.

Mixing locally calibrated `geomorpho` bounds with frozen `surface`
bounds is a **deliberate compromise**, not an oversight: it is still
better than frozen bounds that saturate on your massif. Pass
`surface = NULL` to opt out and let dessertR derive them, at the cost of
extent-relative results.

## See also

[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md),
[`specs_desserte_calibrees()`](https://pobsteta.github.io/foretaccess/reference/specs_desserte_calibrees.md),
`dessertR::dsr_calibrer_specs()`, `specs/026`.

## Examples

``` r
# Forme attendue, sans appeler dessertR :
plat <- list(rugosite = list(type = "croissante", a = 0.04, b = 0.17, poids = 2))
str(specs_depuis_calibration(plat)$geomorpho)
#> List of 1
#>  $ rugosite:List of 4
#>   ..$ type : chr "croissante"
#>   ..$ a    : num 0.04
#>   ..$ b    : num 0.17
#>   ..$ poids: num 2
```
