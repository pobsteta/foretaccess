# Spec 012 — Fidélité fine & performance des moteurs terrestres

* **Statut** : proposé (2026-07-14)
* **Prérequis** : Lot 11 livré (`v0.13.0`) — le banc oracle Sylvaccess v3.6 tourne et mesure.
* **Release visée** : `v0.14.0` (fidélité), `v0.15.0` (performance), puis `v1.0.0`.

## 1. Pourquoi ce lot

Le Lot 11 a mis ForêtAccess à **99,95 % / 99,72 % / 96,58 %** d'accord avec Sylvaccess
(skidder / porteur / câble) sur le jeu officiel ColduPre. Ce qui reste n'est plus du gros
œuvre, mais il reste :

* **trois écarts de fidélité identifiés**, dont un qui *fausse une sortie utilisateur* sur un
  jeu autre que ColduPre (la pondération de la piste) ;
* **un moteur jamais confronté** (DFCI), construit sur une hypothèse fausse ;
* **un moteur 30 % plus lent que le Cython** (porteur), dont les causes sont chiffrées.

## 2. Ordre de bataille : la fidélité AVANT la performance

**Règle du lot, non négociable.** Toute optimisation se valide par une non-régression
**bit-pour-bit** contre la sortie courante (c'est ainsi que le portage Rust du câble a été
validé, cf. `v0.12.0`). Or un test bit-pour-bit **fige la sortie courante comme référence**.
Optimiser un moteur dont on sait la sortie fausse revient donc à :

1. graver l'erreur dans un test de non-régression ;
2. rendre le correctif de fidélité ultérieur *indiscernable d'une régression* ;
3. accélérer la convergence vers la mauvaise cible.

D'où la séquence : **12a → 12b → 12c**, et jamais l'inverse. Le seul travail de performance
autorisé avant 12b est celui dont on peut prouver qu'il ne change **aucun** bit de sortie
(§ 5.1, la dilatation du grappin).

---

## 3. Lot 12a — Fidélité : les écarts connus

### 12a.1 — Pondération de la piste dans l'arbitrage du skidder ⚠️ *sortie fausse*

**Le seul écart qui produit une carte fausse.** Sylvaccess ne minimise pas la distance en forêt
seule : il fait payer au skidder la piste qu'il devra remonter.

| Où | Ce que Sylvaccess minimise |
|---|---|
| `pyx:3714` (propagation vers les pistes) | `d_foret + 0,5 · d_piste` |
| `pyx:4283` / `pyx:4304` (arbitrage route forestière ↔ piste) | `d_foret + 0,1 · d_piste` |

Chez nous, `propager_cout()` (`R/skidder.R:96-101`) minimise `d_foret` **seul** — routes et
pistes toutes semées à coût nul — puis `.piste_allouee()` (`R/skidder.R:446`) ajoute la distance
réseau *a posteriori*. Pondération effective : **0**.

*Effet* : nul sur ColduPre (réseau dense, écart piste mesuré 0,4 m). Mais dès qu'une **piste
longue jouxte une route forestière plus lointaine**, les deux moteurs allouent la cellule à des
dessertes différentes — et c'est la **distance totale**, pas seulement sa ventilation, qui
diverge. Un massif à réseau lâche (le cas normal en montagne) l'exposera.

*Travail* : deux propagations distinctes, comme Sylvaccess (`Sylvaccess_1_skidder.py:435` et
`:442`) — depuis les pistes sur la zone privée des routes, depuis les routes sur la zone privée
des pistes — puis arbitrage `d_foret_route ≤ d_foret_piste + 0,1 · d_piste`. Les deux
coefficients (0,5 propagation, 0,1 arbitrage) deviennent des paramètres de config (ADR-003).

⚠️ **Piège de conception, découvert en mesurant.** La première rédaction de cette spec disait
« semer le Dijkstra avec un coût initial `0,5 × d_piste` », c'est-à-dire minimiser *vraiment*
`d_foret + 0,5 · d_piste`. **C'est faux.** Chez Sylvaccess, le test pondéré (`pyx:3715`) est
**imbriqué dans** `if Out_distance > Dist` (`pyx:3712`) : la pondération est un **veto**, pas un
moteur. Elle peut *bloquer* une amélioration du coût forêt, jamais faire accepter un chemin
forestier plus long pour gagner de la piste. Conséquence, invisible sans l'oracle : chez
Sylvaccess la distance en forêt reste **pilotée par le coût forestier**. L'argmin « propre »
échange forêt contre piste et **allonge** le traînage — mesuré : médiane 138,3 m contre 124,0
(Sylvaccess), là où le veto rend 120,2 m. **On transcrit la lettre, pas l'intention.**

