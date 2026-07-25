# CVAT composite (Combined VAT) from a DEM – RVT QGIS default

Reproduces the RVT QGIS plugin's default archaeological product,
**CVAT** (Combined Visualization for Archaeological Topography): the
50/50 blend of two
[`vat_archeo()`](https://pobsteta.github.io/foretaccess/reference/vat_archeo.md)-style
VATs computed with the `general` and `flat` terrain presets. It adapts
to both flat and steep ground far better than a single VAT.

## Usage

``` r
vat_combined(mnt, params = cvat_terrain_params(), as_byte = FALSE)
```

## Arguments

- mnt:

  Digital terrain model as a single-layer `SpatRaster` (square cells;
  the first layer is used if several).

- params:

  Terrain parameter sets, default
  [`cvat_terrain_params()`](https://pobsteta.github.io/foretaccess/reference/cvat_terrain_params.md).

- as_byte:

  If `TRUE`, return the 8-bit raster (`0..255`, `NA`-\>255) as the
  plugin writes it (`*_CVAT_8bit.tif`); if `FALSE` (default), the float
  composite in `[0, 1]`.

## Value

A single-layer `SpatRaster` named `cvat`, aligned to `mnt`.

## Details

The SVF and positive-openness channels come from the validated Rust
kernel
[`rvt_svf_opns()`](https://pobsteta.github.io/foretaccess/reference/rvt_svf_opns.md)
(search radii taken **in pixels** from the terrain preset); slope,
hillshade and the 8-bit conversion are ported to the letter from
`rvt/vis.py` (`slope_aspect`, `hillshade`, `byte_scale`) – RVT uses
2-cell central differences with edge padding, **not** `terra`'s Horn
slope. Feed a DEM at **1 m or finer** (the 0.5 m IGN LiDAR HD DTM).
Validated pixel-to-pixel against the RVT oracle
(`data-raw/oracle_rvt.R`).

## See also

[`vat_archeo()`](https://pobsteta.github.io/foretaccess/reference/vat_archeo.md)
(single VAT),
[`cvat_terrain_params()`](https://pobsteta.github.io/foretaccess/reference/cvat_terrain_params.md),
[`blend_rvt()`](https://pobsteta.github.io/foretaccess/reference/blend_rvt.md).

## Examples

``` r
mnt <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30,
                   ymin = 0, ymax = 30, crs = "EPSG:2154")
terra::values(mnt) <- 100 + as.vector(terra::rowFromCell(mnt, 1:900)) * 0.2
cvat <- vat_combined(mnt)
names(cvat)
#> [1] "cvat"
```
