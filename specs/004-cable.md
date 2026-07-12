# specs/004 — Lot 4 : Noyau câble (CableHelp, en Rust)

> **Statut** : **validé** (décisions §10 du 2026-07-12, prises sur **lecture du code source**
> Sylvaccess v3.6 : `Sylvaccess_2_cable.py`, `sylvaccess_cython3.pyx` lignes 1040-1400, cf. §12).
> **Lot** : 4 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 4 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md)). **Exigence** : EF-6 ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 0 (squelette `extendr` : `cablehelp_version()` prouve la chaîne R↔Rust),
> Lot 1 (`preprocess()`), Lot 7 (tuilage — le câble en hérite pour l'échelle).
> **Prépare** : Lot 5 (sélection multicritère des lignes, EF-7).
> **ADR liés** : ADR-001 (langages : noyau câble en **Rust**, `extendr`, `rayon`), ADR-003
> (config/défauts v3.6), ADR-005 (passage à l'échelle), ADR-006 (non-régression).
> **Attribution** : les équations §4 dérivent du code source Sylvaccess (GPL v3) — §12.

---

## 1. Contexte

Le câble-mât est le seul moteur **non terrestre**, et le seul dont le brief impose le
portage **Rust** dès l'origine (ADR-001) : c'est le point chaud, ~60 M lignes testées à
l'échelle d'un massif. La mécanique est une **caténaire élastique** résolue par
Newton-Raphson — pur calcul numérique, sans SIG. C'est la frontière R↔Rust idéale :
R prépare la géométrie et les paramètres, Rust résout, R oriente et agrège.

Le Lot 0 a posé le squelette (`cablehelp_version()` traverse `extendr` de bout en bout).
Ce lot y installe la mécanique.

---

## 2. Périmètre

### Dans le périmètre

- Le **solveur de caténaire élastique** : tensions `(Th, Tv)` au support haut pour une
  travée donnée, par Newton-Raphson à Jacobien analytique, avec repli sur recherche par
  grille (`newton_ThTv`, `find_ThTvTmax`).
- La **hauteur du câble** le long d'une travée (`calcul_zs`) et la **flèche** — contrainte
  de garde au sol `∈ [hauteur_cable_min_m, hauteur_cable_max_m]` (défauts 3,5 m / 50 m).
- Le **test de faisabilité** d'une travée : tension résultante `≤ tension_rupture / sécurité`.
- L'**optimisation des supports intermédiaires** (0…`nb_supports_max`, défaut 3) : placement
  et raccourcissement pour rendre faisable une ligne qui ne l'est pas d'un seul tenant.
- L'exposition **`extendr`** de ces fonctions, avec tests `cargo test` **et** tests
  d'intégration R.

### Hors périmètre

- Le **balayage 360°/pixel** et l'orchestration SIG (génération des profils de terrain,
  masques forêt/obstacles) : côté R, incrément 4d, réutilisant `.rayons()` et le tuilage.
- La **sélection multicritère** des lignes (surface, supports, sens, longueur, volume, IPC) :
  Lot 5.
- Le **chariot automoteur** (`c_car_type = 1`) et l'optimisation de hauteur des supports
  (`c_option_h`) : reportés (§10).

---

## 3. Entrées / sorties

### Frontière R↔Rust (minimale et typée, ADR-001)

R ne passe à Rust que des **scalaires** et des **vecteurs de `f64`** : jamais un `SpatRaster`,
jamais un objet SIG. Une travée est décrite par :

- la géométrie : `D` (portée horizontale, m), `H` (dénivelé entre supports, m), le profil
  d'altitudes sous la ligne (vecteur `f64`) ;
- les paramètres câble (`config$cable`, défauts v3.6) : masse linéaire, diamètre, module de
  Young, tension de rupture, facteur de sécurité, hauteurs de support, garde au sol min/max ;
- la charge : poids max + poids du chariot.

Rust renvoie, par travée : `(Th, Tv)`, la tension maximale, un booléen **faisable**, et la
hauteur de câble au point le plus contraignant.

### Sortie R (incrément 4d)

Un objet `foretaccess_cable` : raster du **potentiel câble** (faisable / non), longueur et
sens (amont/aval) de la meilleure ligne par pixel, nombre de supports — dans la forme
commune aux autres moteurs, prêt pour la sélection du Lot 5.

---

## 4. Algorithme (mécanique CableHelp)

### 4.1 Constantes physiques

- `g = 9,80665` m/s² ; `Fo = g · (charge_max + poids_chariot)` — force de gravité de la charge
  (défauts `c_load_max = 2500` kg, `c_car_w = 400` kg).
- `Ao = 0,25 · π · d²` — section du câble porteur (`c_d = 18` mm de diamètre).
- `EAo = E · Ao` — rigidité axiale (module de Young × section). **`c_E` (N/mm²) n'est pas dans
  `Tab_Param_cable.csv`** : c'est un paramètre du `paramdict` global de Sylvaccess, à porter
  dans `config$cable` (§10.7).
- `Tmax = tension_rupture · g / sécurité` — tension admissible (`c_rupt_res = 35000` kgF,
  `c_safe = 2`).
- `W = q₁ · g · Lo` — poids du câble porteur sur la longueur `Lo` à vide (`c_q1 = 1,85` kg/m).
  Les câbles de **traction** et de **retour** ont leurs propres masses `c_q2`, `c_q3` (aussi
  hors CSV câble, dans le `paramdict`) ; elles interviennent dans le bilan d'effort (§4.4).

### 4.2 Caténaire élastique — équations de position

Pour une travée de longueur à vide `Lo`, chargée en abscisse curviligne `s1`, les tensions
`(Th, Tv)` au support haut satisfont deux équations (`f_x`, `f_z` du `.pyx`) :

\deqn{f_x = \frac{T_h L_o}{EA_o} + \frac{T_h L_o}{W}\left[\operatorname{asinh}\frac{T_v}{T_h}
  - \operatorname{asinh}\frac{T_v - F - W}{T_h}
  + \operatorname{asinh}\frac{T_v - F - W s_1/L_o}{T_h}
  - \operatorname{asinh}\frac{T_v - W s_1/L_o}{T_h}\right] - D = 0}

\deqn{f_z = \frac{W L_o}{EA_o}\left(\frac{T_v}{W} - \tfrac12\right)
  + \frac{T_h L_o}{W}\,\Theta - H = 0}

où `Θ` regroupe les termes en `√(1 + (·/Th)²)` (cf. `f_z`). La position du câble à l'abscisse
`s` est donnée par `calcul_xs` / `calcul_zs` — c'est elle qui fournit la **hauteur au-dessus
du sol** à tester contre la garde `[hauteur_cable_min_m, hauteur_cable_max_m]`.

Le modèle est **élastique** (terme `Lo/EAo`), pas une caténaire idéale : le câble s'allonge
sous tension. C'est une décision de fidélité (§10.2).

### 4.3 Résolution : Newton-Raphson à Jacobien analytique

`newton_ThTv` résout `f_x = f_z = 0` :

- amorçage `(Th, Tv)` par recherche sur grille (`find_ThTvTmax`, pas de 50 N jusqu'à `Tmax`) ;
- itération de Newton avec le Jacobien **analytique** (`df_dTh`, `dg_dTh`, et les dérivées en
  `Tv`) : `[h, k] = J⁻¹ · [−f_x, −f_z]` ;
- **repli** sur recherche par grille dès qu'un `Th` ou `Tv` devient négatif (hors domaine) ;
- arrêt à `|h|, |k| < err` (1 N) ou 20 itérations.

Faisabilité : `√(Th² + Tv²) ≤ Tmax`. Le port Rust reproduit ces fonctions **une pour une**,
avec des valeurs de référence exactes (§5) : ce sont elles l'oracle, pas une exécution SIG.

### 4.4 Frottement aux supports et effort de traction

Aux supports intermédiaires, la tension se transmet avec **frottement** (`frottement`,
`frottement_inv`), fonction du coefficient de frottement et des pentes du câble avant/après
le support. L'effort de la ligne de traction (`mainline`) ajoute la composante due à la
charge. Ces fonctions ferment le bilan de tension sur une ligne à plusieurs travées.

### 4.5 Optimisation des supports (incrément 4c)

Une ligne infaisable d'un seul tenant (flèche trop basse, tension trop haute) peut le devenir
en insérant 0…`nb_supports_max` supports intermédiaires. Sylvaccess cherche leur placement et
un éventuel **raccourcissement** de la ligne. L'optimisation est un balayage discret (pas
`c_precision`) — data-parallèle par ligne, d'où `rayon`.

---

## 5. Critères d'acceptation

- **CA-4.1** `cablehelp_version()` traverse toujours `extendr` (héritage Lot 0).
- **CA-4.2** Sur une travée de référence (D, H, Lo, charge donnés), `newton_ThTv` renvoie
  `(Th, Tv)` à ±1 N des valeurs calculées depuis le `.pyx`, et `f_x, f_z` y valent 0 à 0,05 près.
- **CA-4.3** `calcul_zs` reproduit la hauteur du câble à l'abscisse `s` à ±1 cm de la référence ;
  la flèche (point le plus bas) est correcte.
- **CA-4.4** Une travée dont la tension dépasse `Tmax` est déclarée **infaisable** ; une sous
  le seuil, **faisable**. Le seuil est exactement `tension_rupture · g / sécurité`.
- **CA-4.5** Une travée dont le câble descend sous `hauteur_cable_min_m` au-dessus du sol est
  infaisable (garde au sol) ; au-dessus de `hauteur_cable_max_m`, également (portée du grappin).
- **CA-4.6** Newton converge en ≤ 20 itérations sur les cas de référence ; le repli sur grille
  se déclenche quand une tension devient négative, et retrouve une solution.
- **CA-4.7** Chaque fonction `#[extendr]` a un test `cargo test` **et** un test d'intégration
  R qui l'appelle et retrouve la même valeur (frontière typée, ADR-001).
- **CA-4.8** L'insertion de supports rend faisable une ligne de référence qui ne l'est pas
  d'un seul tenant (incrément 4c).

---

## 6. Tests

- **Rust** (`cargo test`) : `f_x`/`f_z` s'annulent à la solution ; `newton_ThTv` converge ;
  `calcul_zs` reproduit la flèche ; frottement symétrique (`frottement`∘`frottement_inv` =
  identité) ; repli sur grille.
- **R** (`testthat`) : appel de chaque binding `extendr`, égalité à la valeur Rust ; faisabilité
  vs tension ; garde au sol ; (4c) supports.

**Oracle** : les équations mécaniques, avec valeurs de référence **exactes lues dans le
`.pyx`**. Une exécution Sylvaccess v3.6 sur un profil réel reste souhaitable pour valider
l'optimisation des supports (§10.5), mais la mécanique de travée est verrouillée sans elle.

---

## 7. Fichiers (proposition)

```
src/rust/src/cable/mod.rs        → API du module cable
src/rust/src/cable/catenaire.rs  → f_x, f_z, dérivées, calcul_xs/zs (caténaire élastique)
src/rust/src/cable/newton.rs     → newton_ThTv, find_ThTvTmax
src/rust/src/cable/support.rs    → frottement, mainline, optimisation des supports
src/rust/src/lib.rs              → bindings #[extendr] + extendr_module!
R/cable.R                        → wrappers R typés, potentiel_cable() (4d)
tests/testthat/test-cable-*.R    → tests d'intégration R
```

Nouvelles dépendances : côté Rust, `rayon` (parallélisme par ligne) ; aucune côté R.

La logique métier vit dans le crate ; R convertit et oriente (règle stricte 3 de `CLAUDE.md`).
Pas de SIG dans le crate au-delà du profil d'altitudes passé en vecteur.

---

## 8. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Newton diverge sur géométries extrêmes | Repli sur grille (reproduit du `.pyx`), plafond 20 itérations, test CA-4.6. |
| Écart numérique R↔Rust (f32 vs f64) | Tout le noyau en `f64` ; tolérances explicites (CA-4.2/4.3). |
| Frontière `extendr` mal typée | Structs plats de `f64` ; un test `cargo` + un test R par fonction (CA-4.7). |
| Optimisation des supports coûteuse | `rayon` par ligne (ADR-005) ; le balayage 360°/pixel hérite du tuilage (Lot 7). |
| Unités (kgF vs N, mm vs m) | Converties explicitement à la frontière ; `Tmax`, `Ao` calculés comme dans le driver (§4.1). |

---

## 9. Definition of Done (Lot 4)

- [ ] `catenaire.rs`, `newton.rs`, `support.rs` livrés, `cargo test` + `cargo clippy` verts.
- [ ] Bindings `#[extendr]` regénérés (`rextendr::document()`), NAMESPACE à jour.
- [ ] CA-4.1 à CA-4.7 couverts (4a/4b), CA-4.8 (4c) ; un test `cargo` + un test R par fonction.
- [ ] `R CMD check` OK en CI (compile le crate) ; couverture R ≥ `main`.
- [ ] Chaînes du code R en **ASCII** ; commentaires Rust en français, doc en anglais.
- [ ] Doc roxygen des wrappers ; entrée `NEWS.md` ; `PLAN.md` à jour.
- [ ] Branche dédiée + PR ; commits atomiques ; release `v0.6.0` (nouveau moteur).

---

## 10. Décisions (tranchées 2026-07-12, sur lecture du code source)

1. **Le noyau câble va en Rust** (ADR-001), exposé via `extendr`/`rextendr`. La frontière
   est minimale et typée : scalaires et vecteurs de `f64`, jamais de SIG dans le crate.
2. **Caténaire élastique**, pas idéale : le terme `Lo/EAo` (allongement sous tension) est
   dans les équations du `.pyx`. On le reproduit — la fidélité prime.
3. **Newton-Raphson à Jacobien analytique** avec repli sur grille, tel quel. Le Jacobien
   analytique (`df_dTh`, `dg_dTh`, …) est dans la source : pas de différences finies.
4. **Découpage** : 4a (caténaire + Newton), 4b (faisabilité d'une travée : tension + garde au
   sol), 4c (optimisation des supports), 4d (balayage 360°/pixel + orchestration R + tuilage).
   4a est le cœur, testable seul contre les équations.
5. **Chariot classique seulement** (`c_car_type = 0`). L'automoteur et l'optimisation de
   hauteur des supports (`c_option_h`) sont reportés — comme l'option 2 du skidder.
6. **Défauts matériels v3.6** dans `config$cable`, complétés depuis `Tab_Param_cable.csv`
   (masse linéaire 1,85 kg/m, diamètre 18 mm, rupture 35000 kgF, sécurité 2, mât 10,5 m,
   `lmax` 750 m, `lmin` 150 m, garde `[3,5 ; 50]` m, `nb_supports_max` 3).
9. **Amorçage substitué aux tables (tranché 2026-07-12, affiné en 4d).** `Find_Lomin`
   s'amorce dans Sylvaccess depuis les tables `Tabmesh` (`rastLosup`, `rastTh`, `rastTv`,
   ~80 lignes de pré-calcul indexé par `(H, D)`). On les **remplace** par une **grille
   grossière bornée** (`seed_grid`, 40 × 40, coût **indépendant de `Tmax`**) qui fournit un
   bon amorçage, puis Newton chaud raffine et la marche sur `Lo` progresse en réchauffant
   chaque solve. Point crucial pour 4d : le repli sur grille de `newton_thtv` coûte
   `O((Tmax/pas)²)` (≈ 3 M évaluations au `Tmax` matériel) — **prohibitif** dans la boucle
   chaude du balayage 360°/pixel ; `seed_grid` (1600 évaluations fixes) le remplace. C'est un
   choix de **performance, pas de correction** (le noyau reste fidèle). Un `Tabmesh` porté
   accélérerait encore.
