# RVT terrain presets used by the CVAT combination

Returns the two parameter sets that
[`vat_combined()`](https://pobsteta.github.io/foretaccess/reference/vat_combined.md)
blends – `general` and `flat` – transcribed from the RVT QGIS plugin's
`settings/default_terrains_settings.json`. Each set carries the
SVF/openness search geometry (in **pixels**), the hillshade sun
elevation and the four VAT layer stretches; the blend modes, opacities
and slope inversion are those of the base VAT
([`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md)).

## Usage

``` r
cvat_terrain_params()
```

## Value

A named list with elements `general` and `flat`, each a list of
`svf_r_max`, `svf_r_min`, `svf_n_dir`, `sun_elevation`, `sun_azimuth`
and a `layers` spec (as in
[`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md))
with the terrain-specific normalization ranges.

## See also

[`vat_combined()`](https://pobsteta.github.io/foretaccess/reference/vat_combined.md),
[`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md).
