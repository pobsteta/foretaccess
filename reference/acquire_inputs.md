# Acquiert les entrées ForêtAccess depuis une AOI

Télécharge automatiquement, à partir d'un simple polygone d'emprise
(AOI), les couches attendues par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
: MNT (RGE ALTI), desserte (BD TOPO), forêt (BD Forêt v2), obstacles
(OpenStreetMap) et, en option, le parcellaire cadastral. Approche
**config-driven** (patron nemeton) : endpoints et couches sont déclarés
dans `inst/datasources/<pays>.json`, jamais codés en dur (voir
[datasources](https://pobsteta.github.io/foretaccess/reference/datasources.md)).

## Usage

``` r
acquire_inputs(
  aoi,
  sources = c("mnt", "desserte", "foret", "obstacles", "cadastre"),
  cache_dir = tempdir(),
  res_m = 5,
  res_lidar_m = 1,
  crs = 2154,
  buffer_m = 100,
  overwrite = FALSE,
  country = "FR",
  dfci = TRUE,
  volume = NULL,
  champ_volume = "P1",
  config = NULL
)
```

## Arguments

- aoi:

  Emprise : chemin d'un fichier vectoriel, ou objet `sf`/`sfc`
  polygonal. **Doit porter un CRS** (règle stricte du projet).

- sources:

  Sources à acquérir (sous-ensemble de `mnt`, `desserte`, `foret`,
  `obstacles`, `cadastre`).

- cache_dir:

  Répertoire de cache. Défaut
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html).

- res_m:

  Résolution du MNT (m). Défaut 5.

- res_lidar_m:

  Résolution fine (m) de téléchargement du MNT LIDAR HD, agrégée à
  `res_m` (cf.
  [`acquire_mnt()`](https://pobsteta.github.io/foretaccess/reference/acquire_mnt.md)).
  Défaut 1.

- crs:

  Code EPSG de sortie. Défaut 2154.

- buffer_m:

  Buffer d'emprise (m) autour de l'AOI. Défaut 100.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

- country:

  Code pays ISO. Défaut `"FR"`.

- dfci:

  Alimenter le flag DFCI (`CL_DFCI`) sur la desserte, source du camion
  DFCI (spec 006) : réseau OSM `ref:FR:DFCI`
  ([`acquire_dfci()`](https://pobsteta.github.io/foretaccess/reference/acquire_dfci.md)),
  avec repli géométrique
  ([`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md))
  si OSM ne rend rien. Défaut `TRUE`.

- volume:

  Volume sur pied à injecter (facultatif). **Jamais téléchargé** : sa
  source est un inventaire ou l'indicateur **P1** de Nemeton (cf.
  [`volume_depuis_p1()`](https://pobsteta.github.io/foretaccess/reference/volume_depuis_p1.md)).
  Accepte un `SpatRaster` en m3/ha, un chemin de raster, ou un `sf`
  d'unités portant un champ m3/ha (rasterisé via
  [`volume_depuis_p1()`](https://pobsteta.github.io/foretaccess/reference/volume_depuis_p1.md)).
  Aligné sur la grille du **MNT bufferisé** : le câble somme le volume
  jusque dans le halo, un volume tronqué à l'AOI sous-estime l'IPC des
  lignes de bord (spec 019). CRS différent du MNT : erreur (ADR-004) ;
  grille différente (même CRS) : rééchantillonné, avec avertissement.
  `NULL` (défaut) : pas de volume.

- champ_volume:

  Nom du champ m3/ha, utilisé seulement quand `volume` est un `sf`.
  Défaut `"P1"` (la colonne écrite par Nemeton).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md)
  fournissant les seuils DFCI (`dfci$tol_appariement_m`,
  `emprise_min_m`, `rayon_retournement_m`) passés à
  [`flag_dfci()`](https://pobsteta.github.io/foretaccess/reference/flag_dfci.md).
  Défaut `NULL` (seuils par défaut).

## Value

Un objet `foretaccess_inputs` : `mnt` (chemin raster), `desserte`,
`foret`, `obstacles`, `parcellaire` (`sf` ou `NULL`), `volume`
(`SpatRaster` m3/ha ou `NULL`), `aoi` (`sf` stricte), `meta` (sources,
CRS, buffer, date), `cache_dir`. Directement consommable par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).

## Details

Les clients réseau (`happign` pour l'IGN, `osmdata` pour OSM) sont en
**Suggests** : le cœur du paquet s'installe sans eux, et seule
l'acquisition les requiert (message d'installation ciblé sinon). Chaque
source est mise en **cache** sous `cache_dir/layers/<couche>/` et
réutilisée au 2ᵉ appel, sauf `overwrite = TRUE`.

L'AOI est reprojetée dans `crs` (EPSG:2154 par défaut). Un **buffer**
(`buffer_m`, défaut 100 m) élargit l'emprise d'acquisition pour capter
la desserte juste hors de l'AOI — utile au plus court chemin (Lot 2) ;
les couches sont découpées sur cette emprise élargie. L'AOI stricte est
conservée dans le résultat (`$aoi`).

## See also

[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md),
[`volume_depuis_p1()`](https://pobsteta.github.io/foretaccess/reference/volume_depuis_p1.md),
[datasources](https://pobsteta.github.io/foretaccess/reference/datasources.md),
[`acquire_mnt()`](https://pobsteta.github.io/foretaccess/reference/acquire_mnt.md)

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("mon_massif.gpkg")
inputs <- acquire_inputs(aoi, cache_dir = "cache")
pre <- preprocess(inputs$mnt, inputs$desserte, inputs$foret,
                  obstacles_complets = inputs$obstacles)

# Volume via l'indicateur P1 de Nemeton (inventaire ou MNH LiDAR). Nemeton
# calcule P1 sur l'emprise bufferisee ; acquire_inputs le rasterise.
p1 <- nemeton::indicateur_p1_volume(parcelles, chm = mnh_lidar)
inputs <- acquire_inputs(aoi, cache_dir = "cache", volume = p1)
pre <- preprocess(inputs$mnt, inputs$desserte, inputs$foret,
                  volume = inputs$volume)
} # }
```
