# Classify detected linear features (desserte, skid trail, firebreak...)

Wraps `dessertR::dsr_classer()`: labels each line of a **detected**
network with `CLASSE`, `CLASSE_CONF` (share of informed criteria that
agree), `CLASSE_MOTIF` (which criteria voted) and `OSM_TAGS` (a
*proposed* tagging, never uploaded).

## Usage

``` r
classer_desserte(
  traces,
  reference = NULL,
  parcellaire = NULL,
  sous_type_parcelle = c("section", "border"),
  stations = NULL,
  ndvi = NULL,
  tpi = NULL,
  ...
)
```

## Arguments

- traces:

  Detected network: path or `sf` of lines (the output of
  [`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md)).

- reference:

  Reference network (`sf`/`sfc`, e.g. BD TOPO): what it carries is a
  desserte. `NULL` to judge every line on its structure alone.

- parcellaire:

  Forest compartment boundaries (`sf`/`sfc`) or `NULL`.

- sous_type_parcelle:

  OSM sub-type of those boundaries: `"section"` (management units –
  boundaries marked on the ground) or `"border"` (cadastral property
  limits). Passed **explicitly** to `dessertR`, which otherwise emits a
  notice: the value cannot be read off the geometry.

- stations:

  Per-station measurements (`sf`/`data.frame` with a `troncon` column,
  from `dsr_measure()`) or `NULL`.

- ndvi:

  `SpatRaster` of NDVI, or `NULL` – without it, road/track is never
  decided and `pare_feu` is never posted.

- tpi:

  `SpatRaster` of topographic position, or `NULL`.

- ...:

  Passed to `dessertR::dsr_classer()`.

## Value

The input `sf` with `CLASSE`, `CLASSE_CONF`, `CLASSE_MOTIF` and
`OSM_TAGS`. Attribute `disponible`: `FALSE` when `dessertR` is missing
or the classification failed – the columns are then all `NA` and a
**warning** is emitted. `NA` classes mean *"not classified"*, never
*"nothing found"*.

## Details

**Why it lives here.** Callers depend on `foretaccess`, never on its
engine. The app used to call `dessertR::dsr_classer()` directly, wrapped
in a [`tryCatch()`](https://rdrr.io/r/base/conditions.html) that
returned `NULL`: without `dessertR` installed the classification
vanished **silently**. Here the unavailability is a warning and an
attribute, not an absence.

**Geometry.** `dsr_classer()` requires `LINESTRING`; BD TOPO and most
detection outputs are `MULTILINESTRING`. The recast is done here, once.

**The criteria you do not pass are unknown, not false.** `stations`
([`acquire_desserte_lidar()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_lidar.md)'s
measurement), `ndvi` and `tpi` each switch on a family of criteria;
without them `dessertR` declares them unknown and `CLASSE_CONF` drops.
**Always display `CLASSE_CONF` next to `CLASSE`.**

## See also

[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md),
[`dessertR_disponible()`](https://pobsteta.github.io/foretaccess/reference/dessertR_disponible.md),
`specs/030`.

## Examples

``` r
det <- sf::st_sf(geometry = sf::st_sfc(
  sf::st_linestring(rbind(c(0, 0), c(100, 0))), crs = 2154))
cl <- classer_desserte(det)      # sans dessertR : colonnes a NA, avertissement
#> Warning: ! Lineaires NON CLASSES : dessertR absent.
#> ✖ Une classe "NA" signifie non classe, jamais rien trouve.
#> ℹ `remotes::install_github("pobsteta/dessertR")`
#> ℹ Tester d'avance avec `dessertR_disponible()`.
attr(cl, "disponible")
#> [1] FALSE
```
