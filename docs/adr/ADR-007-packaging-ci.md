# ADR-007 — Packaging & CI : package R + crate Rust (`rextendr`)

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-08
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-007), §8 ; ADR-001 ; `CLAUDE.md`

## Contexte

Le brief proposait un packaging Python (`pyproject.toml` + `Cargo.toml` via maturin, CI
`ruff`/`mypy`/`pytest`/`cargo test`). La stack étant **R + Rust `extendr`** (ADR-001), le
packaging et la CI doivent être transposés, en cohérence avec les conventions de release du
projet (`CLAUDE.md` : `DESCRIPTION`/`NEWS.md`/`CITATION.cff`, tag & release automatisés).

## Décision

- **Package R** : `DESCRIPTION` (deps épinglées ; `SystemRequirements: Cargo` pour la crate),
  `NAMESPACE` généré par roxygen, structure `R/`, `src/rust/` (crate `cablehelp`),
  `tests/testthat/`, `inst/extdata/` (jeu jouet + oracles légers).
- **Build Rust** via **`rextendr::document()`** (remplace maturin) ; `Cargo.lock` versionné.
- **Reproductibilité** : `renv` (R) + `Cargo.lock` (Rust).
- **CI (GitHub Actions)** :
  - R : `lintr`, `testthat`, `covr` (couverture), **`R CMD check`** sans ERROR/WARNING ;
  - Rust : `cargo test`, `clippy` (deny warnings) ;
  - job `version-consistency` (`DESCRIPTION` = `NEWS.md` = `CITATION.cff` pour une version
    stable, cf. `CLAUDE.md`) ;
  - `release.yml` : tag + release automatiques au push sur `main` d'une version stable `X.Y.Z`.
- **CLI** : point d'entrée `Rscript` (script `inst/` ou fonction exportée) — pas de dépendance UI.

## Conséquences

- Un seul artefact installable (`devtools::install()` compile la crate).
- La CI est le garde-fou de la DoD (brief §12).
- Les développeurs doivent avoir la toolchain Rust (`cargo`) — documenté dans le README.

## Alternatives écartées

- **`pyproject.toml` + maturin** (brief) : sans objet (stack R).
- **Vendorer un binaire Rust pré-compilé** : écarté pour la v1 (build source = reproductible,
  portable) ; réévaluable pour la distribution binaire ultérieure.
