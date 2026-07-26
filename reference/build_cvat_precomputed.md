# Precompute the CVAT relief over an AOI + buffer, guaranteeing coverage

Materializes the **CVAT** (Combined VAT,
[`vat_combined()`](https://pobsteta.github.io/foretaccess/reference/vat_combined.md))
as an 8-bit GeoTIFF covering the working extent (**AOI widened by
`buffer_m`**). If a DEM is passed via `mnt_existant` and it **covers the
whole AOI + buffer**, it is used as is; otherwise (missing LiDAR HD
tiles -\> the mosaic is too short, or mostly `NA`) the LiDAR HD DEM is
**re-acquired over the buffered extent** with
[`acquire_mnt()`](https://pobsteta.github.io/foretaccess/reference/acquire_mnt.md)
(WMS, which always spans the requested bbox) and the CVAT is recomputed.
This prevents a CVAT built on a partial mosaic from leaving holes or a
truncated relief in the comparator background.

## Usage

``` r
build_cvat_precomputed(
  aoi,
  cache_dir,
  buffer_m = 100,
  res_lidar_m = 0.5,
  crs = 2154,
  mnt_existant = NULL,
  out = NULL,
  overwrite = FALSE,
  seuil_couverture = 0.9,
  country = "FR"
)
```

## Arguments

- aoi:

  Working area: a path to a vector file, or an `sf`/`sfc` object.

- cache_dir:

  Directory for the (re-)acquired DEM and, by default, the CVAT.

- buffer_m:

  Buffer (m) grown around the AOI to define the extent to cover. Default
  100.

- res_lidar_m:

  LiDAR HD DEM resolution (m) used when (re-)acquiring. Default 0.5
  (native IGN LiDAR HD DTM).

- crs:

  Target CRS (EPSG code or WKT). Default 2154 (Lambert-93).

- mnt_existant:

  Optional path to an existing DEM (e.g. a native LiDAR mosaic). Reused
  when it covers the AOI + buffer; otherwise ignored.

- out:

  Output path for the 8-bit CVAT. Default `cache_dir/cvat_8bit.tif`.

- overwrite:

  Force re-acquisition (if needed) and recomputation even if `out`
  already exists.

- seuil_couverture:

  Minimal finite-cell fraction inside the extent for a DEM to count as
  covering it. Default 0.9.

- country:

  Country code for
  [`acquire_mnt()`](https://pobsteta.github.io/foretaccess/reference/acquire_mnt.md)
  layer resolution. Default `"FR"`.

## Value

Path to the 8-bit CVAT GeoTIFF (`0..255`, `NA`-\>255), covering the
AOI + buffer.

## Details

foretaccess does **not** download individual LiDAR HD tiles
(`.copc.laz`): it acquires the DEM through the IGN WMS, so
re-acquisition inherently spans the full AOI + buffer (no "missing tile"
to chase). A caller that owns a native 0.5 m tile mosaic (e.g. an app's
LiDAR ingestion) should pass it as `mnt_existant`; it is kept whenever
it already covers the extent, and only replaced by the (coarser-looking)
WMS DEM when it is too short.

## See also

[`vat_combined()`](https://pobsteta.github.io/foretaccess/reference/vat_combined.md),
[`acquire_mnt()`](https://pobsteta.github.io/foretaccess/reference/acquire_mnt.md).

## Examples

``` r
# \donttest{
# Emprise + MNT deja couvrant -> pas de reacquisition reseau :
aoi <- sf::st_as_sf(sf::st_sfc(
  sf::st_polygon(list(rbind(c(0, 0), c(20, 0), c(20, 20), c(0, 20), c(0, 0)))),
  crs = 2154))
mnt <- terra::rast(xmin = -10, xmax = 30, ymin = -10, ymax = 30,
                   resolution = 1, crs = "EPSG:2154")
terra::values(mnt) <- 100 + terra::rowFromCell(mnt, seq_len(terra::ncell(mnt)))
d <- withr::local_tempdir()
terra::writeRaster(mnt, file.path(d, "mnt.tif"))
#> Error: [writeRaster] path does not exist
p <- build_cvat_precomputed(aoi, cache_dir = d, buffer_m = 5,
                            mnt_existant = file.path(d, "mnt.tif"))
#> MNT fourni absent ou ne couvrant pas l'emprise AOI+buffer : (re)acquisition
#> LiDAR HD sur l'emprise.
terra::rast(p)
#> class       : SpatRaster
#> size        : 60, 60, 1  (nrow, ncol, nlyr)
#> resolution  : 0.5, 0.5  (x, y)
#> extent      : -5, 25, -5, 25  (xmin, xmax, ymin, ymax)
#> coord. ref. : RGF93 v1 / Lambert-93 (EPSG:2154)
#> source      : cvat_8bit.tif
#> name        : cvat
#> min value   :  213
#> max value   :  213
# }
```
