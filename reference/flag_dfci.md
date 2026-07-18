# Pose le flag DFCI (CL_DFCI) sur la desserte

Marks the road segments that make up the fire-defence network (DFCI),
the source of the DFCI truck engine (spec 006). The flag is orthogonal
to the `route`/`piste`/`reseau_public` classes. Two strategies, in
order:

- **Route A (dedicated OSM source)** — a segment is flagged when it
  coincides (within `tol_appariement_m`) with an OSM DFCI track
  (`ref:FR:DFCI`).

- **Route B (geometric fallback)** — when `dfci_lignes` is empty/`NULL`,
  keep the tracks that are either *through-routes* wider than
  `emprise_min_m`, or *dead-ends fitted with a turning area* (within
  `rayon_retournement_m` of the dangling end). This is an explicitly
  heuristic guess (false positives possible), logged as such.

## Usage

``` r
flag_dfci(
  desserte,
  dfci_lignes = NULL,
  retournements = NULL,
  emprise_min_m = 10,
  rayon_retournement_m = 20,
  tol_appariement_m = 10
)
```

## Arguments

- desserte:

  An `sf` of line features (from
  [`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)).

- dfci_lignes:

  An `sf` of DFCI tracks (from
  [`acquire_dfci()`](https://pobsteta.github.io/foretaccess/reference/acquire_dfci.md)),
  or `NULL`.

- retournements:

  An `sf` of turning-area points, or `NULL`.

- emprise_min_m:

  Minimum width of a through DFCI track (m). Default 10.

- rayon_retournement_m:

  Max distance dead-end tip \<-\> turning area (m). Default 20.

- tol_appariement_m:

  Matching tolerance desserte \<-\> OSM DFCI (m). Default 10.

## Value

`desserte` with an added integer column `dfci` (0/1).

## See also

[`acquire_dfci()`](https://pobsteta.github.io/foretaccess/reference/acquire_dfci.md),
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
