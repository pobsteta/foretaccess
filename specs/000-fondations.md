# specs/000 — Lot 0 : Fondations

> **Statut** : proposé — en attente de validation.
> **Lot** : 0 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 0 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md), US-0.1…0.6).
> **ADR liés** : ADR-001 (langages), ADR-002 (stockage), ADR-003 (config), ADR-004
> (découplage), ADR-007 (packaging/CI).
> **Ne rien coder avant validation de cette spec.** Le scaffolding du package R et de la crate
> Rust n'intervient qu'**après** ce feu vert.

---

## 1. Contexte

ForêtAccess démarre à vide (docs seulement). Le Lot 0 pose le **socle technique** permettant
de développer les lots suivants en respectant la Definition of Done : un **package R
installable** avec une **crate Rust liée par `rextendr`**, une **configuration validée**
(défauts Sylvaccess v3.6), une **interface de stockage** (PostGIS + GeoPackage), une **CI**
verte, un **jeu de données jouet** et le **harnais de non-régression** qui servira d'oracle
à tous les moteurs.

**Aucune logique métier** dans ce lot : ni prétraitement, ni moteur, ni mécanique câble. Le
noyau Rust se limite à une fonction triviale prouvant que la chaîne R↔Rust fonctionne.

---

## 2. Périmètre

### Dans le périmètre (Lot 0)
1. **Squelette de package R** : `DESCRIPTION`, `NAMESPACE` (roxygen), `R/`, `tests/testthat/`,
   `inst/`, `.Rbuildignore`, `README` (existant) + `LICENSE`.
2. **Squelette de crate Rust** liée par `rextendr` sous `src/rust/`, avec une fonction
   `#[extendr]` triviale (ex. `cablehelp_version()`), `Cargo.toml` + `Cargo.lock` versionnés.
3. **Configuration** (`R/config.R`) : structure + validation, **défauts v3.6** (§6 du brief),
   chargement YAML.
4. **Interface `StorageBackend`** (`R/storage*.R`) : contrat commun + implémentations **PostGIS**
   et **GeoPackage**, **sans backend par défaut** (ADR-002).
5. **Jeu de données jouet** (`inst/extdata/toy/`) + script de génération (`data-raw/`).
6. **Harnais de non-régression** (`R/nonreg.R` + `tests/testthat/`) : mécanisme de comparaison
   à un oracle avec tolérance paramétrable ; test « à blanc » vert.
7. **CI** (`.github/workflows/`) : lint, tests, `R CMD check`, `cargo test`, `clippy`, service
   PostGIS ; garde-fou `version-consistency` ; `release.yml`.
8. **Infra de versionnage** : `NEWS.md`, `CITATION.cff`, `DESCRIPTION Version`, conformes au
   `CLAUDE.md`. À partir de ce lot, le versionnage **automatisé** remplace les tags manuels.
9. **ADR** : finaliser 001/002/003/004/007 (déjà rédigés, statut → « accepté » à la clôture).

### Hors périmètre (Lot 0)
- Lecture réelle des données IGN, prétraitement (→ Lot 1).
- Tout moteur (skidder/porteur/câble/DFCI) et la mécanique CableHelp (→ Lots 2–4, 6).
- Le service least-cost (→ Lot 2).
- Les **oracles réels** issus de Sylvaccess v3.6 (générés au fil des Lots 1–5) ; le Lot 0 ne
  fournit que la **plomberie** du harnais + un oracle synthétique de démonstration.
- Les **tableaux matériels câble** complets (dépendent de la récupération article/`.pyx`,
  ADR-006) ; Lot 0 pose seulement le **schéma de config** correspondant.

---

## 3. Entrées / sorties

### Entrées
- Aucune donnée métier externe. Le jeu jouet est **généré** de façon déterministe (seed fixe)
  par `data-raw/make_toy.R` : petit **MNT synthétique** (raster, ex. 50×50 @ 5 m avec une
  pente connue), **desserte** (polylignes classées route/piste/DFCI), **forêt** (polygone),
  et un ou deux **profils câble** analytiques.
- Variables d'environnement de test PostGIS : `FORETACCESS_DB_URL_TEST` (cf. §7, mêmes garde-
  fous que Nemeton).

### Sorties
- Package installable (`devtools::install()` / `R CMD INSTALL`).
- Bindings Rust générés (`R/extendr-wrappers.R`) + bibliothèque compilée.
- Jeu jouet versionné sous `inst/extdata/toy/`.
- CI verte ; artefact de couverture (`covr`).

---

## 4. Structure de dépôt cible (transposition R du brief §11)

