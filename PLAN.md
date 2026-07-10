# PLAN.md — walking skeleton ForêtAccess

> **Source unique de vérité** de l'avancement (règle 5 de `CLAUDE.md`).
> Mise à jour à chaque étape terminée. Ne jamais clore un lot sans la release
> correspondante.

## État courant

- **Branche** : `main` (cycle de dev)
- **Version `DESCRIPTION`** : `0.2.0.9000` (dernière release `v0.2.0`)
- **Lot en cours** : aucun. Prochain : **Lot 2 — Moteur Skidder** (spec à écrire).

## Avancement par lot

| Lot | Nom | Spec | État | Release |
|---|---|---|---|---|
| 0 | Fondations | `specs/000-fondations.md` | ✅ terminé | `v0.1.0` |
| 1 | I/O & prétraitement | `specs/001-pretraitement.md` | ✅ terminé | `v0.2.0` |
| 2 | Moteur Skidder | à écrire | ⬜ | — |
| 3 | Moteur Porteur | à écrire | ⬜ | — |
| 4 | Noyau Câble (Rust) | à écrire | ⬜ | — |
| 5 | Sélection lignes câble | à écrire | ⬜ | — |
| 6 | Camion DFCI (beta) | à écrire | ⬜ (post-MVP) | — |
| 7 | Passage à l'échelle | à écrire | ⬜ | — |
| 8 | Base spatiale & agrégation | à écrire | ⬜ | — |
| 9 | Doc & publication | à écrire | ⬜ | — |
| 10 | Acquisition depuis AOI | `specs/010-acquisition-aoi.md` | ⬜ spec validée | — |

Chemin critique MVP : 0 → 1 → (2 ∥ 3 ∥ 4) → 5 → 7 → 8 → 9.

## Décisions structurantes

Les ADR font foi (`docs/adr/`). Rappel des décisions qui contraignent le code en cours :

- **ADR-002** : le vectoriel va en PostGIS/GeoPackage, le raster sur disque
  (GeoTIFF/COG). Jamais de raster en base.
- **ADR-003** : aucune valeur métier codée en dur ; tout seuil vient de
  `foretaccess_config()` (défauts Sylvaccess v3.6).
- **ADR-004** : découplage de l'I/O — chaque entrée est acceptée soit comme chemin
  de fichier, soit comme objet déjà chargé (`SpatRaster` / `sf`).
- **ADR-006** : non-régression via `compare_to_oracle()`. Au Lot 1 l'oracle est
  **analytique** (MNT jouet = plan incliné à 20 %) ; les oracles réels Sylvaccess
  v3.6 viendront plus tard.
- **Lot 1, §10** : politique CRS/grille **stricte** (erreur, pas de reprojection ni
  de rééchantillonnage silencieux) ; pente/exposition via `terra`/Horn, méthode
  **configurable** ; rasters en mémoire, écriture COG **optionnelle**.
- **Aucune couche sans CRS** n'est admise dans le projet : `valider_entrees()`
  rejette toute entrée dont le CRS est absent, sans jamais le compléter par
  défaut. Verrouillé par un test de non-régression.
- **Code R portable** : `R CMD check` interdit le non-ASCII dans les *chaînes*
  littérales (les commentaires et le roxygen le tolèrent). Les messages `cli`
  s'écrivent donc translittérés (é→e, à→a, ç→c).

## Lot 1 — état détaillé

Lot **terminé** et publié en `v0.2.0` (PR #7). Definition of Done intégralement
satisfaite : `preprocess()`, `valider_entrees()`, `calculer_terrain()` et
`lire_rasters()` livrés, critères d'acceptation CA-1.1 à CA-1.6 tous couverts par
des tests verts (oracle analytique du MNT jouet), CI verte sur les sept checks,
couverture globale à **97,91 %** (`R/io.R`, `R/validate.R`, `R/terrain.R` et
`R/preprocess.R` à 100 %).

### Effets de bord assumés

- `slope_pct`, `aspect_deg` et `exclusion_mask` valent `NA` sur la couronne de
  bordure : le calcul de pente exige les 8 voisins. Documenté (roxygen) et testé.
- `aspect_deg` vaut `NA` sur les cellules plates, là où `terra` renvoie 90.
- Le raster de desserte relu depuis un COG voit sa colonne de catégories renommée
  d'après la couche (`desserte` et non `classe`) : c'est GDAL. Les libellés sont
  préservés.

## Prochaine étape

Rédiger `specs/002-skidder.md` (Lot 2 — Moteur Skidder), qui introduit le service
least-cost partagé avec le Lot 6 (DFCI). Ne rien coder avant validation de la spec
et de ses questions ouvertes.

---

## Journal

### 2026-07-09
- Lot 0 clos et publié (`v0.1.0`), retour en cycle de dev `0.1.0.9000`.
- Specs des Lots 1 et 10 rédigées, décisions §10 tranchées, mergées sur `main`
  (PR #5 et #6).
- Ouverture de la branche `lot-1-pretraitement` ; `R/io.R` (helpers `.as_raster()`
  / `.as_vector()`) écrit.
- Création de ce `PLAN.md` (manquait alors que la règle 5 l'impose).
- **Lot 1 implémenté** : `R/validate.R`, `R/terrain.R`, `R/preprocess.R` et six
  fichiers de tests (`test-io`, `test-validate`, `test-slope-aspect`,
  `test-rasterize-masks`, `test-grid`, `test-cog`) + `helper-toy.R`. Suite verte.
- Ajout de `general$methode_pente` à la config (défaut `"Horn"`), pour permettre
  la réconciliation ultérieure avec l'oracle Sylvaccess v3.6 sans refonte.
- `DESCRIPTION`/`NEWS.md`/`CITATION.cff` alignés sur `0.2.0` ; spec 001 passée en
  statut « validé » et sa DoD cochée.

### 2026-07-10
- PR #7 : la CI a rattrapé deux défauts que la suite locale ne voyait pas.
  `R CMD check` refusait le non-ASCII dans les chaînes du code R (messages `cli`
  accentués) et signalait `PLAN.md` comme fichier non standard à la racine ;
  Codecov refusait la baisse de couverture (95,21 % → 94,21 %). `covr` a situé
  quatre branches d'erreur non exercées dans `R/validate.R` (résolution
  divergente, emprise décalée, géométrie invalide, couche sans CRS) — le test
  « volume non aligné » n'exerçait en réalité que le contrôle des dimensions.
  Corrigé : couverture à 97,91 %, CI verte sur les sept checks.
- `lintr` et `covr` installés dans la bibliothèque `renv` locale (sans toucher à
  `renv.lock`) : ils manquaient, d'où l'angle mort local.
- **Lot 1 mergé et publié en `v0.2.0`** ; retour en cycle de dev `0.2.0.9000`.
