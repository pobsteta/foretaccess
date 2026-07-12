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
  crs = 2154,
  buffer_m = 100,
  overwrite = FALSE,
  country = "FR"
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

- crs:

  Code EPSG de sortie. Défaut 2154.

- buffer_m:

  Buffer d'emprise (m) autour de l'AOI. Défaut 100.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

- country:

  Code pays ISO. Défaut `"FR"`.

## Value

Un objet `foretaccess_inputs` : `mnt` (chemin raster), `desserte`,
`foret`, `obstacles`, `parcellaire` (`sf` ou `NULL`), `aoi` (`sf`
stricte), `meta` (sources, CRS, buffer, date), `cache_dir`. Directement
consommable par
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
[datasources](https://pobsteta.github.io/foretaccess/reference/datasources.md),
[`acquire_mnt()`](https://pobsteta.github.io/foretaccess/reference/acquire_mnt.md)

## Examples

``` r
if (FALSE) { # \dontrun{
aoi <- sf::st_read("mon_massif.gpkg")
inputs <- acquire_inputs(aoi, cache_dir = "cache")
pre <- preprocess(inputs$mnt, inputs$desserte, inputs$foret,
                  obstacles_complets = inputs$obstacles)
} # }
```
