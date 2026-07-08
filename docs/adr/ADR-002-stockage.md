# ADR-002 — Stockage : interface `StorageBackend` (PostGIS + GeoPackage)

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-08
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-002), §9.1, §9.6 ; décision utilisateur 2026-07-08

## Contexte

Sylvaccess écrit ses sorties « à la main ». ForêtAccess doit produire des sorties **en base
spatiale** requêtables, tout en restant utilisable sans serveur. Deux cibles : PostGIS
(écosystème Nemeton) et GeoPackage (autonome).

## Décision

- Une **interface `StorageBackend` unique** (contrat : `write_layer` / `read_layer` /
  `list_layers`, écriture idempotente) avec **deux implémentations** :
  - **PostGIS** via `DBI`/`RPostgres` (+ `sf::st_write`/`st_read`) ;
  - **GeoPackage** via `sf`.
- **Aucun backend n'est le défaut** (§9.1) : PostGIS et GeoPackage sont **au même niveau** ; le
  backend est un **paramètre explicite de chaque run**.
- **Rasters hors base** : GeoTIFF/COG sur disque (jamais stockés en PostgreSQL).
- **Modèle PostGIS** (§9.6) : **base dédiée `foretaccess`**, **un schéma PostgreSQL par
  run/massif** (isolation forte, `DROP SCHEMA` simple). Index spatiaux systématiques.

## Conséquences

- Le cœur ne connaît que l'interface ; PostGIS/GeoPackage sont interchangeables (testés en
  round-trip au Lot 0).
- Le DDL et l'agrégation zonale sont détaillés au Lot 8 (`specs/008`).
- Un schéma par run facilite la reprise/purge mais multiplie les schémas : prévoir une
  convention de nommage (`run_<id>` / `massif_<code>`) et un inventaire.
- Les requêtes cross-run se font par UNION de schémas (accepté ; alternative run_id écartée).

## Alternatives écartées

- **PostGIS par défaut** ou **GeoPackage par défaut** : écarté (§9.1 → parité).
- **Table unique + colonne `run_id`** (§9.6) : écarté au profit de l'isolation par schéma.
- **Rasters en base** : écarté (volumétrie ; COG sur disque plus adapté).
