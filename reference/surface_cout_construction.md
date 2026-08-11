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
  surcout = NULL,
  methode_pente = c("bareme", "terrassement"),
  largeur_m = 4,
  pente_max_pct = NULL
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

- methode_pente:

  How the slope term is priced: `"bareme"` (default, the Lot 14 step
  function) or `"terrassement"` (spec 029, cut-and-fill volumes priced
  per cubic metre – continuous, and sensitive to platform width). The
  default is deliberate: switching the slope term changes every route
  the solver produces, so a side-by-side run on a real massif must come
  first.

- largeur_m:

  Target platform width (m), used by `methode_pente = "terrassement"`
  only. Default 4.

- pente_max_pct:

  Constructibility ceiling: cells at or above this terrain slope
  (percent) are not crossable, **whichever pricing method is used**.
  `NULL` (default) takes the ceiling the step function already implies –
  the first class priced `Inf`, i.e. 60 % with the shipped scale – so
  that switching method changes only the pricing. `Inf` gives the
  earthwork model its full reach, which on the DABO bench opens 5 % of
  the massif between 60 % and 100 % of slope. That is a separate
  decision from the pricing one, and it is meant to be taken separately.

## Value

A `foretaccess_cout_construction` object: a list of two `SpatRaster`
aligned on the DEM — `cout` (€/m, `NA` outside the crossable zone) and
`franchissable` (logical).
