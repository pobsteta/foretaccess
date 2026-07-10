# Prétraitement commun aux moteurs d'accessibilité

Socle commun aux quatre moteurs (skidder, porteur, câble, DFCI).
Transforme des entrées SIG hétérogènes en un jeu de rasters **alignés
sur la grille du MNT**, après validation stricte. Aucune règle de moteur
n'est appliquée ici.

## Usage

``` r
preprocess(
  mnt,
  desserte,
  foret,
  obstacles_complets = NULL,
  obstacles_partiels = NULL,
  volume = NULL,
  parcellaire = NULL,
  config = foretaccess_config(),
  write_dir = NULL
)
```

## Arguments

- mnt:

  MNT : chemin de raster ou `SpatRaster`. Définit la grille, la
  résolution et le CRS de référence.

- desserte:

  Desserte : chemin de vecteur ou `sf` de lignes, avec un champ `classe`
  dans `route`, `piste`, `dfci`.

- foret:

  Forêt : chemin de vecteur ou `sf` de polygones.

- obstacles_complets:

  Obstacles bloquant tous les engins (facultatif).

- obstacles_partiels:

  Obstacles spécifiques au skidder (facultatif ; la sémantique est posée
  au Lot 2).

- volume:

  Volume sur pied : raster aligné sur la grille du MNT (facultatif).

- parcellaire:

  Parcellaire : vecteur de polygones (facultatif ; utilisé au Lot 8 pour
  l'agrégation).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

- write_dir:

  Répertoire où écrire les rasters en GeoTIFF/COG. `NULL` (défaut) :
  tout reste en mémoire.

## Value

Un objet de classe `foretaccess_preprocessing` : une liste dont les
rasters partagent exactement la grille du MNT.

- `slope_pct`:

  pente en pourcentage.

- `aspect_deg`:

  exposition en degrés depuis le nord (plat = `NA`).

- `foret_mask`:

  1 dans les polygones forêt, 0 ailleurs.

- `desserte`:

  raster catégoriel de classe de desserte (`NA` hors desserte).

- `desserte_sf`:

  la desserte vectorielle, conservée pour le least-cost (Lot 2).

- `obstacles_complets_mask`, `obstacles_partiels_mask`:

  1 où obstacle, 0 sinon.

- `exclusion_mask`:

  1 là où la pente dépasse le seuil d'abattage manuel.

- `volume`:

  raster de volume aligné, ou `NULL`.

- `parcellaire`:

  objet `sf`, ou `NULL`.

- `grid`:

  métadonnées de grille (emprise, résolution, dimensions, CRS).

- `config`:

  la configuration utilisée.

- `fichiers`:

  chemins écrits si `write_dir`, sinon `NULL`.

## Details

Chaque entrée est acceptée soit comme **chemin de fichier**, soit comme
objet déjà chargé (`SpatRaster` pour les rasters, `sf` pour les
vecteurs), cf. ADR-004. Les seuils proviennent de `config` — aucune
valeur métier n'est codée en dur (ADR-003).

## Bordures

`slope_pct`, `aspect_deg` et donc `exclusion_mask` valent `NA` sur la
première couronne de cellules : le calcul de pente exige les 8 voisins.

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(
  mnt = file.path(toy, "mnt.tif"),
  desserte = file.path(toy, "desserte.gpkg"),
  foret = file.path(toy, "foret.gpkg")
)
pre$grid$res
#> [1] 5 5
```
