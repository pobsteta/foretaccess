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
  write_dir = NULL,
  ecarter_infractions = FALSE
)
```

## Arguments

- mnt:

  MNT : chemin de raster ou `SpatRaster`. Définit la grille, la
  résolution et le CRS de référence.

- desserte:

  Desserte : chemin de vecteur ou `sf` de lignes, avec un champ `classe`
  dans `route`, `piste`, `dfci`, `reseau_public`. `reseau_public` est la
  route ouverte à la circulation : point de chargement du camion, mais
  **barrière** pour les engins de débardage — on n'y dépose pas de bois
  et on ne la traverse pas.

- foret:

  Forêt : chemin de vecteur ou `sf` de polygones.

- obstacles_complets:

  Obstacles bloquant tous les engins (facultatif).

- obstacles_partiels:

  Obstacles spécifiques au skidder (facultatif ; la sémantique est posée
  au Lot 2).

- volume:

  Volume sur pied : raster en m3/ha aligné sur la grille du MNT
  (facultatif). Voir
  [`volume_depuis_p1()`](https://pobsteta.github.io/foretaccess/reference/volume_depuis_p1.md)
  pour le dériver d'une couche d'unités (indicateur P1 de Nemeton,
  inventaire).

- parcellaire:

  Parcellaire : vecteur de polygones (facultatif ; utilisé au Lot 8 pour
  l'agrégation).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

- write_dir:

  Répertoire où écrire les rasters en GeoTIFF/COG. `NULL` (défaut) :
  tout reste en mémoire.

- ecarter_infractions:

  Écarter les tronçons dont
  [`verifier_integrite_desserte()`](https://pobsteta.github.io/foretaccess/reference/verifier_integrite_desserte.md)
  a jugé l'infraction **réelle** (ni bord d'AOI, ni topologie) ? Défaut
  `FALSE` — on ne retire pas une information terrain potentiellement
  juste. Sans les colonnes de diagnostic, la desserte passe telle quelle
  avec un avertissement. Cf. `specs/025` (CA-25.6).

## Value

Un objet de classe `foretaccess_preprocessing` : une liste dont les
rasters partagent exactement la grille du MNT.

- `mnt`:

  le MNT, grille de référence. Les moteurs en ont besoin : le treuillage
  du skidder raisonne sur les altitudes (Lot 2).

- `slope_pct`:

  pente en pourcentage.

- `slope_max_local`:

  maximum de la pente sur la fenêtre 3 × 3. C'est lui, et non
  `slope_pct`, que le seuil d'abattage manuel interroge : la zone
  d'exclusion est *dilatée* d'une cellule (`slopes_skid()` de
  Sylvaccess).

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

- `reseau_public_mask`:

  1 sur le réseau public. Ce n'est pas une desserte forestière mais une
  **barrière** : ni source de débardage, ni terrain traversable par les
  engins.

- `exclusion_mask`:

  1 là où le maximum local de pente dépasse le seuil d'abattage manuel.

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
