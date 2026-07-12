# ForêtAccess — Roadmap par lots

> **Statut** : proposé — en attente de validation.
> Repris du **brief §10 (Lotissement)** et transposé à la stack **R + Rust `extendr`**, en
> intégrant les décisions §9 (voir [`PRD.md`](PRD.md) §8). Chaque lot → une spec
> `specs/0XX-<nom>.md` + ADR éventuel + tests. Un lot n'est codé qu'après validation de sa spec.

**Principe agile** : petits incréments livrables, une **branche git par lot**, commits
atomiques, PR par lot, Definition of Done (brief §12) respectée. Les moteurs reproduisant
Sylvaccess ne sont « faits » qu'avec **non-régression verte** contre l'oracle v3.6.

**Note stack** : les mentions Python du brief §10 sont transposées — `pip install -e .` +
`maturin develop` → `devtools::install()` + `rextendr::document()` ; `ruff/mypy/pytest` →
`lintr`/`testthat` ; `pydantic` → config R validée ; `scikit-image MCP` →
`leastcostpath`/`gdistance`.

---

## Vue d'ensemble

| Lot | Nom | Spec | MVP ? | Dépend de | ADR |
|---|---|---|---|---|---|
| **0** | Fondations | `specs/000-fondations.md` | ✅ | — | 001,002,003,004,007 |
| **1** | I/O & prétraitement | `specs/001-pretraitement.md` | ✅ | 0 | — |
| **2** | Moteur Skidder | `specs/002-skidder.md` | ✅ | 1 | 006 |
| **3** | Moteur Porteur | `specs/003-porteur.md` | ✅ | 1 | — |
| **4** | Noyau Câble (Rust) | `specs/004-cable.md` | ✅ | 0,1 | 005 |
| **5** | Sélection lignes câble | `specs/005-selection.md` | ✅ | 4 | — |
| **6** | Camion DFCI (beta) | `specs/006-dfci.md` | ✅ (beta) | 1,2 | `v0.8.0` |
| **7** | Passage à l'échelle | `specs/007-echelle.md` | ✅ | 2,3,4 | 005 |
| **8** | Base spatiale & agrégation | `specs/008-base-spatiale.md` | ✅ | 0 | 002 |
| **9** | Doc & publication | `specs/009-publication.md` | ✅ | tous | — |
| **10** | Acquisition depuis AOI | `specs/010-acquisition-aoi.md` | ✅ | 0 | 002,003,004 |

**Chemin critique MVP** : 0 → 1 → (2 ∥ 3 ∥ 4) → 5 → 7 → 8 → 9. Le **Lot 6 (DFCI)** est
livrable indépendamment, après le Lot 2 (partage du service least-cost).

**Lot 10 — Acquisition depuis AOI** (numéroté 10 pour ne pas renuméroter les lots existants,
mais **logiquement en amont du Lot 1**) : téléchargement automatique des entrées (MNT RGE ALTI
5 m, desserte BD TOPO, forêt BD Forêt v2, obstacles OSM, cadastre) à partir d'une `AOI.gpkg`,
via `happign`/`osmdata` (patron nemeton, config JSON par pays). Développable **en parallèle**
du Lot 1 (le prétraitement se valide sur le jeu jouet). Phase 2 : MNH LiDAR HD + volume,
BD Forêt v3.

---

## Détail des lots

### Lot 0 — Fondations
**Livrables** : dépôt structuré, `DESCRIPTION` + `Cargo.toml` (`rextendr`), config R validée
(défauts v3.6), interface `StorageBackend` (PostGIS + GeoPackage, aucun défaut privilégié),
CI (lintr/testthat/`R CMD check`/cargo test/clippy), **jeu de données jouet** + harnais de
non-régression, squelette Rust (`rextendr::document()` OK). ADR-001/002/003/004/007.
**Critères de sortie** : `devtools::install()` + `rextendr::document()` OK ; CI verte ;
round-trip d'une couche test **en PostGIS et en GeoPackage** ; `testthat` de base passe.

### Lot 1 — I/O & prétraitement
**Livrables** : lecture IGN (raster/vecteur), validation des entrées, alignement de grille,
pente/exposition, rasterisation, masques, exclusion de pente ; parcellaire lu comme couche
**optionnelle**. `specs/001`.
**Critères de sortie** : sur le jeu jouet, rasters pente/expo et masques conformes à l'oracle
(tolérance définie) ; erreurs d'entrée explicites.

### Lot 2 — Moteur Skidder
**Livrables** : règles v3.6 + **service least-cost partagé (R)** + sorties rasters/tableau.
`specs/002`. Non-régression. ADR-006 (validation).
**Critères de sortie** : distances (treuillage, traînage, totale) et zones vs v3.6 sous
tolérance ; tableau récap correct. *Si la fonction de coût R ne tient pas la tolérance →
déclencher l'évaluation portage Rust (ADR-001).*

### Lot 3 — Moteur Porteur
**Livrables** : cône d'azimuts, pentes long/travers, portée grue. `specs/003`. Non-régression.
**Critères de sortie** : sorties conformes à v3.6 (hors treuillage).

### Lot 4 — Noyau Câble (Rust)
**Livrables** : crate `cablehelp` (CableHelp + faisabilité + optimisation supports) via
`extendr` ; balayage 360°/pixel parallèle (`rayon`). `specs/004`, ADR-005. Non-régression profils.
**Critères de sortie** : sur N profils de référence, trajectoire ≤ 0,1 %, tension ≤ 1,5 % ;
base des lignes faisables produite ; speedup mesuré vs mono-thread.

### Lot 5 — Sélection lignes câble
**Livrables** : sélection multicritère (surface, supports, sens, longueur, volume, IPC).
`specs/005`.
**Critères de sortie** : sélection reproductible vs v3.6 sur jeu test ; requêtable en base.

### Lot 6 — Camion DFCI (beta) — *post-MVP* ✅ `v0.8.0`
**Livrables** : zone défendable depuis desserte DFCI (`camion_dfci()`). `specs/006`.
**Critères de sortie** : sortie beta documentée + testée sur zone échantillon. **Fait.**

### Lot 7 — Passage à l'échelle
**Livrables** : tuilage + parallélisme + sorties COG. `specs/007`, ADR-005.
**Critères de sortie** : massif complet traité en tuiles, résultat identique au traitement
mono-bloc (raccords corrects).

### Lot 8 — Base spatiale & agrégation
**Livrables** : schéma PostGIS (DDL, **base dédiée `foretaccess`, schéma par run/massif**),
export GPKG, agrégation zonale SQL (massif/parcelle/commune). `specs/008`, ADR-002.
**Critères de sortie** : écriture idempotente ; index spatiaux ; requêtes d'agrégation validées.

### Lot 9 — Doc & publication
**Livrables** : README, doc d'usage (CLI `Rscript`), exemples, `NEWS.md`/`CHANGELOG`,
packaging. `specs/009`.
**Critères de sortie** : doc à jour ; exemple reproductible de bout en bout ; version taguée
(via `release.yml`, cf. `CLAUDE.md`).

---

## Séquencement des specs

Les specs sont rédigées et validées **une par une, avant le lot correspondant**. Prochaine
étape après validation du PRD/backlog/roadmap/ADR : **`specs/000-fondations.md`** (Lot 0),
soumise pour validation avant tout scaffolding du package R / de la crate Rust.
