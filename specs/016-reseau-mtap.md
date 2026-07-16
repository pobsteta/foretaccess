# specs/016 — Lot 16 : Réseau de desserte multi-cibles (MTAP, approximation de Steiner)

> **Statut** : **proposé** — en attente de validation.
> **Lot** : 16 (roadmap [`docs/ROADMAP-desserte.md`](../docs/ROADMAP-desserte.md)).
> **Dépend de** : Lot 14 (coût), Lot 15 (solveur de tracé A\*), Lot 7 (tuilage).
> **Prépare** : Lot 17 (flux & types), Lot 18 (optimisation multi-start).
> **ADR liés** : ADR-008 (graphe étendu), ADR-001 (Rust — parallélisme `rayon`),
> ADR-006 (non-régression).
> **Attribution** : la logique MTAP→STAP glouton reproduit **ForestRoadNetwork** (Klemet,
> GPL v3) ; la formulation en **arbre de Steiner** suit **Chung & Sessions 2007**
> (*Can. J. For. Res.*, modèle de référence de la famille SylvaRoad). Voir §10.

---

## 1. Contexte

Le Lot 15 trace **un** tronçon entre deux points imposés. Aucun outil libre étudié
(SylvaRoad, FRD) ne construit un **réseau** desservant N parcelles : SylvaRoad enchaîne des
waypoints fournis, FRD idem. Seul **ForestRoadNetwork** attaque le problème multi-cibles
(MTAP), mais avec un Dijkstra 8-connexe glouton, sans les contraintes géométriques du Lot 15.

Ce lot est donc **la valeur ajoutée** de ForêtAccess : coiffer le solveur de tracé d'une
couche réseau. Le problème (MTAP — Multiple Target Access Problem) est classiquement approché
en le découpant en STAP (Single Target Access Problem) résolus dans un ordre heuristique,
**avec réutilisation** du réseau déjà construit — méthode des logiciels professionnels
(REMSOFT Road Optimizer). La formulation « juste » est un **arbre de Steiner** de poids
minimal reliant les terminaux (parcelles + points de raccordement au réseau existant) ;
le glouton en est une approximation.

---

## 2. Périmètre

### Dans le périmètre

- La construction d'un **réseau** desservant N polygones (parcelles à exploiter), raccordé au
  **réseau de desserte existant** (entrée), au moindre coût cumulé de construction.
- Trois **heuristiques d'ordre** d'insertion des cibles (comme ForestRoadNetwork) : plus proche
  d'abord, plus gros volume d'abord, aléatoire (graine fixée).
- La **réutilisation du réseau** : une cellule déjà construite passe à coût ~0 pour les cibles
  suivantes → arborescence, pas des chemins isolés.
- Une **approximation d'arbre de Steiner** (MST sur graphe des terminaux, arêtes = chemins de
  moindre coût du Lot 15, puis élagage) comme mode « qualité » alternatif au glouton.
- La génération des **points de raccordement** de chaque parcelle (accroche au réseau courant).

### Hors périmètre

- Le **tracé** d'un chemin cible→réseau : délégué au Lot 15.
- L'**optimisation** au-delà du glouton/MST (multi-start, recuit) : Lot 18.
- Le **flux de bois** et le **typage** des routes : Lot 17.
- La **géométrie fine** (lissage, lacets) : héritée du Lot 15.

---

## 3. Entrées / sorties

### Entrées

- `cout` : `foretaccess_cout_construction` (Lot 14).
- `parcelles` : `sf` POLYGON des zones à desservir (avec volume optionnel).
- `desserte_existante` : `sf` LINESTRING du réseau auquel se raccorder.
- `heuristique` : `"plus_proche" | "plus_gros_volume" | "aleatoire"` (défaut : plus proche).
- `mode` : `"glouton" | "steiner"` (défaut : glouton).
- paramètres géométriques du solveur (transmis au Lot 15).

### Sorties

Un objet `foretaccess_reseau` : `sf` LINESTRING du réseau créé (attribut : ordre de création,
cible desservie), `SpatRaster` du réseau rastérisé (pour le Lot 17), coût total, et le rappel
de l'heuristique/mode.

---

## 4. Algorithme

### 4.1 Mode glouton (MTAP → STAP, ForestRoadNetwork)

```
reseau_courant  <- desserte_existante (rasterisée : coût des cellules -> ~0)
ordre           <- trier(parcelles, selon heuristique)
pour chaque parcelle P dans ordre :
    source      <- point(s) de P
    cible        <- réseau_courant (multi-cible : n'importe quelle cellule du réseau)
    chemin       <- solveur_trace(cout_courant, source -> cible)      # Lot 15
    reseau_courant <- reseau_courant ∪ chemin
    cout_courant   <- abaisser à ~0 le coût des cellules de chemin      # réutilisation
```

