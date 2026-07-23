# Micro-relief channels from a DEM (RVT sky-view factor & openness, spec 021)

Derives the **sky-view factor** and **openness** (positive and negative)
of a terrain model – the micro-relief channels that carry the signal of
a forest track (platform depression, up-slope and down-slope
embankments) far better than the raw DEM. Thin GIS wrapper over the Rust
kernel
[`rvt_svf_opns()`](https://pobsteta.github.io/foretaccess/reference/rvt_svf_opns.md)
(ported from the Relief Visualization Toolbox, Apache 2.0); the horizon
sweep runs in the crate, `terra` only lays the channels back onto the
DEM grid.

## Usage

``` r
micro_relief(
  mnt,
  radius_m = 10,
  radius_min_m = NULL,
  num_directions = 16L,
  canaux = c("svf", "openness_pos", "openness_neg")
)
```

## Arguments

- mnt:

  Digital terrain model as a single-layer `SpatRaster` (assumed square
  cells; the first layer is used if several).

- radius_m:

  Maximal horizon search radius in **metres**. Default 10.

- radius_min_m:

  Minimal search radius in metres (noise reduction). Default `NULL` -\>
  one pixel.

- num_directions:

  Number of azimuth directions swept. Default 16.

- canaux:

  Which channels to return, any of `"svf"`, `"openness_pos"`,
  `"openness_neg"`. Default: all three.

## Value

A `SpatRaster` aligned to `mnt` with one layer per requested channel
(`svf` in 0..1, `openness_pos`/`openness_neg` in degrees), `NA` where
the DEM is `NA`.

## Details

**Negative openness** is the openness of the **inverted** DEM (it lights
up up-slope banks / ditches), computed here by running the kernel on
`-z`.

The search radius is given in **metres** and converted to pixels against
the DEM resolution. RVT's scale parameters are tuned for archaeological
features a few metres wide – compatible with 3-6 m track platforms, but
run a **sensitivity sweep** on a pilot massif before freezing them (spec
021 sec.6). Feed a DEM at **1 m or finer** for road work (see
[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)).

## See also

[`rvt_svf_opns()`](https://pobsteta.github.io/foretaccess/reference/rvt_svf_opns.md)
(the Rust kernel),
[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)
and
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md)
(consumers of a \>= 1 m DEM).

## Examples

``` r
mnt <- terra::rast(nrows = 30, ncols = 30, xmin = 0, xmax = 30,
                   ymin = 0, ymax = 30, crs = "EPSG:2154")
terra::values(mnt) <- 100 # terrain plat -> svf = 1, openness = 90
mr <- micro_relief(mnt, radius_m = 5)
names(mr)
#> [1] "svf"          "openness_pos" "openness_neg"
```
