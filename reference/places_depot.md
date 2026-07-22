# Derive candidate cable landings from a road network

A cable yarder line cannot start just anywhere: it needs a landing with
a truck-accessible platform. `potentiel_cable(departs = )` therefore
expects a dedicated layer, which Sylvaccess treats as an input of its
own (`c_file_departure`, attribute `CABLE`). When no such survey exists,
this function derives **candidates** from the road network, by filters
that are checkable on the available data.

## Usage

``` r
places_depot(
  desserte,
  mnt,
  foret = NULL,
  retournements = NULL,
  largeur_min_m = 4,
  pente_max_pct = 6,
  fenetre_plateforme_m = 50,
  distance_foret_max_m = 100,
  espacement_min_m = 200,
  rayon_retournement_m = 20,
  sortie = c("points", "troncons")
)
```

## Arguments

- desserte:

  Road network: path to a vector file or an `sf` of lines.

- mnt:

  Digital terrain model: `SpatRaster` or path. Must share the CRS of
  `desserte` (no implicit reprojection, ADR-004).

- foret:

  Forest: path or `sf` of polygons, or `NULL` (criterion 4 off).

- retournements:

  Turning areas: path or `sf` of points, or `NULL` (criterion 2 off).

- largeur_min_m:

  Minimum carriageway width for a log truck (m). Only ever applied to a
  *measured* width; see criterion 1.

- pente_max_pct:

  Maximum **longitudinal grade** of the road at the platform (%), not
  terrain slope – see criterion 3.

- fenetre_plateforme_m:

  Length of road over which that grade is measured, centred on the
  candidate point (m). Roughly the length a landing occupies.

- distance_foret_max_m:

  Maximum distance to forest (m), used when `foret` is supplied.

- espacement_min_m:

  Spacing between two candidates *along the same* segment (m). At least
  one candidate per segment regardless.

- rayon_retournement_m:

  Max distance dead-end tip \<-\> turning area (m), used when
  `retournements` is supplied.

- sortie:

  `"points"` (default) for the landings themselves, `"troncons"` for the
  road segments that carry them.

## Value

An `sf` with a `cable` column (always `1L`, the field read by
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)):
`POINT` when `sortie = "points"` (columns `id`, `cable`, `troncon` – the
row of `desserte` it sits on –, `acces`, `largeur_m`, `pente_pct` – the
longitudinal grade), `LINESTRING` when `sortie = "troncons"` (columns
`troncon`, `cable`, `acces`, `largeur_m`, `pente_pct`, `n_places`).

## Details

