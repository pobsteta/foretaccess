# specs/017 — Lot 17 : Flux de bois & typage des routes

> **Statut** : **proposé** — en attente de validation.
> **Lot** : 17 (roadmap [`docs/ROADMAP-desserte.md`](../docs/ROADMAP-desserte.md)).
> **Dépend de** : Lot 16 (réseau de desserte), Lot 8 (base spatiale & agrégation).
> **Prépare** : Lot 18 (optimisation — le flux peut nourrir le critère volume).
> **ADR liés** : ADR-002 (stockage), ADR-004 (découplage), ADR-006 (non-régression).
> **Attribution** : reproduit les algorithmes **« Wood Flux Determination »** et
> **« Road Type Determination »** de **ForestRoadNetwork** (Klemet, GPL v3). Voir §9.
> **Note** : lot **R pur** — pas de nouvelle frontière Rust (calcul de graphe léger).

---

## 1. Contexte

Une fois le réseau tracé (Lot 16), deux traitements aval, présents dans ForestRoadNetwork mais
absents de SylvaRoad/FRD, complètent la chaîne stratégique :

1. **Flux de bois** : combien de bois transite par chaque tronçon, en le « faisant descendre »
   depuis les parcelles récoltées jusqu'aux exutoires (raccordements au réseau principal) ?
2. **Typage des routes** : quel type (primaire, secondaire, tertiaire, temporaire/hivernale)
   pour chaque tronçon, selon le flux qui le traverse ?

Contrairement au tracé (raster), ces traitements opèrent sur un **graphe** (nœuds/arêtes) : il
faut d'abord vectoriser proprement le réseau. C'est du graphe simple → **R pur**
(`sfnetworks`/`igraph`), sans Rust.

---

## 2. Périmètre

### Dans le périmètre

- La **vectorisation topologique** du réseau (raster Lot 16 → polylignes propres, nœuds/arêtes
  cohérents, degré correct aux jonctions).
- La génération des **points sources** dans les parcelles (densité utilisateur, **min. 1 par
  parcelle** même si la densité est trop faible).
- Le **calcul de flux** : accumulation hydrologique-like du volume depuis les sources vers les
  exutoires, via plus court chemin sur graphe de chaque tronçon aux exutoires.
- Le **typage** : classement de chaque tronçon par **seuils de flux** (bornes utilisateur) ;
  option de conversion d'un type en **routes temporaires** (pourcentage de longueur, zones
  dédiées optionnelles).

### Hors périmètre

- Le **tracé** et le **réseau** (Lots 15/16).
- L'**optimisation** du réseau selon le flux : Lot 18.

---

## 3. Entrées / sorties

### Entrées

- `reseau` : `foretaccess_reseau` (Lot 16) — réseau créé + raster.
- `parcelles` : `sf` POLYGON récoltées, avec **volume** (ou densité de volume).
- `exutoires` : points de raccordement au réseau principal (déduits du Lot 16 ou fournis).
- `densite_sources` : points/ha pour l'échantillonnage des sources.
- `seuils_flux` : bornes de classes de type de route.
- `conversion_temporaire` (optionnel) : type cible, % de longueur, zones préférentielles.

### Sorties

Un objet `foretaccess_desserte_typee` : `sf` LINESTRING du réseau avec, par tronçon, le **flux**
(volume cumulé) et le **type** ; `sfnetwork`/`igraph` du réseau ; récapitulatif de longueur par
type. Persistable via la base spatiale (Lot 8).

---

## 4. Algorithme

### 4.1 Vectorisation

Raster du réseau → squelette → polylignes ; construction du graphe (`sfnetworks`) ; contrôle de
topologie (jonctions = nœuds de degré ≥ 3, extrémités = exutoires/culs-de-sac).

### 4.2 Sources et flux (Wood Flux Determination)

- Semer des **points sources** dans chaque parcelle à `densite_sources` pt/ha ; garantir **≥ 1
  point par parcelle** (adaptation si densité trop faible pour la taille du polygone).
- Chaque source injecte sa part de volume ; le volume « descend » le réseau par le **plus court
  chemin (moindre coût) de la source à un exutoire**, en s'accumulant sur chaque arête traversée.
- Le flux d'une arête = somme des volumes des sources dont le chemin l'emprunte.

### 4.3 Typage (Road Type Determination)

- Classer chaque arête selon `seuils_flux` : flux fort → primaire, … , flux faible → tertiaire.
- Option **temporaire** : convertir un pourcentage de longueur d'un type donné en routes
  temporaires/hivernales, en priorité dans les zones dédiées si fournies.

---

## 5. Critères d'acceptation

- **CA-17.1** — Vectorisation topologiquement correcte (degrés aux jonctions, pas d'arête
  pendante non justifiée).
- **CA-17.2** — Chaque parcelle reçoit **au moins un** point source, quelle que soit la densité.
- **CA-17.3** — Conservation du volume : la somme des flux aux exutoires = volume total récolté.
- **CA-17.4** — Le flux **croît** de l'amont (parcelles) vers l'aval (exutoires) le long d'une
  branche (monotonie sur un chemin source→exutoire).
- **CA-17.5** — Le typage respecte les seuils ; la longueur par type est cohérente.
- **CA-17.6** — Conversion temporaire : le % de longueur converti est respecté (± tolérance).
- **CA-17.7** — Non-régression qualitative vs ForestRoadNetwork (Wood Flux / Road Type) sur son
  `Test_data/`.

---

## 6. Tests & oracle

- **Oracle** : ForestRoadNetwork (`woodFluxInNetwork_algorithm.py`,
  `RoadTypeDetermination_algorithm.py`) sur `Test_data/`.
- `testthat` : conservation du volume (CA-17.3), min. 1 source/parcelle (CA-17.2), monotonie
  du flux (CA-17.4).

---

## 7. Découpage du lot

- **17a** — vectorisation topologique (raster → `sfnetwork`).
- **17b** — sources + accumulation de flux.
- **17c** — typage + conversion temporaire + persistance (Lot 8).

---

## 8. Definition of Done (Lot 17)

- [ ] 17a/17b/17c livrés ; `foretaccess_desserte_typee` (`sf` + `sfnetwork`).
- [ ] CA-17.1 à CA-17.7 couverts (`testthat`).
- [ ] Persistance en base spatiale (PostGIS/GPKG) via le socle Lot 8.
- [ ] `R CMD check` OK ; chaînes ASCII ; `lintr` 0 ; doc roxygen ; `NEWS.md` ; `PLAN.md`.
- [ ] Branche dédiée + PR ; commits atomiques ; release proposée `v0.16.0`.

---

## 9. Attribution

Les algorithmes §4 dérivent de **ForestRoadNetwork** (Klemet, `woodFluxInNetwork_algorithm.py`,
`RoadTypeDetermination_algorithm.py`, GPL v3). Réécriture R (`sfnetworks`/`igraph`), aucune
copie de source. ForêtAccess est distribué sous GPL v3.