*Implémentation retenue* : `.propager_trainage()` dans `R/skidder.R` — un label-correcting sur
tas binaire (le veto brise la monotonie de l'étiquette, donc pas de `fige`), avec `d_piste` en
payload de la semence. La règle métier reste **hors** de `propager_cout()` (dont l'en-tête
promet « aucune règle métier ») ; le tas binaire est factorisé (`.tas_binaire()`).

*Critère d'acceptation* : ✅ accord skidder **99,95 % maintenu**, traînage en forêt **120,2 m**
(eux 124,0 ; p95 de l'écart 13,7 m contre 52,1 pour l'argmin), et deux tests sur un jeu
synthétique « piste longue vs route lointaine » où l'allocation bascule (plus une contre-épreuve
à coefficient nul).

### 12a.2 — Distances du porteur

**Angle mort du harnais fermé.** `data-raw/oracle_compare.R` ne comparait que l'**accessibilité**
du porteur, jamais ses distances. Étendu aux trois composantes. Appariement : Sylvaccess n'expose
que **deux** rasters (`Distance_sur_piste`, `Distance_dans_foret`) là où nous en avons trois
(piste, conduite, grappin) — il **fond le grappin dans la forêt** (`fwd_fill_hoist`, `pyx:4668`).
On compare donc `distance_conduite + distance_grappin` à `Distance_dans_foret`. *(La note du
journal disant que `porteur.R:97` « replie » à tort le contour est **fausse** : le contour va bien
dans la forêt des deux côtés, `pyx:4613`. Le seul regroupement qui diffère est le grappin.)*

**Ce que la mesure a révélé — le total du porteur n'a jamais été fidèle.** Le journal affirmait
« le total reste juste » ; il ne l'était pas, faute d'avoir été mesuré. Sur ColduPre :

| Composante | Nous (méd.) | Eux | Écart moyen | p95 \|écart\| |
|---|---|---|---|---|
| Distance sur piste | 122,2 | 213,0 | **−50,9** | 367 |
| Distance dans forêt | 15,8 | 32,0 | −11,9 | 110 |
| **Distance totale** | 57,7 | 112,0 | **−38,4** | 358 |

