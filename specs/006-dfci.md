# specs/006 — Lot 6 : Camion DFCI (beta) — zone défendable

> **Statut** : **validé** (décisions §10 du 2026-07-12). Sortie **beta** au sens du
> brief §4.5 : modèle volontairement simple, limites explicites (§9).
> **Lot** : 6 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 6 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md)). **Exigence** : EF-8 ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 1 (`preprocess()` : MNT, pente, forêt, desserte classée),
> Lot 2 (service partagé `propager_cout()` et `surface_cout_skidder()`), Lot 7
> (`traiter_par_tuiles()`, `certifier_propagation()`).
> **Prépare** : Lot 8 (base spatiale — la zone défendable y est persistée/requêtable).
> **Post-MVP** : ce lot n'est pas sur le chemin critique produit (décision PRD §9.2).

---

## 1. Contexte

Le camion DFCI (défense de la forêt contre les incendies) stationne sur une desserte
carrossable et **défend** le terrain avoisinant contre le feu, dans une **portée
latérale** limitée. Le Lot 6 cartographie la **zone défendable** — la forêt qu'un
camion peut atteindre et défendre depuis les dessertes DFCI.

C'est une sortie **beta** : elle vise une première **hiérarchisation** du territoire
(où la défense est possible depuis le réseau existant), pas un dimensionnement
opérationnel. Le raffinement du modèle dépend du projet **QUALIROAD** (qualification
fine de la carrossabilité des dessertes) — hors périmètre ici.

---

## 2. Périmètre

### Dans le périmètre

- La **zone défendable** : raster catégoriel `defendable` / `non_defendable` /
  `hors_foret`, sur la grille du prétraitement.
- La **distance de défense** au terrain (m) depuis la desserte-source la plus proche.
- L'**allocation** : la cellule de desserte de rattachement.
- Le **récapitulatif** surfaces/volumes par classe.
- La compatibilité **tuilage** (Lot 7) : sortie `certifie`, résultat identique au
  mono-bloc sur les cellules certifiées.

### Hors périmètre (voir §9)

- Tout modèle de **combustible**, de **vent**, ou de **physique de lance** (portée du
  jet, débit, pression).
- La **qualification** de la carrossabilité réelle des dessertes (QUALIROAD).
- L'agrégation zonale (massif/parcelle/commune) → Lot 8.

---

## 3. API

```r
camion_dfci(pre, config = foretaccess_config(), write_dir = NULL, bord = NULL)
```

Signature **identique** à [`skidder()`] et [`porteur()`] (mêmes `pre`, `config`,
`write_dir`, `bord`), donc directement branchable sur `traiter_par_tuiles()`.

Retour : objet `foretaccess_dfci` — `accessibilite`, `distance_defense`,
`allocation`, `certifie`, `recap`, `grid`, `config`, `fichiers`.

---

## 4. Modèle

La portée de défense est modélisée par un **tampon au terrain** : un plus court chemin
pondéré par la pente ([`propager_cout()`] + [`surface_cout_skidder()`], la même
pondération 3D `sqrt(1 + (p/100)^2)` que le skidder), depuis les cellules de
desserte-source, **plafonné** à `distance_defense_max_m` et **interdit** au-delà de la
pente d'intervention `pente_defense_max_pct`.

1. **Sources** : cellules de desserte dont la classe ∈ `config$dfci$classes_source`
   (défaut `"dfci"` seul). Codes du raster desserte : route=1, piste=2, dfci=3.
2. **Terrain défendable** (`zone`) : pente ≤ `pente_defense_max_pct` et hors obstacle
   complet ; la pente `NA` est infranchissable.
3. **Propagation** : `propager_cout(cout, sources, zone, cout_max = distance_defense_max_m)`.
4. **Classement** : cellule de forêt atteinte → `defendable` ; cellule de forêt non
   atteinte → `non_defendable` ; hors forêt → `hors_foret` ; pente `NA` → indéterminé.

### 4.1 Tuilage

Tous les mécanismes ont une **portée bornée** par `distance_defense_max_m`. Sous
tuilage, la sortie porte un `certifie` issu de [`certifier_propagation()`] (avec le même
`cout_max`) : une cellule est certifiée quand le coût depuis les sources de la fenêtre
est prouvé global. Un halo ≥ `distance_defense_max_m` (+ marge) certifie l'intérieur.

Le **réseau DFCI est clairsemé** (souvent une poignée de pistes) : une tuile peut ne
contenir **aucune** source DFCI dans sa fenêtre, tout en ayant d'autres dessertes.
`.tuile_calculable()` (Lot 7) ne teste que la présence d'une desserte quelconque : le
moteur DFCI ne peut donc pas s'y fier. Décision : `camion_dfci()` **tolère** l'absence
de source **sous tuilage** (`bord` non `NULL`) en renvoyant une tuile **indéterminée**
(rien de certifié, le halo grandit) ; au **niveau top-level** (`bord = NULL`), l'absence
de source DFCI reste une **erreur ciblée**.

