# specs/001 — Lot 1 : I/O & prétraitement (commun)

> **Statut** : **validé** (décisions §10 tranchées le 2026-07-09) — implémenté au
> Lot 1, livré en `v0.2.0`.
> **Lot** : 1 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 1 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md), US-1.1…1.4). **Exigences** : EF-1, EF-2, EF-3
> ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 0 (config, `StorageBackend`, jeu jouet, harnais non-régression).
> **ADR liés** : ADR-003 (config/défauts v3.6), ADR-004 (découplage), ADR-006 (non-régression).
> **Ne rien coder avant validation de cette spec** (et des questions ouvertes §10).

---

## 1. Contexte

Le prétraitement est le **socle commun** aux 4 moteurs (skidder, porteur, câble, DFCI). Il
transforme les entrées SIG hétérogènes en un **jeu de rasters intermédiaires alignés** sur la
grille du MNT (pente, exposition, rasterisation des vecteurs, masques), après **validation
stricte** des entrées. Il correspond au §4.1 du brief. Aucune règle de moteur ici.

---

## 2. Périmètre

### Dans le périmètre
1. **Lecture** des entrées (US-1.1) : MNT (raster), desserte (polylignes classées), forêt
   (polygones), obstacles complets (vecteur), obstacles partiels (vecteur, skidder), volume sur
   pied (raster, optionnel), parcellaire (vecteur, optionnel — décision §9.5).
2. **Validation** (US-1.2, EF-2) : CRS commun, alignement sur la grille du MNT, champs
   attributaires requis ; messages d'erreur ciblés.
3. **Pente & exposition** (US-1.3) : rasters pente (%) et exposition (° depuis le nord) dérivés
   du MNT.
4. **Rasterisation & masques** (US-1.4) : rasterisation des vecteurs à la résolution du MNT ;
   masque forêt ; masque obstacles (complets/partiels) ; **masque d'exclusion** pente > seuil
   d'abattage manuel (défaut v3.6 = 100 %).
5. **Sortie** : un objet de prétraitement (`foretaccess_preprocessing`) regroupant les rasters
   alignés + métadonnées de grille, avec écriture optionnelle en GeoTIFF/COG.

