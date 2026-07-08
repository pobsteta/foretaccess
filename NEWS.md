# foretaccess (development version)

## Lot 0 — Fondations (en cours)

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
