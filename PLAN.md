# PLAN.md — walking skeleton ForêtAccess

> **Source unique de vérité** de l’avancement (règle 5 de `CLAUDE.md`).
> Mise à jour à chaque étape terminée. Ne jamais clore un lot sans la
> release correspondante.

## État courant

- **Branche** : `lot-1-pretraitement`
- **Version `DESCRIPTION`** : `0.2.0` (version stable préparée ; la
  release est posée automatiquement par `release.yml` au merge sur
  `main`)
- **Lot en cours** : **Lot 1 — I/O & prétraitement** — code et tests
  terminés, reste la PR et la revue.

## Avancement par lot

| Lot | Nom | Spec | État | Release |
|----|----|----|----|----|
| 0 | Fondations | `specs/000-fondations.md` | ✅ terminé | `v0.1.0` |
| 1 | I/O & prétraitement | `specs/001-pretraitement.md` | 🟡 code fait, PR à ouvrir | `v0.2.0` (à poser) |
| 2 | Moteur Skidder | à écrire | ⬜ | — |
| 3 | Moteur Porteur | à écrire | ⬜ | — |
| 4 | Noyau Câble (Rust) | à écrire | ⬜ | — |
| 5 | Sélection lignes câble | à écrire | ⬜ | — |
| 6 | Camion DFCI (beta) | à écrire | ⬜ (post-MVP) | — |
| 7 | Passage à l’échelle | à écrire | ⬜ | — |
| 8 | Base spatiale & agrégation | à écrire | ⬜ | — |
| 9 | Doc & publication | à écrire | ⬜ | — |
| 10 | Acquisition depuis AOI | `specs/010-acquisition-aoi.md` | ⬜ spec validée | — |

Chemin critique MVP : 0 → 1 → (2 ∥ 3 ∥ 4) → 5 → 7 → 8 → 9.

## Décisions structurantes

Les ADR font foi (`docs/adr/`). Rappel des décisions qui contraignent le
code en cours :

- **ADR-002** : le vectoriel va en PostGIS/GeoPackage, le raster sur
  disque (GeoTIFF/COG). Jamais de raster en base.
- **ADR-003** : aucune valeur métier codée en dur ; tout seuil vient de
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md)
  (défauts Sylvaccess v3.6).
- **ADR-004** : découplage de l’I/O — chaque entrée est acceptée soit
  comme chemin de fichier, soit comme objet déjà chargé (`SpatRaster` /
  `sf`).
- **ADR-006** : non-régression via
  [`compare_to_oracle()`](https://pobsteta.github.io/foretaccess/reference/compare_to_oracle.md).
  Au Lot 1 l’oracle est **analytique** (MNT jouet = plan incliné à 20 %)
  ; les oracles réels Sylvaccess v3.6 viendront plus tard.
- **Lot 1, §10** : politique CRS/grille **stricte** (erreur, pas de
  reprojection ni de rééchantillonnage silencieux) ; pente/exposition
  via `terra`/Horn, méthode **configurable** ; rasters en mémoire,
  écriture COG **optionnelle**.

## Lot 1 — état détaillé

| Étape | Fichier | État |
|----|----|----|
| Normalisation des entrées (chemin \| objet) | `R/io.R` | ✅ |
| Validation CRS / grille / attributs / géométries | `R/validate.R` | ✅ |
| Pente (%) & exposition (°), méthode configurable | `R/terrain.R` | ✅ |
| Rasterisation, masques, exclusion de pente | `R/preprocess.R` | ✅ |
| Orchestrateur [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md) + classe de sortie | `R/preprocess.R` | ✅ |
| Écriture COG optionnelle + [`lire_rasters()`](https://pobsteta.github.io/foretaccess/reference/lire_rasters.md) | `R/preprocess.R` | ✅ |
| Tests (io, validate, slope-aspect, masks, grid, cog) | `tests/testthat/` | ✅ |
| `NEWS.md` + doc roxygen (`NAMESPACE`, `man/`) | — | ✅ |
| `lintr` / `R CMD check` / `cargo` / `clippy` | CI | ⬜ à vérifier en CI |
| PR + release `v0.2.0` | — | ⬜ |

**Definition of Done** : cf. `specs/001-pretraitement.md` §9.

Critères d’acceptation CA-1.1 à CA-1.6 : tous couverts par des tests
verts (117 tests au total, dont l’oracle analytique du MNT jouet).

### Effets de bord assumés

- `slope_pct`, `aspect_deg` et `exclusion_mask` valent `NA` sur la
  couronne de bordure : le calcul de pente exige les 8 voisins.
  Documenté (roxygen) et testé.
- `aspect_deg` vaut `NA` sur les cellules plates, là où `terra` renvoie
  90.
- Le raster de desserte relu depuis un COG voit sa colonne de catégories
  renommée d’après la couche (`desserte` et non `classe`) : c’est GDAL.
  Les libellés sont préservés.

## Prochaine étape

Ouvrir la PR `lot-1-pretraitement` → `main` (le merge déclenche
`release.yml` et pose le tag `v0.2.0`), puis repasser en cycle de dev
`0.2.0.9000`. Ensuite : rédiger `specs/002-skidder.md`.

------------------------------------------------------------------------

## Journal

### 2026-07-09

- Lot 0 clos et publié (`v0.1.0`), retour en cycle de dev `0.1.0.9000`.
- Specs des Lots 1 et 10 rédigées, décisions §10 tranchées, mergées sur
  `main` (PR \#5 et \#6).
- Ouverture de la branche `lot-1-pretraitement` ; `R/io.R` (helpers
  `.as_raster()` / `.as_vector()`) écrit.
- Création de ce `PLAN.md` (manquait alors que la règle 5 l’impose).
- **Lot 1 implémenté** : `R/validate.R`, `R/terrain.R`, `R/preprocess.R`
  et six fichiers de tests (`test-io`, `test-validate`,
  `test-slope-aspect`, `test-rasterize-masks`, `test-grid`,
  `test-cog`) + `helper-toy.R`. Suite verte.
- Ajout de `general$methode_pente` à la config (défaut `"Horn"`), pour
  permettre la réconciliation ultérieure avec l’oracle Sylvaccess v3.6
  sans refonte.
- `DESCRIPTION`/`NEWS.md`/`CITATION.cff` alignés sur `0.2.0` ; spec 001
  passée en statut « validé » et sa DoD cochée.
