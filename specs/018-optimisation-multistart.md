# specs/018 — Lot 18 : Optimisation du réseau (multi-start & amélioration locale)

> **Statut** : **implémenté** — `optimiser_reseau()` / `vectoriser_reseau()` (optimisation multi-start). Cf. `PLAN.md` et `NEWS.md`. **Post-MVP desserte.**
> **Lot** : 18 (roadmap [`docs/ROADMAP-desserte.md`](../docs/ROADMAP-desserte.md)).
> **Dépend de** : Lot 16 (réseau MTAP), Lot 15 (solveur de tracé).
> **ADR liés** : ADR-001 (Rust — `rayon`), ADR-006 (non-régression).
> **Attribution** : métaheuristiques standard de la littérature desserte (Akay 2004 — recuit
> simulé, réduction ~25 % du coût ; ACO — Contreras/Chung). Voir §8.
> **Note** : lot **optionnel**, activé si la qualité du glouton (Lot 16) est jugée insuffisante.

---

## 1. Contexte

Le découpage MTAP→STAP séquentiel (Lot 16, glouton) ne garantit **aucune** optimalité globale :
l'ordre d'insertion des cibles change fortement le réseau. La littérature montre des gains
typiques de ~25 % en passant du glouton à une métaheuristique (recuit simulé, Akay 2004).

Ce lot ajoute une couche d'optimisation **au-dessus** du Lot 16, sans le remplacer : le glouton
reste la baseline rapide, le mode Steiner la borne de qualité, et ce lot cherche à faire mieux
par exploration. C'est du calcul massivement parallèle (chaque essai est indépendant) →
**`rayon`**.

---

## 2. Périmètre

### Dans le périmètre

- **Multi-start** : lancer le réseau glouton (Lot 16) sous **K ordres d'insertion** perturbés
  (permutations, graines fixées), retenir le réseau de moindre coût. Parallèle (`rayon`).
- **Recuit simulé sur l'ordre** : explorer l'espace des ordres d'insertion par perturbations
  acceptées/refusées selon un schéma de température, avec le coût total du réseau comme énergie.
- **Amélioration locale « rip-up & reroute »** : retirer un chemin du réseau, re-router sa cible
  avec le reste du réseau à coût ~0, garder si le coût baisse.

### Hors périmètre

- Le **tracé** (Lot 15) et la **construction** de base (Lot 16), réutilisés tels quels.
- L'optimisation **exacte** (MIP/Steiner exact) : hors budget calcul à l'échelle raster.
- Toute nouvelle contrainte géométrique (héritée du Lot 15).

---

## 3. Entrées / sorties

### Entrées

- Tous les intrants du Lot 16 (coût, parcelles, desserte existante, paramètres géométriques).
- `strategie` : `"multistart" | "recuit" | "riprute"`.
- `budget` : nombre d'essais / itérations, température initiale (recuit), graine.

### Sorties

Un `foretaccess_reseau` (même type que Lot 16) — le **meilleur** réseau trouvé — enrichi d'un
journal d'optimisation (coût par essai, courbe de convergence).

---

## 4. Algorithme

### 4.1 Multi-start (parallèle)

```
essais <- permutations perturbées de l'ordre (K graines)
reseaux <- rayon::par_map(essais, |ordre| reseau_glouton(ordre))   # Lot 16, en parallèle
retenir argmin(cout_total(reseaux))
```

### 4.2 Recuit simulé sur l'ordre

Énergie = coût total du réseau. Voisin = échange/décalage dans l'ordre d'insertion. Acceptation
Metropolis (`exp(-Δ/T)`), refroidissement géométrique. Retour du meilleur rencontré.

### 4.3 Rip-up & reroute (amélioration locale)

Pour chaque cible (ou un échantillon) : retirer son chemin, remettre le reste du réseau à coût
~0, re-router (Lot 15), accepter si le coût total baisse. Répéter jusqu'à stabilité.

---

## 5. Critères d'acceptation

- **CA-18.1** — Le meilleur réseau trouvé a un coût **≤** au glouton simple du Lot 16 (jamais pire).
- **CA-18.2** — Reproductibilité à graine fixée (multi-start et recuit déterministes).
- **CA-18.3** — Le multi-start **scale** : speedup mesuré avec `rayon` vs séquentiel.
- **CA-18.4** — La courbe de convergence du recuit est **monotone décroissante** sur le meilleur
  rencontré.
- **CA-18.5** — Le réseau final reste **valide** (toutes parcelles desservies, connexité —
  reprise des CA du Lot 16).

---

## 6. Tests

- `testthat` : gain ≥ 0 vs glouton (CA-18.1) sur cas test ; reproductibilité (CA-18.2).
- `cargo test` : parallélisme correct (résultat identique séquentiel/parallèle à ordre égal).
- Micro-benchmark : speedup `rayon`.

---

## 7. Definition of Done (Lot 18)

- [ ] Les trois stratégies livrées ; sortie `foretaccess_reseau` + journal.
- [ ] CA-18.1 à CA-18.5 couverts (`testthat` + `cargo test`).
- [ ] Speedup `rayon` documenté ; `Cargo.lock` versionné.
- [ ] `R CMD check` OK ; chaînes ASCII ; `lintr` 0 ; doc roxygen ; `NEWS.md` ; `PLAN.md`.
- [ ] Branche dédiée + PR ; commits atomiques ; release proposée `v0.17.0`.

---

## 8. Attribution

Métaheuristiques standard du domaine : recuit simulé pour la desserte forestière (**Akay 2004**,
*Minimizing total costs of forest roads…*), colonies de fourmis (**Contreras & Chung**), sur la
base MTAP→STAP de **ForestRoadNetwork** (Klemet, GPL v3). Implémentation propre.
ForêtAccess est distribué sous GPL v3.
