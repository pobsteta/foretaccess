# VAT composite (Visualization for Archaeological Topography) from a DEM

Builds the **VAT** blend (Kokalj & Somrak 2019) from a digital terrain
model: it derives the four RVT channels – **sky-view factor** and
**positive openness** via the Rust kernel
[`micro_relief()`](https://pobsteta.github.io/foretaccess/reference/micro_relief.md),
**slope** and analytical **hillshade** via `terra` – then fuses them
with
[`blend_rvt()`](https://pobsteta.github.io/foretaccess/reference/blend_rvt.md)
into a single grayscale composite that reveals micro-relief (platforms,
embankments, ditches, mounds) far better than any single visualization.

## Usage

``` r
vat_archeo(
  mnt,
  radius_m = 10,
  num_directions = 16L,
  sun_azimuth = 315,
  sun_elevation = 35,
  layers = vat_default_layers()
)
```

## Arguments

- mnt:

  Digital terrain model as a single-layer `SpatRaster` (square cells;
  the first layer is used if several).

- radius_m:

  Maximal horizon search radius in metres for the SVF/openness channels.
  Default 10.

- num_directions:

  Number of azimuth directions swept. Default 16.

- sun_azimuth:

  Hillshade illumination azimuth in degrees (0 = North, clockwise).
  Default 315.

- sun_elevation:

  Hillshade illumination elevation above the horizon, in degrees.
  Default 35.

- layers:

  Layer specification passed to
  [`blend_rvt()`](https://pobsteta.github.io/foretaccess/reference/blend_rvt.md);
  its `name` fields must be a subset of `"svf"`, `"openness_pos"`,
  `"slope"`, `"hillshade"`. Default
  [`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md).

## Value

A single-layer `SpatRaster` named `vat`, values in `[0, 1]`, aligned to
`mnt`.

## Details

Feed a DEM at **1 m or finer** – ideally the 0.5 m IGN LiDAR HD DTM (see
[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md));
coarser grids wash out the signal.

The default layer stack
([`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md))
reproduces RVT's shipped `VAT - Archaeological` preset
(`blender_VAT.json`); both the blend machinery and the constants are
validated pixel-to-pixel against the RVT_py oracle (as done for
[`rvt_svf_opns()`](https://pobsteta.github.io/foretaccess/reference/rvt_svf_opns.md)).
Note that the slope layer is rendered on an **inverted** scale (steep =
dark, per RVT's `normalize_image`) and that the Overlay layer's opacity
is neutralized (see
[`blend_rvt()`](https://pobsteta.github.io/foretaccess/reference/blend_rvt.md)).
Override `layers` to experiment.

## See also

[`micro_relief()`](https://pobsteta.github.io/foretaccess/reference/micro_relief.md)
(SVF/openness kernel),
[`blend_rvt()`](https://pobsteta.github.io/foretaccess/reference/blend_rvt.md)
(the blend),
[`vat_default_layers()`](https://pobsteta.github.io/foretaccess/reference/vat_default_layers.md)
(default recipe).

## Examples

``` r
mnt <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30,
                   ymin = 0, ymax = 30, crs = "EPSG:2154")
terra::values(mnt) <- 100 + as.vector(terra::rowFromCell(mnt, 1:900)) * 0.2
vat <- vat_archeo(mnt, radius_m = 5)
names(vat)
#> [1] "vat"
```
