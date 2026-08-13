# Query the Overpass API for OpenStreetMap features

The ecosystem's canonical Overpass client (ADR-010). Fetches raw XML
over `curl`, then reads it through GDAL's OSM driver.

## Usage

``` r
osm_overpass(
  bbox_wgs,
  cle,
  valeur = NULL,
  timeout = 90,
  serveurs = OSM_SERVEURS_OVERPASS,
  max_reprises = 2,
  couches = c("lines", "multipolygons")
)
```

## Arguments

- bbox_wgs:

  Bounding box in WGS84
  ([`sf::st_bbox()`](https://r-spatial.github.io/sf/reference/st_bbox.html),
  or a numeric vector `xmin, ymin, xmax, ymax`).

- cle:

  OSM key (e.g. `"highway"`), **or** a list of `list(cle=, valeur=)`
  filters to fetch in a **single** query as an Overpass union. Grouping
  filters is the point: Overpass caps the number of requests, not the
  area.

- valeur:

  Optional value for `cle`. Ignored when `cle` is a filter list.

- timeout:

  Per-request ceiling (s), passed to both libcurl and Overpass QL.

- serveurs:

  Instances tried in order.

- max_reprises:

  Retries per instance before moving on.

- couches:

  GDAL OSM layers to read. Default `lines` and `multipolygons`, which
  together cover what the obstacle and road layers need.

## Value

An `sf` (possibly with zero rows), carrying the attributes `instance`,
`requete` and `date_requete` – see
[`osm_provenance()`](https://pobsteta.github.io/foretaccess/reference/osm_provenance.md).

## Details

**Three outcomes, never conflated.** This is the contract:

|  |  |  |
|----|----|----|
| outcome | signal | behaviour |
| data | XML contains `<way` | returns the `sf` |
| genuinely empty | valid XML, no `<way`, **no** `<remark>` | returns an empty `sf` – that *is* a result |
| refusal | `<remark>`, HTTP 429/504, timeout, or body under 100 bytes | **errors** |

**A refusal never becomes an empty layer.** A throttled instance answers
with well-formed XML of a few hundred bytes, no HTTP error code, and a
`<remark>` element. Read naively, that says *"nothing here"* – the
mistake that hid the absence of DFCI data for a whole day.

**Why `curl` and not `osmdata`.** A saturated instance does not error,
it *stalls*: `osmdata` then loops on a 60 s backoff with no ceiling (16
consecutive retries measured, 16 minutes of pure waiting).
[`setTimeLimit()`](https://rdrr.io/r/base/setTimeLimit.html) cannot help
– it only fires at R interpreter checkpoints, never on a socket blocked
inside C. The bound must live in the transport, and libcurl's `timeout`
provides exactly that.

**Why instance rotation used to fail.** `osmdata::set_overpass_url()`
calls `overpass_status()`, so *switching instances is itself a network
call*: when the instance is saturated it is the switch that fails, and
rotation dies before trying a single mirror. Passing the URL as a loop
argument removes the problem by construction.

## Bounded duration

No call can exceed `timeout * length(serveurs) * (1 + max_reprises)`
seconds – 90 x 4 x 3 = **18 minutes** worst case with the defaults, and
a few seconds nominally. Lower `timeout` or shorten `serveurs` to
tighten it. On HTTP 429 a `Retry-After` header is honoured **only if
under 10 s**; beyond that, moving to the next instance beats waiting.

## See also

[`acquire_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_osm.md),
[`acquire_obstacles()`](https://pobsteta.github.io/foretaccess/reference/acquire_obstacles.md),
[`acquire_dfci()`](https://pobsteta.github.io/foretaccess/reference/acquire_dfci.md).

## Examples

``` r
# Construire la requete sans l'envoyer (aucun acces reseau) :
cat(foretaccess:::.osm_requete(
  c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway"))
#> [out:xml][timeout:90];
#> (
#>   way["highway"](45.00,6.00,45.01,6.01);
#>   relation["highway"](45.00,6.00,45.01,6.01);
#> );
#> (._;>;);
#> out body;
```
