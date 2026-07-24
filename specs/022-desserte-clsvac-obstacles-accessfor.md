# specs/022 — Desserte CL_SVAC + obstacles conformes ACCESSFOR

> **Statut** : **proposé** — en attente de validation.
> **Type** : acquisition/prétraitement (amont des moteurs). Étend `specs/010`
> (acquisition) et le prétraitement `specs/001`.
> **Origine** : diagnostic de divergence `classes_debardage()` vs la couche
> **ACCESSFOR** de l'IGN (édition 2025), mené sur l'AOI Chastel-Nouvel.
> **But** : rapprocher notre accessibilité de la référence nationale ACCESSFOR en
> alignant **la couche desserte** (classification CL_SVAC) et **la couche
> obstacles/zonages** — les **deux seules** sources de divergence identifiées.

---

## 1. Contexte et diagnostic

ACCESSFOR (INRAE-LESSEM + IGN, *Rapport final ACCESSFOR*, févr. 2025) cartographie
l'accessibilité forestière **avec le même moteur que nous, Sylvaccess**, à partir de
**BD Forêt V2 + MNT RGE Alti 5 m + BD Topo IGN**. foretaccess est validé cellule à
cellule contre l'oracle Sylvaccess (ColduPre, skidder **99,95 %**). Pourtant, sur
Chastel-Nouvel, l'accord `classes_debardage()` vs ACCESSFOR n'est que de **81 %
agrégé / 31 % à 9 classes**, avec un **biais systématique : nous mesurons des
distances de débardage plus longues** (60 % des cellules, **+1,26 bande** en moyenne
à 5 m ; +1,37 à 1 m — la résolution du MNT n'y change quasi rien).

**Ce qui a été écarté, preuves à l'appui :**

- **Paramètres machine** — le rapport ACCESSFOR (§2.2) donne les valeurs génériques :
  débusquage 50 m amont / 100 m aval, pentes bascule 75/20 %, pente skidder max
  30 %, hors-desserte 50 m, abattage 100 %. **Tous IDENTIQUES à `config$skidder`.**
  *(Seule exception, côté porteur : pente descente max = 25 % chez ACCESSFOR, 40 %
  chez nous — à traiter si l'on compare le porteur.)*
- **MNT** — ACCESSFOR utilise **RGE Alti 5 m**, exactement notre test. Écarté (test
  1 m→5 m : effet négligeable, +0,11 bande).

**Ce qui reste (l'objet de cette spec) :**

1. **La classification de la desserte.** Sur l'AOI, `acquire_desserte()` classe
   **82 % du linéaire en `piste`** (49 km) contre 18 % en `route` (10,6 km), et
   **`reseau_public` n'est JAMAIS assigné** (0 km). Or notre `distance_debardage`
   inclut le **traînage sur piste jusqu'à une route** : plus le réseau est « piste »,
   plus le traînage s'allonge → distances gonflées → « plus loin ». ACCESSFOR, avec
   la même BD Topo mais une classification **CL_SVAC** plus fine, place davantage de
   points d'arrivée (route forestière / réseau public) → traînage court → « plus
   proche ». **C'est le driver principal du +1,3 bande.**
2. **Les obstacles et zonages réglementaires.** ACCESSFOR (§2.3.4) intègre des
   obstacles BD Topo (cours d'eau, voies ferrées, bâtis, autoroutes, routes
   principales, surfaces hydro, aérodromes, réservoirs, terrains de sport) **et** des
   zonages réglementaires (réserve intégrale de parc national, réserves biologiques
   intégrales/dirigées, APB, réserves naturelles). Notre run de comparaison passe
   `preprocess(mnt, desserte, foret)` **sans obstacles** → explique les **flips
   accessible↔inaccessible** de la matrice de confusion.

---

## 2. Périmètre

**Deux volets, livrables séparément :**

- **Volet A — Desserte CL_SVAC** : reclasser la BD Topo `troncon_de_route` selon les
  **trois catégories Sylvaccess** (piste / route forestière / réseau public) et
  **alimenter `reseau_public`**. C'est le levier dominant.
- **Volet B — Obstacles + zonages ACCESSFOR** : une acquisition d'obstacles **BD
  Topo** (et non OSM comme `acquire_obstacles()` actuel) + zonages réglementaires
  **INPN/BD Topo filtrés**, câblée dans `preprocess(obstacles_complets=)`.

Hors périmètre : les paramètres machine (déjà iso, sauf `pente_descente` porteur,
trivial). Aucun changement aux moteurs ni à la non-régression Sylvaccess.

---

## 3. Volet A — Desserte CL_SVAC

### 3.1. Sémantique Sylvaccess (rapport ACCESSFOR §2.3.2)

Le champ `CL_SVAC` classe la desserte en trois :

| CL_SVAC | Classe | Rôle |
|---|---|---|
| 1 | **piste forestière** | circulation engins **+ traînage** (skidder) / portage (porteur) ; point d'appui débusquage |
| 2 | **route forestière** | camions circulent, **traînage INTERDIT** ; point d'appui débusquage |
| 3 | **réseau public** | route ouverte : **terminus** du traînage (chargement camion) |

Le débardage traîne le bois sur les pistes **jusqu'à la connexion la plus proche
entre une piste et une route du réseau public**. Notre modèle porte déjà cette
sémantique (`.classes_desserte() = route, piste, dfci, reseau_public` ;
`reseau_public` = **barrière/terminus**, cf. `preprocess()` `@param desserte`).

### 3.2. Le gap actuel

`.mapper_classe_desserte()` (`R/acquire-ign.R`) est une heuristique de mots-clés :
`piste` si `nature` ∈ {chemin, sentier, empierrée, escalier, piste cyclable}, sinon
`route`. **Jamais `reseau_public`.** Trop grossier → sur-classification en piste,
terminus non identifié.

### 3.3. Proposé

- **Table `nature` × `importance` BD Topo → CL_SVAC**, calquée sur ACCESSFOR :
  - `reseau_public` (=3) : routes revêtues à `importance` élevée (départementales,
    nationales, routes principales carrossables camion) ;
  - `route forestière` (=2, notre `route`) : routes empierrées/forestières
    carrossables mais non « réseau public » ;
  - `piste` (=1) : chemins, sentiers, pistes non carrossables camion.
  - Table paramétrable (config), défaut aligné ACCESSFOR ; valeurs `nature`/
    `importance` à figer sur la nomenclature BD Topo V3 `troncon_de_route`.
- **Alimenter `reseau_public`** dans la sortie d'`acquire_desserte()` (champ `classe`
  = `reseau_public` pour CL_SVAC=3).
- Rétro-compat : garder l'ancienne heuristique derrière un flag
  (`classification = c("clsvac", "heuristique")`, défaut `"clsvac"`).

### 3.4. Attention

La correspondance exacte `nature`/`importance` → CL_SVAC n'est **pas publiée telle
quelle** par ACCESSFOR (ils décrivent les 3 classes, pas la table de mapping BD
Topo). À **caler empiriquement** contre la couche ACCESSFOR (maximiser l'accord),
puis documenter. Ne pas figer la table sans confrontation à l'oracle (cf.
mémoire : valider sur ColduPre/ACCESSFOR avant de conclure).

---

## 4. Volet B — Obstacles + zonages conformes ACCESSFOR

### 4.1. Sources confirmées récupérables (WFS `data.geopf.fr`, testé sur l'AOI)

| Obstacle (rapport §2.3.4) | Couche WFS | Testé Chastel-Nouvel |
|---|---|---|
| Cours d'eau | `BDTOPO_V3:cours_d_eau` | 15 obj ✅ |
| Surfaces hydro | `BDTOPO_V3:surface_hydrographique` | 0 (zone sèche) |
| Voies ferrées | `BDTOPO_V3:troncon_de_voie_ferree` | 0 (aucune) |
| Bâtis | `BDTOPO_V3:batiment` | à ajouter |
| Routes principales / autoroutes | `BDTOPO_V3:troncon_de_route` (filtré `importance`) | déjà acquis |
| Zonages réglementaires | `BDTOPO_V3:parc_ou_reserve` **+ INPN** | 2 obj (à filtrer) |

`happign` est installé et wrappe ces couches (`happign::get_wfs()`) — alternative à
l'appel `httr2` direct.

### 4.2. Filtrage des zonages (crucial)

`parc_ou_reserve` renvoie ici **« Parc national »** et **« Réserve de biosphère »** —
qui **ne sont PAS** des exclusions ACCESSFOR. Le rapport ne liste que : **réserve
intégrale** de parc national, **réserves biologiques** intégrales/dirigées, **arrêté
de protection de biotope (APB)**, **réserves naturelles** nationales/régionales.
→ **Filtrer par `nature`/`nature_detaillee`** ; compléter par l'**INPN espaces
protégés** (typologie fine, `inpn.mnhn.fr/programme/espaces-proteges`, WFS
`download_inpn_wfs` côté app). **Ne PAS exclure tout un parc national** (sur-blocage).

### 4.3. Proposé

- **`acquire_obstacles_bdtopo(aoi, ...)`** (nouvelle fonction, ou variante
  `source = "bdtopo"` d'`acquire_obstacles()`) : agrège les couches ci-dessus en un
  `sf` d'obstacles (lignes/polygones), filtrage des zonages inclus.
- Câblage : `preprocess(obstacles_complets = <obstacles>)` — le masque existe déjà
  (`obstacles_complets_mask`), rien à changer aux moteurs.
- `acquire_inputs(sources = c(..., "obstacles"))` : brancher la source BD Topo.

---

## 5. Critères d'acceptation

- [ ] **CA-22.1** — `acquire_desserte(classification = "clsvac")` produit un champ
  `classe` à **trois valeurs présentes** (`piste`/`route`/`reseau_public`) sur une
  AOI où la BD Topo contient des routes principales ; `reseau_public` non vide.
- [ ] **CA-22.2** — Rétro-compat : `classification = "heuristique"` reproduit
  exactement l'ancienne sortie (bit-identique).
- [ ] **CA-22.3** — `acquire_obstacles_bdtopo()` récupère cours d'eau + hydro +
  voies ferrées + bâtis + routes principales sur l'AOI, et les zonages réglementaires
  **filtrés** (pas le parc national entier).
- [ ] **CA-22.4** — `preprocess(obstacles_complets=)` consomme la couche sans erreur ;
  le masque d'obstacles est non vide là où la donnée l'est.
- [ ] **CA-22.5 (le juge de paix)** — Sur Chastel-Nouvel, l'accord vs ACCESSFOR
  **remonte** : le Δ moyen (+1,26 bande) **diminue** et l'accord 9-classes (31 %)
  **augmente**, après reclassification CL_SVAC (volet A) puis + obstacles (volet B).
  Mesuré par `comparer_accessfor()` / `data-raw/accessfor_compare.R`. Documenter le
  gain de chaque volet séparément.

---

## 6. Tests

- `testthat` : `.mapper_classe_desserte(classification="clsvac")` sur un `sf` BD Topo
  jouet couvrant les cas nature/importance → CL_SVAC attendus ; rétro-compat de
  l'heuristique ; filtrage des zonages (un « Parc national » n'est pas exclu, une
  « Réserve naturelle » l'est).
- `data-raw/accessfor_compare.R` : ajouter la variante desserte-CL_SVAC + obstacles,
  et rapporter l'accord avant/après (reproductible, hors CI — réseau WFS).

---

## 7. Risques / points ouverts

| Risque | Mitigation |
|---|---|
| Table `nature`/`importance` → CL_SVAC non publiée par ACCESSFOR | Caler empiriquement contre la couche ACCESSFOR ; documenter le mapping retenu |
| INPN : typologie et filtrage des exclusions | S'appuyer sur la liste explicite du rapport §2.3.4 ; valider qu'on n'exclut pas un parc entier |
| Obstacles alourdissent l'acquisition (réseau WFS, plusieurs couches) | Cache par couche (comme `acquire_*`) ; opt-in |
| Sur-ajustement à ACCESSFOR au détriment de la fidélité Sylvaccess/ColduPre | La non-régression ColduPre reste le garde-fou : elle ne doit PAS bouger (desserte de test ColduPre inchangée) |

---

## 8. Sources

- *Cartographie de l'accessibilité des forêts. Projet ACCESSFOR* — Rapport final,
  INRAE-LESSEM + IGN, févr. 2025 (HAL `hal-04988956`). §2.2 (paramètres), §2.3.2
  (desserte CL_SVAC), §2.3.4 (obstacles/zonages).
- WFS IGN `data.geopf.fr` : `BDTOPO_V3:{cours_d_eau, surface_hydrographique,
  troncon_de_voie_ferree, batiment, troncon_de_route, parc_ou_reserve}`.
- INPN espaces protégés : `inpn.mnhn.fr/programme/espaces-proteges`.
- `happign` (wrapper R WFS/WMS Géoplateforme) — installé.
