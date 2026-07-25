# Layered RVT blend of a channel stack into a single composite

Folds a multi-layer `SpatRaster` – ordered **top to bottom** – into one
grayscale composite in `[0, 1]`, following the RVT blending model: each
layer is linearly normalized (with optional inversion), fused with the
accumulated background through its blend mode, then alpha-composited by
its opacity. The bottom layer is the base canvas. Thin GIS wrapper: the
arithmetic runs on the extracted cell values (mirroring
[`micro_relief()`](https://pobsteta.github.io/foretaccess/reference/micro_relief.md)).

## Usage

``` r
blend_rvt(stack, layers)
```

## Arguments

- stack:

  A `SpatRaster` whose layers are the channels to blend, in the **same
  order** as `layers` (layer 1 = top, last layer = bottom / base).

- layers:

  A list of per-layer specs (see
  [`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md));
  each is a list with `min`, `max`, `invert`, `mode` (`"normal"`,
  `"multiply"`, `"screen"`, `"overlay"`, `"soft_light"`, `"luminosity"`
  – RVT's mode set) and `opacity` (0..1). Must have one entry per layer
  of `stack`.

## Value

A single-layer `SpatRaster` named `vat`, values in `[0, 1]`, aligned to
`stack`; `NA` where any contributing layer is `NA`.

## Details

Reproduces RVT's blend faithfully, **including** the quirk that
`"overlay"` and `"soft_light"` mutate the background in place, which
**neutralizes their opacity** (the layer applies at 100%). This is
intentional – it keeps the output identical to RVT's own VAT – and is
pinned to the RVT_py oracle (`data-raw/oracle_rvt.R`); do not "fix" it.

## See also

[`vat_archeo()`](https://pobsteta.github.io/foretaccess/reference/vat_archeo.md),
[`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md).
