# specs/002 — Lot 2 : Moteur Skidder (+ service least-cost partagé)

> **Statut** : **validé** (décisions §10 du 2026-07-10, prises sur **lecture du code source**
> Sylvaccess v3.6, cf. §12). Les deux incréments **2a** et **2b** sont **débloqués**.
> **Lot** : 2 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 2 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md), US-2.1…2.3). **Exigence** : EF-4
> ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 1 (`preprocess()`, objet `foretaccess_preprocessing`).
> **Partagé avec** : Lot 3 (porteur) et Lot 6 (DFCI) — le **service least-cost** est
> livré ici mais conçu pour les trois moteurs.
> **ADR liés** : ADR-003 (config/défauts v3.6), ADR-004 (découplage), ADR-006
> (non-régression), ADR-001 (langages — cf. risque §8).
> **Attribution** : les règles §4.2–§4.5 dérivent du code source Sylvaccess (GPL v3) — §12.

---

## 1. Contexte

Le skidder (débusqueur) est le premier des quatre moteurs. Il consomme le jeu de rasters
alignés produit par `preprocess()` (Lot 1) et produit une **carte d'accessibilité** assortie
de **distances de débardage**. C'est le §4.2 du brief.

Ce lot porte aussi le **service de propagation least-cost**, extrait dès maintenant parce
qu'il est mutualisé avec le porteur (Lot 3) et le camion DFCI (Lot 6). Le concevoir comme
un composant autonome, testable sans règle métier, est la principale décision d'architecture
du lot.

---

## 2. Périmètre

### Dans le périmètre
1. **Service least-cost** (US-2.1) : coût-distance cumulé depuis une source (la desserte) sur
   une surface de coût, avec plafond de coût, et reconstruction du **trajet optimal** d'un
   pixel vers sa source.
2. **Règles skidder v3.6** (US-2.2, EF-4) : circulation libre sous le seuil de pente,
   treuillage au-delà, bascules de pente amont/aval, distance max hors desserte.
3. **Classement d'accessibilité** : zones *accessible* / *parcourable par l'engin* /
   *non accessible*.
4. **Distances** : treuillage, traînage (piste et forêt), débardage totale.
5. **Trajet optimal** vers la place de dépôt (sortie vectorielle).
6. **Tableau récapitulatif** (US-2.3) : surfaces par classe, et volumes si le raster de
   volume est fourni.

