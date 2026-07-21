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
  pente_max_pct = 15,
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

  Minimum carriageway width for a log truck (m).

- pente_max_pct:

  Maximum terrain slope of the platform (%).

- distance_foret_max_m:

  Maximum distance to forest (m), used when `foret` is supplied.

- espacement_min_m:

  Minimum spacing between two landings (m).

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
row of `desserte` it sits on –, `acces`, `largeur_m`, `pente_pct`),
`LINESTRING` when `sortie = "troncons"` (columns `troncon`, `cable`,
`acces`, `largeur_m`, `pente_pct`, `n_places`).

## Details

The result is an `sf` carrying a `cable` field, ready to be passed
straight to
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
or written with
[`sf::st_write()`](https://r-spatial.github.io/sf/reference/st_write.html).

## Criteres

A road segment yields candidate landings when it passes, in order:

1.  **Truck access** – carriageway width `>= largeur_min_m` where a
    width attribute is available (`largeur`, `largeur_de_chaussee`);
    failing that, the `dfci` flag of
    [`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md);
    failing that, a `classe` of `"route"` or `"dfci"`. A network
    carrying none of those attributes cannot be filtered on access at
    all: everything passes, and the function says so.

2.  **Turn-around** – only when `retournements` is supplied: the segment
    is either a through-route (both ends connected to the network) or a
    dead-end with a turning area within `rayon_retournement_m` of its
    dangling tip. Without that layer the criterion is **not** applied –
    absence of evidence is not evidence of absence.

3.  **Platform** – terrain slope at the candidate point
    `<= pente_max_pct` (Horn,
    [`calculer_terrain()`](https://pobsteta.github.io/foretaccess/reference/calculer_terrain.md)).
    A point where slope is undefined (MNT border) is dropped.

4.  **Usefulness** – only when `foret` is supplied: within
    `distance_foret_max_m` of forest. A landing with no wood to reach is
    not one.

Surviving points are then **thinned** to `espacement_min_m`, flattest
first: the balance of
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
is proportional to the number of departure cells, and two landings 20 m
apart sweep the same forest twice.

## See also

[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
(consumes the layer),
[`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md)
(feeds the `dfci` flag used by criterion 1).

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
# Le MNT jouet est un plan a 20 % : on releve le seuil de planeite en
# consequence (aucune plateforme a 15 % sur ce terrain).
places <- places_depot(
  desserte = file.path(toy, "desserte.gpkg"),
  mnt = file.path(toy, "mnt.tif"),
  foret = file.path(toy, "foret.gpkg"),
  pente_max_pct = 25,
  espacement_min_m = 100
)
#> ℹ Aucune couche `retournements` : le critere de demi-tour n'est pas applique.
#> ✔ 3 places de depot candidates sur 1/3 troncons.
#> ! Candidates heuristiques, pas un releve : une place de depot exige une
#>   plateforme et un acces grumier a valider sur le terrain.
#> ℹ A defaut, `potentiel_cable()` part de TOUTE la desserte -- couverture
#>   beaucoup trop optimiste.
places
#> Simple feature collection with 3 features and 6 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 41.66667 ymin: 41.66667 xmax: 208.3333 ymax: 208.3333
#> Projected CRS: RGF93 v1 / Lambert-93
#>   id cable troncon  acces largeur_m pente_pct                  geometry
#> 3  1     1       3 classe        NA        20 POINT (41.66667 41.66667)
#> 4  2     1       3 classe        NA        20           POINT (125 125)
#> 5  3     1       3 classe        NA        20 POINT (208.3333 208.3333)
```