### Hors périmètre
- Toute **règle de moteur** (treuillage, cône d'azimuts, câble, DFCI) → Lots 2–4, 6.
- Le **service least-cost** → Lot 2.
- Le **tuilage / passage à l'échelle** → Lot 7 (Lot 1 traite un bloc en mémoire).
- L'**écriture en base** des sorties (les rasters vont sur disque, pas en base — ADR-002).

---

## 3. Entrées / sorties

### Entrées (US-1.1)
| Rôle | Type | Obligatoire | Champs / notes |
|---|---|---|---|
| MNT | raster (GeoTIFF…) | oui | définit **grille, résolution, CRS de référence** |
| Desserte | vecteur lignes | oui | champ **`classe`** ∈ {`route`, `piste`, `dfci`} |
| Forêt | vecteur polygones | oui | emprise d'intérêt |
| Obstacles complets | vecteur | non | bloquent tous les engins |
| Obstacles partiels | vecteur | non | spécifiques skidder (sémantique au Lot 2) |
| Volume sur pied | raster | non | pour tableaux volumes (Lots 2+) |
| Parcellaire | vecteur polygones | non | agrégation par parcelle (Lot 8) |

Chaque entrée est acceptée soit comme **chemin de fichier** (lu via `terra`/`sf`), soit comme
objet déjà chargé (`SpatRaster`/`sf`) — pour rester testable et découplé (ADR-004).

### Sortie
Objet de classe **`foretaccess_preprocessing`** (liste structurée) :
- `slope_pct` : `SpatRaster` pente en %.
- `aspect_deg` : `SpatRaster` exposition en degrés (0–360, depuis le nord ; plat = `NA`).
- `foret_mask` : `SpatRaster` logique (1 = forêt).
- `desserte` : `SpatRaster` de classe de desserte (catégoriel : route/piste/dfci) + version
  vectorielle conservée pour le least-cost (Lot 2).
- `obstacles_complets_mask`, `obstacles_partiels_mask` : `SpatRaster` logiques (0 si absent).
- `exclusion_mask` : `SpatRaster` logique (1 = exclu : pente > seuil abattage).
- `volume` : `SpatRaster` (ou `NULL`), aligné.
- `parcellaire` : `sf` (ou `NULL`).
- `grid` : métadonnées (emprise, résolution, CRS, dimensions).

Tous les rasters partagent **exactement** la grille du MNT. Écriture optionnelle en
**GeoTIFF/COG** via un paramètre `write_dir` (chemin) ; sinon objets en mémoire.

---

## 4. Algorithme

Fonction publique proposée : `preprocess(mnt, desserte, foret, obstacles_complets = NULL,
obstacles_partiels = NULL, volume = NULL, parcellaire = NULL, config = foretaccess_config(),
write_dir = NULL)`.

1. **Chargement** : lire les entrées fournies en chemins (`terra::rast`, `sf::st_read`).
2. **Validation** (échec précoce, message ciblé) :
   - CRS : toutes les couches ont le **même CRS** que le MNT (politique — voir §10 Q1).
   - Grille : les rasters (volume) sont **alignés** sur la grille du MNT (origine, résolution,
     dimensions) ; sinon erreur (rééchantillonnage = §10 Q1).
   - Attributs : la desserte possède le champ `classe` avec des valeurs ∈ {route, piste, dfci}.
   - Géométries valides et non vides ; emprises se recouvrant.
3. **Pente & exposition** depuis le MNT :
   - pente en % = `tan(pente_radians) * 100`, exposition en degrés — méthode de calcul à
     **aligner sur Sylvaccess v3.6** (voir §10 Q2). Défaut proposé : Horn (8 voisins), comme
     `terra::terrain`.
4. **Rasterisation** des vecteurs à la grille du MNT (`terra::rasterize`) :
   - `foret_mask` (1 dans les polygones forêt) ;
   - `desserte` catégoriel (route/piste/dfci) ;
   - masques obstacles complets/partiels (1 où obstacle).
5. **Masque d'exclusion** : `exclusion_mask = slope_pct > config$skidder$pente_abattage_max_pct`
   (défaut 100 %). C'est la zone où l'abattage manuel est impossible (commune aux moteurs).
6. **Alignement du volume** (si fourni) sur la grille (contrôle, pas de rééchantillonnage
   silencieux — §10 Q1).
7. **Assemblage** de l'objet `foretaccess_preprocessing` ; écriture COG si `write_dir`.

Aucune valeur métier n'est codée en dur : les seuils viennent de `config` (ADR-003).

---

## 5. Critères d'acceptation

- **CA-1.1** `preprocess()` lit MNT + desserte + forêt du jeu jouet (et parcellaire s'il est
  fourni ; absence tolérée) et retourne un objet `foretaccess_preprocessing`.
- **CA-1.2** Validation : un CRS divergent, un champ `classe` manquant/inconnu, un volume non
  aligné, une géométrie vide → **erreur ciblée** (un test par cas).
- **CA-1.3** `slope_pct` et `aspect_deg` sont conformes à l'oracle **sous tolérance** : sur le
  MNT jouet (plan incliné 20 %), la pente vaut **20 %** (intérieur) et l'exposition est
  constante ; comparaison via `compare_to_oracle()`.
- **CA-1.4** `foret_mask`, `desserte` (catégoriel), masques obstacles et `exclusion_mask` sont
  alignés sur la grille du MNT et corrects (sur le jouet, `exclusion_mask` toute à 0 : 20 % <
  100 %).
- **CA-1.5** Tous les rasters de sortie partagent exactement la grille du MNT (emprise,
  résolution, dimensions, CRS).
- **CA-1.6** Écriture COG optionnelle (`write_dir`) : fichiers relus identiques (round-trip).

---

## 6. Tests (`testthat`)

- `test-io.R` : lecture depuis chemins et depuis objets ; parcellaire optionnel absent toléré.
- `test-validate.R` : CRS divergent, `classe` manquant, valeur `classe` inconnue, volume non
  aligné, géométrie vide → erreurs ciblées (messages testés).
- `test-slope-aspect.R` : pente ≈ 20 % (intérieur) et exposition constante sur le MNT jouet ;
  `compare_to_oracle()` sous tolérance ; robustesse aux bords documentée.
- `test-rasterize-masks.R` : `foret_mask` (comptage de cellules attendu), `desserte` catégoriel
  (3 classes), `exclusion_mask` = 0 partout sur le jouet, masques obstacles.
- `test-grid.R` : toutes les sorties partagent la grille du MNT.
- `test-cog.R` : round-trip GeoTIFF/COG si `write_dir`.

**Oracle** : au Lot 1, l'oracle est **analytique** (le MNT jouet a une pente connue de 20 %),
ce qui permet de valider pente/expo/masques sans exécuter Sylvaccess. Les **oracles réels
Sylvaccess v3.6** (sur un MNT réaliste) seront ajoutés dès qu'ils sont disponibles (ADR-006,
dépend §10 Q3).

