# Sky-view factor and openness (RVT micro-relief channels, spec 021 J3).

Ports RVT's `sky_view_factor_compute` (Relief Visualization Toolbox,
Apache 2.0): a `roll`+`fmax` horizon sweep over `num_directions`
azimuths and search radii, from which the **sky-view factor**
(hemisphere) and **openness** (sphere, degrees) fall out of the same
pass. These channels light up the platform, embankments and shoulders of
a forest track under canopy – inputs for road qualification (spec 021).
No GIS in the crate (rule 3): R passes the flat elevation grid and
re-attaches the channels to the DEM. **Negative openness** is obtained
by calling this on the negated DEM.

## Usage

``` r
rvt_svf_opns(
  height,
  nr,
  nc,
  resolution,
  radius_max,
  radius_min,
  num_directions,
  compute_svf,
  compute_opns
)
```

## Arguments

- height:

  Elevation values (row-major, `NA`/`NaN` as NoData).

- nr:

  Number of raster rows.

- nc:

  Number of raster columns.

- resolution:

  Cell size (m); corrects the vertical horizon angle.

- radius_max:

  Maximal search radius in **pixels**.

- radius_min:

  Minimal search radius in **pixels** (noise reduction).

- num_directions:

  Number of azimuth directions swept.

- compute_svf:

  Whether to compute the sky-view factor.

- compute_opns:

  Whether to compute the openness (degrees).

## Value

A list with `svf` (0..1) and `opns` (degrees), each row-major with `NaN`
where the input elevation is `NaN`; an unrequested channel is empty.
