# Acquérir les entrées depuis une AOI

Le pipeline ForêtAccess part de couches SIG (MNT, desserte, forêt,
obstacles). Le **Lot 10** les **télécharge automatiquement** à partir
d’un simple polygone d’emprise (AOI), sans que vous ayez à récupérer les
fichiers à la main.

``` r

library(foretaccess)
```

## Sources config-driven

Les endpoints et identifiants de couche ne sont **jamais codés en dur**
: ils vivent dans `inst/datasources/<pays>.json`. Un résolveur les lit
par **clé logique**.

``` r

get_national_crs("FR")
#> [1] 2154
get_layer_service("dem", "FR")$layer
#> [1] "IGNF_LIDAR-HD_MNT_ELEVATION.ELEVATIONGRIDCOVERAGE.LAMB93"
get_layer_service("roads", "FR")$typename
#> [1] "BDTOPO_V3:troncon_de_route"
list_countries()
#> [1] "FR"
```

Pour l’IGN, ForêtAccess utilise la **Géoplateforme** (via le paquet
`happign`, anonyme) ; pour les obstacles, **OpenStreetMap** (via
`osmdata`). Ces deux paquets sont en `Suggests` : le cœur s’installe
sans eux, et seule l’acquisition les requiert.

``` r

install.packages(c("happign", "osmdata"))
```

## Acquérir depuis une AOI

[`acquire_inputs()`](https://pobsteta.github.io/foretaccess/reference/acquire_inputs.md)
orchestre le tout à partir d’une AOI (chemin de fichier ou objet `sf`).
Chaque couche est mise en cache et réutilisée au second appel.

``` r

aoi <- sf::st_read("mon_massif.gpkg")   # doit porter un CRS

inputs <- acquire_inputs(
  aoi,
  sources   = c("mnt", "desserte", "foret", "obstacles", "cadastre"),
  cache_dir = "cache",
  res_m     = 5,      # MNT RGE ALTI a 5 m
  buffer_m  = 100     # capte la desserte juste hors emprise (utile au least-cost)
)
inputs
```

Les sorties sont **directement consommables** par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
(Lot 1) :

``` r

pre <- preprocess(
  mnt      = inputs$mnt,
  desserte = inputs$desserte,
  foret    = inputs$foret,
  obstacles_complets = inputs$obstacles,
  parcellaire = inputs$parcellaire
)
sk <- skidder(pre)
```

## Ce que produit chaque source

| Source | Fournisseur | Sortie |
|----|----|----|
| `mnt` | RGE ALTI (IGN WMS) | raster 5 m (`mnt.tif`) |
| `desserte` | BD TOPO (IGN WFS) | `sf` lignes + champs `classe` (route / piste) et `dfci` (flag `CL_DFCI`) |
| `foret` | BD Forêt v2 (IGN WFS) | `sf` polygones |
| `obstacles` | OpenStreetMap | `sf` (bâti, eau, voies ferrées, falaises) |
| `dfci` | OpenStreetMap | `sf` pistes DFCI (`ref:FR:DFCI`) — pose le flag |
| `cadastre` | PCI Express (IGN WFS) | `sf` parcelles (optionnel) |

Le champ `classe` de la desserte est dérivé de l’attribut `nature` de BD
TOPO. Le flag `dfci` (`CL_DFCI`), source du camion DFCI
(`vignette("dfci")`), est posé par \[flag_dfci()\] : d’abord depuis le
**réseau DFCI OpenStreetMap** (`ref:FR:DFCI`, via \[acquire_dfci()\]),
puis, si OSM ne couvre pas l’emprise, par un **repli géométrique**
(piste traversante d’emprise ≥ 10 m, ou cul-de-sac muni d’une aire de
retournement). L’appel est piloté par `acquire_inputs(..., dfci = TRUE)`
(défaut).

## Robustesse

- **Cache idempotent** : un 2ᵉ appel ne re-télécharge pas (sauf
  `overwrite = TRUE`).
- **Dépendance absente** : message d’installation ciblé, pas d’erreur
  obscure.
- **Verrou CRS** : une AOI sans CRS est refusée (règle stricte du
  projet).

## Attribution

Données © IGN (Géoplateforme) et © contributeurs OpenStreetMap.
ForêtAccess est distribué sous GPL v3.
