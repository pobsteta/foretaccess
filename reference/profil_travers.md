# Cross-section of a road segment at a clicked point (spec 030)

Returns everything needed to **draw** the cross-section of the nearest
road segment: the LiDAR points of a slice taken across the axis, the
ground profile, a fitted road crown, and five families of edges with
their widths. It draws nothing itself – the caller does (no plotting in
the core, no business logic in the app).

## Usage

``` r
profil_travers(
  desserte,
  xy,
  las_source,
  mnt,
  crs = 2154,
  tolerance_m = 25,
  demi_largeur = 20,
  epaisseur_m = 2,
  pas_travers = 0.25,
  h_obstacle = c(0.5, 5),
  pente_max = 0.2,
  tol_chaussee = 0.05,
  tol_plateforme = 0.15,
  cache_dir = tempdir()
)
```

## Arguments

- desserte:

  Road network: path or `sf` of lines (BD TOPO, ideally the
  corrected/qualified one – see
  [`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md)).

- xy:

  The clicked point: `numeric(2)` (x, y in `crs`) or an `sf`/`sfc`
  `POINT`.

- las_source:

  Airborne LiDAR: a directory, a vector of `.las`/`.laz` files, or a
  `dessertR` catalogue (column `laz`) – same vocabulary as
  [`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md).

- mnt:

  Digital terrain model: `SpatRaster` or path, **1 m or finer**.

- crs:

  Target EPSG code. Default 2154.

- tolerance_m:

  Snapping radius (m): beyond it, no segment is deemed clicked. Default
  25.

- demi_largeur:

  Half-width of the cross-section (m). Default 20.

- epaisseur_m:

  Thickness (m) of the slice taken **along** the axis. The points of the
  slice are projected onto the section plane; a thicker slice shows more
  points and more longitudinal blur. Default 2.

- pas_travers:

  Transverse sampling step (m) of the ground profile and of the
  occupancy bins. Default 0.25.

- h_obstacle:

  Height band (m) above ground read as **standing obstacles** (trunks,
  regrowth, blocks), for `right_of_way`. Default `c(0.5, 5)`.

- pente_max:

  Cross-slope (m/m) up to which the ground is deemed crossable, for
  `rescue`. Default 0.20.

- tol_chaussee, tol_plateforme:

  Vertical tolerances (m) of the `drivable` and `road` runs. Defaults
  0.05 and 0.15.

- cache_dir:

  Directory for the per-click cache. Default
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

## Value

A `list`, or `NULL` (see Details). Elements:

- `troncon` – `sf`, one row: the snapped segment with its attributes;

- `station` – `list`: `chainage_m` along the segment, `xy` of the point
  projected on the axis;

- `points` – `data.frame`, one LiDAR point per row: `x_travers` (m,
  **signed**, 0 = axis), `z` (m, 0 = ground at the axis), `intensite`,
  `sol` (logical), `classification`, plus `hauteur_sol` and `abscisse`
  (position along the axis within the slice);

- `sol` – `data.frame`: `x_travers`, `z` of the ground profile;

- `ajustement` – `list`: `a`, `b`, `c` of the crown parabola, `rmse`,
  `n`, `source` (`"points_sol"` or `"mnt"`), or `NULL` if unfittable;

- `bords` – `data.frame`, one row per edge family: `type` (one of
  `drivable`, `road`, `right_of_way`, `shoulder`, `rescue`), `cote`,
  `x_gauche`, `x_droite`, `largeur_m`;

- `meta` – `list`: `moteur`, `n_points`, `n_dalles`, `demi_largeur`,
  `epaisseur_m`, `pas_travers`, `crs`, `z_ref` (absolute elevation of
  `z = 0`), `tolerance_m`, `cache`.

## Details

**Vertical datum.** `z = 0` is the ground **at the axis** (the DTM
elevation at the station), not the ground under each point. Normalising
point by point would flatten the road crown, which is exactly what
`ajustement` fits. Height above the local ground is available per point
as `hauteur_sol`.

**The five edge families.** They are defined here, not by any engine
(`dsr_measure()` gives the drivable width, `dsr_emprise_certu()` a
normative footprint; neither yields the five). All are derived from
*this* profile:

- `road` – the **platform** (road prism): the run around the axis where
  the ground stays within `tol_plateforme` of the plane fitted on the
  central window. It stops at the ditch, the cut slope or the fill toe.

- `drivable` – the **carriageway**: the run where the ground stays
  within `tol_chaussee` of the fitted crown parabola, **clipped to
  `road`**. Clipping is what makes `drivable <= road` a property rather
  than a hope.

- `shoulder` – what is left of the platform on each side, hence **two
  rows** (`cote` = `"gauche"` / `"droite"`), possibly of zero width.

- `rescue` – the width usable by an **emergency vehicle**: grown
  outwards from `road` while the ground stays crossable (cross-slope
  under `pente_max`), then clipped to `right_of_way`. Neither the ditch,
  nor the cut slope, nor the undergrowth.

- `right_of_way` – the cleared corridor: the run around the axis free of
  any echo in the **trunk band** (`h_obstacle` m above the ground),
  **unioned with `road`**.

The four symmetric families are therefore **nested by construction**:
`drivable <= road <= rescue <= right_of_way`. It is a property of the
code, not a hope about the terrain.

**Trunks, not canopy.** The corridor is read on the trunk band and not
on the canopy, and that is a measurement, not a preference: on the
`dessertR` sample tile (Lozère, closed high forest) the crowns close
**over** a 3.6 m track, so a *"no echo above 2 m"* rule returns a
zero-width gap and a right of way equal to the platform – a family that
no longer says anything. Trunks stand back: 23 m of clear corridor at
the very same station.

**Cost.** Only a rectangle of `epaisseur_m` x 2 `demi_largeur` is read,
and only from the tiles whose LAS header meets it. A click reads a few
thousand points, not a tile.

**Degraded modes all return `NULL`** – never an error, never a
half-filled list: no segment within `tolerance_m`, no `rlas` (the
point-cloud reader, a `dessertR` dependency), no tile under the station,
or an empty slice. The `cli` message says which one.

## See also

[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md)
(the corrected network to feed it),
[`classer_desserte()`](https://pobsteta.github.io/foretaccess/reference/classer_desserte.md),
`specs/030`.

## Examples

``` r
if (FALSE) { # \dontrun{
des <- acquire_desserte(aoi)
p <- profil_travers(des, c(937500, 6480000), "cache/lidar_nuage", mnt)
if (!is.null(p)) p$bords
} # }
```
