# Enrich/correct a road network with airborne LiDAR (dessertR, NDP 1)

Recomputes, from an airborne LiDAR HD point cloud, a **realigned
geometry** and per-segment attributes for a BD TOPO road network:
**drivable width**, platform width, longitudinal slope, **state** and
(dessertR) cross-slope, ditches, curvature and **timber-truck
trafficability**. The drivable width is the discriminator
[`places_depot()`](https://pobsteta.github.io/foretaccess/reference/places_depot.md)
lacks on raw BD TOPO (its truck-access criterion is blind without a
measured width); a measured width turns that criterion on.

## Usage

``` r
acquire_desserte_lidar(
  desserte,
  las_source,
  mnt,
  mnh = NULL,
  moteur = c("auto", "dessertr"),
  crs = 2154,
  cache_dir = tempdir(),
  dtm_res = 1,
  long_min_m = 40,
  deviation_max = 10
)
```

## Arguments

- desserte:

  Road network: path to a vector file or an `sf` of lines (the output of
  [`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)).

- las_source:

  Airborne LiDAR: a directory/vector of `.las`/`.laz`/`.copc.laz` tiles.
  Not downloaded here – the caller provides it (e.g. the app's
  `download_ign_lidar_hd(product = "nuage")`).

- mnt:

  Digital terrain model: `SpatRaster` or path, **1 m or finer**. Must
  share the CRS of `desserte` (no implicit reprojection, ADR-004).

- mnh:

  Canopy height model (`SpatRaster`/path) or `NULL`. Used by the
  dessertR surface channel (`sigma_surf`).

- moteur:

  LiDAR engine: `"auto"` (default) or `"dessertr"` – both resolve to
  dessertR if installed, else NDP 0. Kept for API stability;
  `"alsroads"` is an error since v1.27.0.

- crs:

  Target EPSG code. Default 2154.

- cache_dir:

  Directory for the per-segment measurement cache. Default
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

- dtm_res:

  Resolution (m) of the reference grid built from `mnt`. Default 1
  (robust under canopy); 0.5 sharpens the profiles but needs a denser
  ground return.

- long_min_m:

  Minimum tronçon length (m) below which measurement is skipped
  (returned `NA`) – shorter roads are unstable under the search buffer.
  Default 40. A full BD TOPO desserte has many short segments; only long
  tronçons under a tile get a width.

- deviation_max:

  Maximum lateral shift (m) allowed when dessertR re-registers a tronçon
  onto the LiDAR-detected roadbed (`dsr_repositionner()`). BD TOPO stays
  authoritative: beyond this budget the declared geometry is kept rather
  than snapped to a neighbouring track. Default 10.

## Value

An `sf` in the format of
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
**plus** the contract columns `largeur_carrossable_m`,
`largeur_plateforme_m`, `pente_pct`, `etat_classe` (state, 4 classes)
and `score_lidar`. **`score_lidar` is not a 0-100 confidence like
ALSroads' former `SCORE`**: it is dessertR's `CONFIANCE_MNT`, i.e. the
**ground point density** (pts/m²) sampled along the tronçon – higher
means the DTM under the road rests on more ground returns. Compare it
across tronçons, not against a fixed scale. Also the bonus columns
`etat_dessertr` (state label), `devers` (cross-slope), `fosses` (ditches
0/1/2), `rayon_courbure_p05`, `apte_grumier` and `motif_inaptitude`. In
NDP 0 all these are `NA`. Attributes: `ndp` (`0L`/`1L`) and `moteur`
(`"dessertr"`/`"ndp0"`).

## Details

**Engine.** The engine is **dessertR** (`pobsteta/dessertR`, GPL-3, Rust
core) – a maintained **French** reimplementation of the ALSroads method
(Roussel et al. 2022), calibrated for BD TOPO / IGN LiDAR HD (specs
023 + ADR-009). It is an **optional, undeclared** dependency accessed
dynamically; install it with
`remotes::install_github("pobsteta/dessertR")` (it is **not** published
on any r-universe). Without it, the function falls back to **NDP 0**:
the road network is returned unchanged, the LiDAR columns set to `NA`.
It **never** errors on a missing point cloud.

**ALSroads was removed** in v1.27.0 (spec 023 Phase C, ADR-009) after
the Phase B bench validated the dessertR adapter. It had been the engine
from v1.16.0, then a deprecated transition fallback.
`moteur = "alsroads"` is now an error.

**DTM resolution is critical.** Edge-detection profiles are built at a
sub-metre step; a DTM coarser than 1 m yields `NA` widths (this was the
cause of the initial 0/6 in spec 020 Phase B, fed a 5 m accessibility
grid). Pass a DTM at **1 m or finer** – IGN's LiDAR HD DTM is ideal.

**Geometry and coverage.** Measurement needs a **single `LINESTRING`**
centerline, and BD TOPO `troncon_de_route` is `MULTILINESTRING`; each
tronçon is therefore recast to one `LINESTRING` (contiguous parts
merged, else the longest part kept). Tronçons **outside the tiles'
footprint** are dropped to `NA` **before** any measurement, and tronçons
**shorter than `long_min_m`** are likewise skipped. Expect **most of a
full desserte to be `NA`** and only the long tronçons lying under a tile
to carry a width. The `bilan` attribute of the result breaks the outcome
down: `mesure`, `trop_court`, `hors_couverture`, `geometrie`, `echec`,
`total`.

## See also

[`places_depot()`](https://pobsteta.github.io/foretaccess/reference/places_depot.md)
(consumes the drivable width),
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md).

## Examples

``` r
if (FALSE) { # \dontrun{
# NDP 1 (requires dessertR + a point cloud):
des <- acquire_desserte(aoi)
des_lidar <- acquire_desserte_lidar(des, las_source = "cache/lidar_nuage", mnt = mnt)
places <- places_depot(des_lidar, mnt, largeur_min_m = 4) # acces camion discriminant
} # }
```
