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
