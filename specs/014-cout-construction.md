# specs/014 — Lot 14 : Surface de coût de construction de desserte

> **Statut** : **implémenté** — `surface_cout_construction()` (épic conception de desserte). Cf. `PLAN.md` et `NEWS.md`.
> **Lot** : 14 (roadmap [`docs/ROADMAP-desserte.md`](../docs/ROADMAP-desserte.md)).
> **Épic desserte** : conception de nouvelles dessertes (au-delà de l'accessibilité).
> **Dépend de** : Lot 1 (`preprocess()` : MNT aligné, pente/exposition, masques d'obstacles),
> Lot 10 (acquisition AOI — à étendre à l'hydrographie, cf. §7).
> **Prépare** : Lot 15 (solveur de tracé A\*), Lot 16 (réseau MTAP).
> **ADR liés** : ADR-003 (config/défauts validés), ADR-004 (découplage), ADR-008 (graphe
> étendu — voir [`docs/adr/ADR-008-graphe-etendu.md`](../docs/adr/ADR-008-graphe-etendu.md)).
> **Attribution** : la structure de coût s'inspire du « Cost Raster Creator » de
> **ForestRoadNetwork** (Klemet, GPL v3) et des paramètres de coût de construction de la
> littérature (Weintraub/PLANEX, Chung-Sessions). Aucune réutilisation de code : formulation
> propre en R.

---

## 1. Contexte

Les moteurs actuels (skidder, porteur, câble, DFCI) répondent à *« où peut-on exploiter
avec le matériel M ? »*. La conception de desserte répond à une question différente :
*« par où faire passer une **nouvelle** route/piste au moindre coût de construction ? »*.

Le coût pertinent n'est plus un facteur d'allongement de déplacement (`ponderation_pente`,
Lot 2, isotrope, sans unité) mais un **coût monétaire de construction au mètre** : terrasser
une pente forte coûte cher, franchir un cours d'eau demande une buse, franchir une rivière
un pont, certains sols sont plus onéreux, certaines zones sont interdites.

Ce lot produit la **surface de coût de construction** que le solveur de tracé (Lot 15)
propagera. Il est volontairement séparé du solveur : le coût est du calcul raster R pur,
sans dépendance Rust.

---

## 2. Périmètre

### Dans le périmètre

- Une fonction `surface_cout_construction(pre, config)` produisant un `SpatRaster` de coût
  linéaire (€/m projeté, ou unité cohérente) par cellule, sur la grille du MNT.
- La prise en compte, quand les couches sont disponibles, de : coût de base linéaire, surcoût
  de pente (par classes, déblai/remblai), surcoût de sol, franchissements ponctuels (pont sur
  plan d'eau, buse sur cours d'eau), surcoûts additionnels (réglementaire, habitats).
- Un raster de **franchissabilité** (`NA` = infranchissable : zones interdites, obstacles
  complets) distinct du coût.
- La configuration `config$desserte$cout` (barème de classes, coûts unitaires), validée.

### Hors périmètre

- La **contrainte de pente en long** (min/max) et les **pénalités de direction/pente** :
  elles vivent dans le solveur (Lot 15), car elles dépendent du chemin, pas de la cellule.
- Le **profil déblai/remblai** fin (écart altitude tracé/terrain) : Lot 15 (`check_profile`).
- Toute **notion de réseau** (ordre, réutilisation) : Lot 16.

---

## 3. Entrées / sorties

### Entrées

- `pre` : objet `foretaccess_preprocessing` (Lot 1) — MNT, pente (%), masques d'obstacles.
- Couches optionnelles (rasterisées sur la grille du MNT) :
  - hydrographie linéaire (cours d'eau → buses) et surfacique (plans d'eau/rivières → ponts) ;
  - sols (classes de surcoût) ;
  - foncier / zones interdites (→ franchissabilité `NA`) ;
  - surcoûts additionnels libres (€/m).
- `config$desserte$cout`.

### Sorties

Un objet `foretaccess_cout_construction` : liste de deux `SpatRaster` alignés sur le MNT —
`cout` (€/m, `NA` hors zone franchissable) et `franchissable` (logique). Directement
consommable par le solveur du Lot 15.

---

## 4. Algorithme

Le coût d'une cellule est **additif**, comme dans ForestRoadNetwork :

```
cout = cout_base
     + surcout_pente(pente_pct)          # barème par classes (déblai/remblai)
     + surcout_sol(classe_sol)           # table de correspondance
     + cout_pont * masque_plan_eau       # franchissement surfacique
     + cout_buse * densite_cours_eau     # franchissement linéaire
     + surcout_additionnel               # €/m libre
```

- **Coût de base** : coût de construction de la plus petite catégorie de desserte sur terrain
  plat, meilleur sol, sur la longueur d'une cellule (paramètre obligatoire, seul requis).
- **Surcoût de pente** : barème `[borne_basse, borne_haute) → surcout`, estimable par régression
  linéaire sur des coûts réels (avec le bon niveau de référence dans l'intercept = coût de base).
- **Franchissements** : un pont/une buse est un coût **ponctuel** ramené à la cellule
  (coût moyen d'ouvrage sur une cellule de la taille de la grille).
- **Interdits** : les zones foncières exclues et les obstacles complets passent `NA` dans
  `franchissable` ; le solveur ne les traversera pas.

L'unité recommandée est **monétaire** (€), pour paramétrer par des coûts réels et interpréter
les résultats du Lot 15/16. Une unité neutre (indice) reste possible si aucun coût n'est connu.

---

## 5. Critères d'acceptation

- **CA-14.1** — `surface_cout_construction(pre)` tourne avec le seul coût de base ; les couches
  optionnelles absentes n'ajoutent rien (contribution nulle), jamais d'erreur.
- **CA-14.2** — Une cellule de plan d'eau reçoit bien le coût de pont ; une cellule traversée
  par un cours d'eau, le coût de buse (proportionnel à la densité/longueur).
- **CA-14.3** — Une zone foncière interdite ou un obstacle complet est `NA` dans `franchissable`
  et non traversable.
- **CA-14.4** — Le barème de pente est appliqué par classes ; monotonie vérifiée (surcoût
  croissant avec la pente, si le barème l'est).
- **CA-14.5** — Sorties alignées sur la grille du MNT (résolution, emprise, CRS) ; cellules
  carrées (contrainte partagée avec `propager_cout`).
- **CA-14.6** — `config$desserte$cout` validée (bornes de classes croissantes, coûts ≥ 0).

---

## 6. Tests

- `testthat` sur jeu jouet : construction du coût avec/sans chaque couche optionnelle.
- Oracle : recomposition manuelle du coût attendu sur quelques cellules types
  (plat/meilleur sol, forte pente, plan d'eau, cours d'eau, interdit).
- Confrontation qualitative au « Cost Raster Creator » de ForestRoadNetwork sur son
  `Test_data/` (mêmes entrées → coûts de même forme), sans exiger l'identité numérique
  (barèmes différents).

---

## 7. Impact sur le Lot 10 (acquisition)

Le solveur de coût a besoin de l'**hydrographie**, absente du Lot 10 actuel (MNT, desserte,
forêt, obstacles OSM, cadastre). À ajouter à `acquire_inputs()` :

- cours d'eau (BD TOPO hydrographie linéaire) → couche « buses » ;
- plans d'eau/rivières larges (BD TOPO hydrographie surfacique) → couche « ponts ».

Patron identique aux autres acquisitions (config par pays, cache). Incrément **10b**.

---

## 8. Definition of Done (Lot 14)

- [ ] `surface_cout_construction()` livrée ; sortie `foretaccess_cout_construction`.
- [ ] CA-14.1 à CA-14.6 couverts par `testthat`.
- [ ] `config$desserte$cout` + `validate_config()` étendus ; défauts documentés.
- [ ] Acquisition hydrographie (10b) livrée ou explicitement reportée avec ticket.
- [ ] `R CMD check` OK ; chaînes ASCII ; `lintr` 0 ; doc roxygen ; `NEWS.md` ; `PLAN.md`.
- [ ] Branche dédiée + PR ; commits atomiques ; release proposée `v0.13.0`.

---

## 9. Attribution

La structure additive du coût dérive du « Cost Raster Creator » de **ForestRoadNetwork**
(Klemet, GPL v3). Aucune ligne de code reprise : formulation R propre. ForêtAccess est
distribué sous GPL v3.