Nous sommes **systématiquement plus courts**, le poste dominant étant la **distance sur piste**
(l'allocation diffère : notre porteur alloue à une desserte plus proche sur piste). L'accessibilité,
elle, reste à **99,72 %** — c'est bien la décomposition/allocation qui diverge, pas la carte.

**Hypothèse réfutée par la mesure** : appliquer la pondération de piste (12a.1) à la *propagation
plate* du porteur ne bouge **rien** (piste toujours 122 vs 213). Sur ColduPre le porteur est
couvert surtout par le **balayage radial** (`conduire()`) et le **grappin**, pas par la propagation
plate — la pondération doit donc vivre dans l'arbitrage plat/radial (`fwd_fill_res1`, `pyx:4503`)
et le balayage, pas seulement dans le plat. Changement non retenu (fidèle à la source mais sans
effet mesurable — piège « la lettre pas l'intention »).

*Fait en 12a.2* : harnais étendu (les distances porteur sont désormais surveillées), diagnostic,
`.distance_sur_piste()` rendu cohérent (renvoie toujours `injoignable`).

#### 12a.2b — Correction du porteur ✅

Deux corrections, **chacune mesurée sur l'oracle avant d'être retenue** (leçon « la lettre pas
l'intention ») :

1. **Fusion plat / radial** (`fwd_fill_res1`, `pyx:4518`). Nous donnions au plat une priorité
   **inconditionnelle** ; Sylvaccess laisse le radial **écraser** une cellule déjà atteinte à
   plat s'il est strictement meilleur en forêt, l'incumbent plat étant pénalisé de sa piste :
   `Dforet_radial < Dforet_plat + 0,1 · Dpiste_plat` (asymétrique — le challenger n'ajoute pas
   sa propre piste ; strict, donc le plat gagne à égalité). Effet seul : « distance dans forêt »
   identique-à-1 m 40 → 54 %.

2. **Héritage de la rampe par le grappin** (`fwd_fill_hoist`, `pyx:4668`) — **le vrai levier**.
   Le grappin repartait de zéro : sa forêt valait le seul bras `d_grap`, et sa **piste était
   perdue** (allouée à une cellule de forêt hors réseau, donc nulle). Diagnostic ciblé : sur les
   2 288 cellules où nous mettions piste = 0 pour un Sylvaccess > 0 (écart −229 m), **1 975
   étaient du grappin**. Corrigé : la cellule grappillée hérite la distance de conduite **et** la
   desserte allouée de sa rampe (`d_grap + d_conduite(rampe)` en forêt, piste de la rampe).

Résultat sur ColduPre, accessibilité **99,72 % inchangée** (la carte n'a pas bougé, seule la
décomposition est corrigée) :

| Composante | Écart moyen avant | après |
|---|---|---|
| Distance sur piste | −50,9 m | **−3,0 m** |
| Distance dans forêt | −11,9 m | **+1,2 m** |
| Distance totale | −38,4 m | **+0,5 m** |

### 12a.3 — Reliquat du câble (2,79 % trop conservateurs)

L'accord câble est à 96,58 %, et l'écart est **asymétrique** : 2,79 % trop conservateurs contre
0,63 % trop optimistes. Cette signature dit qu'il nous manque encore de la portée, pas qu'on est
trop permissif. Deux candidats **connus et assumés** :

* l'**optimisation de la hauteur de fixation** (`c_option_h = 1`) — hors défaut v3.6, donc hors
  périmètre tant qu'on ne cible que le défaut ;
* le **pêchage latéral** — la charge n'est pas forcément sous la ligne.

*Travail* : d'abord **caractériser** les 2,79 % (sont-elles latérales à une ligne existante ? en
bout de ligne ?) avant d'écrire une ligne de code. Le diagnostic décide lequel des deux porter —
ou aucun.

### 12a.4 — DFCI : moteur jamais confronté, spec fausse

`specs/006` a été écrite sur l'hypothèse que **Sylvaccess n'avait pas de module DFCI**. Faux :
`Sylvaccess_5_dfci.py` existe (356 lignes, `process_dfci`). Les **défauts** ont été corrigés en
`v0.13.0` (`dfci_lmax` 440 m, `dfci_slope_max` 110 %, classes `0;120;280;440`), mais **le moteur
lui-même n'a jamais été confronté à l'oracle** — il reste en statut *beta* sur une base
hypothétique.

*Travail* : lire `Sylvaccess_5_dfci.py`, réécrire `specs/006` **sur la source**, brancher le DFCI
au banc oracle, corriger. C'est le dernier moteur non validé.

*Divergence assumée à re-arbitrer* : `dfci$classes_source` reste filtré sur les dessertes DFCI là
où Sylvaccess part de tout le réseau. Justifiée en commentaire (un camion-citerne ne s'engage pas
sur une piste de débardage) — à confirmer ou abandonner à la lumière de la source.

---

## 4. Lot 12b — Verrouiller la référence

Avant toute optimisation, geler ce qui vient d'être rendu fidèle :

* **Fixtures d'oracle** légères (extraits de ColduPre) sous `inst/extdata/`, versionnées, pour
  que la non-régression ne dépende pas d'un clone Sylvaccess hors dépôt.
* **Tests bit-pour-bit** sur les sorties des trois moteurs terrestres — le contrat que toute
  optimisation devra honorer.
* Le banc complet (`data-raw/oracle_*.R`) reste le juge de l'**accord**, les fixtures celui de la
  **non-régression**. Deux rôles distincts ; ne pas les confondre.

---

## 5. Lot 12c — Performance

Le porteur met **18,8 s** contre 14 s au Cython ; le skidder est à parité (14,1 s). Les causes
sont chiffrées (analyse du 2026-07-14). Par ordre de rendement décroissant :

### 5.1 — Le grappin est un Dijkstra pour une dilatation *(gain facile, sortie inchangée)*

`.grappiller()` (`R/porteur.R:310-328`) monte un raster où **chaque cellule conduite est sa
propre source**, à coût **uniforme** (`values(cout) <- 1`), puis lance le Dijkstra R maison — des
dizaines de milliers d'insertions au tas binaire, en boucle scalaire. C'est une **dilatation
morphologique de 8 m**, rien d'autre : `terra::focal` / `terra::buffer` la fait en C++.

C'est la **seule** optimisation autorisée avant 12b, parce qu'on peut prouver l'égalité exacte
des sorties (coût uniforme ⇒ distance de propagation = distance de chanfrein). À valider
bit-pour-bit malgré tout.

### 5.2 — La boucle interne de `conduire()` *(20-30 % du balayage)*

Par pas et par cellule, `conduire()` (`R/conduite.R:122-143`) fait un `cos()`, un modulo, **trois
`ifelse()`** (3-4 vecteurs temporaires alloués chacun) et un **gather redondant** de `alt[cel]`
(`conduite.R:128` — `dz > 0` suffit). `treuiller()`, lui, se contente de `pmax`/`pmin`.

* `cos_t` ne dépend que de (azimut, aspect) : **tabulable une fois pour toutes** hors boucle.
* Les `ifelse()` scalaires → arithmétique booléenne (`s_up + (s_down - s_up) * descend`).
* `ray$dl[i]` / `ray$dc[i]` / `ray$hdist[i]` sont des accès `$` sur `data.frame` **dans la boucle
  interne** : ~57 600 dispatch `[.data.frame` par appel. Sortir les colonnes en vecteurs nus
  avant la boucle est gratuit.

*Ce que ce n'est pas* : la compaction des survivants **est** implémentée (`conduite.R:164-171`) —
le porteur n'a pas raté l'optimisation du skidder. Inutile de rechercher ce bug-là.

### 5.3 — Redondances d'étages

* Deux Dijkstra bornés à **200 m** (`cout.R:195` via `zone_plate_connectee()`, `porteur.R:301`
  via `.saut_hors_foret()`) explorent largement la même couronne autour de la forêt. Le skidder
  n'en fait qu'un, **à 50 m** — bande 4× plus étroite. Mutualiser.
* `surface_cout_skidder()` est recalculé **3×** (`porteur.R:58`, `cout.R:169`, `porteur.R:292`),
  `terrain_plat()` **2×** — algèbre terra sur 924 k cellules à chaque fois. Mémoïser.

### 5.4 — Portage Rust du Dijkstra et du balayage terrestre *(le gros morceau)*

La cause **principale** de l'écart porteur n'est pas une inefficacité : c'est que le porteur
**fait plus de travail**. Sa portée de conduite est de 300 m contre 100 m au treuil, et surtout
**ses rayons ne meurent pas** — le treuillage a deux critères *cumulatifs* qui se resserrent à
chaque pas (les bornes de dégagement du câble, `treuillage.R:232`), la conduite n'a que des tests
*locaux sans mémoire*. Mesuré : **25 659 cellules-pas par source contre 8 882** (2,89× en
théorie, 4 à 6× en pratique sur zone plate). Et le balayage tourne **deux fois** (conduite +
passe contour).

R paie ce surcroît plein tarif là où le Cython l'absorbe. Deux candidats au portage, dans cet
ordre :

1. **`.dijkstra()`** (`R/leastcost.R:128-232`) — boucle scalaire R, ~1 µs/nœud contre ~10 ns en
   compilé. Il est appelé **5 fois** par `porteur()` contre 3 par `skidder()`. C'était déjà le
   candidat désigné par la mesure de 2026-07-10 (59 % du CPU skidder).
2. **Le balayage radial** (`conduire()` / `treuiller()`), avec `rayon` sur les sources.

Précédent : le portage du balayage câble a rendu **~5×** (`v0.12.0`), non-régression bit-pour-bit
comprise. La frontière R↔Rust reste minimale et typée (ADR-001) : R prépare les entrées SIG et
réassemble les sorties, la logique vit dans le crate.

*Garde-fou* : ne porter qu'**après** 12a/12b, et valider chaque portage bit-pour-bit contre les
fixtures. Répliquer exactement `round()` (demi-au-pair) et `seq()`, comme pour le câble.

---

## 6. Definition of Done

* [ ] Accord ColduPre : skidder ≥ 99,95 %, porteur ≥ 99,72 %, câble ≥ 96,58 % — **aucun recul**.
* [ ] DFCI confronté à l'oracle, `specs/006` réécrite sur la source.
* [ ] Distances du porteur comparées par le harnais (angle mort fermé).
* [ ] Pondération de la piste implémentée, avec test sur un jeu où elle mord.
* [ ] Fixtures de non-régression versionnées, indépendantes du clone Sylvaccess.
* [ ] Porteur ≤ 14 s sur ColduPre (parité Cython), sorties **bit-pour-bit** identiques à 12b.
* [ ] `lintr` 0, ASCII OK, suite verte, couverture non dégradée.

## 7. Ce qui reste hors périmètre

* `c_option_h = 1` (hauteur de fixation optimisée) — hors défaut Sylvaccess v3.6.
* Pêchage latéral — sauf si 12a.3 le désigne comme cause du reliquat.
* Phase 2 acquisition (MNH LiDAR → volume, BD Forêt v3).
