# specs/002 — Lot 2 : Moteur Skidder (+ service least-cost partagé)

> **Statut** : **partiellement validé** (décisions §10 du 2026-07-10). L'incrément **2a**
> (service least-cost) est **débloqué** ; l'incrément **2b** (règles skidder) reste **bloqué**
> sur la lecture du `.pyx` de Sylvaccess (§10.3–10.5, §11).
> **Lot** : 2 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 2 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md), US-2.1…2.3). **Exigence** : EF-4
> ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 1 (`preprocess()`, objet `foretaccess_preprocessing`).
> **Partagé avec** : Lot 3 (porteur) et Lot 6 (DFCI) — le **service least-cost** est
> livré ici mais conçu pour les trois moteurs.
> **ADR liés** : ADR-003 (config/défauts v3.6), ADR-004 (découplage), ADR-006
> (non-régression), ADR-001 (langages — cf. risque §8).
> **Ne rien coder avant validation de cette spec** (et des questions ouvertes §10).

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
| Place de dépôt | `sf` de points | non | défaut : décision §10 Q4 |

Le moteur **ne relit aucun fichier** : il consomme l'objet du Lot 1. C'est ce qui le rend
testable sans I/O (ADR-004).

### Sortie
Objet de classe **`foretaccess_skidder`** (liste structurée) :
- `accessibilite` : `SpatRaster` **catégoriel** à trois classes — `accessible`,
  `parcourable`, `non_accessible`.
- `distance_treuillage` : `SpatRaster` (m) — `NA` là où il n'y a pas de treuillage.
- `distance_trainage_piste`, `distance_trainage_foret` : `SpatRaster` (m).
- `distance_debardage` : `SpatRaster` (m) — total.
- `trajet` : `sf` de `LINESTRING` — trajets optimaux vers la place de dépôt.
- `recap` : `data.frame` — surfaces (ha) et volumes (m³, si disponible) par classe.
- `grid`, `config` : métadonnées, comme au Lot 1.

Tous les rasters partagent **exactement** la grille du MNT. Écriture GeoTIFF/COG optionnelle
via `write_dir`, cohérente avec `preprocess()`.

---

## 4. Algorithme

### 4.1 Service least-cost (US-2.1)

Fonctions proposées, **sans aucune règle métier** :

```r
propager_cout(surface_cout, sources, cout_max = Inf)  # -> list(cout_cumule, retour)
chemin_optimal(retour, depuis)                        # -> sf LINESTRING
```

- `surface_cout` : surface de coût **orientée** — le coût est porté par la **transition**
  `a → b` entre cellules voisines, pas par la cellule (décision §10.2, anisotropie de type
  Tobler). Une transition `NA` est infranchissable.
- `sources` : `SpatRaster` logique ou `sf` (la desserte).
- Renvoie le **coût cumulé** depuis la source la plus proche, et un raster de **retour**
  (*backlink*) permettant de remonter le trajet.
- `cout_max` élague la propagation : indispensable pour le passage à l'échelle (ADR-005).

Implémentation : **`leastcostpath`** (décision §10.1), qui s'appuie sur `terra` et expose des
surfaces de coût orientées (`create_slope_cs()`). La **fonction de coût métier**, elle, est
fournie **par le moteur**, jamais par le service : celui-ci ne connaît que des transitions.

### 4.2 Règles skidder (US-2.2)

Notations : `p` = pente en % (`slope_pct` du Lot 1) ; les seuils viennent de
`config$skidder` (ADR-003, défauts v3.6 rappelés §6 du brief).

1. **Exclusion** : les cellules du `exclusion_mask` (pente > `pente_abattage_max_pct`,
   défaut 100 %) sont **non accessibles** — l'abattage manuel y est impossible. Idem pour
   les cellules d'`obstacles_complets_mask`.