### Hors périmètre
- Les règles **porteur** (cône d'azimuts), **câble** et **DFCI** → Lots 3, 4, 6. Seul le
  *service* least-cost leur est destiné, pas les règles.
- Le **tuilage / passage à l'échelle** → Lot 7. Ici, un bloc en mémoire.
- L'**agrégation zonale** par parcelle / commune → Lot 8. Ici, un tableau global.
- L'**écriture en base** : les rasters vont sur disque (ADR-002). Le trajet optimal, lui,
  est vectoriel et pourra passer par `StorageBackend` au Lot 8.

---

## 3. Entrées / sorties

### Entrées
| Rôle | Type | Obligatoire | Notes |
|---|---|---|---|
| Prétraitement | `foretaccess_preprocessing` | oui | sortie du Lot 1 (grille de référence) |
| Configuration | `foretaccess_config` | oui | seuils `skidder` (défauts v3.6) |
| Place de dépôt | `sf` de points | non | à défaut : la cellule de desserte d'`allocation` (§10.7) |

Le moteur **ne relit aucun fichier** : il consomme l'objet du Lot 1. C'est ce qui le rend
testable sans I/O (ADR-004).

### Sortie
Objet de classe **`foretaccess_skidder`** (liste structurée) :
- `accessibilite` : `SpatRaster` **catégoriel** — `parcourable`, `accessible`,
  `non_accessible`, `hors_foret` ; `NA` = indéterminé (bordures du calcul de pente).
- `distance_treuillage` : `SpatRaster` (m), distance **3D** — 0 là où il n'y a pas de treuillage.
- `allocation` : `SpatRaster` — identifiant de la cellule de desserte de rattachement.
- `distance_trainage_piste`, `distance_trainage_foret` : `SpatRaster` (m).
- `distance_debardage` : `SpatRaster` (m) — total.
- `trajet` : `sf` de `LINESTRING` — trajets optimaux vers la place de dépôt.
- `recap` : `data.frame` — surfaces (ha) et volumes (m³, si disponible) par classe.
- `grid`, `config` : métadonnées, comme au Lot 1.

Tous les rasters partagent **exactement** la grille du MNT. Écriture GeoTIFF/COG optionnelle
via `write_dir`, cohérente avec `preprocess()`.

---

## 4. Algorithme

> **Toutes les règles ci-dessous sont lues dans le code source Sylvaccess v3.6**
> (`scripts/sylvaccess_cython3.pyx` et `scripts/Sylvaccess_1_skidder.py`, dépôt public
> `forge.inrae.fr/sylvain.dupire/sylvaccess`, GPL v3), et non déduites de l'article.
> Les numéros de fonction cités permettent de retrouver la source.

### 4.1 Service de propagation least-cost (US-2.1)

Reproduit `calcul_distance_de_cout()` du `.pyx`. **Sans aucune règle métier.**

```r
propager_cout(surface_cout, sources, zone, cout_max = Inf)  # -> foretaccess_propagation
chemin_optimal(propagation, depuis)                         # -> sf LINESTRING
```

`propager_cout()` renvoie trois `SpatRaster` : `cout_cumule`, `allocation`, et
`predecesseur` — ce dernier, absent du `.pyx` (qui rejoue la propagation), rend la
reconstruction du trajet exacte et immédiate.

Sémantique exacte, à respecter au pixel près :
- **8-connexité** ; le pas vaut la taille de cellule, ou `taille × √2` en diagonale ;
- le coût d'un pas est `surface_cout[cellule d'arrivée] × pas` — c'est le **coût de la
  cellule d'arrivée**, pas la moyenne des deux cellules. C'est ce qui distingue Sylvaccess de
  `terra::costDist()` (qui moyenne) et interdit de s'en servir tel quel ;
- `zone` (logique) délimite les cellules traversables ; hors zone, la propagation s'arrête ;
- `cout_max` plafonne la propagation ; au-delà, la sortie vaut `NA` ;
- **`allocation`** renvoie l'identifiant de la cellule source atteinte au moindre coût. C'est
  `Out_alloc` dans le `.pyx` ; il est indispensable pour rattacher chaque pixel à sa desserte
  et reconstituer le chemin du bois.

**Implémentation** (décision §10.1) : Dijkstra maison, en R, dans `R/leastcost.R`. Aucune
dépendance nouvelle. Ni `terra::costDist()` ni `leastcostpath` ne reproduisent cette
accumulation, et aucun des deux ne renvoie l'allocation. C'est le candidat naturel à un
portage Rust si la performance l'exige (ADR-001).

### 4.2 Fonction de coût (pondération de pente)

Reproduit `Pond_pente` (`Sylvaccess_1_skidder.py:121`) :

```
surface_cout = sqrt(1 + (pente_pct / 100)^2)
```

C'est le **facteur d'allongement 3D** de la traversée d'une cellule : la distance least-cost
qui en résulte est la longueur réelle du chemin épousant le terrain. Elle ne dépend que de la
**valeur absolue** de la pente — la propagation est donc **isotrope** (décision §10.2). Il n'y
a aucune fonction de Tobler dans Sylvaccess.

Les **obstacles complets** ne sont pas infranchissables : ils reçoivent un surcoût additif de
`1000` (`Pond_pente + 1000 × Full_Obstacles`), donc prohibitif mais fini. Les **obstacles
partiels** sont retirés de la **zone de roulage** du skidder (`zone_rast[partiel == 1] <- 0`)
mais **pas** de la zone de treuillage : on peut treuiller au-dessus, pas rouler dessus
(décision §10.4).

### 4.3 Treuillage — balayage radial, et non least-cost

C'est la découverte structurante du lot. Le treuillage reproduit `skid_debusq_RF()`
(`.pyx:3116`) et `skid_debusq_Piste()`, qui ne sont **pas** des plus courts chemins :

Pour **chaque pixel de desserte**, et pour **chaque azimut de 0° à 359° (pas de 1°)**, on
marche en **ligne droite** le long du rayon. Pour chaque pixel rencontré à la distance
horizontale `Hdist` :

1. **Distance 3D** : `dist = sqrt(Hdist² + Δalt²)` où `Δalt = alt(pixel) − alt(desserte)`.
   Ce n'est pas la distance horizontale.
2. **Pente signée du rayon** : `s = Δalt / Hdist`. Attention : c'est la pente de la corde
   desserte → pixel, **pas** la pente locale du MNT.
3. **Contrainte de dégagement du câble** : en tout point intermédiaire du rayon, la corde
   tendue depuis la desserte à la hauteur d'attache doit rester **au-dessus du sol et sous la
   hauteur de dégagement maximale** :
   ```
   0 <= (alt_desserte + s * d_j + hauteur_attache) - alt_terrain(j) <= degagement_max
   ```
   Sinon le rayon est **interrompu** (`break`), et tout ce qui est au-delà est inaccessible
   par cet azimut. Valeurs v3.6 : `hauteur_attache = 10 m`, `degagement_max = 30 m` — en dur
   dans le `.pyx`, promues en **paramètres de config** ici (décision §10.3, ADR-003).
4. **Distance maximale admissible** — la « loi de bascule » (§4.4).
5. Le rayon s'interrompt aussi dès qu'il sort de la zone treuillable (`Zone_ok` = forêt,
   hors obstacles complets, pente ≤ pente d'abattage manuel).

Chaque pixel retient la **plus petite** distance de treuillage trouvée, tous azimuts et toutes
cellules de desserte confondus.

### 4.4 Loi de bascule pente → distance de treuillage admissible

Reproduit `Sylvaccess_1_skidder.py:336-370` et `.pyx:3164-3168`. Ce **n'est pas** une fonction
affine de la pente : c'est une fonction affine du **dénivelé**, `Dmax = coeff · Δalt + orig`,
calibrée sur deux points d'ancrage. Exprimée en fonction de la pente signée `s` du rayon, elle
devient :

```
Dmax(s) = daval                          si s <= -pente_bascule_aval        (défaut -20 %)
Dmax(s) = damont                         si s >  +pente_bascule_amont       (défaut +75 %)
Dmax(s) = orig / (1 - coeff * s / sqrt(1 + s^2))   sinon
```

avec, `p_up = pente_bascule_amont_pct/100` et `p_down = -pente_bascule_aval_pct/100` :

```
deniv_up   =  sqrt(damont^2 / (1 + 1/p_up^2))
deniv_down = -sqrt(daval^2  / (1 + 1/p_down^2))
coeff      = (damont - daval) / (deniv_up - deniv_down)
orig       = damont - coeff * deniv_up
```

Cas particuliers du code source, à reproduire : si `damont == daval`, alors `coeff = 0` et
`orig = damont` ; si l'un des deux est nul, `coeff = 0` et `orig` vaut l'autre.

**Valeurs de référence** (défauts v3.6 : `damont = 50 m`, `daval = 100 m`, bascules 75 % et
20 %) → `coeff = -1,007829`, `orig = 80,2349 m`. La loi est continue aux deux ancrages :

| Pente signée du rayon | `Dmax` | |
|---|---|---|
| ≤ −20 % | 100,00 m | plafond aval |
| −10 % | 89,18 m | |
| **0 % (plat)** | **80,23 m** | |
| +30 % | 62,22 m | |
| +50 % | 55,31 m | |
| > +75 % | 50,00 m | plafond amont |

Le point à retenir : **à plat, la distance admissible vaut 80 m**, ni `damont` ni `daval`. Une
interpolation linéaire en pente — l'hypothèse naturelle — donnerait 50 m à 30 % au lieu de
62 m, soit 20 % d'erreur, et **silencieuse**.

Le test `dist > dmax` n'est appliqué que si `dist > min(damont, daval)` : en deçà, tout est
admissible sans calcul.

### 4.5 Classement, distances, option de modélisation

- `zone_parcourable` = forêt ∩ `pente ≤ pente_skidder_max_pct` (défaut 30 %) ∩ hors obstacles
  complets ∩ hors obstacles partiels.
- `zone_abattage` (`Pente_ok_buch`) = `pente ≤ pente_abattage_max_pct` (défaut 100 %).
- Une cellule est **accessible** si elle est atteinte soit par roulage (least-cost depuis la
  desserte, dans la limite de `distance_hors_desserte_max_m`), soit par treuillage (§4.3).
- `distance_debardage = distance_treuillage + distance_trainage_foret + distance_trainage_piste`.
- **`s_option`** (nouveau paramètre, absent de la config actuelle) arbitre entre les deux
  stratégies : `1` = privilégier le treuillage (limiter l'impact sur le sol, **défaut v3.6**),
  `2` = privilégier le débusquage. Les deux ordonnancent différemment roulage et treuillage.
  Le Lot 2b n'implémente que l'**option 1** ; l'option 2 est reportée (§10.7).

### 4.6 Tableau récapitulatif (US-2.3)

Surface d'une classe = `nombre de cellules × résolution² / 10 000` (ha). Volume = somme du
raster `volume` sur la classe, si le Lot 1 en a produit un. Les cellules `NA` (bordures du
calcul de pente, cf. Lot 1) forment une ligne `indetermine` explicite, jamais rangées
silencieusement dans `non_accessible`.

Sylvaccess produit aussi des **classes de distance totale** (`s_class` : 0 ; 250 ; 500 ;
1000 ; 1500 ; 2000 m) — à ajouter à la config.

---

## 5. Critères d'acceptation

- **CA-2.1** `propager_cout()` sur une surface de coût uniforme à 1 retourne un coût cumulé
  égal à la distance euclidienne 8-connexe (10 cellules → 10 × taille ; diagonale → `√2 ×`),
  et **non** 9,5 comme `terra::costDist()`. `cout_max` tronque exactement au seuil.
- **CA-2.2** `propager_cout()` renvoie une `allocation` correcte : chaque cellule porte
  l'identifiant de la source atteinte au moindre coût (test à deux sources).
- **CA-2.3** Une cellule de coût `NA` est infranchissable : une cellule enclavée est `NA`.
- **CA-2.4** `chemin_optimal()` reconstruit un `LINESTRING` valide, dans le CRS du MNT, qui
  aboutit sur la source ; sa longueur égale le coût cumulé sur une surface uniforme.
- **CA-2.5** La fonction de coût vaut `√(1 + (p/100)²)` : 1 à pente nulle, `√2` à 100 %.
- **CA-2.6** La loi de bascule reproduit le tableau de référence du §4.4 sous tolérance
  `1e-6` — **en particulier 80,2349 m à plat**, et la continuité aux deux ancrages.
- **CA-2.7** Le rayon de treuillage s'interrompt quand la corde sort de
  `[0, degagement_max]` : un relief intercalé bloque le treuillage au-delà (test dédié).
- **CA-2.8** Sur le MNT jouet (plan à 20 %), la pente est partout ≤ 30 % : toute cellule
  atteinte est `parcourable`, et aucune n'est `non_accessible`. Oracle analytique.
  *Attention* : le treuillage **s'applique quand même** près de la desserte. Dans le `.pyx`,
  `Zone_OK` borne le treuillage par la pente d'**abattage manuel** (100 %), et non par la
  pente skidder (30 %) : sous l'option 1, une cellule proche de la desserte est treuillée même
  si l'engin pourrait y rouler. La classe `parcourable` décrit la **praticabilité du terrain**,
  pas le mécanisme d'extraction retenu.
- **CA-2.9** Sur le MNT jouet à pente forte (§7), le treuillage se déclenche, avec les
  distances amont/aval attendues. Un test par sens.
- **CA-2.10** `distance_debardage` = somme exacte des trois composantes, sans `NA` parasite.
- **CA-2.11** Le récapitulatif conserve la surface totale (classes + `indetermine`).
- **CA-2.12** Tous les rasters de sortie partagent exactement la grille du MNT.
- **CA-2.13** Les obstacles partiels bloquent le **roulage** mais pas le **treuillage** ; les
  obstacles complets bloquent les deux.

---

## 6. Tests (`testthat`)

- `test-leastcost.R` : coût uniforme, allocation, `cout_max`, cellules `NA`, source vide.
- `test-chemin.R` : trajet optimal analytique ; validité et CRS du `LINESTRING`.
- `test-cout-pente.R` : `√(1 + (p/100)²)` ; surcoût des obstacles complets.
- `test-bascule.R` : tableau de référence du §4.4 ; continuité ; cas particuliers
  (`damont == daval`, l'un des deux nul).
- `test-treuillage.R` : balayage radial, distance 3D, contrainte de dégagement, interruption
  du rayon ; amont et aval.
- `test-skidder-regles.R` : classement, obstacles complets vs partiels, exclusion.
- `test-skidder-distances.R` : additivité des distances.
- `test-skidder-recap.R` : conservation de la surface ; volumes ; ligne `indetermine`.
- `test-skidder-grid.R` : grille de sortie.

**Oracle** : analytique, mais désormais **calibré sur le code source** — la loi de bascule et
la fonction de coût ont des valeurs de référence exactes (§4.4, §5). Les sorties réelles
Sylvaccess v3.6 restent souhaitables (§10.8) mais ne sont plus indispensables pour verrouiller
ces deux points.

---

## 7. Fichiers (proposition)

```
R/leastcost.R       → propager_cout(), chemin_optimal() — Dijkstra, sans métier
R/cout.R            → surface de coût (pondération de pente, obstacles)
R/treuillage.R      → balayage radial 360°, loi de bascule, contrainte de dégagement
R/skidder.R         → skidder() + classe foretaccess_skidder
R/recap.R           → surfaces/volumes par classe (réutilisé au Lot 3)
tests/testthat/…    → cf. §6
tests/testthat/helper-skidder.R → MNT à pente forte, desserte, zones (déterministe)
```

**Aucune nouvelle dépendance** (décision §10.1).

Le jeu jouet du Lot 0 ne suffit pas à exercer toutes les règles. On lui adjoint, **en mémoire
et de façon déterministe** (helpers de test, aucune fixture volumineuse à versionner) : un
**MNT à pente forte** (plan à 60 %), un **relief intercalé** et une **fosse** pour exercer les
deux bornes de la contrainte de dégagement (CA-2.7), et des **obstacles** complets et partiels.
Le carré d'obstacles doit être placé **hors de la piste DFCI diagonale** du jouet, qui va de
(0, 0) à (250, 250) : sinon ses cellules sont aussi des cellules de desserte.

Nouveaux paramètres de config (`config$skidder`), défauts v3.6 :
`hauteur_attache_treuil_m = 10`, `hauteur_degagement_max_m = 30`,
`surcout_obstacle_complet = 1000`, `option_modelisation = 1`,
`classes_distance_m = c(0, 250, 500, 1000, 1500, 2000)`.

---

## 8. Risques & mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Dijkstra en R pur trop lent (295 k cellules sur l'AOI réelle) | Perf | Mesurer tôt ; `cout_max` élague ; portage Rust prévu (ADR-001), la frontière est déjà la bonne |
| Balayage radial 360° × chaque pixel de desserte | Coût quadratique | Sylvaccess pré-calcule les rayons une fois (`create_buffer_skidder`) : faire de même |
| Écart sur la loi de bascule | Distances fausses **et silencieuses** | Valeurs de référence exactes en test (§4.4) ; c'est le piège principal du lot |
| Pente du rayon ≠ pente locale du MNT | Confusion de modèle | Nommer explicitement `pente_rayon` vs `slope_pct` |
| Option 2 (`s_option`) non implémentée | Couverture partielle de v3.6 | Documenter ; erreur explicite si `option_modelisation = 2` |
| Bordures `NA` héritées du Lot 1 | Classes faussées en lisière | Ligne `indetermine` explicite |

---

## 9. Definition of Done (Lot 2)

- [x] Spec validée + questions §10 tranchées (2026-07-10).
- [x] Service least-cost (2a) : Dijkstra + allocation + chemin, tests verts.
- [x] Fonction de coût, loi de bascule, treuillage radial (2b).
- [x] Jeu jouet enrichi (pente forte, relief intercalé, obstacles), déterministe.
- [x] Règles, distances, récap ; tests verts (un test par règle et par cas d'erreur).
- [ ] `lintr` / `testthat` / `R CMD check` / `cargo` / `clippy` OK en CI ; couverture ≥ `main`.
- [x] Chaînes du code R en **ASCII** (contrainte `R CMD check`, cf. `PLAN.md`).
- [x] Doc d'usage (roxygen) ; entrée `NEWS.md` ; `PLAN.md` à jour.
- [ ] Branche dédiée + PR + revue ; commits atomiques ; release `v0.3.0`.

---

## 10. Décisions (tranchées 2026-07-10, sur lecture du code source)

Le dépôt `forge.inrae.fr/sylvain.dupire/sylvaccess` est **public** (l'API GitLab répond sans
authentification ; c'est la page HTML qui affiche un écran de connexion trompeur). Les trois
points réputés bloquants ont été lus dans `sylvaccess_cython3.pyx`. Le code source ne se
contente pas de les trancher : il **contredit** deux hypothèses de la première rédaction.

1. **Backend least-cost** : **Dijkstra maison**, sans dépendance. `terra::costDist()` accumule
   la friction **moyenne** des deux cellules (9,5 au lieu de 10 sur dix cellules à friction 1)
   et diverge donc systématiquement ; ni lui ni `leastcostpath` ne renvoient l'**allocation**.
   *Renverse le choix initial de `leastcostpath`.*
2. **Coût isotrope** : `√(1 + (p/100)²)`, fonction de la pente **absolue**. Il n'y a **aucune**
   fonction de Tobler dans Sylvaccess. *Renverse la décision d'anisotropie : la fidélité à
   l'oracle prime, c'est la raison d'être du projet.*
3. **Contrainte de dégagement du treuil** : `hauteur_attache_treuil_m = 10` et
   `hauteur_degagement_max_m = 30` deviennent des **paramètres de config** (défauts v3.6),
   plutôt que des constantes en dur comme dans le `.pyx` (ADR-003).
4. **Obstacles partiels** : ils bloquent le **roulage** du skidder, pas le **treuillage**. Les
   obstacles complets bloquent les deux, via un surcoût additif de 1000 (prohibitif, fini).
5. **Loi de bascule** : affine en **dénivelé**, pas en pente (§4.4). À plat, `Dmax = 80,23 m`.
6. **Treuillage** : balayage radial 360° au pas de 1°, en ligne droite, distance **3D** — pas
   un plus court chemin. Le service least-cost ne sert qu'au **traînage**.
7. **Place de dépôt** : couche `sf` de points fournie par l'utilisateur ; à défaut, la cellule
   de desserte d'`allocation` (le `.pyx` fournit exactement cette information).

### Questions restantes (non bloquantes)

8. **Option de modélisation** (`s_option`) : le Lot 2b n'implémente que l'option 1
   (privilégier le treuillage, défaut v3.6). L'option 2 fera l'objet d'un incrément ultérieur.
9. **Oracle réel** : les valeurs de référence de la loi de bascule et de la fonction de coût
   sont désormais **exactes** (lues dans la source), ce qui verrouille les deux points les plus
   risqués. Une exécution Sylvaccess v3.6 sur le jeu jouet reste souhaitable pour valider les
   sorties d'ensemble.

---

## 11. Découpage du lot

| Incrément | Contenu | État |
|---|---|---|
| **2a — Service least-cost** | `propager_cout()` (Dijkstra + allocation), `chemin_optimal()`, tests analytiques (CA-2.1 … CA-2.4) | **débloqué**, aucune règle métier |
| **2b — Règles skidder** | coût de pente, loi de bascule, treuillage radial, classement, distances, récap (CA-2.5 … CA-2.13) | **débloqué** — le `.pyx` a répondu |

Le jeu jouet enrichi relève de 2b. 2a se teste sur des surfaces de coût synthétiques.

---

## 12. Attribution

Les règles des §4.2 à §4.5 sont **dérivées du code source de Sylvaccess v3.6** (INRAE,
S. Dupire), distribué sous **GPL v3** — d'où la licence GPL v3 de ForêtAccess (règle 4 de
`CLAUDE.md`). Le code source n'est **pas** vendu avec ce dépôt ; il est lu depuis
`forge.inrae.fr/sylvain.dupire/sylvaccess`. Les fonctions de référence sont
`calcul_distance_de_cout()`, `skid_debusq_RF()`, `skid_debusq_Piste()`
(`sylvaccess_cython3.pyx`) et le calcul de `coeff`/`orig` (`Sylvaccess_1_skidder.py`).
