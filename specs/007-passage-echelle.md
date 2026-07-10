# specs/007 — Lot 7 : Passage à l'échelle (tuilage, parallélisme, COG)

> **Statut** : **validé** (décisions §10 du 2026-07-10).
> **Lot** : 7 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 7 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md), US-7.1). **Exigence** : ENF-1
> ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 1 (`preprocess()`), Lot 2 (`skidder()`, `propager_cout()`).
> **Partagé avec** : Lots 3, 4, 6 — le tuilage est un **service**, indépendant du moteur.
> **ADR liés** : ADR-005 (tuilage + parallélisme), ADR-002 (stockage), ADR-004
> (découplage), ADR-006 (non-régression).

---

## 1. Contexte

`skidder()` traite 7,2 km² en **22 s CPU** sur un cœur, soit **3,05 s/km²** (mesure du
2026-07-10, cf. `PLAN.md`). L'extrapolation dit tout du lot :

| Échelle | 1 cœur | 8 cœurs |
|---|---|---|
| Massif (100 km²) | 5 min | 40 s |
| Département (2 000 km²) | 1,7 h | 13 min |
| Région (20 000 km²) | 17 h | 2,1 h |
| France (170 000 km²) | 6 j | 18 h |

Le temps n'est pourtant pas le premier obstacle : c'est la **mémoire**. Le moteur matérialise
une dizaine de vecteurs de la taille de la grille (`terra::values()`), plus un tas de Dijkstra.
À 5 m, un département fait 80 millions de cellules — chaque vecteur `double` pèse 640 Mo. Un
département ne tient pas en mémoire, quel que soit le nombre de cœurs.

Le tuilage résout les deux à la fois. Ce lot le livre **avant** tout portage Rust, décision
prise sur mesure : à l'échelle du massif et du département, il suffit ; Rust ne se justifie
qu'à partir de la région (§10.5).

---

## 2. Périmètre

### Dans le périmètre

- Découpage d'une emprise en **tuiles avec halo**, et recomposition.
- **Certificat d'exactitude** par cellule, et **halo adaptatif** (§4.3, §4.4).
- **Parallélisme par tuile** (`mirai`), nombre de workers paramétrable.
- Écriture des sorties en **COG** recomposé, une couche par sortie du moteur.
- Application au moteur **skidder** (le seul livré). L'interface est générique.

### Hors périmètre

- Parallélisme **intra-tuile** (rayons de treuil, Dijkstra) : c'est le Lot 4 / le portage Rust.
- Conservation des tuiles sur disque, reprise sur erreur, traitement incrémental (§10.4).
- Agrégation zonale et écriture en base : Lot 8.
- Acquisition des données sur l'emprise : Lot 10.

---

## 3. Entrées / sorties

### Entrées

Les mêmes qu'au Lot 1 (chemins de fichiers ou objets chargés, ADR-004), mais **sans
contrainte de tenue en mémoire** : le MNT est lu tuile par tuile via `terra`, qui n'en charge
que la fenêtre demandée. La desserte et la forêt (vecteurs) sont supposées tenir en mémoire —
hypothèse tenable : la BD TOPO d'un département pèse quelques dizaines de Mo.

### Sortie

Un objet `foretaccess_mosaique` :

| Champ | Contenu |
|---|---|
| `couches` | liste nommée de chemins vers les **COG** recomposés |
| `recap` | `data.frame` agrégé sur toute l'emprise |
| `tuiles` | `sf` des emprises de tuiles, avec halo final et statut |
| `indetermine_ha` | surface non certifiée, **toujours reportée**, jamais tue |
| `grid`, `config` | comme au Lot 1 |

---

## 4. Algorithme

### 4.1 Ce qui se tuile, et ce qui résiste

Les trois étages du skidder n'ont pas la même portée spatiale. C'est la seule chose qui
compte pour le tuilage.

| Étage | Portée | Halo suffisant |
|---|---|---|
| Pente / exposition (Horn) | 1 cellule | `1 × res` |
| Treuillage (balayage radial) | `max(debardage_amont_max_m, debardage_aval_max_m)` | `portée + 1,5 × res` |
| Traînage (Dijkstra) | **non bornée** | — |
| `zone_roulable_connectee()` | **non bornée** (connexité) | — |
| Traînage sur piste | **non bornée** (le long du réseau) | — |

