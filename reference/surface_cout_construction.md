# Build the construction-cost surface of a new forest road

Produces the per-cell **construction cost** (monetary, €/m of road
crossing the cell) that the route solver (Lot 15) will propagate, plus a
**crossability** layer (`NA`/`FALSE` = the solver must not traverse the
cell). The cost is additive: base cost + slope surcharge (by class) +
soil surcharge + point crossings (bridge over water bodies, culvert over
streams) + a free additional surcharge. Only the base cost is required;
every optional layer that is absent contributes nothing (never errors).

## Usage

``` r
surface_cout_construction(
  pre,
  config = foretaccess_config(),
  plan_eau = NULL,
  cours_eau = NULL,
  sol = NULL,
  interdit = NULL,
  surcout = NULL
)
```

## Arguments

- pre:

  A `foretaccess_preprocessing` object (Lot 1): supplies the DEM grid,
  terrain slope (`slope_pct`) and the complete-obstacle mask.

- config:

  A `foretaccess_config`; the cost scale lives in
  `config$desserte$cout`.

- plan_eau:

  Optional water-body layer (bridges): `SpatRaster` (`> 0` = water) or
  `sf` polygons. Cells receive `cout_pont_m`.

- cours_eau:

  Optional stream layer (culverts): `SpatRaster` (metres of stream per
  cell, or `> 0`) or `sf` lines. Cells receive `cout_buse_m` scaled by
  the crossed fraction.

- sol:

  Optional soil-class layer (`SpatRaster` of class codes or `sf`
  polygons with a `classe` field); mapped through
  `config$desserte$cout$bareme_sol`.

- interdit:

  Optional forbidden-area layer (`SpatRaster` `> 0` or `sf` polygons):
  those cells are not crossable.

- surcout:

  Optional free additional surcharge (`SpatRaster`, €/m).

## Value

A `foretaccess_cout_construction` object: a list of two `SpatRaster`
aligned on the DEM — `cout` (€/m, `NA` outside the crossable zone) and
`franchissable` (logical).