```
foretaccess/
├─ DESCRIPTION                 # métadonnées package, Version, SystemRequirements: Cargo
├─ NAMESPACE                   # généré par roxygen
├─ NEWS.md                     # journal de versions (CLAUDE.md)
├─ CITATION.cff                # citation + version
├─ LICENSE / LICENSE.md        # GPL v3
├─ README.md                   # (existant)
├─ .Rbuildignore
├─ R/
│  ├─ foretaccess-package.R    # doc du package, imports
│  ├─ config.R                 # config + validation, défauts v3.6
│  ├─ storage.R                # générique StorageBackend (contrat)
│  ├─ storage-postgis.R        # implémentation PostGIS (DBI/RPostgres + sf)
│  ├─ storage-gpkg.R           # implémentation GeoPackage (sf)
│  ├─ nonreg.R                 # comparaison aux oracles (tolérances)
│  └─ extendr-wrappers.R       # généré par rextendr (ne pas éditer)
├─ src/
│  ├─ rust/
│  │  ├─ Cargo.toml            # crate (ex. `cablehelp`)
│  │  ├─ Cargo.lock            # versionné
│  │  └─ src/lib.rs            # #[extendr] cablehelp_version() (trivial)
│  ├─ Makevars / Makevars.win  # générés par rextendr
│  └─ entrypoint.c             # généré par rextendr
├─ tests/
│  ├─ testthat.R
│  └─ testthat/
│     ├─ test-config.R
│     ├─ test-storage-gpkg.R
│     ├─ test-storage-postgis.R
│     ├─ test-rust-binding.R
│     └─ test-nonreg.R
├─ inst/
│  └─ extdata/
│     └─ toy/                  # MNT, desserte, forêt, profils câble (générés)
├─ data-raw/
│  └─ make_toy.R              # génération déterministe du jeu jouet
├─ docs/                       # PRD, ROADMAP, BACKLOG, adr/, brief, architecture (existants)
├─ specs/                      # 000-fondations.md (ce fichier), 001…
└─ .github/workflows/
   ├─ R-CMD-check.yaml         # lint + testthat + R CMD check + cargo/clippy (+ service PostGIS)
   └─ release.yml             # tag + release auto sur version stable (CLAUDE.md)
```

> Note : `rextendr` impose la crate sous `src/rust/` et génère `src/entrypoint.c`,
> `src/Makevars*`, `R/extendr-wrappers.R`. On ne les édite pas à la main.

---

## 5. Démarche de mise en place (pas d'algorithme métier)

1. **Package R** : `usethis`/`devtools` pour l'ossature ; roxygen pour `NAMESPACE`.
2. **Crate Rust** : `rextendr::use_extendr()` (crée `src/rust/` + wrappers) ; ajouter
   `cablehelp_version()` ; `rextendr::document()` compile et régénère les bindings.
3. **Config** (`config.R`) :
   - un constructeur `foretaccess_config(...)` retournant une liste structurée validée ;
   - **défauts terrestres v3.6 concrets** (brief §6) — skidder : amont 50 m, aval 100 m,
     bascule amont 75 %, bascule aval 20 %, pente skidder 30 %, abattage 100 %, hors-desserte
     50 m ; porteur : travers 15 %, long 30 %/25 %, grue 8 m, 300 m, hors-desserte 200 m ;
   - **schéma câble** présent mais **valeurs matérielles à compléter** (dépend ADR-006 —
     marquées `NA`/placeholder documenté, complétées au Lot 4) ;
   - validation via helper (`checkmate` ou équivalent) : types, bornes, cohérence ; erreurs
     ciblées ;
   - chargement YAML (`yaml`/`config`), round-trip testé.
4. **StorageBackend** :
   - un contrat (générique S3 ou objet) : `sb_write_layer()`, `sb_read_layer()`,
     `sb_list_layers()`, écriture **idempotente** ;
   - `storage_gpkg(path)` via `sf` ; `storage_postgis(dsn/schema)` via `DBI`/`RPostgres` + `sf` ;
   - **aucun défaut** : le backend est un argument explicite ;
   - le modèle PostGIS suit ADR-002 (schéma par run/massif) — au Lot 0, création/suppression
     d'un **schéma jetable** pour le test.
5. **Jeu jouet + harnais** :
   - `make_toy.R` déterministe (seed) écrit les fichiers sous `inst/extdata/toy/` ;
   - `compare_to_oracle(actual, oracle, tol)` : compare rasters/tables numériques avec
     tolérances (absolue/relative) et renvoie un rapport d'écart ;
   - un **oracle synthétique** (généré, connu analytiquement) permet un test « à blanc » vert.
6. **CI + versionnage** : workflows, `NEWS.md`/`CITATION.cff`/`DESCRIPTION` cohérents,
   `release.yml` (gate « stable only », ignore `.9000`).

---

## 6. Critères d'acceptation

Reprend EPIC 0 (US-0.1…0.6) + DoD (brief §12).

- **CA-0.1** `devtools::install()` (ou `R CMD INSTALL .`) réussit ; `rextendr::document()`
  compile la crate et `cablehelp_version()` est appelable depuis R et renvoie une chaîne.
- **CA-0.2** La config expose tous les paramètres du brief §6 ; **chaque défaut terrestre v3.6
  est vérifié par test** ; une config invalide (type/borne) échoue avec un message ciblé ;
  round-trip YAML testé.
