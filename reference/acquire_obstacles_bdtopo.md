# Acquire ACCESSFOR-conformant obstacles from BD TOPO and INPN (spec 022 volet B)

Assembles the **obstacle layer ACCESSFOR uses** (report Feb. 2025, sec.
2.3.4) into a single `sf` of polygons ready for
`preprocess(obstacles_complets = )`: BD TOPO obstacles (watercourses,
water surfaces, railways, buildings, main roads) **plus** the INPN/MNHN
regulatory exclusions (biotope-protection orders, national and regional
nature reserves, biological reserves, and the **integral reserve** of
national parks – not the whole park). Distinct from
[`acquire_obstacles()`](https://pobsteta.github.io/foretaccess/reference/acquire_obstacles.md)
(OpenStreetMap source).

## Usage

``` r
acquire_obstacles_bdtopo(
  aoi,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  country = "FR",
  routes_importance_max = NA_integer_,
  classements_routes = .CLASSEMENTS_ROUTES_ACCESSFOR,
  tampon_m = 5,
  zonages = TRUE
)
```

## Arguments

- aoi:

  Objet `sf`/`sfc` d'emprise, dans le CRS cible.

- crs:

  Code EPSG de sortie. Défaut 2154.

- cache_dir:

  Répertoire de cache.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

- country:

  Code pays ISO. Défaut `"FR"`.

- routes_importance_max:

  Fallback selection of main roads by BD TOPO `importance` (at most this
  value), used **only** when `cpx_classement_administratif` is absent
  from the WFS feed. Default `NA` (no fallback) – ACCESSFOR selects on
  the administrative class, not on `importance`, and the two do not
  coincide.

- classements_routes:

  Values of BD TOPO `cpx_classement_administratif` making a road an
  obstacle. Default: the ACCESSFOR list (annexe p. 52) – motorway,
  département, national, European and intercommunal roads. `NULL`
  disables the classement filter (then `routes_importance_max` applies).

- tampon_m:

  Buffer (m) applied to line obstacles. Default 5.

- zonages:

  Include the INPN/Patrinat regulatory exclusions? Default `TRUE`.

## Value

An `sf` of `MULTIPOLYGON` obstacles in `crs`, clipped to `aoi`. Empty
layers are skipped; if nothing is found the result has zero rows.

## Details

Line features (watercourses, railways, main roads) are buffered by half
a `tampon_m` so they rasterise to a continuous barrier; polygons are
kept as is. National parks are filtered on their `zone` attribute to the
**integral reserve** only – excluding the whole park would over-block
massively. `PNR`, `ZNIEFF`, Natura 2000 and hunting reserves are **not**
ACCESSFOR exclusions and are never included. On a massif without
reserves the effect comes from the BD TOPO obstacles alone.

## See also

[`acquire_obstacles()`](https://pobsteta.github.io/foretaccess/reference/acquire_obstacles.md)
(OSM),
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
(consumes `obstacles_complets`), `specs/022`.
