# Map the IGN ACCESSFOR classes onto `classes_debardage()`

The IGN publishes a national forest-accessibility layer (project
**ACCESSFOR**, edition 2025-01-01) over WFS: polygonal `acces_skidder` /
`acces_porteur` layers with an integer `class` and a `cat` label. On the
target department (48, Chastel-Nouvel) the observed class domain matches
[`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md)
band for band – both descend from Sylvaccess. This function returns the
explicit crosswalk so a comparison joins on the **integer** code, never
on the label (`cat` carries accents and punctuation that must not be
matched on).

## Usage

``` r
accessfor_correspondance(config = foretaccess_config())
```

## Arguments

- config:

  A `foretaccess_config`. Its `skidder$classes_distance_m` must equal
  the ACCESSFOR bands. Default
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

A `data.frame` with one row per
[`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md)
value: `fa_value` (integer, the raster code), `fa_classe` (label),
`accessfor_class` (integer ACCESSFOR code, `NA` for `hors_foret`),
`accessfor_cat` (indicative ASCII label – do not join on it).

## Details

The ACCESSFOR bands are **frozen** at `0, 250, 500, 1000, 1500, 2000` m
(the Sylvaccess defaults). If `config` sets different
`skidder$classes_distance_m`, the crosswalk is undefined and the
function errors rather than align mismatched bands silently.

## Correspondence

|  |  |  |
|----|----|----|
| ACCESSFOR `class` | [`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md) | meaning |
| 3, 4, 5, 6, 7, 8 | 1, 2, 3, 4, 5, 6 | bands 0-250 ... \> 2000 m |
| 1 | `k+1` | inaccessible |
| 2 | `k+2` | inexploitable (harvest slope exceeded) |
| – | `k+3` | hors_foret (no ACCESSFOR code – outside its forest mask) |

where `k = length(config$skidder$classes_distance_m)` (6 by default).
ACCESSFOR has **no** `hors_foret` code: its polygons *are* the forest,
so `hors_foret` maps to "outside the ACCESSFOR mask" and is excluded
from any comparison.

## See also

[`classes_debardage()`](https://pobsteta.github.io/foretaccess/reference/classes_debardage.md).

## Examples

``` r
accessfor_correspondance()
#>   fa_value     fa_classe accessfor_class
#> 1        1         0-250               3
#> 2        2       250-500               4
#> 3        3      500-1000               5
#> 4        4     1000-1500               6
#> 5        5     1500-2000               7
#> 6        6        > 2000               8
#> 7        7  inaccessible               1
#> 8        8 inexploitable               2
#> 9        9    hors_foret              NA
#>                                    accessfor_cat
#> 1     Accessible - Classe de debardage 1 : 0-250
#> 2   Accessible - Classe de debardage 2 : 250-500
#> 3  Accessible - Classe de debardage 3 : 500-1000
#> 4 Accessible - Classe de debardage 4 : 1000-1500
#> 5 Accessible - Classe de debardage 5 : 1500-2000
#> 6    Accessible - Classe de debardage 6 : > 2000
#> 7                                   Inaccessible
#> 8       Zone non exploitable (pente trop elevee)
#> 9                                           <NA>
```