2. **Circulation libre** : si `p ≤ pente_skidder_max_pct` (défaut 30 %) et la cellule est
   atteignable depuis la desserte sans franchir d'obstacle, elle est **parcourable** par
   l'engin. La distance parcourue hors desserte et hors forêt est plafonnée par
   `distance_hors_desserte_max_m` (défaut 50 m).
3. **Treuillage** : si `p > pente_skidder_max_pct`, la cellule n'est atteignable qu'en
   treuillant depuis une cellule de desserte. La distance de treuillage admissible dépend du
   **sens** et de la **pente** :
   - **amont** (la cellule est plus haute que la desserte) : distance max
     `debardage_amont_max_m` (défaut 50 m), atteinte à partir de
     `pente_bascule_amont_pct` (défaut 75 %) ;
   - **aval** (la cellule est plus basse) : distance max `debardage_aval_max_m`
     (défaut 100 m), atteinte à partir de `pente_bascule_aval_pct` (défaut 20 %).

   La **loi reliant la pente à la distance admissible sous le seuil de bascule** n'est pas
   donnée par l'article. C'est la question ouverte **§10 Q1** — elle doit être lue dans le
   `.pyx` de Sylvaccess avant tout codage.
4. **Classement** : `accessible` = atteignable (libre ou par treuillage) ;
   `parcourable` = atteignable **et** `p ≤ pente_skidder_max_pct` ; `non_accessible` sinon.
   Une cellule `parcourable` est nécessairement `accessible` : le raster catégoriel encode la
   classe **la plus favorable**.
5. **Distances** : `distance_debardage = distance_treuillage + distance_trainage_foret +
   distance_trainage_piste`, chaque terme valant 0 (et non `NA`) quand il ne s'applique pas.

### 4.3 Tableau récapitulatif (US-2.3)

Surface d'une classe = `nombre de cellules × résolution² / 10 000` (ha). Volume = somme du
raster `volume` sur la classe, si le Lot 1 en a produit un ; sinon colonne absente. Les
cellules `NA` (bordures du calcul de pente, cf. Lot 1) sont **comptées à part**, dans une
ligne `indetermine`, jamais silencieusement rangées dans `non_accessible`.

Aucune valeur métier n'est codée en dur : tous les seuils viennent de `config` (ADR-003).

---

## 5. Critères d'acceptation

- **CA-2.1** `propager_cout()` sur une surface de coût uniforme retourne un coût cumulé égal
  à la **distance euclidienne** à la source, sous tolérance ; `cout_max` tronque la
  propagation exactement au seuil.
- **CA-2.2** `chemin_optimal()` reconstruit, sur un cas analytique, le trajet de longueur
  minimale ; le trajet est un `LINESTRING` valide, dans le CRS du MNT, qui **aboutit sur la
  source**.
- **CA-2.3** Sur le MNT jouet (plan incliné 20 %), la pente est **partout ≤ 30 %** : toutes
  les cellules atteignables sont donc `parcourable`, `distance_treuillage` est nulle partout,
  et aucune cellule n'est `non_accessible` hors bordures. C'est l'**oracle analytique** du lot.
- **CA-2.4** Sur un MNT jouet **à pente forte** (à ajouter, cf. §7), les cellules au-delà de
  30 % sont `accessible` par treuillage dans la limite des distances amont/aval, et
  `non_accessible` au-delà. Un test par sens (amont, aval).
- **CA-2.5** `distance_debardage` = somme exacte des trois composantes, sans `NA` parasite.
- **CA-2.6** Le tableau récapitulatif conserve la **surface totale** : la somme des surfaces
  par classe (y compris `indetermine`) égale la surface du MNT.
- **CA-2.7** Tous les rasters de sortie partagent exactement la grille du MNT.
- **CA-2.8** Les obstacles complets sont infranchissables : une cellule enclavée derrière un
  obstacle est `non_accessible` même si sa pente est faible.

---

## 6. Tests (`testthat`)

