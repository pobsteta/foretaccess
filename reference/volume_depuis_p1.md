# Rasterise a per-hectare volume layer onto the DTM grid

The cable engine and the line selection (Lot 5) read a **standing-volume
raster** from `pre$volume`, in m3/ha per cell:
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
sums it over the forest cells a line covers to get the line volume and
the cable production index (IPC = volume / length). ForetAccess does
**not** compute that volume – it is an input.

## Usage

``` r
volume_depuis_p1(p1, mnt, champ = "P1", fun = "mean")
```

## Arguments

- p1:

  Units carrying the per-hectare volume: path to a vector file or an
  `sf` of polygons (the output of `nemeton::indicateur_p1_volume()`, or
  any equivalent layer).

- mnt:

  DTM defining the target grid: `SpatRaster` or path. Must share the CRS
  of `p1` (no implicit reprojection, ADR-004).

- champ:

  Name of the m3/ha column to rasterise. Default `"P1"` (the column
  Nemeton writes).

- fun:

  How to combine when several units cover one cell. Default `"mean"` –
  correct for a density; overlapping units are unusual but must not be
  summed. Passed to
  [`terra::rasterize()`](https://rspatial.github.io/terra/reference/rasterize.html).

## Value

A single-layer `SpatRaster` named `volume`, aligned on `mnt`, ready for
`preprocess(volume = )`. Cells no unit covers are `NA` (no wood, not
zero).

## Details

Its natural source is a forest inventory or a LiDAR canopy-height model,
e.g. Nemeton's **P1** indicator (`nemeton::indicateur_p1_volume()`),
which returns an `sf` of units carrying a volume in **m3/ha**.
`volume_depuis_p1()` bridges that `sf` to the grid the engines expect.
It takes no dependency on Nemeton: it rasterises whatever per-hectare
field you give it, wherever it comes from.

## Unites

`champ` **must be a density in m3/ha**, not an absolute volume per unit.
The cable multiplies each cell by `aire_cellule / 10000` to turn m3/ha
back into m3; a field in absolute m3 would inflate the result by the
number of cells per unit. This is the same convention as `vol_ha.tif` in
the Sylvaccess ColduPre set.

## See also

[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
(consumes the raster),
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
(sums it per line into volume and IPC).

## Examples

``` r
if (FALSE) { # \dontrun{
# Volume from Nemeton's P1 indicator (inventory or LiDAR CHM), then cable.
p1  <- nemeton::indicateur_p1_volume(parcelles, chm = mnh_lidar)
vol <- volume_depuis_p1(p1, mnt)
pre <- preprocess(mnt, desserte, foret, volume = vol)
ca  <- potentiel_cable(pre, departs = places)
} # }
```