Conséquence assumée : la garantie « identique au mono-bloc » porte sur les cellules
**certifiées**. Une tuile dont le halo n'atteint jamais la ligne DFCI reste indéterminée
(comme une tuile sans desserte pour le skidder, spec 007 §4.3).

---

## 5. Configuration (`config$dfci`)

| Clé | Défaut | Sens |
|---|---|---|
| `distance_defense_max_m` | `100` | Portée latérale de défense depuis une desserte (m). |
| `pente_defense_max_pct` | `40` | Pente au-delà de laquelle le terrain est réputé non défendable (%). |
| `classes_source` | `"dfci"` | Classes de desserte servant de base (sous-ensemble de route/piste/dfci). |

Ce sont des **hypothèses de travail**, pas des valeurs Sylvaccess v3.6 : le module DFCI
de Sylvaccess n'est pas dans les sources de référence (RdV Experts 2026). Elles sont
documentées comme telles (ADR-003 : défauts explicites et surchargables).

---

## 6. Sorties

- `accessibilite` : raster catégoriel (`defendable`, `non_defendable`, `hors_foret`).
- `distance_defense` : distance de défense au terrain (m) ; 0 sur la desserte, `NA` hors
  portée / indéterminé.
- `allocation` : cellule de desserte de rattachement.
- `certifie` : logique (tuilage), ou `NULL`.
- `recap` : `data.frame` surfaces (ha) et volumes (m³) par classe, ligne `indetermine`
  comprise (la somme des surfaces égale le raster entier).
- Écriture COG optionnelle (`write_dir`) des trois rasters `accessibilite`,
  `distance_defense`, `allocation`.

---

## 7. Tests (`tests/testthat/test-dfci.R`)

- **Tampon borné** : zone défendable non vide, distance ≤ portée (CA1).
- **Monotonie de portée** : une portée plus grande étend la zone défendable.
- **Coupure de pente** : un plan raide (> seuil) effondre la zone défendable.
- **`classes_source`** : une piste seule est ignorée par défaut, utilisée si ajoutée.
- **Récap** conserve la surface totale ; classes attendues présentes.
- **Erreur ciblée** sans source DFCI (top-level).
- **Écriture COG** relisible.
- **`print`** résume le moteur.
- **Tuilage** : égalité au mono-bloc sur les cellules certifiées ; halo trop court →
  indéterminé.

---

## 8. Critère d'acceptation (backlog US-6.1)

**CA1** : sortie beta documentée (limites explicites, §9) et testée sur une zone
échantillon (jeu jouet + plans synthétiques). ✅

---

## 9. Limites (beta) — assumées et documentées

Le modèle **ne représente pas** :

1. le **combustible** (type de peuplement, charge, continuité horizontale/verticale) ;
2. le **vent** (direction, force) ni la dynamique du feu ;
3. la **physique de la lance** : la portée est un **paramètre unique**
   (`distance_defense_max_m`), non dérivée du débit / de la pression / du type de
   matériel ;
4. la **carrossabilité réelle** des dessertes par un camion (QUALIROAD) : elles sont
   prises telles quelles depuis la classe `dfci`.

La coupure `pente_defense_max_pct` est un **proxy grossier** d'atteignabilité. Ces
sorties valent pour une **première hiérarchisation** du territoire, pas pour du
dimensionnement opérationnel.

---

## 10. Décisions figées (2026-07-12)

1. **Modèle** : tampon au terrain (plus court chemin pondéré par la pente, plafonné),
   réutilisant le service partagé `propager_cout()` — pas de nouveau noyau.
2. **Sources** : classes de desserte configurables, défaut `"dfci"` seul.
3. **Défauts** : portée 100 m, pente d'intervention 40 % — hypothèses de travail
   explicites, non Sylvaccess.
4. **Tuilage** : tolérance de l'absence de source sous tuilage (tuile indéterminée) ;
   erreur au top-level. Garantie mono-bloc sur cellules certifiées.
5. **Beta** : limites §9 documentées dans la roxygen (`@section Section limites`) et
   ici. Raffinement (combustible, QUALIROAD) reporté.

---

## 11. Attribution

ForêtAccess dérive de Sylvaccess (INRAE, S. Dupire — GPL v3). Le module DFCI de
Sylvaccess n'étant pas dans les sources de référence, ce lot est une **conception
propre** cohérente avec l'architecture des moteurs terrestres, distribuée sous GPL v3.
