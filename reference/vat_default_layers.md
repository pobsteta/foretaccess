# Default RVT layer stack for the Archaeological (VAT) blend

Returns the layer specification of the **Visualization for
Archaeological Topography** blend: sky-view factor, positive openness,
slope and hillshade, stacked **top to bottom** with per-layer
normalization range, blend mode and opacity. These defaults are **pinned
to RVT's shipped `blender_VAT.json`** preset (`VAT - Archaeological`)
and validated pixel-to-pixel against the RVT_py oracle
(`data-raw/oracle_rvt.R`).

## Usage

``` r
vat_default_layers()
```

## Value

A named list of four layer specs, each a list with `name`, `min`, `max`,
`invert`, `mode` and `opacity`, ordered top (rendered over) to bottom
(base canvas). Field `name` maps to the channels
[`vat_archeo()`](https://pobsteta.github.io/foretaccess/reference/vat_archeo.md)
computes: `"svf"`, `"openness_pos"`, `"slope"`, `"hillshade"`.

## See also

[`vat_archeo()`](https://pobsteta.github.io/foretaccess/reference/vat_archeo.md),
[`blend_rvt()`](https://pobsteta.github.io/foretaccess/reference/blend_rvt.md).