- `test-leastcost.R` : coût uniforme → distance euclidienne ; `cout_max` ; cellules `NA`
  infranchissables ; source vide → erreur ciblée.
- `test-chemin.R` : trajet optimal analytique ; validité et CRS du `LINESTRING`.
- `test-skidder-regles.R` : circulation libre sur le jouet ; treuillage amont et aval sur le
  jouet à pente forte ; bascules de pente ; exclusion et obstacles.
- `test-skidder-distances.R` : additivité des distances ; absence de `NA` parasite.
- `test-skidder-recap.R` : conservation de la surface totale ; volumes si raster fourni ;
  ligne `indetermine`.
- `test-skidder-grid.R` : grille de sortie identique à celle du MNT.

**Oracle** : comme au Lot 1, **analytique** — le MNT jouet a une pente connue, ce qui rend
les distances de treuillage et les classes prédictibles à la main. Les **oracles réels
Sylvaccess v3.6** seront branchés via `compare_to_oracle()` dès qu'ils sont disponibles
(ADR-006, cf. §10 Q6).

---

## 7. Fichiers (proposition)

```
R/leastcost.R       → propager_cout(), chemin_optimal() — service pur, sans métier
R/skidder.R         → skidder() + classe foretaccess_skidder + tableau récap
R/recap.R           → helpers surfaces/volumes par classe (réutilisés au Lot 3)
tests/testthat/test-leastcost.R, test-chemin.R, test-skidder-regles.R,
                   test-skidder-distances.R, test-skidder-recap.R, test-skidder-grid.R
data-raw/make_toy.R → ajouter un MNT à pente forte + des obstacles (déterministe)
```

Le jeu jouet du Lot 0 ne suffit pas : sa pente est de 20 % partout, donc **aucun treuillage
n'y est déclenché**. Il faut lui adjoindre un **MNT à pente forte** (par exemple un plan à
60 %, plus une zone > 100 % pour exercer l'exclusion) et une couche d'**obstacles**, générés
de façon déterministe par `data-raw/make_toy.R`.

**Nouvelle dépendance** : `leastcostpath` (ou `gdistance`) entre dans `Imports` — ni l'une ni
l'autre n'est aujourd'hui installée. Cf. §10 Q2.

---

## 8. Risques & mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Loi de bascule pente → distance inconnue | Distances de treuillage fausses | **Bloquant** : lire `calcul_distance_de_cout` et la règle de bascule dans le `.pyx` avant de coder (§10 Q1) |
| Fonction de coût R ≠ Sylvaccess | Non-régression rouge | Fonction de coût **injectable** ; si la tolérance ne tient pas → évaluer le portage Rust (roadmap Lot 2, ADR-001) |
| `leastcostpath`/`gdistance` trop lents ou trop rigides | Perf, ou API inadaptée au plafond de coût | Service isolé derrière `propager_cout()` : l'implémentation est remplaçable sans toucher aux moteurs |
| Anisotropie (coût amont ≠ aval) | Distances fausses | Le sens amont/aval est une **règle métier**, portée par la surface de coût, pas par le service (§10 Q3) |
| Bordures `NA` héritées du Lot 1 | Classes faussées en lisière | Ligne `indetermine` explicite dans le récap ; jamais rangées en `non_accessible` |
| Place de dépôt non définie | Trajet optimal ambigu | Décision §10 Q4 |

---

## 9. Definition of Done (Lot 2)