10. **`OptPyl_Up` (placement multi-supports) différé.** L'optimiseur de placement des supports
    intermédiaires (~150 lignes, boucles imbriquées, table `Span` typée) n'est pas validable
    par oracle manufacturé — comme la double passe du porteur, sa fidélité exige une exécution
    Sylvaccess réelle. 4c livre les **primitives validables** (`find_lomin`, `test_span` avec
    la contrainte d'angle `angle_intsup`) ; le placement viendra avec un oracle réel (§8),
    porté ou orchestré côté R. Principe : pas de code plausible-mais-faux.

### Questions restantes (non bloquantes)

7. **Paramètres hors `Tab_Param_cable.csv`** : `c_E` (module de Young, N/mm²), `c_q2`/`c_q3`
   (masses linéaires des câbles de traction/retour, kg/m), `c_angle` (angle de déviation aux
   supports intermédiaires), `c_l_span` (longueur min de travée). Ils viennent du `paramdict`
   global de Sylvaccess (`globals().update(paramdict)`), pas du CSV câble : à porter dans
   `config$cable` avec des défauts documentés. `c_E` n'affecte pas la structure du solveur,
   seulement la valeur de `EAo`.
8. **Oracle réel** : les valeurs de référence de la mécanique sont exactes (lues dans la
   source). Une exécution Sylvaccess v3.6 sur un profil valide l'optimisation des supports.

---

## 11. Découpage du lot

- **4a** — caténaire élastique + Newton-Raphson en Rust, `cargo test`, binding `extendr`,
  test d'intégration R. Le cœur numérique, l'incrément à plus haute valeur et à risque isolé.
- **4b** — faisabilité d'une travée : tension `≤ Tmax`, garde au sol via `calcul_zs`.
- **4c** — primitives d'optimisation de travée : `find_lomin` (Lo minimal à tension = Tmax
  + garde) et `test_span` (segment : pré-filtre, pente bornée, angle inter-support). Le
  placement multi-supports `OptPyl_Up` est différé (§10.10). Amorçage substitué (§10.9).