Le treuillage est borné parce que `.dmax()` est **plafonné** hors des pentes de bascule :
`.dmax(p) ∈ [daval, damont]` par construction (`R/treuillage.R`). Un rayon meurt donc au plus
tard à 100 m avec les défauts v3.6. Le halo se calcule, il ne se devine pas.

Le traînage, lui, est un plus court chemin **sans plafond** : un chemin de débardage peut
traverser toute la carte, et la connexité d'un massif à la desserte peut passer par un détour
arbitrairement long. **Aucun halo fixe ne garantit l'identité au mono-bloc.** C'est le cœur
du lot, et le critère CA1 de l'US-7.1 l'exige pourtant.

### 4.2 Le halo fixe ne suffit pas, et il échoue en silence

Un halo de 500 m produit un résultat *plausible* : les distances de débardage y sont
légèrement trop grandes près des bords (le chemin optimal sort du halo, on lui en substitue
un moins bon), et certaines cellules y sont déclarées inaccessibles alors qu'elles sont
reliées à une desserte hors halo. Rien ne le signale. Un artefact de bordure ressemble à un
résultat.

Sur l'AOI réelle, la distance de traînage sur piste atteint **4 030 m** (médiane 1 020 m). Un
halo « raisonnable » de 500 m aurait faussé chaque cellule dont le chemin dépasse 500 m — soit
la majorité.

### 4.3 Certificat d'exactitude (décision §10.1)

Soit une tuile `T`, son halo `H`, et la région `R = T ∪ H`. On fait tourner **deux**
propagations sur `R` :

- `d_R` : Dijkstra depuis les cellules de desserte présentes dans `R` (le calcul normal) ;
- `d_∂` : Dijkstra depuis le **bord externe** de `R`, à coût nul.

**Certificat.** Pour toute cellule `v ∈ T` : si `d_R(v) ≤ d_∂(v)`, alors `d_R(v) = d_G(v)`,
où `d_G` est le coût global sur tout le territoire.

*Preuve.* Soit `P` un chemin global optimal aboutissant en `v`. Si `P ⊂ R`, alors sa source
est dans `R` et `d_R(v) ≤ coût(P) = d_G(v) ≤ d_R(v)`. Sinon `P` sort de `R` ; soit `b` sa
**dernière** entrée dans `R`, sur le bord externe. Le suffixe de `P` de `b` à `v` est inclus
dans `R` et coûte au plus `coût(P)`. Comme `d_∂` part de `b` à coût nul et que les coûts sont
positifs, `d_∂(v) ≤ coût(suffixe) ≤ coût(P) = d_G(v)`. Avec l'hypothèse, `d_R(v) ≤ d_∂(v) ≤
d_G(v) ≤ d_R(v)`, donc égalité. ∎

Trois corollaires, tous utiles :

- **Allocation.** Si l'inégalité est **stricte** (`d_R(v) < d_∂(v)`), aucun chemin extérieur
  n'atteint le coût optimal : la source allouée est elle aussi exacte. À égalité, le coût est
  exact mais l'allocation peut différer — la cellule est certifiée pour la distance, pas pour
  l'allocation.
- **Inaccessibilité.** `d_R(v) = ∞` et `d_∂(v) = ∞` satisfont `∞ ≤ ∞` : la cellule est
  certifiée **inaccessible**. Le bord du halo lui-même est hors zone, donc rien ne peut entrer.
  C'est le cas le plus fréquent en pratique, et il ne coûte rien.
- **Connexité.** `zone_roulable_connectee()` n'est que le cas `coût ≡ 0` : une composante
  connexe qui touche le bord externe sans toucher de desserte est **non certifiée**. La même
  règle s'applique, sans code spécifique.

Le certificat ne connaît rien du territoire hors de `R`. Il ne suppose rien sur la densité de
la desserte. Il coûte **une propagation de plus par tuile** — soit environ 2× le temps de
l'étage least-cost, qui pèse 59 % du moteur, donc ~1,6× au total. C'est le prix de la
garantie, et il est explicite.

### 4.4 Halo adaptatif

```
h ← halo_initial                       # défaut : 500 m
répéter
    calculer la tuile sur T ∪ halo(h)
    C ← cellules de T non certifiées
    si C est vide           → tuile exacte, sortir
    si h ≥ halo_max         → sortir, C reste indéterminée
    h ← 2 h
