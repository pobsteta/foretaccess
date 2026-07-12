# specs/009 — Lot 9 : Documentation & publication

> **Statut** : **validé** (décisions §7 du 2026-07-12).
> **Lot** : 9 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 9 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md)). **Exigence** : DoD produit
> ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : tous les lots fonctionnels (0–8) — la doc les met en scène.
> **Clôt** : le périmètre v1 du produit (Lots 0–5, 7–9 « faits », DFCI Lot 6 beta).

---

## 1. Contexte

Les moteurs, le câble, l'agrégation et le stockage sont livrés (Lots 0–8). Le Lot 9
rend le paquet **utilisable par un tiers** : un exemple reproductible de bout en
bout, un README à jour, et un site de référence (pkgdown) organisé.

Le « CLI » du brief (hérité de l'ère Python) se lit, côté paquet R, comme une
**vignette** exécutable + les pages d'aide : l'usage réel passe par des appels R
(`Rscript` ou session), pas par une commande shell dédiée.

---

## 2. Périmètre

### Dans le périmètre

- Une **vignette** `foretaccess` : le pipeline complet sur le jeu jouet
  (prétraitement → moteurs → câble → agrégation → persistance), **exécutée** à la
  compilation (donc testée par `R CMD check`).
- Le **README** à jour : démarrage rapide, statut réel, renvoi à la vignette et à
  la roadmap, attribution Sylvaccess (GPL v3).
- Le **`_pkgdown.yml`** : index de référence groupé par thème/lot + article.
- `NEWS.md` à jour (déjà tenu lot par lot) ; version taguée par `release.yml`.

### Hors périmètre

- Un exécutable/CLI shell dédié : non nécessaire pour un paquet R.
- Un `CHANGELOG.md` séparé : `NEWS.md` en tient lieu (convention R).

---

## 3. Livrables

| Livrable | Fichier |
|---|---|
| Vignette bout-en-bout | `vignettes/foretaccess.Rmd` |
| README | `README.md` (section *Démarrage rapide*) |
| Index pkgdown | `_pkgdown.yml` (`reference`, `articles`) |
| Dépendances vignette | `DESCRIPTION` : `Suggests: knitr, rmarkdown` + `VignetteBuilder: knitr` |

---

## 4. Vignette

Le fil conducteur, sur `inst/extdata/toy/` (exécution < 2 s) :

1. **Configuration** — `foretaccess_config()`, surcharge d'une clé.
2. **Prétraitement** — `preprocess()`.
3. **Moteurs terrestres** — `skidder()`, `porteur()` + `recap`.
4. **Camion DFCI** — `camion_dfci()` (renvoi aux limites beta).
5. **Câble** — `potentiel_cable()` puis `selectionner_lignes()`.
6. **Agrégation zonale** — `agreger_zones()` sur deux zones.
7. **Persistance** — `storage_gpkg()` + `sb_write_layer()` ; variante PostGIS en
   `eval = FALSE`.
8. **Passage à l'échelle** — mention de `traiter_par_tuiles()`.
9. **Attribution** — Sylvaccess, GPL v3.

La vignette est **reproductible** : chaque bloc s'exécute à la compilation, ce qui
en fait aussi un test d'intégration du pipeline complet.

---

## 5. Critères d'acceptation (backlog)

- **US-9.1 CA1** : README + doc d'usage à jour ; **exemple reproductible de bout en
  bout** sur le jouet (la vignette). ✅
- **US-9.2 CA1** : `NEWS.md` à jour ; version taguée (via `release.yml`) ;
  **attribution Sylvaccess** présente (README, `CITATION.cff`, licence GPL v3). ✅

---

## 6. Vérification

- `R CMD check --as-cran` **compile la vignette** : si le pipeline casse, le check
  échoue — la vignette est donc auto-vérifiante.
- Le workflow **pkgdown** construit le site ; l'index de référence liste **tous**
  les exports (aucun topic manquant).

---

## 7. Décisions figées (2026-07-12)

1. **Vignette exécutée** (pas `eval = FALSE`) : elle documente *et* teste le
   pipeline. Le jouet garantit un temps de compilation négligeable.
2. **Pas de CLI shell** : l'usage est R-natif ; la vignette + les pages d'aide
   couvrent la DoD « doc d'usage ».
3. **`NEWS.md` = changelog** : pas de `CHANGELOG.md` séparé (convention R).
4. **v1.0.0** : après ce lot, le périmètre v1 (Lots 0–5, 7–9 + DFCI beta) est
   atteint. Le passage `1.0.0` est un **bump majeur** — soumis à confirmation
   explicite (règle `CLAUDE.md`), non posé d'office par ce lot (release `v0.10.0`).

---

## 8. Attribution

ForêtAccess dérive de Sylvaccess (INRAE, S. Dupire — GPL v3), cité dans le README
et `CITATION.cff`. Distribué sous **GPL v3**.