- [ ] Spec validée (ce fichier) + questions §10 tranchées.
- [ ] Service least-cost + règles skidder + distances + récap implémentés.
- [ ] Jeu jouet enrichi (MNT à pente forte, obstacles), déterministe.
- [ ] Tests verts (oracle analytique ; un test par règle et par cas d'erreur).
- [ ] `lintr` / `testthat` / `R CMD check` / `cargo` / `clippy` OK en CI ; couverture
      maintenue (≥ celle de `main`, seuil Codecov).
- [ ] Chaînes du code R en **ASCII** (contrainte `R CMD check`, cf. `PLAN.md`).
- [ ] Doc d'usage (roxygen) ; entrée `NEWS.md` ; `PLAN.md` à jour.
- [ ] Branche dédiée + PR + revue ; commits atomiques ; release `v0.3.0`.

---

## 10. Décisions et questions ouvertes

### Décisions tranchées (2026-07-10)

1. **Bibliothèque least-cost** : **`leastcostpath`** (moderne, bâtie sur `terra` comme le
   Lot 1, maintenue sur CRAN), et non `gdistance` (bâtie sur `raster`, en fin de vie, ce qui
   introduirait une seconde pile raster dans le package). Elle entre dans `Imports`. Le
   service `propager_cout()` reste en **façade**, pour pouvoir en changer sans toucher aux
   moteurs. *À vérifier à l'implémentation : le plafond de coût (`cout_max`) et la
   reconstruction du trajet ne sont pas exposés de la même façon selon les versions.*
2. **Anisotropie du coût** : **anisotrope, de type Tobler** — le coût dépend de la **pente
   signée** entre cellules voisines, monter ne coûte pas comme descendre. Le service
   `propager_cout()` doit donc opérer sur des **transitions orientées** (`a → b`), et non sur
   un coût par cellule. C'est une contrainte forte sur le backend
   (`leastcostpath::create_slope_cs()`), à honorer dès la conception du service.

### Bloqué sur le code source Sylvaccess

Trois points ne peuvent pas être devinés sans faire des distances **silencieusement fausses**
(l'oracle analytique ne les contredirait pas). Ils sont explicitement rangés par le brief §7
dans « à récupérer depuis le code source » (`sylvaccess_cython3.pyx`, GPL v3, `forge.inrae.fr`).
**Le Lot 2b est bloqué tant qu'ils ne sont pas lus.**

3. **Loi de bascule pente → distance de treuillage.** Sous la pente de bascule (75 % amont,
   20 % aval), la distance admissible croît-elle linéairement, est-elle constante au maximum
   dès le seuil skidder, ou suit-elle des paliers ?
4. **Fonction de coût** des plus courts chemins (`calcul_distance_de_cout`) : forme exacte de
   la pénalité de pente signée.
5. **Obstacles partiels** : infranchissables pour le skidder, ou franchissables avec surcoût ?
   Le brief dit seulement « spécifiques skidder », sans sémantique.

### Questions restantes (non bloquantes)

6. **Place de dépôt** : couche `sf` de points fournie par l'utilisateur ; à défaut, la cellule
   de desserte de coût minimal. *Proposition retenue sauf avis contraire.*
7. **Traînage piste vs forêt** : décomposition selon que la cellule traversée par le trajet
   least-cost porte une desserte ou non. *Interprétation retenue sauf avis contraire.*
8. **Oracle** : analytique à ce lot (comme au Lot 1), les oracles réels Sylvaccess v3.6 étant
   branchés via `compare_to_oracle()` dès qu'une exécution de référence est disponible.

---

## 11. Découpage du lot

Les décisions ci-dessus scindent le Lot 2 en deux incréments livrables séparément :

| Incrément | Contenu | État |
|---|---|---|
| **2a — Service least-cost** | `propager_cout()`, `chemin_optimal()`, transitions anisotropes, tests analytiques (CA-2.1, CA-2.2) | **débloqué** — aucune règle métier, donc aucune dépendance au `.pyx` |
| **2b — Règles skidder** | règles v3.6, classement, distances, récap (CA-2.3 … CA-2.8) | **bloqué** sur §10.3–10.5 |

Le jeu jouet enrichi (MNT à pente forte, obstacles) relève de 2b, puisqu'il n'existe que pour
exercer les règles. 2a se teste sur des surfaces de coût synthétiques.