```

Le doublement converge vite : chaque itération quadruple la surface du halo, donc le nombre
de cellules non certifiées s'effondre. En pratique, une tuile de forêt bien desservie est
certifiée dès la première passe, et seules les tuiles de lisière en demandent une seconde.

`halo_max` (défaut : 4 000 m — l'ordre de grandeur du traînage sur piste observé) borne le
coût du pire cas. Au-delà, les cellules restantes sortent en **`indetermine`**, la classe que
`recapituler()` produit déjà pour les bordures de pente. Elles sont comptées, et leur surface
figure dans `indetermine_ha`. **Aucune troncature silencieuse** : c'est la règle du projet,
et c'est ce qui distingue ce lot d'un halo fixe déguisé.

### 4.5 Recomposition

Chaque tuile écrit sa fenêtre `T` (**sans le halo**). Les tuiles ne se recouvrent donc pas, et
la recomposition est une simple mosaïque — aucune règle de fusion, aucune moyenne de bordure.
C'est précisément ce que le halo achète.

L'`allocation` porte un **identifiant de cellule de desserte**, qui est un indice dans la
grille **globale**. Il doit donc être calculé sur la grille de l'emprise entière, jamais sur
celle de la tuile, sinon deux tuiles allouent le même identifiant à deux dessertes
différentes. C'est le seul champ non local du moteur, et le piège principal de ce lot.

Le `recap` global est la **somme** des récaps de tuiles, classe par classe. Les tuiles étant
disjointes, la surface totale est conservée par construction — c'est un invariant testable
(CA-7.4), pas une propriété espérée.

### 4.6 Parallélisme (décision §10.2)

`mirai` : un pool de démons, `mirai::daemons(n)`, une tâche par tuile. Choisi contre
`future`/`furrr` pour trois raisons, dans cet ordre : les démons **meurent avec la session**
(les workers `workRSOCK` de `future` survivent aux crashs et saturent la machine — observé
pendant le développement de ce lot) ; le démarrage est plus rapide ; c'est une dépendance,
pas deux.

Le nombre de workers vient de `config$general$workers` (défaut : `max(1, cœurs - 1)`).
`workers = 1` doit exécuter le code **sans démon**, séquentiellement : c'est indispensable au
débogage et aux tests, où un plantage dans un démon ne remonte qu'une trace tronquée.

Aucun aléatoire n'intervient : la reproductibilité ne demande pas de graine. Le résultat ne
dépend **pas** du nombre de workers — c'est CA-7.2, et c'est vérifiable.

### 4.7 Élagage spatial

Une tuile sans aucune cellule de forêt est **sautée** (aucun calcul, sortie `hors_foret`).
Une tuile sans desserte dans `T ∪ H` n'est pas sautée : elle peut être accessible depuis une
desserte plus lointaine, et c'est le certificat qui tranche.

---

## 5. Critères d'acceptation

- **CA-7.1** *(US-7.1 CA1)* Sur le jeu jouet, `traiter_par_tuiles()` avec des tuiles de
  20 cellules donne un résultat **identique bit à bit** à `skidder()` mono-bloc, pour les six
  couches — accessibilité, quatre distances, allocation.
- **CA-7.2** Le résultat ne dépend pas du nombre de workers : `workers = 1` et `workers = 4`
  donnent des sorties identiques.
- **CA-7.3** Le certificat est **correct** : sur une tuile dont le halo est artificiellement
  réduit à 1 cellule, les cellules non certifiées sont exactement celles dont le résultat
  diffère du mono-bloc. Aucun faux positif (une cellule certifiée est toujours exacte).
- **CA-7.4** La somme des surfaces par classe des tuiles égale celle du mono-bloc, à la
  cellule près, `indetermine` compris.
- **CA-7.5** Le halo adaptatif converge : sur le jouet, une tuile de bordure démarre non
  certifiée à `halo_initial = 5 m` et se certifie après doublements, sans atteindre `halo_max`.
- **CA-7.6** Quand `halo_max` est atteint, les cellules restantes sont classées `indetermine`,
  leur surface est reportée dans `indetermine_ha`, et un **avertissement** est émis. Jamais
  rangées dans `non_accessible`.
- **CA-7.7** L'`allocation` est cohérente entre tuiles : deux cellules de tuiles différentes
  allouées à la même desserte portent le même identifiant.
- **CA-7.8** *(US-7.1 CA2)* Les sorties sont des **COG** valides et relisibles, avec la table
  de catégories de l'accessibilité préservée (piège du Lot 1 : pas d'option de création).
- **CA-7.9** Une tuile sans forêt est sautée sans calcul (mesurable : le moteur n'est pas
  appelé).
- **CA-7.10** Sur l'AOI réelle (7,2 km², hors CI), le résultat tuilé est identique au
  mono-bloc, et le temps sur `n` cœurs est inférieur à `1,6 × T₁ / n × 1,3` (surcoût du
  certificat, plus 30 % de marge d'ordonnancement).

---

## 6. Tests (`testthat`)

- `test-tuilage.R` : découpage, halo, fenêtres disjointes, couverture exacte de l'emprise.
- `test-certificat.R` : la preuve du §4.3 sur des cas construits — chemin optimal qui sort du
  halo, cellule inaccessible certifiée, égalité stricte vs large pour l'allocation.
- `test-halo-adaptatif.R` : convergence, plafond, `indetermine`, avertissement.
- `test-mosaique.R` : identité bit à bit au mono-bloc (CA-7.1), invariance aux workers,
  conservation des surfaces, cohérence de l'allocation.
- `test-tuilage-cog.R` : COG valides, catégories préservées.

**Oracle** : le résultat mono-bloc du Lot 2, sur le jeu jouet. C'est le seul lot dont l'oracle
est **le projet lui-même** — et c'est ce qui le rend testable sans données lourdes.

Un test d'intégration sur l'AOI réelle (`data-raw/aoi.gpkg`) est **exclu de la CI** (données
non versionnées, ADR-002) mais scripté dans `data-raw/`. Le Lot 2 a montré qu'un jeu jouet
peut laisser passer deux bogues à travers 383 tests verts : sa pente constante masquait la
pondération de piste, sa forêt d'un seul tenant masquait le saut hors desserte. Le tuilage
mérite le même garde-fou.

---

## 7. Fichiers (proposition)

```
R/tuilage.R      → decouper_emprise(), .fenetre_halo(), classe foretaccess_tuiles
R/certificat.R   → certifier_propagation() — le §4.3, sans règle métier
R/mosaique.R     → traiter_par_tuiles(), recomposer(), classe foretaccess_mosaique
R/config.R       → general$workers, general$halo_initial_m, general$halo_max_m, tuile_m
tests/testthat/… → cf. §6
data-raw/integration_aoi.R → test d'intégration sur l'AOI réelle, hors CI
```

Nouvelle dépendance : **`mirai`** (Imports). Aucune autre.

`certifier_propagation()` vit à côté de `propager_cout()` et n'a **aucune** connaissance du
skidder : c'est un théorème sur les plus courts chemins, pas une règle forestière. Les Lots 3,
4 et 6 le réutiliseront tel quel.

---

## 8. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Le certificat double le coût du least-cost | Mesuré (CA-7.10). La propagation depuis le bord s'arrête tôt : ses coûts croissent depuis la bordure, et `cout_max` la tronque au coût maximal observé dans `d_R`. |
| L'`allocation` en indices globaux déborde le `double` | 2^53 cellules : sans objet, même au national (7 × 10^12 cellules à 5 m). |
| Un halo qui grandit fait exploser la mémoire d'une tuile | `halo_max` borne la fenêtre. Une tuile de 1 km avec 4 km de halo fait 81 km² : 3,2 M cellules, quelques centaines de Mo. Tenable. |
| `mirai` jeune face à `future` | L'interface d'orchestration est isolée dans une fonction (`.appliquer_tuiles()`) ; en changer coûte une fonction. |
| Les démons héritent mal de l'environnement de `pkgload` | Tests avec `workers > 1` exécutés sur le package installé, pas chargé. |

---

## 9. Definition of Done (Lot 7)

- [ ] `decouper_emprise()`, `certifier_propagation()`, `traiter_par_tuiles()` livrées et documentées.
- [ ] CA-7.1 à CA-7.9 couverts par des tests ; CA-7.10 mesuré hors CI et consigné dans `PLAN.md`.
- [ ] `mirai` ajouté aux `Imports` ; `workers = 1` sans démon.
- [ ] `lintr` / `testthat` / `R CMD check` OK en CI ; couverture ≥ `main`.
- [ ] Chaînes du code R en **ASCII**.
- [ ] Doc roxygen ; entrée `NEWS.md` ; `PLAN.md` à jour.
- [ ] Branche dédiée + PR ; commits atomiques ; release `v0.4.0` (nouvelle fonctionnalité).

---

## 10. Décisions (tranchées 2026-07-10)

1. **Exactitude** : **certificat + halo adaptatif**. Le critère CA1 de l'US-7.1 demande un
   résultat *identique* au mono-bloc ; un halo fixe ne le donne pas, il l'espère, et échoue en
   silence. Le certificat le **prouve** par cellule, sans rien savoir du territoire alentour.
   Coût assumé : ~1,6× le mono-bloc, avant parallélisme.
2. **Parallélisme** : **`mirai`**. Contre `future`/`furrr` : démons qui meurent avec la
   session, démarrage plus rapide, une dépendance au lieu de deux. Décision d'ADR-005 laissée
   ouverte, ici figée.
3. **Sorties** : **COG recomposé** seul. Pas de conservation des tuiles sur disque, pas de
   couche de certificat séparée : les cellules non certifiées sortent en `indetermine`, la
   classe que `recapituler()` produit déjà. Une classe existante vaut mieux qu'une couche neuve.
4. **Reprise sur erreur et traitement incrémental** : **hors périmètre**. Ils supposent un
   catalogue de tuiles persistant, qui relève du Lot 8 (base spatiale). Ne pas l'inventer ici.
5. **Rust** : **après ce lot, pas avant**. À 3,05 s/km², le tuilage suffit jusqu'au
   département (13 min sur 8 cœurs). Le portage se justifie à partir de la région, et sa cible
   est le **Dijkstra** (59 % du temps CPU), non le balayage radial — l'inverse de ce que
   suggérait la première mesure, prise avant `zone_roulable_connectee()`.

### Questions restantes (non bloquantes)

6. **Taille de tuile par défaut** : à calibrer sur l'AOI réelle. Trop petite, le halo domine
   (une tuile de 500 m avec 500 m de halo calcule 9× sa propre surface) ; trop grande, la
   mémoire et le grain du parallélisme souffrent. Piste : `tuile_m ≈ 4 × halo_initial_m`,
   soit 2 km par défaut, où le halo ne coûte que 125 % de surcoût surfacique.
7. **`cout_max` sur la propagation de bord** : la tronquer au coût maximal de `d_R` est
   correct (au-delà, le certificat est satisfait de toute façon) et divise son coût. À mesurer.

---

## 11. Découpage du lot

- **7a** — `decouper_emprise()` + `certifier_propagation()` + tests. Aucun parallélisme,
  aucune I/O : le cœur théorique, testable seul. C'est le seul incrément risqué.
- **7b** — `traiter_par_tuiles()` séquentiel, halo adaptatif, recomposition COG, identité au
  mono-bloc (CA-7.1, CA-7.3 à CA-7.9).
- **7c** — parallélisme `mirai`, invariance aux workers (CA-7.2), mesure sur l'AOI (CA-7.10).

Chaque incrément est mergeable seul. `7a` livre un théorème, `7b` la garantie, `7c` la vitesse
— et c'est délibérément l'ordre inverse de l'urgence apparente.

---

## 12. Attribution

Ce lot ne dérive d'aucun code Sylvaccess : le tuilage de la v3.6 (`joblib`/`dask`) est en
Python et hors de notre stack (ADR-005). Le certificat du §4.3 est un argument classique de
domaine de dépendance sur les plus courts chemins ; il est ici démontré et non emprunté.
