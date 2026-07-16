# specs/013 — Optimisation de la hauteur des supports façon SEILAPLAN (Bont & Heinimann 2012)

> **Statut** : **proposé, algorithme précisé sur le source** (2026-07-16). Remplace le
> chantier `c_option_h` transcrit de Sylvaccess (`OptPyl_Up`/`OptPyl_Up2`), **shelvé**
> car bugué (réduit la couverture) et lent (~20× le `_NoH`) — cf. `PLAN.md` (journal
> 16/07), `specs/004` (§ Statut c_option_h). L'algorithme SEILAPLAN a été **lu dans le
> code du plugin** (§2), pas seulement dans le papier.
> **Exigence** : fidélité du moteur câble (levier : optimisation de la hauteur).
> **Dépend de** : Lot 4 (noyau câble Rust `cablehelp` : caténaire Newton/Irvine,
> `test_span`, faisabilité de travée), Lot 5 (sélection de lignes, à terme).
> **Référence de conception** : `docs/comparaison-cable-seilaplan.md`.

---

## 1. Contexte et décision

L'optimisation de la hauteur de fixation des supports est une **dette du Lot 4**. Deux
voies :

1. **Transcrire `OptPyl_Up`/`Up2` de Sylvaccess** (`c_option_h=1`). *Tentée et
   abandonnée* : le port réduit la couverture (net −999) au lieu de l'augmenter (oracle
   +470), il est ~20× plus lent, et le **code d'origine plante lui-même** (bug de
   tampon `Tab`, chemin jamais exercé sur un vrai jeu — voilà pourquoi le défaut v3.6
   est `false`). L'heuristique de faisceau `get_Tabis` est fragile et dépendante de
   l'ordre.

