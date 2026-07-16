# specs/015 — Lot 15 : Solveur de tracé (A\* sur graphe étendu, noyau Rust)

> **Statut** : **proposé** — en attente de validation.
> **Lot** : 15 (roadmap [`docs/ROADMAP-desserte.md`](../docs/ROADMAP-desserte.md)).
> **Dépend de** : Lot 14 (surface de coût + franchissabilité), Lot 0 (chaîne `extendr`),
> Lot 7 (tuilage — le solveur en héritera pour l'échelle).
> **Prépare** : Lot 16 (réseau MTAP), Lot 17 (flux & types).
> **ADR liés** : ADR-001 (langages — **ce lot déclenche un portage Rust**, cf. §9),
> ADR-008 (graphe étendu à voisinage disque), ADR-006 (non-régression sur oracle).
> **Attribution** : l'algorithme reproduit **SylvaRoad** (S. Dupire / SylvaLab / ONF, 2021,
> GPL v3, `gitlab.com/SDupire/sylvaroad` ; adaptation QGIS `github.com/Tijjat/SylvaRoad_qgis_plugin`)
> et **Forest Road Designer** (PANOimagen / Gob. La Rioja, GPL v3,
> `github.com/GobiernoLaRioja/forestroaddesigner`). Voir §11.

---

## 1. Contexte

C'est le **cœur** de la conception de desserte : trouver le meilleur itinéraire d'un point de
départ à un point d'arrivée (avec points de passage obligatoires), sur une surface de coût,
en respectant des contraintes de géométrie routière — pente en long bornée, virages doux,
rayon de braquage minimal, épingles maîtrisées, profil compatible avec le terrain.

Deux outils libres résolvent **exactement** ce problème, dans la même famille (A\* + pénalités
paraboliques) :

- **SylvaRoad** : A\* sur voisinage **disque paramétrable** (`D_neighborhood`), heuristique =
  distance-de-coût **pré-calculée depuis la cible** (Dijkstra inverse), gestion explicite des
  **épingles** (rayon `Radius`, angle limite trigonométrique tenant compte de la largeur de
  plateforme), contrôle de profil (`check_profile`, `max_diff_z`).
- **Forest Road Designer (FRD)** : même A\*, avec en plus un **rayon de courbure explicite**
  (`min_curve_radius` + pénalité dédiée), déduplication angulaire du voisinage, simplification
  de polyligne (`polysimplify`), mode interactif, Processing provider.

