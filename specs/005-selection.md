# specs/005 — Lot 5 : Sélection multicritère des lignes câble

> **Statut** : **validé** (décisions §10 du 2026-07-12, sur **lecture du code source**
> Sylvaccess v3.6 : `Sylvaccess_2_cable.py::line_selection`,
> `Sylvaccess_0_functions.py::{select_best_lines, create_best_table, gen_sel_table}`,
> `sylvaccess_cython3.pyx::{get_line_carac_simple, get_line_carac_vol, Check_line2,
> Check_line3, get_prop}`, cf. §12).
> **Lot** : 5 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 5 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md)). **Exigence** : EF-7 ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 4 (noyau câble, `potentiel_cable()` et le noyau Rust `cablehelp`),
> Lot 1 (`preprocess()`, `pre$volume`).
> **Prépare** : Lot 8 (base spatiale — les lignes sélectionnées y sont persistées/requêtables).
> **Attribution** : les règles §4 dérivent du code source Sylvaccess (GPL v3) — §12.

---

## 1. Contexte

Le Lot 4 produit, par le balayage 360°/pixel, l'**ensemble des lignes de câble faisables**.
Il y en a beaucoup (jusqu'à 360 par pixel de desserte) et elles se **recouvrent**
largement. Le Lot 5 en **sélectionne un sous-ensemble** exploitable — celui qui couvre au
mieux la forêt selon des critères pondérés (surface, supports, sens, longueur, volume, IPC),
sans lignes redondantes. C'est la sortie **décisionnelle** du volet câble (EF-7).

---

## 2. Périmètre

### Dans le périmètre

- La **table des lignes candidates** : une ligne par couple (départ, azimut) faisable, avec
  ses attributs — départ, azimut, longueur, **surface forêt couverte**, distance moyenne du
  chariot, nombre de supports (0 dans ce lot, cf. Lot 4d), et — si un raster de volume est
  fourni — **volume total**, volume moyen de l'arbre, **IPC** (indice de production câble).
- La **sélection multicritère** : filtrage par limites (min/max), score pondéré normalisé par
  critère, classement, **sélection gloutonne avec évitement de recouvrement**, filtre de
  contribution (une ligne retenue doit apporter une surface **nouvelle** significative).
- Les **sorties** : les lignes sélectionnées en objet **`sf`** (géométries + attributs,
  requêtable/persistable — Lot 8) et un **raster de couverture** de la zone câble retenue.

### Hors périmètre

- Le **placement des supports intermédiaires** (`OptPyl_Up`) : dette du Lot 4, nécessite un
  oracle réel. Ici `nb_supports = 0`.
- La **persistance en base** proprement dite (PostGIS/GeoPackage) : interface du Lot 8. Le
  Lot 5 produit l'objet `sf` prêt à écrire.
- Le **coût €/m³** et le **VAM×10** : critères optionnels de v3.6, repoussés (§10.5).

---

## 3. Entrées / sorties

### Entrées

- L'objet `foretaccess_cable` du Lot 4 (ou directement `pre` + `config`), enrichi de la
  **table des lignes candidates** (`$lignes`).
- Un **raster de volume/ha** optionnel (`pre$volume`) : sans lui, les critères volume/IPC sont
  neutralisés (poids et limites mis à 0, comme Sylvaccess `cls_pbvol`).
- Les **poids** (`config$cable$selection$poids`) et **limites** (`…$limites`) par critère.

### Sorties

- `lignes_selectionnees` : objet **`sf`** (LINESTRING) — une géométrie par ligne retenue,
  attributs : départ, azimut, longueur, surface, distance moyenne, supports, volume, IPC.
- `couverture` : `SpatRaster` de la zone câble couverte par les lignes retenues.

---

## 4. Algorithme

### 4.1 Caractérisation d'une ligne (`get_line_carac_*`)

Pour une ligne (départ `(x, y)`, azimut `az`, longueur `Lline`), on parcourt son **emprise**
(le rayon élargi de la demi-largeur de pêchage `distance_laterale_max_m`) et on compte :

- **Surface** = nombre de cellules **forestières** couvertes × aire de cellule ;
- **Distance moyenne** du chariot (distance latérale moyenne des cellules à l'axe) ;
- si volume fourni : **Vtot** = Σ volume/ha des cellules couvertes × aire, **VAM** moyen.

**IPC** (indice de production câble) = `100 · Vtot · prélèvement / longueur`
(volume prélevable par mètre linéaire de câble).

### 4.2 Filtrage par limites, puis score pondéré (`create_best_table`)

Chaque critère `k` a un **poids** `w_k ≥ 0` (0 = ignoré) et une **limite** `lim_k` de sens
donné (minimum ou maximum) :

1. **Filtre** : on écarte toute ligne violant une limite active (`valeur < lim` pour un
   minimum, `valeur > lim` pour un maximum).
2. **Normalisation** dans `[0, ~1]`, pondérée :
   - critère à **minimiser** (supports, longueur, distance) : `(1 − valeur/max) · w_k` ;
   - critère à **maximiser** (surface, volume, IPC) : `(valeur / p98) · w_k`
     (`p98` = 98ᵉ centile, robuste aux extrêmes).
3. **Score total** = Σ des critères normalisés.
4. **Classement** par score décroissant. Si un **sens de débardage** préféré est choisi, ses
   lignes sont classées d'abord, puis l'autre sens.

### 4.3 Sélection gloutonne (`select_best_lines`)

Sur les lignes classées, du meilleur score au moins bon :

1. **Évitement de recouvrement** (`Check_line2`) : une ligne n'est retenue que si son axe ne
   croise pas une ligne déjà retenue à moins de `recouv = min(0.6·Lhor, Lhor − taille_cellule)`.
   Retenue ⇒ son emprise est marquée dans le raster de couverture.
2. **Contribution** (`get_prop` + `Check_line3`) : chaque ligne retenue doit apporter une
   **proportion de surface nouvelle** ≥ 60 % ; sinon elle est retirée. Re-tri par contribution.

Le résultat est l'ensemble des lignes non redondantes couvrant au mieux la forêt.

---

## 5. Critères d'acceptation

- **CA-5.1** La table des lignes candidates a une ligne par (départ, azimut) faisable, avec
  surface > 0 et longueur ∈ `[longueur_min_m, longueur_max_m]`.
- **CA-5.2** Sans raster de volume, les critères volume/IPC sont neutralisés (poids/limite 0)
  et la sélection fonctionne sur les critères géométriques.
- **CA-5.3** Le filtrage par limites écarte exactement les lignes hors bornes.
- **CA-5.4** Le score pondéré ordonne les lignes : à poids « surface » seul, la ligne de plus
  grande surface est première ; à poids « supports » seul (minimiser), la ligne au moins de
  supports est première.
- **CA-5.5** Deux lignes qui se recouvrent (axes proches) ne sont pas toutes deux retenues ;
  la mieux classée gagne.
- **CA-5.6** Une ligne n'apportant pas de surface nouvelle significative (< 60 %) est retirée.
- **CA-5.7** La sortie `sf` est valide (CRS présent, géométries LINESTRING) et le raster de
  couverture ne marque que des cellules couvertes par une ligne retenue.
- **CA-5.8** **Reproductibilité** : à poids/limites fixés et même entrée, la sélection est
  déterministe (tri stable).

---

## 6. Tests

- **R** (`testthat`) : table des lignes sur MNT synthétique (Lot 4) ; filtrage par limites ;
  ordre du score selon le poids dominant ; évitement de recouvrement (deux lignes parallèles
  proches) ; filtre de contribution ; validité `sf` (CRS, LINESTRING) et couverture.

**Oracle** : les formules (§4) sont exactes (lues dans la source). La reproductibilité **vs
v3.6 sur le jeu test** (CA2 du backlog) nécessite une exécution Sylvaccess de référence ;
d'ici là, l'oracle est **analytique** sur des tables de lignes construites à la main.

---

## 7. Fichiers (proposition)

```
R/cable.R          → potentiel_cable() emet aussi $lignes (table candidate)  [5a]
R/selection.R      → selectionner_lignes(cable, config) : score + greedy      [5b]
tests/testthat/test-cable-lignes.R       → table des lignes candidates
tests/testthat/test-selection.R          → filtrage, score, greedy, sortie sf
```

La caractérisation des lignes (§4.1) est peu coûteuse et reste en **R** (parcours d'emprise) ;
pas de nouvelle frontière Rust. Le noyau câble Rust du Lot 4 suffit.

---

## 8. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Table de lignes volumineuse (360/pixel) | On ne garde qu'**une candidate par (départ, azimut)** : la plus longue faisable (Lot 4d). |
| Critères volume absents | Neutralisation automatique (poids/limite 0), cf. CA-5.2. |
| Recouvrement mal mesuré | Tolérance `recouv` reproduite du `.pyx` ; test dédié (CA-5.5). |
| Non-déterminisme du tri | Tri **lexicographique stable** (score, id) comme `np.lexsort` (CA-5.8). |
| Reproductibilité vs v3.6 non vérifiable | Oracle analytique en attendant une exécution de référence (§6, §10.6). |

---

## 9. Definition of Done (Lot 5)

- [ ] `potentiel_cable()` émet `$lignes` (5a) ; `selectionner_lignes()` livré (5b).
- [ ] CA-5.1 à CA-5.8 couverts par des tests `testthat`.
- [ ] Sortie `sf` avec CRS strict (règle projet) ; raster de couverture cohérent.
- [ ] `R CMD check` OK en CI ; couverture ≥ `main` ; chaînes R **ASCII** ; `lintr` 0.
- [ ] Doc roxygen ; entrée `NEWS.md` ; `PLAN.md` à jour.
- [ ] Branche dédiée + PR ; commits atomiques ; release `v0.7.0` (sortie décisionnelle câble).

---

## 10. Décisions (tranchées 2026-07-12, sur lecture du code source)

1. **La sélection reste en R.** La caractérisation des lignes et le glouton sont du parcours
   de raster + tri, sans calcul câble : pas de nouvelle frontière Rust (le noyau du Lot 4
   suffit). Cohérent avec ADR-001 (Rust = mécanique câble seulement).
2. **Une candidate par (départ, azimut)** : la plus longue ligne faisable trouvée en 4d. On
   évite l'explosion combinatoire des sous-longueurs, sans perte pour la couverture.
3. **Six critères MVP** (EF-7) : surface (max), supports (min), sens (amont/aval), longueur
   (min/max), volume (max), IPC (max). Chacun a **poids** et **limite** dans
   `config$cable$selection`. Le **VAM×10** et le **coût €/m³** de v3.6 sont repoussés (§10.5).
4. **Normalisation fidèle** : minimiser → `1 − v/max` ; maximiser → `v/p98`. Score = Σ pondérée.
   Filtre par limites amont. Tri lexicographique stable (déterminisme).
5. **Chariot classique, 0 support** (héritage Lot 4). Le nombre de supports est un critère
   (toujours 0 ici) ; il redeviendra discriminant quand `OptPyl_Up` sera porté.
6. **Reproductibilité vs v3.6** (CA2 backlog) : visée mais non vérifiable sans exécution
   Sylvaccess de référence. On verrouille le **déterminisme** (CA-5.8) et la fidélité des
   formules ; la confrontation à l'oracle réel viendra avec le jeu test v3.6.

### Découpage du lot

- **5a** — table des lignes candidates : `potentiel_cable()` émet `$lignes` (surface,
  longueur, azimut, départ, distance moyenne, volume/IPC si `pre$volume`).
- **5b** — sélection : `selectionner_lignes()` (filtre, score, glouton, contribution), sortie
  `sf` + raster de couverture.

---

## 11. Attribution

Les règles §4 dérivent du code source Sylvaccess v3.6 (`line_selection`, `select_best_lines`,
`create_best_table`, `get_line_carac_simple`/`_vol`, `Check_line2`/`3`, `get_prop`),
distribué sous GPL v3. ForêtAccess est distribué sous GPL v3 (règle 4 de `CLAUDE.md`).
