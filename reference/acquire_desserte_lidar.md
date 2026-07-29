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
  moteur = c("auto", "dessertr", "alsroads"),
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

  Airborne LiDAR: a directory/vector of `.las`/`.laz`/`.copc.laz` tiles,
  or a lidR `LAScatalog`. Passed to `lidR::readLAScatalog()`. Not
  downloaded here – the caller provides it (e.g. the app's
  `download_ign_lidar_hd(product = "nuage")`).

- mnt:

  Digital terrain model: `SpatRaster` or path. Must share the CRS of
  `desserte` (no implicit reprojection, ADR-004).

- mnh:

  Canopy height model (`SpatRaster`/path) or `NULL`. Used by the
  dessertR surface channel (`sigma_surf`) and left `NULL` for ALSroads.

- moteur:

  LiDAR engine: `"auto"` (default – dessertR if installed, else
  ALSroads, else NDP 0), `"dessertr"` or `"alsroads"` (deprecated).

- crs:

  Target EPSG code. Default 2154.

- cache_dir:

  Directory for the per-segment measurement cache. Default
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

- dtm_res:

  Resolution (m) of the DTM derived from ground points when `mnt` is
  coarser than 1.5 m. Default 1 (robust under canopy). 0.5 matches
  ALSroads' internal profile but needs a denser ground return.

- long_min_m:

  Minimum tronçon length (m) below which measurement is skipped
  (returned `NA`) without calling ALSroads – shorter roads are unstable
  under its search buffer. Default 40. A full BD TOPO desserte has many
  short segments; only long tronçons under a tile get a width.

- deviation_max:

  Maximum lateral shift (m) allowed when dessertR re-registers a tronçon
  onto the LiDAR-detected roadbed (`dsr_repositionner()`). BD TOPO stays
  authoritative: beyond this budget the declared geometry is kept rather
  than snapped to a neighbouring track. Default 10. Ignored by the
  ALSroads engine, which has its own search buffer.

## Value

An `sf` in the format of
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
**plus** the contract columns `largeur_carrossable_m`,
`largeur_plateforme_m`, `pente_pct`, `etat_classe` (state, 4 classes)
and `score_lidar`. **`score_lidar` is not a 0-100 confidence like
ALSroads' `SCORE`**: with the dessertR engine it is dessertR's
`CONFIANCE_MNT`, i.e. the **ground point density** (pts/m²) sampled
along the tronçon – higher means the DTM under the road rests on more
ground returns. Compare it across tronçons, not against a fixed scale.
With the **dessertR** engine, also the bonus columns `etat_dessertr`
(state label), `devers` (cross-slope), `fosses` (ditches 0/1/2),
`rayon_courbure_p05`, `apte_grumier` and `motif_inaptitude`. In NDP 0
all these are `NA`. Attributes: `ndp` (`0L`/`1L`) and `moteur`
(`"dessertr"`/`"alsroads"`/`"ndp0"`).

## Details

**Engine.** The default engine is **dessertR** (`pobsteta/dessertR`,
GPL-3, Rust core) – a maintained **French** reimplementation of the
ALSroads method (Roussel et al. 2022), calibrated for BD TOPO / IGN
LiDAR HD (specs 023 + ADR-009). **ALSroads** (`r-lidar-lab/ALSroads`,
unmaintained, Quebec-calibrated) is kept as a **deprecated transition
fallback** (`moteur = "alsroads"`). Both are **optional, undeclared**
dependencies accessed dynamically; install dessertR with
`remotes::install_github("pobsteta/dessertR")` (it is **not** published
on any r-universe). Without any engine, the function falls back to **NDP
0**: the road network is returned unchanged, the LiDAR columns set to
`NA`. It **never** errors on a missing point cloud.

**DTM resolution is critical.** ALSroads builds its edge-detection
profiles at `profile_resolution = 0.5 m`; a DTM coarser than 1 m yields
`NA` widths (this was the cause of the initial 0/6 in spec 020 Phase B,
fed a 5 m accessibility grid). When the supplied `mnt` is coarser than
1.5 m, a `dtm_res`-metre DTM is derived here from the tile's ground
points – prefer passing IGN's 0.5 m LiDAR HD DTM directly.

**Calibration.** ALSroads is calibrated on Quebec (MFFP) forest roads,
but with a \>= 1 m DTM it **does** measure French BD TOPO forest roads
(spec 020 Phase B, Chastel-Nouvel: Class-1 pistes measured at ~7 m).
Still treat widths as experimental and cross-check against an orthophoto
on sensitive sites.

**Geometry and coverage.** ALSroads requires a **single `LINESTRING`**
centerline and errors on the `MULTILINESTRING` of BD TOPO
`troncon_de_route`; each tronçon is therefore recast to one `LINESTRING`
(contiguous parts merged, else the longest part kept). Tronçons
**outside the tiles' footprint** are dropped to `NA` **before** any
`measure_road` call: this is not just an optimisation but a **safety
guard** – calling ALSroads on the thousands of point-less tronçons of a
full project desserte (hundreds of km for a handful of tiles) makes
lidR/ALSroads **segfault** (an uncatchable C++ crash). Tronçons
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
# NDP 1 (requires lidR + ALSroads + a point cloud):
des <- acquire_desserte(aoi)
des_lidar <- acquire_desserte_lidar(des, las_source = "cache/lidar_nuage", mnt = mnt)
places <- places_depot(des_lidar, mnt, largeur_min_m = 4) # acces camion discriminant
} # }
```