Ce lot **fusionne** les deux : structure et rayon de courbure de FRD, heuristique pré-calculée
et traitement des épingles de SylvaRoad. Le solveur ne fait **pas** de réseau (c'est le Lot 16) :
il trace un tronçon entre deux points imposés.

`propager_cout()` / `.dijkstra()` (Lot 2, R, voisinage 8, sans pénalité d'angle) est un **cas
dégénéré** de ce solveur ; ce lot le généralise et le remplace là où la desserte l'exige.

---

## 2. Périmètre

### Dans le périmètre

- La **table de voisinage étendu** : pour un rayon `D_neighborhood`, tous les voisins dans le
  disque, angles dédupliqués (une direction par azimut distinct), avec distance et azimut.
  Filtrage amont des voisins hors `[pente_long_min, pente_long_max]` (contrainte **dure**).
- Le **solveur A\*** : file de priorité binaire, priorité `g + h` avec `h` = distance-de-coût
  pré-calculée depuis la cible (Dijkstra inverse sur le coût de franchissabilité).
- Le **coût de transition** : `distance + penalite_direction + penalite_pente + longueur_devers_excessif`,
  pénalités **quadratiques** (`(Δangle/angle_ref)²`, `(Δpente/pente_ref)²`).
- La **gestion des épingles** : détection (angle > `angle_epingle`), contrainte de rayon de
  braquage `Radius`, angle limite fonction de la largeur de plateforme ; surcoût dédié.
- Le **rayon de courbure minimal** (FRD) comme pénalité géométrique continue.
- Le **contrôle de profil** (`check_profile`) : écart altitude tracé/terrain ≤ `max_diff_z`
  proportionnel à la longueur, et cumul de dévers excessif ≤ `Lmax_ab_sl`.
- L'enchaînement des **points de passage obligatoires** (segments successifs).
- L'exposition **`extendr`** du solveur ; `cargo test` **et** tests d'intégration R.

### Hors périmètre

- Le **coût de construction** lui-même : Lot 14 (fourni en entrée).
- L'**ordonnancement de cibles** et la **réutilisation du réseau** : Lot 16 (MTAP).
- La **vectorisation** en polylignes propres et le **retracé des lacets** : côté R
  (post-traitement, incrément 15c), réutilisant `chemin_optimal()`.
- Le **mode interactif** de FRD : hors périmètre (batch uniquement).

---

## 3. Entrées / sorties

### Frontière R↔Rust (minimale et typée, ADR-001)

R prépare et passe des **tableaux `f64`/`i32`**, jamais un objet SIG :

- la surface de coût et le masque de franchissabilité (Lot 14), en grilles aplaties + dims ;
- le MNT (profil d'altitude, pour `check_profile`) ;
- les **waypoints** (indices de cellules : départ, arrivée, passages obligatoires) ;
- les paramètres : `D_neighborhood`, `pente_long_min/max`, `pente_travers_max`,
  `pente_travers_max_epingle`, `angle_epingle`, `Radius`, `rayon_courbure_min`,
  `penalty_direction`, `penalty_pente`, `max_diff_z`, `Lmax_ab_sl`, largeur de plateforme.

Rust renvoie, par segment : la **suite d'indices de cellules** du tracé optimal (via table de
prédécesseurs), le **coût total**, et un **booléen faisable**.

### Sortie R (incrément 15c)

Un objet `foretaccess_trace` : un `sf` LINESTRING par tronçon optimal, un `sf` LINESTRING avec
lacets retracés, un tableau récapitulatif par tronçon (longueur, coût, pente moyenne, nb
épingles), et le rappel des paramètres.

---

## 4. Algorithme (A\* fusionné)

### 4.1 Voisinage (build_NeibTable / precalc_neighbourhood)

Fenêtre carrée de rayon `nb = round(D_neighborhood / Csize)` autour de chaque cellule ; on
garde les voisins dans le **disque** de rayon `D_neighborhood`. **Déduplication angulaire**
(FRD) : pour chaque azimut, un seul voisin (le plus proche). Pré-calcul distance + azimut.
Les arêtes dont la pente en long sort de `[min, max]` sont **supprimées** (contrainte dure).

### 4.2 Heuristique (SylvaRoad)

`h(n)` = distance-de-coût de `n` à la cible, pré-calculée par un **Dijkstra inverse** depuis la
cible sur le coût de franchissabilité (`calcul_distance_de_cout`). Admissible (borne inférieure
du coût restant) → A\* optimal, et fournit l'**arrêt anticipé**.

### 4.3 Coût de transition (basic_calc / ParabolicPenalty)

Pour aller de la cellule courante à un voisin, à distance `D`, azimut `az` :

```
Δangle       = diff_azimut(az, az_precedent)
penalite_dir = penalty_direction * (max(Δangle, Δangle2) / angle_epingle)^2      # quadratique
Δpente       = |pente_courante - pente_voisin|
penalite_pente = penalty_pente * (Δpente / max_slope_change)^2                    # quadratique
newLsl       = longueur cumulée en dévers > pente_travers_max (contrôle check_profile)
cout         = g_courant + D + penalite_dir + penalite_pente + newLsl
```

- **Épingle** si `Δangle > angle_epingle` : impose `Radius` (le point courant doit être à
  distance ≥ ~`2·Radius` du précédent), surcoût `+= 100·(pente_locale/pente_travers_max)²`.
- **Rayon de courbure** (FRD) : pénalité continue `penalty_radius·(rayon_min - cot(angle/2))²`
  quand le rayon effectif passe sous `rayon_courbure_min`.
- **Profil** (`check_profile`) : rejet du voisin si l'écart altitude tracé/terrain dépasse
  `max_diff_z · L / D_neighborhood`, ou si le cumul de dévers excessif dépasse `Lmax_ab_sl`.

### 4.4 Boucle A\* et waypoints

File binaire ordonnée par `g + h`. À chaque cellule dépilée, relaxation des voisins ; mise à
jour si `g` amélioré. Arrêt du segment à l'atteinte de la cible (+ marge `Dcheck` pour la
finition). Les **points de passage obligatoires** découpent le tracé en segments successifs,
chacun résolu de son départ à sa cible, le point d'arrivée d'un segment étant le départ du
suivant.

---

## 5. Critères d'acceptation

- **CA-15.1** — Sur un coût uniforme sans contrainte, le tracé est la **droite** départ→arrivée
  (aux artefacts de discrétisation près) ; il équivaut à `propager_cout` + `chemin_optimal`.
- **CA-15.2** — Une arête dont la pente en long sort de `[min, max]` n'est **jamais** empruntée.
- **CA-15.3** — Augmenter `penalty_direction` **lisse** le tracé (moins de changements d'azimut) ;
  augmenter `penalty_pente` lisse le profil en long.
- **CA-15.4** — Un obstacle infranchissable (Lot 14, `NA`) est **contourné** ; jamais traversé.
- **CA-15.5** — En terrain raide imposant un demi-tour, une **épingle** est tracée en respectant
  `Radius` et `angle_epingle`.
- **CA-15.6** — Les points de passage obligatoires sont **tous traversés**, dans l'ordre.
- **CA-15.7** — Non-régression contre **SylvaRoad** sur son jeu `meisenthal2` : même tracé à
  tolérance définie (longueur ≤ 1 %, coût ≤ 2 %), mêmes segments infaisables signalés.
- **CA-15.8** — `h` admissible : le coût A\* égale le coût Dijkstra complet (mêmes tracés) sur
  cas test réduit (preuve d'optimalité).
- **CA-15.9** — Déterminisme : deux exécutions identiques → tracés identiques (départage stable
  des égalités dans la file).

---

## 6. Tests & oracle

- **Oracle principal** : SylvaRoad (`test files/meisenthal2`), exécuté en référence, tracés
  comparés géométriquement (Hausdorff/longueur/coût) sous tolérance.
- **Oracle secondaire** : FRD sur ses propres cas (rayon de courbure).
- `cargo test` : voisinage (dédup, filtrage pente), `diff_azimut`, `check_profile`, une itération
  A\* sur micro-grille.
- Intégration R : bout-en-bout sur jeu jouet + `meisenthal2`.

---

## 7. Découpage du lot

- **15a** — voisinage étendu + Dijkstra inverse (`h`) en Rust ; exposition `extendr`.
- **15b** — solveur A\* complet (transition, épingles, rayon, profil, waypoints) en Rust.
- **15c** — orchestration R : préparation des tableaux, appel, reconstruction des polylignes,
  retracé des lacets, sortie `foretaccess_trace` (`sf`).

---

## 8. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Explosion mémoire du voisinage (grand `D_neighborhood`) | Voisinage dédupliqué angulairement (FRD) ; borne sur `D_neighborhood` documentée. |
| Non-admissibilité de `h` → tracé sous-optimal | `h` = Dijkstra inverse exact sur coût minoré ; test CA-15.8. |
| Divergence numérique vs SylvaRoad | Reproduction fidèle des formules §4 ; tolérance CA-15.7. |
| Point chaud non tenable en R | Portage Rust dès ce lot (déclencheur ADR-001 activé, §9). |
| Épingles instables | Reprise du calcul d'angle limite SylvaRoad (largeur plateforme). |

---

## 9. Déclenchement du portage Rust (ADR-001)

ADR-001 réserve le portage Rust au-delà du câble « si la performance l'exige ». **Ce lot
l'exige** : le solveur balaie tous les voisins du disque (~30-50) à chaque cellule dépilée, sur
des grilles de massif, et le Lot 16 le rappellera des dizaines à centaines de fois. C'est du
calcul pur sans I/O SIG → **frontière R↔Rust idéale**, parallélisable (`rayon`) au Lot 16.
Le voisinage et le Dijkstra inverse (15a) sont portés d'abord pour valider la frontière.

---

## 10. Definition of Done (Lot 15)

- [ ] 15a/15b/15c livrés ; `foretaccess_trace` produit des `sf` (CRS strict).
- [ ] CA-15.1 à CA-15.9 couverts (`cargo test` + `testthat`).
- [ ] Non-régression verte contre SylvaRoad (`meisenthal2`) sous tolérance.
- [ ] `Cargo.lock` versionné ; `rextendr::document()` OK ; speedup mesuré vs R pur.
- [ ] `R CMD check` OK ; chaînes ASCII ; `lintr` 0 ; doc roxygen ; `NEWS.md` ; `PLAN.md`.
- [ ] Branche dédiée + PR ; commits atomiques ; release proposée `v0.14.0`.

---

## 11. Attribution

L'algorithme §4 dérive de **SylvaRoad** (`functions.py`, `functions_np.py`, `GIS.py` :
`Astar_buf_wp`, `basic_calc`, `calc_init`, `build_NeibTable`, `check_profile`,
`calcul_distance_de_cout`) et de **Forest Road Designer** (`route_optimizer/a_star.py`,
`penalties.py`, `heuristics.py` : `ParabolicPenalty`, `precalc_neighbourhood`,
`min_curve_radius`), tous deux GPL v3. FRD s'inspire lui-même de l'extension ArcView PEGGER.
ForêtAccess est distribué sous GPL v3 : réécriture en Rust, aucune copie de source.