2. **Transcrire SEILAPLAN** (algorithme **Bont & Heinimann 2012**). *Voie retenue.*
   Publié, validé contre des mesures (Bont et al. 2022), open-source (GPL,
   <https://github.com/piMoll/SEILAPLAN>). Il pose le problème comme un **graphe** —
   plus court chemin, donc **polynomial et déterministe**, sans l'explosion du double
   balayage `Hg×Hd`.

**Décision** : coder l'optimisation position+hauteur des supports **à la SEILAPLAN**,
en **réutilisant notre mécanique caténaire** (Newton/Irvine déjà validée à l'oracle),
et non celle de Zweifel. On découple *optimisation* (nouvelle) et *mécanique*
(inchangée).

---

## 2. Le modèle SEILAPLAN (Bont & Heinimann 2012)

**Source lu** (2026-07-16) : plugin SEILAPLAN, `core/main_opti.py` (graphe + Dijkstra),
`core/opti_sta.py` (`calcSTA`), `core/cableline.py` (`calcCable`/`calcBandH`, Zweifel),
`core/peakdetect.py` (positions candidates). L'algorithme ci-dessous est transcrit de ce
code, pas seulement du papier.

Le problème « placer les supports (position **et** hauteur) minimisant leur **nombre**
puis leur **hauteur** » est un **plus court chemin dans un graphe** :

### 2.1 Nœuds
Un nœud = un couple **(position candidate, hauteur)**.
- **Positions** : les points **saillants** du profil (`StuetzenPos`, détectés par
  `peakdetect`), soumis à un espacement minimal `Min_Dist_Mast`. Pas *tous* les pixels
  au pas `δl` — seulement les crêtes de terrain où un support a un sens.
- **Hauteurs** : `range(min_HM, max_HM + 1, Abstufung_HM)` — niveaux au pas
  `Abstufung_HM` (`δh ≈ 1 m`), de `min_HM` à `max_HM`.
- **Extrémités** : mât de départ (hauteur fixe `HM_Kran`, ou variable si support/ancrage),
  ancrage d'arrivée (hauteur 0, ou variable). Traités à part (`stufenAnzAnf`,
  `stufenAnzEnd`).

### 2.2 Arêtes — plage de pré-tension admissible (`calcSTA`)
Pour chaque paire de nœuds `(a, e)` telle que `di[e] - di[a] > Min_Dist_Mast` (plus les
arêtes départ/arrivée), on calcule via `calcSTA` la **plage de pré-tension globale du
câble** `[MinSTA, MaxSTA]` pour laquelle la travée est faisable :
- `calcSTA` fait une **bissection** sur la pré-tension `STA` entre `min_SK` et `zul_SK` ;
- à chaque `STA`, `calcCable` (mécanique **Zweifel**) vérifie **garde au sol** (via
  `checkCable` + `sc`, le *soil clearance*) **et effort** (`ST_max ≤ zul_SK`) ;
- rend `Min`/`Max` = bornes de `STA` où la travée tient. `CableLineImpossible` sinon.

C'est la **différence de modèle majeure** avec nous (voir §3) : SEILAPLAN a **une
pré-tension globale unique** pour toute la ligne (skyline à ancrages fixes des deux
côtés), et chaque travée la **contraint** ; il ne propage pas la tension travée à travée.

### 2.3 Coût des arêtes
```
KostStue = (h == 0 ? 1 : (h + 100)²) × (1 + 4·[h > HM_nat])   (+ pénalité 1er support)
```
où `h` = hauteur du support **aval** de l'arête, `HM_nat` = hauteur d'un support
*naturel* (arbre disponible). Donc : chaque support coûte au moins `≈ 100² = 10000`
(→ minimise le **nombre**), puis `(h+100)²` croît avec la hauteur (→ minimise la
**hauteur**), avec un facteur **×5** si le support dépasse l'arbre naturel disponible
(→ évite les mâts artificiels). Hauteur 0 → coût 1 (jamais 0, sinon « pas d'arête »).

### 2.4 Balayage de pré-tension + plus court chemin
Boucle externe sur la pré-tension entière `sk` de `min_SK` à `zul_SK` :
1. arête `(a,e)` **active** ssi `MinSTA < sk < MaxSTA` (travée compatible avec `sk`) ;
2. matrice de graphe `G[a,e] = KostStue` sur les arêtes actives, plus nœuds
   source/puits virtuels ;
3. **Dijkstra** (`scipy.sparse.csgraph.dijkstra`, orienté) depuis le puits ;
4. `LengthInLP` = nœud le plus lointain atteignable (**portée maximale** ; coupe si le
   profil entier ne passe pas).
On retient la solution qui **maximise la portée** puis **minimise le coût** ; `OptSTA`
= la pré-tension optimale associée.

**Sorties** : positions des supports (`stueIdx`), leurs hauteurs (`Loesung_HM`), la
pré-tension optimale (`OptSTA`), la valeur objectif (`Value`).

**Réglages exposés** : `δh = Abstufung_HM` (≈ 1 m), `Min_Dist_Mast` (≈ 10 m),
`[min_SK, zul_SK]` (plage de pré-tension), `HM_nat` (hauteur d'arbre-support).

---

## 3. Périmètre, frontières et le point dur mécanique

**Ce qu'on remplace** : le placement des supports `OptPyl_*` (faisceau `get_Tabis`,
propagation de tension travée à travée) → **graphe + Dijkstra** à la B&H (§2), avec
optimisation de la hauteur.

**Le point dur : deux modèles mécaniques différents.**
- **Nous/Sylvaccess** : la tension est **propagée** travée à travée (chaque travée
  hérite `tcalc` de la précédente ; `test_span` teste **une** tension). Heuristique
  gloutonne, dépendante de l'ordre.
- **SEILAPLAN** : **une pré-tension globale unique** `STA` pour toute la ligne ; chaque
  travée fournit une **plage** `[MinSTA, MaxSTA]` ; une ligne est faisable à `sk` ssi
  **toutes** ses travées admettent `sk` (Dijkstra à `sk` fixe). Modèle « standing
  skyline, ancrages fixes des deux côtés », plus proche de la pose réelle.

Adopter la méthode SEILAPLAN, c'est donc adopter **son modèle de pré-tension globale**,
pas seulement le graphe. Reste à décider **avec quelle mécanique** on évalue une travée
à une pré-tension donnée (`calcCable`) — cf. §4 décision 1.

**Ce qui reste hors périmètre** :
- La **friction** au sabot (absente de Sylvaccess v3.6 comme de notre port ; SEILAPLAN
  l'a, effet mineur et conservateur — décision séparée si un jour souhaité).
- La **sélection de lignes** (Lot 5) et le dimensionnement des arbres-supports (DBH).

---

## 4. Décisions à trancher (avant implémentation)

1. **Mécanique de `calcCable` : notre caténaire ou Zweifel ?** *(la plus importante)*
   Le graphe a besoin, pour une travée + une pré-tension `STA`, de : garde au sol tenue
   ? effort ≤ admissible ? Deux options :
   - **(a) Réutiliser notre caténaire** Newton/Irvine : reparamétrer pour prendre une
     **pré-tension imposée** (au lieu de propager) et rendre `(garde_ok, effort_ok, sag)`.
     Notre solveur Newton résout déjà la caténaire élastique ; il faut l'appeler à
     tension fixée et vérifier `calcul_zs` contre `sc`. **Recommandé** : garde notre
     mécanique validée, évite de porter Zweifel.
   - **(b) Porter Zweifel** (`calcCable`/`calcBandH`, ~200 lignes Python) : fidélité
     exacte à SEILAPLAN, mais deux mécaniques à maintenir et un écart de résultat avec
     notre `_NoH` actuel. *À réserver si (a) diverge trop de SEILAPLAN en CA-13.5.*
2. **Positions candidates** : reprendre `peakdetect` (points saillants du profil) plutôt
   qu'un pas régulier `δl`. Décider du portage de `peakdetect` (détection de crêtes) ou
   d'un équivalent (extrema locaux de la seconde dérivée du profil).
3. **Remplacement ou coexistence ?** Sélecteur `cable$methode_supports =
   c("sylvaccess", "seilaplan")` ; `sylvaccess` (= `OptPyl_NoH`) reste le **défaut**
   (fidélité ColduPre garantie), `seilaplan` active le graphe. Le flag expérimental
   `optimiser_hauteur_fixation` et le code `OptPyl_Up2` shelvé sont **retirés**.
4. **Coût** : reprendre `KostStue = (h==0 ? 1 : (h+100)²)·(1+4·[h>HM_nat])` (§2.3) tel
   quel — il encode déjà « nombre puis hauteur, pénalité arbre ». `HM_nat` = hauteur
   d'arbre-support ; sans donnée d'arbres (cas ForêtAccess actuel), le fixer à `max_HM`
   (pas de pénalité) ou l'exposer.
5. **Machine en haut / en bas** : le graphe est **symétrique** (Dijkstra bidirectionnel
   sur le profil) — un seul solveur, sans la gymnastique `Up`/`Up2`/retournement. À
   confirmer sur le traitement des extrémités (mât fixe vs ancrage 0).
6. **Coupe de ligne** : native — `LengthInLP` = nœud le plus lointain atteignable ; si
   le profil entier ne passe pas, on garde la portée max. Pas de logique séparée.
7. **Rust ou R ?** Graphe petit (nœuds ≤ `n_saillants × H/δh`, ~centaines) mais évalué
   **par départ × azimut** (des milliers de fois). L'implémenter en **Rust** dans
   `cablehelp`, avec un Dijkstra maison (pas de dépendance scipy), appelé par
   `cable_scan`. Cohérent ADR-003.

---

## 5. Prérequis

1. ✅ **Source SEILAPLAN lu** (2026-07-16) : `core/main_opti.py`, `core/opti_sta.py`,
   `core/cableline.py`, `core/peakdetect.py` (dépôt cloné, GPL). L'algorithme est
   transcrit en §2. Reste à lire en détail `cableline.py::calcCable` (formules Zweifel)
   **si** on choisit l'option 4.1(b) — inutile si (a).
2. ⏳ **Obtenir Bont & Heinimann (2012)**, Eur. J. For. Res. 131(5):1439-1448 — utile
   pour la justification théorique et le gradient gravitaire, mais le **code** est déjà
   la référence d'implémentation.
3. **Banc de référence** : réutiliser l'oracle `c_option_h=true` déjà régénéré
   (`data-raw/oracle/coldupre/sylvaccess_hopt/`, cf.
   [[regenerer-oracle-sylvaccess]]) **comme repère de direction** (la couverture doit
   *augmenter*), et — idéalement — **exécuter SEILAPLAN** (STANDALONE.py du dépôt) sur
   quelques profils pour comparer position/hauteur des supports ligne à ligne (CA-13.5).

---

## 6. Critères d'acceptation

- **CA-13.1** : sur un profil manufacturé où un support abaissé rend une travée
  faisable, le graphe trouve la solution ; test `cargo` déterministe.
- **CA-13.2** : à hauteur fixe (`δh` = un seul niveau), le graphe reproduit le
  placement de position de `OptPyl_NoH` (non-régression : mêmes lignes que le défaut
  actuel sur un jeu de profils témoins).
- **CA-13.3** : **direction correcte** — sur ColduPre, activer l'optimisation de
  hauteur **augmente** la couverture câble vs le `_NoH` (contrairement au port
  `OptPyl_Up2` shelvé qui la réduisait), et se rapproche de l'oracle `c_option_h=true`
  (+470 cellules attendues), sans excès de trop-optimiste au-delà du corollaire connu
  (absence de sélection de lignes, Lot 5).
- **CA-13.4** : **perf** — le balayage complet reste du même ordre que le `_NoH`
  (objectif : < 5× le `_NoH`, contre ~20× pour `OptPyl_Up2`).
- **CA-13.5** : si SEILAPLAN est exécutable, **comparaison ligne à ligne** sur ≥ 3
  profils (position et hauteur des supports, faisabilité) — écart documenté.

---

## 7. Découpage

- **13a — brique mécanique** ✅ *(2026-07-16)* : `calc_cable(travée, pré-tension) →
  (garde_ok, effort_ok, sag)` en Rust (`cable::supports::calc_cable`), via notre
  caténaire Newton/Irvine à **tension imposée** (décision 4.1a) — on marche `Lo`
  jusqu'à la tension imposée au lieu de `Tmax`, réutilisant `seed_grid` +
  `newton_centre` + `check_hlinemin` (mécanique inchangée, oracle-validée). +
  `calc_sta` (bissection → `[MinSTA, MaxSTA]`, `cable::seilaplan::calc_sta`)
  transcrit de `opti_sta.py`. 7 tests `cargo` (flèche croissante quand la tension
  baisse, garde violée si sol trop haut, effort refusé au-delà de `tmax`, plage
  `[MinSTA, MaxSTA]` bornée / infaisable). Non câblé à `cable_scan` (→ 13b/13c).
- **13b — graphe + Dijkstra** ✅ *(2026-07-16)* en Rust (`cable::seilaplan`) :
  `optimize_supports(di, zi, candidats, GraphParams, CableMat)` transcrit de
  `main_opti.py::optimization`. Nœuds = (position candidate × niveau de hauteur
  `δh`), extrémités à hauteur fixe ; arêtes forward avec `Min_Dist_Mast` (exceptions
  départ/arrivée), faisabilité par `calc_sta` (13a) ; coût `KostStue` (`kost_stue`) ;
  balayage `n_sk` pré-tensions + **Dijkstra maison** (`BinaryHeap`, sans scipy) ;
  sélection portée max puis coût min ; **coupe native** (portée maximale si
  l'arrivée n'est pas atteignable). Positions candidates = crêtes via `peak_positions`
  (port de `peakdetect`). 6 tests `cargo` : CA-13.1 (support quand le direct échoue),
  pas de support inutile, hauteur fixe = optimisation de position (CA-13.2, esprit),
  coupe native, coût `KostStue`, `peakdetect`. Non câblé à `cable_scan` (→ 13c).
- **13c — intégration** 🔶 *(câblage fait 2026-07-16 ; confrontation ColduPre en cours)* :
  câblage `cable_scan` / config (`methode_supports = "sylvaccess" | "seilaplan"`,
  + `hauteur_support_{min,max}_m`, `pas_hauteur_support_m`, `distance_min_support_m`,
  `nb_pas_pretension`). La branche `seilaplan` de `scan()` appelle `optimize_supports`
  sur le profil au demi-mètre (`zs`), positions candidates = crêtes (`peak_positions`) ∪
  grille régulière au pas `Min_Dist_Mast` (pour couper/poser sur terrain lisse) ; le
  graphe étant **symétrique**, un seul passage (pas de gymnastique machine-en-haut/bas).
  Bindings regénérés, test R bout-en-bout (`methode_supports = "seilaplan"` tourne et
  couvre). **Confrontation ColduPre (16/07)** — deux optims (pré-filtre `check_droite`,
  suppression bissection `maxSTA`, résultats inchangés) puis mesure : **perf ~9× le `_NoH`**
  en config fine (échoue CA-13.4 < 5×) ; **couverture −6105 cellules** vs `_NoH` en config
  légère (échoue CA-13.3, qui veut ↑). **Cause probable** : la portée du graphe est
  **quantifiée aux positions candidates** (coupe au dernier support), là où `OptPyl_NoH` coupe
  au **pixel** et prolonge la dernière travée — écart de modèle *scan* vs *conception*. Cf.
  `PLAN.md` (journal 16/07) : **décision à prendre** (prolonger la portée + réduire le coût, vs
  shelver derrière le défaut `sylvaccess`).
- **13d — validation & nettoyage** : comparaison ligne à ligne à SEILAPLAN (CA-13.5) ;
  retrait du flag `optimiser_hauteur_fixation` expérimental et du code `OptPyl_Up2`.

---

## 8. Definition of Done

- [ ] Graphe B&H implémenté en Rust, réutilisant la caténaire existante.
- [ ] Non-régression : à hauteur fixe, mêmes lignes que le `_NoH` (CA-13.2).
- [ ] Sur ColduPre, l'optimisation de hauteur **augmente** la couverture (CA-13.3) et
      la perf reste raisonnable (CA-13.4).
- [ ] `docs/comparaison-cable-seilaplan.md` et `specs/004` (§ Statut c_option_h) mis à
      jour (renvoi vers ce spec, retrait de la dette).
- [ ] Le code `OptPyl_Up2` shelvé et son flag sont retirés (ou explicitement conservés
      en annexe si utile).
- [ ] `PLAN.md` à jour (dette câble → résolue par la voie SEILAPLAN).

---

## 9. Risques

- **Algorithme mal transcrit** : le graphe B&H a des subtilités (gestion du gradient
  gravitaire, coût lexicographique). Mitigé par la lecture du source SEILAPLAN et la
  comparaison ligne à ligne (CA-13.5).
- **Pas d'oracle exact** : SEILAPLAN (B&H) ≠ Sylvaccess (`OptPyl_Up2`) — on ne cherche
  pas l'égalité cellule à cellule avec l'oracle `c_option_h=true`, mais la **bonne
  direction** (couverture en hausse) et l'accord ligne à ligne avec SEILAPLAN.
- **Divergence de mécanique** : SEILAPLAN utilise Zweifel, nous Irvine — les seuils de
  faisabilité d'arête diffèrent légèrement. Documenté comme écart assumé (cf.
  `docs/comparaison-cable-seilaplan.md`).