---

## 7. Fichiers (proposition)

```
R/io.R              → lecture des entrées (terra/sf), normalisation chemin|objet
R/validate.R        → validation CRS / grille / attributs, erreurs ciblées (cli)
R/terrain.R         → pente (%) + exposition (°) depuis le MNT
R/preprocess.R      → orchestrateur preprocess() + classe foretaccess_preprocessing + write COG
tests/testthat/test-io.R, test-validate.R, test-slope-aspect.R,
                   test-rasterize-masks.R, test-grid.R, test-cog.R
```

Le jeu jouet du Lot 0 (`inst/extdata/toy/`) suffit ; on pourra l'enrichir (obstacles) via
`data-raw/make_toy.R` si besoin, de façon déterministe.

---

## 8. Risques & mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Méthode de pente ≠ Sylvaccess v3.6 | Non-régression terrain fausse | Méthode configurable ; défaut Horn ; réconcilier avec l'oracle v3.6 / le `.pyx` (§10 Q2) |
| Effets de bord du calcul de pente aux bordures | Écarts en lisière de raster | Tolérance + option de recadrage ; documenter |
| Politique CRS (strict vs reprojection) | Ergonomie vs exactitude | Décidé en §10 Q1 ; défaut strict (erreur explicite) |
| Grille volume non alignée | Résultats faux | Contrôle d'alignement ; erreur (pas de rééchantillonnage silencieux) |
| Rasters volumineux en mémoire | Perf/mémoire | Hors périmètre (Lot 7 tuilage) ; Lot 1 = bloc unique |

---

## 9. Definition of Done (Lot 1)

- [x] Spec validée (ce fichier) + questions §10 tranchées.
- [x] `preprocess()` + validation + terrain + rasterisation/masques implémentés.
- [x] Tests verts (pente/expo/masques conformes à l'oracle ; erreurs d'entrée ciblées).
- [ ] `lintr`/`testthat`/`R CMD check` et `cargo`/`clippy` OK en CI ; couverture maintenue.
- [x] Doc d'usage (roxygen) ; entrée `NEWS.md`.
- [ ] Branche dédiée + PR + revue ; commits atomiques.

---

## 10. Décisions (tranchées 2026-07-09)

1. **Politique CRS / grille** : **stricte** — toutes les couches doivent partager le CRS et
   l'alignement de grille du MNT ; sinon **erreur ciblée**. Aucune reprojection/rééchantillonnage
   silencieux (l'utilisateur reprojette en amont).
2. **Pente / exposition** : **`terra`/Horn** (8 voisins) au Lot 1 ; réconciliation avec l'oracle
   Sylvaccess v3.6 (et le `.pyx`) différée. La méthode reste **configurable** pour permettre cet
   ajustement sans refonte.
3. **Oracle de non-régression** : **analytique** — validation sur le MNT jouet (plan incliné
   20 %, exposition constante). Les oracles réels Sylvaccess v3.6 seront ajoutés ultérieurement
   (ADR-006).
4. **Sortie rasters** : **objets en mémoire** + écriture GeoTIFF/COG **optionnelle** via
   `write_dir` (pas d'I/O imposé à chaque appel).