- **CA-0.3** Écriture puis relecture d'une couche test **en GeoPackage** et **en PostGIS**
  donnent des géométries + attributs identiques (round-trip) ; aucun backend n'est « par
  défaut » ; écriture idempotente (ré-écrire ne duplique pas).
- **CA-0.4** Jeu jouet généré de façon déterministe et versionné ; `compare_to_oracle()`
  détecte un écart au-delà de la tolérance et valide en-deçà ; test « à blanc » (oracle vs
  oracle) vert.
- **CA-0.5** CI verte exécutant `lintr`, `testthat`, `R CMD check` (0 ERROR/WARNING),
  `cargo test`, `clippy` ; versions R et Rust épinglées (`renv` / `Cargo.lock`).
- **CA-0.6** ADR-001/002/003/004/007 cohérents avec l'implémentation ; passés « accepté ».
- **CA-0.7** `NEWS.md`, `CITATION.cff`, `DESCRIPTION Version` cohérents ; `release.yml` en
  place ; premier bump de version du package documenté.

---

## 7. Tests

**R (`testthat` edition 3)**
- `test-config.R` : défauts v3.6 (un `expect_equal` par paramètre clé) ; échecs de validation
  (types, bornes) ; round-trip YAML.
- `test-storage-gpkg.R` : round-trip couche en GeoPackage (`withr::local_tempfile`),
  idempotence.
- `test-storage-postgis.R` : round-trip en PostGIS **si** `FORETACCESS_DB_URL_TEST` défini,
  sinon `skip()`. Garde-fous à la Nemeton : skip si égal à une éventuelle URL de prod, si la
  base contient des tables applicatives, ou si non défini ; création/suppression d'un **schéma
  jetable** dédié au test.
- `test-rust-binding.R` : `cablehelp_version()` renvoie une chaîne non vide.
- `test-nonreg.R` : `compare_to_oracle()` (cas sous tolérance = pass, au-delà = fail détecté) ;
  test « à blanc » oracle-vs-oracle.

**Rust (`cargo test`)**
- test unitaire trivial sur la fonction exposée (sanity), `clippy` sans warning.

**CI**
- Job R : `ubuntu-latest`, service **PostGIS** (image `postgis/postgis`), `FORETACCESS_DB_URL_TEST`
  pointant sur une base jetable, toolchain Rust installée ; `lintr` + `testthat` + `R CMD check`.
- Job Rust : `cargo test` + `clippy -D warnings`.
- Job `version-consistency` : `DESCRIPTION` = tête `NEWS.md` = `CITATION.cff` pour une version
  stable.

---

## 8. Risques & mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Sylvaccess v3.6 non exécutable pour figer les vrais oracles | Non-régression réelle repoussée | Lot 0 = plomberie + oracle **synthétique** ; oracles réels dès qu'un moteur existe (Lots 1+) |
| PostGIS indisponible en CI/local | Tests storage PostGIS non exécutés | Service container en CI ; `skip()` propre + garde-fous hors CI (jamais fail) |
| Toolchain Rust absente chez un contributeur | Build KO | `SystemRequirements: Cargo` + doc README ; CI installe la toolchain |
| Tableaux matériels câble indisponibles au Lot 0 | Config câble incomplète | Schéma posé, valeurs `NA`/placeholder documentées, complétées au Lot 4 (ADR-006) |
| Écrasement d'une base réelle par les tests | Perte de données | Garde-fous `FORETACCESS_DB_URL_TEST` (skip si prod / tables applicatives / non défini), schéma jetable |
| Choix lib de parallélisme/validation prématuré | Rework | Lot 0 ne fige que config + storage ; `future`/`furrr` et détails viennent aux lots concernés |

---

## 9. Definition of Done (Lot 0)

- [ ] Spec validée (ce fichier) ; ADR-001/002/003/004/007 « acceptés ».
- [ ] Package installable + `rextendr::document()` OK ; binding Rust appelable.
- [ ] Config défauts v3.6 validée + testée ; `StorageBackend` round-trip PostGIS **et** GPKG.
- [ ] Jeu jouet + harnais non-régression (test « à blanc » vert).
- [ ] CI verte (`lintr`/`testthat`/`R CMD check`/`cargo test`/`clippy`) ; versions épinglées.
- [ ] `NEWS.md`/`CITATION.cff`/`DESCRIPTION` cohérents ; `release.yml` opérationnel.
- [ ] Branche dédiée + PR + revue ; commits atomiques ; entrée `NEWS.md`.

---

## 10. Décisions spécifiques au Lot 0 (tranchées 2026-07-08)

1. **Nom de la crate Rust** : **`cablehelp`** (le package R reste `foretaccess`).
2. **Versionnage** : le tag documentaire est **rebaptisé `v0.0.1`** ; le `DESCRIPTION` démarre
   en cycle dev **`0.0.1.9000`**, et la **première release stable du package** sera **`0.1.0`**
   à la clôture du Lot 0 (posée automatiquement par `release.yml`).
3. **Lib de validation de config** : **`checkmate`**.
4. **`renv`** : **activé dès le Lot 0** (reproductibilité, ENF-3), en tandem avec `Cargo.lock`.
