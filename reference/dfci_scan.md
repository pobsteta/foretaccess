# Balayage radial DFCI (`debusq_dfci`), porté en Rust.

Depuis chaque pixel du réseau DFCI, déroule une lance 360 deg / 1 deg
qui épouse le relief (`Lcum += sqrt(dh² + ddist²)`), plafonnée à `lmax`,
arrêtée par la pente / un obstacle (`zone_ok == 0`) ou le bord. Balayage
séquentiel dans l'ordre des sources (tie-break `>` strict : à longueur
égale, la première source gagne).

## Usage

``` r
dfci_scan(alt, nr, nc, res, foret, sources, zone_ok, lmax)
```

## Arguments

- alt:

  Elevation values (row-major, NA as NaN).

- nr:

  Number of raster rows.

- nc:

  Number of raster columns.

- res:

  Cell size (m); square cells assumed.

- foret:

  Forest mask (1 = forest, `Foret2`), row-major.

- sources:

  DFCI network cell indices (1-based, row-major order).

- zone_ok:

  Passable mask (1 = slope ok, no obstacle, non-nodata), row-major.

- lmax:

  Maximum hose length (m).

## Value

A list: `dist` (m), `deniv` (m), `lien` (1-based source cell), `acc`.
