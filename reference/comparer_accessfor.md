# Compare debarking classes against the IGN ACCESSFOR layer

Confronts a
[`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md)
raster with the IGN **ACCESSFOR** reference (skidder or porteur), on the
grid of the raster itself. ACCESSFOR is rasterised in
**nearest-neighbour** (a class code must never be interpolated), mapped
onto our value scheme via
[`accessfor_correspondance()`](https://pobsteta.github.io/foretaccess/reference/accessfor_correspondance.md),
and the two are cross-tabulated **only on the intersection of the forest
masks** – the three masks (ours, ACCESSFOR, ACCESSFOR-V3) differ, so any
global figure that ignored this would be dominated by a masking
artefact.

## Usage

``` r
comparer_accessfor(
  cl,
  accessfor,
  champ = "class",
  config = foretaccess_config()
)
```

## Arguments

- cl:

  A categorical
  [`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md)
  raster (values `1..k+3`).

- accessfor:

  An `sf`/`SpatVector` of ACCESSFOR polygons carrying an integer class
  column. Must share the CRS of `cl` (no implicit reprojection,
  ADR-004).

- champ:

  Name of the ACCESSFOR class column. Default `"class"`.

- config:

  The `foretaccess_config` whose bands define the crosswalk. Default
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

An object of class `foretaccess_accessfor_compare`: `matrice` (area in
ha, our class in rows x ACCESSFOR class in cols, on the common mask),
`accord_global` (share of area on the diagonal), `accord_agrege`
(accessible/non-accessible 2x2 agreement), `surface_ha` (common, and
each mask-only area excluded from the comparison), and `config`.

## Lecture

The robust number is the **aggregated** agreement (accessible vs not): a
strong disagreement on the far bands is expected (machine parameters,
reference road network), while an accessible-vs-inaccessible flip is a
signal to investigate. The `inexploitable` class only appears if
[`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md)
was given `pre`; its ACCESSFOR threshold (slope) is not published, so a
disagreement there is a parameter artefact, not a defect.

## See also

[`accessfor_correspondance()`](https://pobsteta.github.io/foretaccess/reference/accessfor_correspondance.md),
[`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md).