La clé est l'**abaissement à ~0** des cellules construites : les parcelles suivantes se
greffent sur le réseau existant plutôt que de tracer en parallèle. C'est ce qui transforme des
chemins isolés en réseau arborescent.

### 4.2 Mode Steiner (Chung & Sessions, « qualité »)

1. Terminaux = centroïdes/points d'accès des parcelles + points de raccordement au réseau existant.
2. Graphe complet des terminaux, poids d'arête = coût du chemin de moindre coût (Lot 15) entre
   les deux terminaux.
3. **MST** de ce graphe (Kruskal/Prim).
4. Matérialisation : remplacer chaque arête du MST par son chemin réel ; fusionner les cellules
   partagées ; **élaguer** les branches redondantes (heuristique de Steiner KMB).

Le mode Steiner rapproche de l'optimum global (le glouton séquentiel ne garantit rien) au prix
de N² tracés — d'où le parallélisme `rayon` (les tracés d'arêtes sont indépendants).

---

## 5. Critères d'acceptation

- **CA-16.1** — Toutes les parcelles sont desservies (connexité au réseau existant vérifiée).
- **CA-16.2** — Le réseau est **arborescent** : deux parcelles voisines partagent un tronc
  commun (preuve de réutilisation, coût total < somme des tracés isolés).
- **CA-16.3** — Les trois heuristiques produisent des réseaux valides ; l'aléatoire est
  **reproductible** à graine fixée.
- **CA-16.4** — Mode Steiner : coût total ≤ coût glouton sur cas test (au moins non pire).
- **CA-16.5** — Le réseau se raccorde effectivement à `desserte_existante` (pas de composante
  isolée).
- **CA-16.6** — Non-régression qualitative vs ForestRoadNetwork sur son `Test_data/` : réseau de
  forme comparable (mêmes parcelles desservies, coût du même ordre).
- **CA-16.7** — Déterminisme (hors aléatoire) : mêmes entrées → même réseau.

---

## 6. Tests & oracle

- **Oracle** : ForestRoadNetwork (`Test_data/`) — comparaison de forme et de coût, pas
  d'identité numérique (contraintes géométriques du Lot 15 en plus).
- `testthat` : réutilisation (CA-16.2) sur 2-3 parcelles jouet ; Steiner ≤ glouton (CA-16.4) ;
  reproductibilité aléatoire.
- Vérification de connexité (graphe `igraph`/`sfnetworks`).

---

## 7. Découpage du lot

- **16a** — orchestration glouton (ordre, réutilisation, multi-cible) réutilisant le Lot 15.
- **16b** — mode Steiner (MST + matérialisation + élagage), tracés d'arêtes parallélisés.
- **16c** — sortie `foretaccess_reseau` (`sf` + raster) + raccordement/connexité.

---

## 8. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Coût N² du mode Steiner | Parallélisme `rayon` (arêtes indépendantes) ; glouton par défaut. |
| Réutilisation mal implémentée (chemins parallèles) | Test CA-16.2 (coût < somme isolée) obligatoire. |
| Multi-cible dans le solveur (Lot 15) | Le Dijkstra inverse (`h`) prend le réseau entier comme cible ; `h = 0` sur le réseau. |
| Ordre glouton sous-optimal | Multi-start reporté au Lot 18 ; Steiner comme borne de qualité. |

---

## 9. Definition of Done (Lot 16)

- [ ] 16a/16b/16c livrés ; `foretaccess_reseau` (`sf` + raster, CRS strict).
- [ ] CA-16.1 à CA-16.7 couverts (`testthat`).
- [ ] Non-régression qualitative vs ForestRoadNetwork documentée.
- [ ] `R CMD check` OK ; chaînes ASCII ; `lintr` 0 ; doc roxygen ; `NEWS.md` ; `PLAN.md`.
- [ ] Branche dédiée + PR ; commits atomiques ; release proposée `v0.15.0`.

---

## 10. Attribution

La boucle MTAP→STAP glouton et la réutilisation du réseau dérivent de **ForestRoadNetwork**
(Klemet, `forestRoadNetwork_algorithm.py`, GPL v3). La formulation en arbre de Steiner suit
**Chung & Sessions 2007** (*Improved road network design models…*, Can. J. For. Res.).
ForêtAccess est distribué sous GPL v3 : réécriture propre, aucune copie de source.
