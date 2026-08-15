# Qualify a declared road network with airborne LiDAR (spec 021, step 1)

Turns a **declared** BD TOPO road network into a **qualified** one,
using airborne LiDAR: the geometry is **relocated** onto the
LiDAR-detected centerline and the **width** is filled from the LiDAR
measurement (the BD TOPO `largeur` field is usually empty). This
addresses the weakest link of the pipeline – the desserte is never
computed, only imported, so its position and width errors propagate
untouched into all four engines. The output conforms to
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)'s
input contract, so engines and the Sylvaccess non-regression are
**unchanged**.

## Usage

``` r
qualifier_desserte(
  desserte,
  las_source,
  mnt,
  mnh = NULL,
  moteur = c("auto", "dessertr"),
  crs = 2154,
  cache_dir = tempdir(),
  dtm_res = 1,
  retirer_disparues = FALSE,
  etats_disparus = c("abandonnee", "hors_route"),
  etat_disparue = 4L,
  retirer_inaptes_grumier = FALSE
)
```

## Arguments

- desserte:

  Declared road network: path or `sf` of lines (the output of
  [`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)).
  Must carry the `classe` field preprocess() expects.

- las_source:

  Airborne LiDAR (see
  [`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)).

- mnt:

  Digital terrain model (**1 m or finer**). See
  [`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md).

- mnh:

  Canopy height model for the dessertR surface channel. See
  [`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md).

- moteur:

  LiDAR engine passed to
  [`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md):
  `"auto"` (default) or `"dessertr"`. `"alsroads"` is an error since
  v1.27.0.

- crs:

  Target EPSG code. Default 2154.

- cache_dir:

  Directory for the measurement cache. Default
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

- dtm_res:

  Resolution (m) of the reference grid built from `mnt`. Default 1.

- retirer_disparues:

  Drop segments whose measured state marks them gone (existence
  qualification)? Default `FALSE` – opt-in. Unmeasured segments (state
  `NA`) are **never** dropped.

- etats_disparus:

  dessertR state labels deemed gone when `retirer_disparues = TRUE`.
  Default `c("abandonnee", "hors_route")`.

- etat_disparue:

  Fallback on the integer `etat_classe`: value at/beyond which a segment
  is gone. Used only when the `etat_dessertr` label is absent (NDP 0, or
  a state raster that could not be built). Default `4L`.

- retirer_inaptes_grumier:

  Drop segments **unfit for timber trucks** (`apte_grumier == FALSE`,
  dessertR trafficability)? Default `FALSE` – opt-in. Unmeasured
  segments are never dropped.

## Value

An `sf` conforming to
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
(fields `classe`, `largeur`, geometry) with the LiDAR provenance columns
of
[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)
kept as extras, and a `largeur` filled from the measured drivable width
where available. Attributes: `ndp` (`0L`/`1L`) and `qualifiee` (`TRUE`),
plus a per-row `qualifiee` column carrying the same mark. The **column**
is what
[`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md)
checks (CA-28.4), because it survives subsetting and the merge with the
declared BD TOPO network, whereas the layer attribute does not.

## Details

**Deterministic step 1 (spec 021).** A thin post-processing over
[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)
(which wraps dessertR's `dsr_measure()`): the engine *corrects* an
existing map, it does **not** detect roads absent from BD TOPO – those
stay absent. Detecting missing tracks is step 2 (a CNN on RVT-derived
channels, spec 021 sec.5), a research milestone not implemented here.

**Requires a DTM \>= 1 m** (see
[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)).
Without dessertR, it falls back to **NDP 0** – the network is returned
unchanged (no relocation, width left as-is) and a message says
qualification was inoperative.

**State semantics are not ground-truthed on French data.** dessertR is
calibrated on BD TOPO / IGN LiDAR HD, but on French pistes a worst-state
segment may still be *degraded-but-real*, not *gone*. Dropping segments
by state is therefore **opt-in** (`retirer_disparues = FALSE` by
default) until a French reference (DESSOPT) quantifies the mapping.

## See also

[`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)
(the underlying measurement),
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
(the declared input),
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
(the consumer).

## Examples

``` r
if (FALSE) { # \dontrun{
des  <- acquire_desserte(aoi)                       # declaree (BD TOPO)
desq <- qualifier_desserte(des, "cache/lidar_nuage", mnt) # relocalisee + largeur
pre  <- preprocess(mnt = mnt, desserte = desq, foret = foret)
} # }
```