The result is an `sf` carrying a `cable` field, ready to be passed
straight to
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
or written with
[`sf::st_write()`](https://r-spatial.github.io/sf/reference/st_write.html).

## Criteres

A road segment yields candidate landings when it passes, in order:

1.  **Truck access** – a segment is rejected only on **hard evidence**:
    a *measured* carriageway width (`largeur`, `largeur_de_chaussee`)
    below `largeur_min_m`. The `dfci` flag of
    [`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md)
    and the `classe` are recorded in the `acces` column but never
    reject: on the only oracle available they do not discriminate (see
    *Validation*).

2.  **Turn-around** – only when `retournements` is supplied: the segment
    is either a through-route (both ends connected to the network) or a
    dead-end with a turning area within `rayon_retournement_m` of its
    dangling tip. Without that layer the criterion is **not** applied –
    absence of evidence is not evidence of absence.

3.  **Platform** – **longitudinal grade** of the road at the candidate
    point `<= pente_max_pct`, measured over `fenetre_plateforme_m` along
    the centreline. Deliberately *not* the terrain slope: at 5 m
    resolution a road bench is not resolved by the DTM, so terrain slope
    measures the hillside, not the platform – and would eliminate
    exactly the steep ground where cable yarding is used.

4.  **Usefulness** – only when `foret` is supplied: within
    `distance_foret_max_m` of forest. A landing with no wood to reach is
    not one.

Sampling puts one candidate every `espacement_min_m` **along each
segment** (at least one per segment, whatever its length): the balance
of
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
is proportional to the number of departure cells, so a 2 km road must
not yield 400 of them. The spacing is deliberately **not** enforced
*between* segments: a greedy cross-segment thinning evicted both real
ColduPre landings, each beaten by a flatter point 18 m and 93 m away on
a neighbouring road. Recall matters more than tidiness in a pre-filter.

## Validation

Confronted with the only oracle available – the Sylvaccess ColduPre test
set, whose road network carries the surveyed `CABLE` attribute: **2
landings among 125 segments**. Both are retained (**recall 2/2**) at
every threshold below, and `pente_max_pct` buys the reduction:

|  |  |  |  |
|----|----|----|----|
| `pente_max_pct` | segments kept | recall | margin on the worst true landing |
| 4 % | 43/125 (34 %) | 2/2 | 0.6 pt |
| **6 %** (default) | **54/125 (43 %)** | **2/2** | **2.6 pt** |
| 8 % | 71/125 (57 %) | 2/2 | 4.6 pt |
| 15 % | 104/125 (83 %) | 2/2 | 11.6 pt |

Read the other column honestly: **precision is ~4 %**. This is a
**coarse pre-filter** – it halves the search space while keeping the
real landings – **not** a substitute for a survey. The `CABLE` attribute
encodes field knowledge the geometry does not carry; no threshold on
this data isolates the two real landings. Use the output to *narrow* a
field or photo-interpretation pass, not to feed
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
blind.

The default is calibrated on **two** landings. Treat it as an order of
magnitude, and re-tune it on your own massif if you can.

The bench is reproducible: `data-raw/oracle_places_depot.R`.

## Performance et selectivite

`places_depot()` scans the whole network by pure coordinate
interpolation (no per-point `sf` call): sub-second on a departmental
network. **But its output size – the number of landings – is what
governs the cost of the step after it**,
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md),
whose runtime is proportional to the number of departures. On a raw BD
TOPO network **with no measured width and no `retournements` layer**,
criteria 1-2 reject nothing, so only grade and forest proximity filter –
yielding *hundreds to thousands* of loose departures and an
over-optimistic cable coverage.

To bring departures down to an **exploitable** count (tens), feed it
richer inputs, in order of effect:

- a **`retournements`** layer (turn-arounds) – turns criterion 2 on, the
  single biggest cut on a real network;

- a **measured width** (`largeur` / `largeur_de_chaussee`, or
  LiDAR-derived, see `acquire_desserte_lidar()` roadmap) – turns
  criterion 1 into a real truck-access filter;

- a tighter **`espacement_min_m`** and lower **`pente_max_pct`**.

Without any of these it stays a coarse pre-filter: usable to *narrow* a
manual pass, not to feed the cable engine blind at interactive speed.

## See also

[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
(consumes the layer),
[`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md)
(feeds the `dfci` flag reported by criterion 1).

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
places <- places_depot(
  desserte = file.path(toy, "desserte.gpkg"),
  mnt = file.path(toy, "mnt.tif"),
  foret = file.path(toy, "foret.gpkg"),
  espacement_min_m = 100
)
#> ! Aucune largeur mesuree (largeur / largeur_de_chaussee) : le critere d'acces
#>   camion ne rejette rien.
#> ℹ Les colonnes dfci et classe sont rapportees dans acces mais ne tranchent pas
#>   -- sur l'oracle ColduPre elles ecartent une vraie place de depot sur deux.
#> ℹ Aucune couche `retournements` : le critere de demi-tour n'est pas applique.
#> ✔ 2 places de depot candidates sur 1/3 troncons.
#> ! Pre-filtre grossier, pas un releve. Sur l'oracle ColduPre : les 2 vraies
#>   places de depot sont retrouvees, mais parmi 54 troncons sur 125 (precision ~4
#>   %).
#> ℹ A confirmer par photo-interpretation ou visite. Voir la section Validation de
#>   `places_depot()`.
places
#> Simple feature collection with 2 features and 6 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 125 ymin: 62.5 xmax: 125 ymax: 187.5
#> Projected CRS: RGF93 v1 / Lambert-93
#>     id cable troncon        acces largeur_m pente_pct          geometry
#> 2    1     1       2 classe:piste        NA         0  POINT (125 62.5)
#> 2.1  2     1       2 classe:piste        NA         0 POINT (125 187.5)
```