- **4d** — balayage 360°/pixel, orchestration R (`potentiel_cable()`, **0 support**), tuilage
  (Lot 7). *Livré : `potentiel_cable()` balaie 360° depuis la desserte, extrait le profil MNT
  (interpolé à 0,5 m), teste une ligne 0 support via `cable_test_span`, et marque les cellules
  forestières couvertes. Amorçage `seed_grid` (§10.9). Sortie `foretaccess_cable`
  (accessibilité, longueur/azimut de ligne, nb_supports).* Restent en extension : le
  **placement des supports** (`OptPyl_Up`, oracle réel), le **pêchage latéral**
  (`distance_laterale_max_m`), et le **portage Rust de l'orchestration** (le balayage en R pur
  est correct mais lent à l'échelle réelle — le câble est le point chaud, cf. PRD). *Note : pas
  de fragilité numérique au `Tmax` matériel — ce qu'on croyait tel en 4c était une
  infaisabilité **géométrique** (support trop haut violant `hline_max`).*

Chaque incrément est mergeable seul ; 4a livre la mécanique, 4d la carte.

---

## 12. Attribution

Les équations §4 dérivent du code source Sylvaccess v3.6 (`sylvaccess_cython3.pyx`,
`Sylvaccess_2_cable.py` : `f_x`, `f_z`, `newton_ThTv`, `calcul_zs`, `frottement`, `mainline`),
distribué sous GPL v3. ForêtAccess est distribué sous GPL v3 (règle 4 de `CLAUDE.md`).
La mécanique CableHelp est attribuée à ses auteurs INRAE dans le README.
