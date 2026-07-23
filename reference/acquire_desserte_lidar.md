# Enrich/correct a road network with airborne LiDAR (ALSroads, NDP 1)

Wraps **ALSroads** (`measure_road`) to recompute, from an airborne LiDAR
point cloud, a **realigned geometry** and per-segment attributes for a
BD TOPO road network: **drivable width**, platform width, longitudinal
slope and **state** (in use / decommissioned / gone). The drivable width
is the discriminator
[`places_depot()`](https://pobsteta.github.io/foretaccess/reference/places_depot.md)
lacks on raw BD TOPO (its truck-access criterion is blind without a
measured width, hence loose departures – see its *Performance et
selectivite* section); a measured width turns that criterion on.

## Usage

``` r
acquire_desserte_lidar(
  desserte,
  las_source,
  mnt,
  crs = 2154,
  cache_dir = tempdir()
)
```

## Arguments

- desserte:

  Road network: path to a vector file or an `sf` of lines (the output of
  [`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)).

- las_source:

  Airborne LiDAR: a directory/vector of `.las`/`.laz`/`.copc.laz` tiles,
  or a lidR `LAScatalog`. Passed to `lidR::readLAScatalog()`. Not
  downloaded here – the caller provides it (e.g. the app's
  `download_ign_lidar_hd(product = "nuage")`).

- mnt:

  Digital terrain model: `SpatRaster` or path. Must share the CRS of
  `desserte` (no implicit reprojection, ADR-004).

- crs:

  Target EPSG code. Default 2154.

- cache_dir:

  Directory for the per-segment measurement cache. Default
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

## Value

An `sf` in the format of
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
**plus** the columns `largeur_carrossable_m` (ALSroads `DRIVABLEWIDTH`),
`largeur_plateforme_m` (`ROADWIDTH`), `pente_pct` (computed here from
the realigned geometry), `etat_classe` (ALSroads `CLASS` – road **state
in four classes**) and `score_lidar` (`SCORE`). In NDP 0 (no
LiDAR/ALSroads) the geometry is unchanged and those columns are `NA`.
The `ndp` attribute is `0L` or `1L`.

## Details

**Optional, experimental (NDP 1).** ALSroads and lidR are **not**
declared dependencies – ALSroads is an unmaintained proof-of-concept
(`r-lidar-lab/ALSroads`, v0.2.0). Install them yourself to use this:
`install.packages("lidR")` and
`remotes::install_github("r-lidar-lab/ALSroads")`. Without them, the
function falls back to **NDP 0**: the road network is returned
unchanged, the LiDAR columns set to `NA`, and a message says so. It
**never** errors on a missing point cloud.

**Calibration caveat.** ALSroads is calibrated on Quebec (MFFP) forest
roads. Its widths are **not yet validated on French data** (spec 020,
Phase B). Treat the output as experimental until validated on a local
site; do not base a firm decision on its widths before then.

## See also

[`places_depot()`](https://pobsteta.github.io/foretaccess/reference/places_depot.md)
(consumes the drivable width),
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# NDP 1 (requires lidR + ALSroads + a point cloud):
des <- acquire_desserte(aoi)
des_lidar <- acquire_desserte_lidar(des, las_source = "cache/lidar_nuage", mnt = mnt)
places <- places_depot(des_lidar, mnt, largeur_min_m = 4) # acces camion discriminant
} # }
```
