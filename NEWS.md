# foretaccess 0.3.0 (2026-07-10)

## Lot 2 — Moteur Skidder (+ service least-cost partagé)

Les règles sont **dérivées du code source Sylvaccess v3.6** (GPL v3,
`forge.inrae.fr/sylvain.dupire/sylvaccess`), et non de l'article — qui n'en donne
pas les équations. Trois d'entre elles contredisaient nos hypothèses initiales.

* **`propager_cout()`** et **`chemin_optimal()`** : service de plus court chemin
  sur grille, partagé avec le porteur (Lot 3) et le camion DFCI (Lot 6). Dijkstra
  8-connexe, coût porté par la **cellule d'arrivée** (et non la moyenne des deux
  cellules, comme `terra::costDist()`), diagonale × `sqrt(2)`, plafond de coût, et
  raster d'**allocation** identifiant la source atteinte. Aucune dépendance nouvelle.
  Le tas binaire vit dans des vecteurs mutés en place : le passer en liste ferait
  recopier le vecteur à chaque opération (sémantique de copie de R), rendant le
  Dijkstra quadratique — mesuré à 357× plus lent sur 200 000 insertions.
* **`surface_cout_skidder()`**, **`ponderation_pente()`** : la fonction de coût est
  `sqrt(1 + (p/100)^2)`, le facteur d'allongement 3D de la traversée d'une cellule.
  Elle ne dépend que de la pente **absolue** : la propagation est **isotrope**.
* **`treuiller()`** : le treuillage n'est **pas** un plus court chemin, mais un
  balayage radial 360° au pas de 1°, en ligne droite, avec une distance **3D** et
  une contrainte de dégagement du câble (la corde reste entre le sol et
  `hauteur_degagement_max_m`, attachée à `hauteur_attache_treuil_m`). Les rayons
  vivants sont compactés à chaque pas : la plupart meurent en quelques cellules,
  et le travail s'effondre (2,2× sur terrain réel).
* **`distance_treuillage_max()`**, **`coefficients_bascule()`** : la loi de bascule
  est affine en **dénivelé**, pas en pente. À plat, la distance admissible vaut
  **80,23 m** — ni 50 (plafond amont), ni 100 (plafond aval).
* **`skidder()`** : orchestrateur. Classes d'accessibilité, distances de treuillage,
  de traînage (forêt et piste) et de débardage, allocation, trajets optionnels,
  écriture GeoTIFF/COG.
* **`recapituler()`** : surfaces et volumes par classe, avec une ligne
  `indetermine` explicite — les bordures ne sont jamais rangées silencieusement
  dans une classe métier.
* **`zone_roulage()`**, **`zone_treuillable()`** : les obstacles **partiels**
  bloquent le roulage mais pas le treuillage ; les obstacles **complets** reçoivent
  un surcoût additif prohibitif mais **fini** (1000), et ne sont pas `NA`.

## Changements

* `preprocess()` conserve désormais le **MNT** dans son résultat (`$mnt`) : les
  moteurs en ont besoin, le treuillage raisonnant sur les altitudes. Ajout additif.
* Nouveaux paramètres `config$skidder`, aux défauts v3.6 lus dans le `.pyx` :
  `hauteur_attache_treuil_m`, `hauteur_degagement_max_m`,
  `surcout_obstacle_complet`, `option_modelisation`, `classes_distance_m`.

## Limites connues

* Seule l'**option de modélisation 1** (privilégier le treuillage) est implémentée ;
  l'option 2 lève une erreur explicite.
* Le plafond `distance_hors_desserte_max_m` n'est pas appliqué, et la hiérarchie
  route / piste est réduite à deux niveaux. Voir `specs/002-skidder.md`.

# foretaccess 0.2.0 (2026-07-09)

## Lot 1 — I/O & prétraitement

* **`preprocess()`** : socle commun aux quatre moteurs. Produit un objet
  `foretaccess_preprocessing` dont tous les rasters partagent exactement la
  grille du MNT (pente, exposition, masque forêt, desserte catégorielle, masques
  d'obstacles, masque d'exclusion de pente, volume aligné).
* **`valider_entrees()`** : validation **stricte** des entrées — CRS commun,
  alignement de grille, champ `classe` de la desserte, géométries non vides et
  valides, emprises se recouvrant. Aucune reprojection ni rééchantillonnage
  silencieux ; chaque manquement lève une erreur ciblée.
* **`calculer_terrain()`** : pente en pourcentage et exposition en degrés depuis
  le nord (plat = `NA`), via `terra`. Méthode configurable
  (`config$general$methode_pente` : `"Horn"` par défaut, ou `"Evans"`).
* Écriture GeoTIFF/**COG** optionnelle (`preprocess(write_dir = )`) et relecture
  par **`lire_rasters()`**.
* Chaque entrée est acceptée comme **chemin de fichier** ou comme objet déjà
  chargé (`SpatRaster` / `sf`), conformément à l'ADR-004.
* Non-régression sur oracle **analytique** : le MNT jouet (plan incliné à 20 %)
  valide pente, exposition et masques via `compare_to_oracle()`.

## Divers

* Ajout des badges README (R-CMD-check, version, pkgdown, couverture Codecov,
  lifecycle, licence) et du site pkgdown + job de couverture en CI.

# foretaccess 0.1.0 (2026-07-09)

## Lot 0 — Fondations

* Squelette de **package R** + **crate Rust `cablehelp`** liée par `extendr`
  (`cablehelp_version()` comme preuve de chaîne R ↔ Rust).
* **Configuration** métier validée (`checkmate`), défauts **Sylvaccess v3.6**,
  chargement/écriture YAML.
* Interface **`StorageBackend`** : implémentations **PostGIS** et **GeoPackage**,
  sans backend par défaut (ADR-002).
* **Jeu de données jouet** (`inst/extdata/toy/`) + **harnais de non-régression**
  (`compare_to_oracle()`).
* **CI** (lint/tests/`R CMD check`/`cargo test`/`clippy`) et **infrastructure de
  versionnage** (`release.yml`, garde-fou `version-consistency`).

# foretaccess 0.0.1 (2026-07-08)

* Jalon **documentaire** d'amorçage : PRD, backlog, roadmap (§10), ADR-001…007.
  Aucun code (voir `docs/`).
