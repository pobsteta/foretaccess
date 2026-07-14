# Balayage radial de conduite du porteur

Reproduit `fwd_azimuts_forest_roadnet` de Sylvaccess v3.6 : depuis
chaque cellule du réseau de desserte, un balayage **360° au pas de 1°**,
en ligne droite, jusqu'à `distance_pente_forte_max_m`. Une cellule est
conduisible si l'engin peut l'atteindre sous trois contraintes de pente,
distinctes de celles du skidder (spec 003 §4.2).

## Usage

``` r
conduire(pre, config, zone, sources = NULL, depart_cout = NULL)
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

- zone:

  `SpatRaster` logique des cellules candidates à la conduite (forêt
  roulable).

- sources:

  Indices des cellules de départ. `NULL` (défaut) : les cellules de
  livraison de la desserte. La passe contour (`fwd_azimuts_contour`) y
  passe les cellules du bord de la zone déjà conduite.

- depart_cout:

  Vecteur de longueur `ncell(pre$mnt)` : distance **déjà parcourue**
  pour atteindre chaque source. `NULL` (défaut) : nulle. Sinon le
  critère d'amélioration porte sur le **total**
  `depart_cout + distance parcourue`.

## Value

Une liste de deux `SpatRaster` : `distance` (3D, m) et `allocation`.

## Details

Contrairement au treuillage — dont ce balayage partage la géométrie
interne — les filtres portent sur la **pente du terrain** à la cellule,
en **degrés**, et non sur le gradient du rayon. À chaque cellule `j`
d'un rayon d'azimut `az`, le rayon s'arrête
([`break`](https://rdrr.io/r/base/Control.html)) au premier filtre violé
:

1.  **Pente en long, signée par l'altitude.** Le porteur ramène le bois
    vers la route, chargé : si `alt_j > alt_route` le trajet est une
    descente (`pente_j ≤ pente_descente_max`), sinon une montée
    (`pente_j ≤ pente_montee_max`).

2.  **Dévers**, dépendant de l'azimut : \$\$p\_{lat,max} = \left\|
    \theta\_{lat} / \cos((90 - \Delta)\pi/180) \right\|, \quad \Delta =
    (az - aspect_j) \bmod 180.\$\$ Nul dans le sens de la pente
    (`Δ → 0`, `cos(90°) = 0`, seuil infini), maximal en travers
    (`Δ → 90`, seuil `= θ_lat`). C'est le basculement latéral de la
    machine.

3.  **Distance cumulée en pente forte.** Un accumulateur croît de la
    longueur du pas là où `pente_j > θ_lat` ; le rayon casse si le cumul
    dépasse `distance_pente_forte_max_m`.

La distance retenue est **3D** : `√(Hdist² + (alt_j − alt_route)²)`.
Chaque cellule garde la desserte la plus proche à ce sens.

## See also

[`treuiller()`](https://pobsteta.github.io/foretaccess/reference/treuiller.md)
