# ForêtAccess — Brief projet

> Document d'amorçage destiné à **Claude Code**, dans un workflow *spec-driven* / agile
> par lots (mêmes conventions que le projet Nemeton : `specs/0XX-*.md`, ADR, lots =
> sprints, critères d'acceptation, Definition of Done).
>
> **Stack** : **R** (orchestration + moteurs terrestres) + **Rust** (noyau câble, via
> `extendr`/`rextendr`). Cohérent avec l'écosystème Nemeton (R/Shiny/golem, PostGIS).
> **Statut** : brief initial, à transformer en specs + backlog + roadmap.
> **Dépôt cible** : `github.com/pobsteta/foretaccess`
> **Licence** : GPL v3 (dérivé de Sylvaccess © S. Dupire / INRAE — voir §1).

---

## 0. Mission Claude Code (comment utiliser ce brief)

À partir de ce brief, tu dois produire, **avant tout code** :

1. Un **PRD léger** (`docs/PRD.md`) : objectifs, périmètre MVP, exigences fonctionnelles
   et non-fonctionnelles, hors-périmètre.
2. Un **backlog** structuré en **epics → user stories → critères d'acceptation**,
   dérivé du périmètre fonctionnel (§4) et du lotissement (§10).
3. Une **roadmap par lots** (`docs/ROADMAP.md`) reprenant le lotissement §10, chaque
   lot devenant un fichier `specs/0XX-<nom>.md`.
4. Les **ADR** listés en §5 (`docs/adr/ADR-00X-*.md`), une décision par fichier.
5. Le **scaffolding** du package R (§11) une fois les specs du Lot 0 validées.

Règles de travail (spec-driven) :

- **Une spec avant un lot.** Ne pas coder un lot tant que sa `specs/0XX` n'est pas
  rédigée et validée. Chaque spec contient : contexte, périmètre, entrées/sorties,
  algorithme, critères d'acceptation, tests, risques.
- **Tests d'abord** pour tout ce qui reproduit Sylvaccess : mettre en place le harnais
  de **non-régression** (§7) au Lot 0 (avec `testthat`), puis chaque moteur est validé
  contre les sorties de Sylvaccess v3.6 avant d'être considéré « fait ».
- **Trancher les questions ouvertes (§9) avec l'utilisateur** avant de lancer le lot
  concerné ; ne pas décider seul sur ces points.
- **Petits incréments livrables.** Chaque lot se termine par : code + tests verts +
  doc (`roxygen2`) + entrée `NEWS.md` + éventuel ADR. Respecter la DoD (§12).
- Proposer les commandes `git` (branche par lot, commits atomiques, PR par lot).

---

## 1. Contexte & vision

**ForêtAccess** est une réimplémentation moderne du modèle **Sylvaccess** (INRAE –
Sylvain Dupire, v3.6 2025, GPL v3, DOI `10.15454/JUBESS`), qui cartographie
automatiquement l'accessibilité des forêts selon le mode d'exploitation.

Le code Sylvaccess actuel (Python 3 + Cython, hérité de Python 2.7) est **monolithique
et couplé à une UI PyQt** : logique métier lue directement depuis l'interface, ~80
variables globales, 59 `except:` nus, I/O raster « à la main ». Cela empêche l'usage en
CLI/batch, la réutilisation et les tests automatisés.

**Vision ForêtAccess** : un **cœur métier pur, découplé de toute UI**, testable,
performant, réutilisable (fonctions de package R + pipeline), avec **sorties dans une
base spatiale** (PostGIS / GeoPackage) directement exploitable — y compris depuis
Nemeton (partage d'utilitaires et de la même base PostGIS, consommation possible dans un
onglet Shiny).

**Filiation & licence** : travail dérivé de Sylvaccess (GPL v3), reste sous **GPL v3**.
Toute diffusion doit citer :
- Dupire S., Bourrier F., Monnet J.-M., Berger F. (2015). *Sylvaccess : un modèle pour
  cartographier automatiquement l'accessibilité des forêts.* Revue Forestière Française.
- Dupire S., Bourrier F., Berger F. (2015). *Predicting load path and tensile forces
  during cable yarding operations on steep terrain.* J. of Forest Research,
  DOI `10.1007/s10310-015-0503-4`.

---

## 2. Objectif du développement

Cartographier l'accessibilité pour **4 modes d'exploitation** :

| Moteur | But | Statut cible |
|---|---|---|
| **Skidder** (tracteur/débusqueur) | distances de débardage, zones inaccessibles | MVP |
| **Porteur** | idem (sans distance de treuillage) | MVP |
| **Câble** (câble-mât) | potentiel câble d'un massif, aide à la planification | MVP |
| **Camion DFCI** | zone défendable depuis les dessertes (défense incendie) | **beta** |

Choix structurants :
- **Cœur métier pur** (fonctions prenant config + objets `terra`/`sf`, sans dépendance UI).
- **Orchestration en R** ; **noyau câble en Rust** (le point chaud, ~60 M lignes,
  ~1 ms/ligne dans l'implémentation actuelle), appelé depuis R via **`extendr`**.
- **Entrées** : données nationales IGN (MNT 5 m, BD Forêt V2/V3, BD Topo).
- **Sorties** : **PostGIS (défaut) / GeoPackage** pour les vecteurs (`sf`), **GeoTIFF/COG**
  pour les rasters (`terra`), derrière une interface de stockage commune.
- **Échelle** : du massif au national, via **tuilage** et parallélisme.

---

## 3. Architecture cible

Schéma complet (vectoriel, versionnable) : [`docs/architecture.svg`](architecture.svg).

Version Mermaid (rendue sur GitHub) :

```mermaid
flowchart TD
    A["Données nationales IGN<br/><small>MNT 5 m · BD Forêt V2/V3 · BD Topo · parcellaire</small>"]
    B["Prétraitement commun (R · terra/sf)<br/><small>pente, exposition, rasterisation, masques</small>"]
    SK["Skidder<br/><small>50 / 100 m</small>"]
    PO["Porteur<br/><small>travers 15 %</small>"]
    DF["Camion DFCI<br/><small>beta · zone défendable</small>"]
    CA["Câble<br/><small>360° / pixel</small>"]
    LC["Propagation depuis la desserte<br/><small>R · leastcostpath / gdistance</small>"]
    RS["Noyau Rust — CableHelp<br/><small>extendr · rayon</small>"]
    SE["Sélection lignes câble<br/><small>IPC · volume · supports</small>"]
    OUT["Base spatiale — foretaccess<br/><small>PostGIS (défaut) / GeoPackage · rasters COG</small>"]

    A --> B
    B --> SK & PO & DF & CA
    SK --> LC
    PO --> LC
    DF --> LC
    CA --> RS
    RS --> SE
    LC --> OUT
    SE --> OUT

    class RS kernel
    classDef kernel fill:#FAECE7,stroke:#993C1D,stroke-width:2px,color:#712B13;
```

Lecture par couches :
1. **Données** : couches IGN homogènes au niveau national (parcellaire = évolution future,
   cf. projet DESSOPT).
2. **Prétraitement commun** (R/`terra`,`sf`) : pente/exposition depuis le MNT, rasterisation
   des vecteurs à la résolution du MNT, masques d'obstacles, exclusion des pentes > seuil
   d'abattage.
3. **Moteurs** : 4 modules. Skidder/Porteur/DFCI partagent un **service de propagation
   depuis la desserte** (coût-distance / least-cost, `leastcostpath`/`gdistance`). Le
   **Câble** appelle le **noyau Rust** (via `extendr`) puis la **sélection multicritère**.
4. **Sorties** : écriture dans la base spatiale (`sf` → PostGIS/GPKG) + rasters COG (`terra`).

---

## 4. Périmètre fonctionnel (→ epics)

### 4.1 Prétraitement (commun)
- Entrées : MNT (raster), desserte (polylignes classées : route forestière / piste / DFCI),
  forêt (polygones), obstacles complets (vecteur), obstacles partiels (skidder), volume sur
  pied (raster, optionnel).
- Traitements : validation des entrées (CRS commun, alignement grille sur MNT, champs
  attributaires requis), pente %, exposition, rasterisation, masques d'obstacles, exclusion
  pente > 100 % (abattage manuel impossible).
- Sortie : jeu de rasters intermédiaires alignés + masques.

### 4.2 Skidder
- Règle : pente ≤ 30 % → circulation libre du skidder ; pente > 30 % → treuillage depuis
  desserte (50 m amont / 100 m aval par défaut) avec bascule vers distance max au-delà de
  certaines pentes (voir §6).
- Sorties (rasters) : zone accessible, zone parcourable par l'engin, non accessible, distance
  de treuillage, distances de traînage (piste + forêt), distance totale de débardage, trajet
  optimal vers place de dépôt. + tableau récapitulatif surfaces/volumes par classe.

### 4.3 Porteur
- Règle : pente en travers ≤ 15 % → circulation libre ; sinon portage en ligne droite dans
  un cône d'azimuts respectant la pente en travers max, avec pentes en long ≤ 30 % (montée)
  / ≤ 25 % (descente), portée ≤ 300 m. Portée de grue 8 m.
- Sorties : idem skidder **sans** distance de treuillage.

### 4.4 Câble (+ sélection)
- Pour chaque pixel de route : 360 lignes (pas 1°) de longueur ≤ longueur max du câble.
  Test de faisabilité : hauteur du câble porteur ∈ [4 m, 30 m] et tension ≤ rupture / coeff.
  sécurité (modèle mécanique **CableHelp** : caténaire élastique + frottement aux supports).
  Optimisation du nombre/placement des supports intermédiaires (0…N), raccourcissement,
  longueur ≥ min.
- Sorties : **base des lignes techniquement faisables** (table géométrique), raster des zones
  accessibles, tableau récapitulatif.
- **Sélection multicritère** : max surface, min supports, sens (amont/aval), longueur, max
  volume, max IPC (= volume / longueur).

### 4.5 Camion DFCI (beta)
- Cartographie de la **zone défendable** depuis les dessertes DFCI identifiées.
- À stabiliser (cf. projet QUALIROAD). Peut être un lot ultérieur au MVP (cf. §9).

---

## 5. Décisions techniques (→ ADR, un fichier par décision)

| ADR | Décision | Résumé |
|---|---|---|
| ADR-001 | **Langages** | Orchestration & moteurs terrestres en **R** ; **noyau câble en Rust** exposé via **`extendr` / `rextendr`**, parallélisme **`rayon`**. Libs R : `terra` (raster), `sf` (vecteur), `leastcostpath`/`gdistance` (least-cost), `DBI`/`RPostgres`. |
| ADR-002 | **Stockage** | Interface commune ; deux back-ends : **PostGIS** (défaut, `DBI`+`RPostgres`, `sf::st_write`) et **GeoPackage** (`sf`). Rasters en **GeoTIFF/COG** sur disque via `terra` (pas en base). |
| ADR-003 | **Configuration** | Config validée (ex. `config` + schéma, ou liste typée avec assertions) ; **valeurs par défaut = Sylvaccess v3.6** (§6), pas celles de l'article 2015. |
| ADR-004 | **Découplage** | Cœur pur sans UI ; fonctions `preproc_*`, `skidder_*`, `porteur_*`, `dfci_*`, `cable_*` ; I/O et orchestration séparées ; pas d'état global. |
| ADR-005 | **Passage à l'échelle** | Tuilage du territoire + parallélisme (`future`/`furrr`, `targets`) ; hors-mémoire via `terra` ; élagage spatial (forêt d'intérêt / voisinage desserte). |
| ADR-006 | **Validation** | Tests de **non-régression** (`testthat`) contre Sylvaccess v3.6 comme oracle (§7). |
| ADR-007 | **Packaging & CI** | **Package R** (structure golem-like ou package classique) intégrant la crate Rust via `rextendr` (`src/rust/`) ; `DESCRIPTION`/`NAMESPACE`, `roxygen2` ; CI : `R CMD check`, `testthat`, `lintr`, `cargo test`/`clippy`, build sur plusieurs OS. |

---

## 6. Paramètres métier de référence (Sylvaccess v3.6)

> Ces défauts (RdV Experts 2026, v3.6) **diffèrent de l'article de 2015** ; ce sont
> ceux à encoder dans la config (ADR-003). Deltas notables signalés.

**Skidder**
- Distance max débusquage amont de la desserte : **50 m**
- Distance max débusquage aval de la desserte : **100 m** *(article : 150 m)*
- Pente au-delà de laquelle débusquage amont = distance max : **75 %**
- Pente au-delà de laquelle débusquage aval = distance max : **20 %**
- Distance max parcourable hors forêt et hors desserte : **50 m** *(nouveau)*
- Pente max pour parcourir le terrain en skidder : **30 %** *(article : 25 %)*
- Pente max pour l'abattage manuel : **100 %** *(article : 110 %)*

**Porteur**
- Pente en travers max : **15 %**
- Pente max en remontant les bois : **30 %**
- Pente max en descendant les bois : **25 %**
- Portée de la grue : **8 m** *(nouveau)*
- Distance max quand pente > pente en travers max : **300 m**
- Distance max parcourable hors forêt et hors desserte : **200 m** *(nouveau)*
- Pente max pour l'abattage manuel : **100 %**

**Câble (défauts par type de matériel)** — hauteur mât, longueur/diamètre/masse
linéaire/tension de rupture du câble porteur, nombre max de supports, hauteur câble ∈
[4 m, 30 m], coeff. de sécurité. Reprendre les tableaux 1 & 2 de l'article + config v3.6.

---

## 7. Spécifié vs à récupérer

**Entièrement spécifié** (article + deck + ce brief) : entrées, prétraitement, règles
skidder/porteur, procédure câble (360°/pixel, seuils hauteur/tension, échelle des supports,
raccourcissement), critères de sélection, paramètres par défaut v3.6.

**À récupérer depuis le code source Sylvaccess** (GPL v3, dispo sur `forge.inrae.fr` ;
module Cython `sylvaccess_cython3.pyx`) — car l'article ne donne que les erreurs de
validation :
- **Équations mécaniques CableHelp** : caténaire élastique (`asinh`), tension vs position
  du chariot, frottement aux supports (`frottement`, `mainline`), optimisation des pylônes
  (`OptPyl_Up/Down`, variantes hauteur variable). Cf. aussi Dupire et al. 2015 (JFR). À
  traduire en Rust dans la crate `cablehelp`.
- **Fonction de coût** des plus courts chemins (`calcul_distance_de_cout`) pour skidder/porteur
  → à reproduire côté R (`leastcostpath`/`gdistance` avec la même fonction de conductance).
- **« Unités de vidange optimales »** et le pas de recherche supports / raccourcissement.

**Oracle de non-régression** : générer, avec Sylvaccess v3.6, les sorties sur un petit jeu
de données jouet (MNT synthétique + desserte + forêt) et sur quelques profils câble ; les
figer comme références (`inst/extdata/`). La comparaison porte sur les **sorties** (rasters,
valeurs), donc le changement de langage hôte (Python → R) n'affecte pas la validation.
Cibles : erreur ≤ 0,1 % sur la trajectoire de charge et ≤ 1,5 % sur la tension.

---

## 8. Exigences non-fonctionnelles

- **Performance** : moteurs terrestres rapides (référence v3.6 : PNR Morvan 3290 km² →
  ~18 min skidder / ~1h23 porteur au 5 m) ; câble = point chaud → noyau Rust + parallélisme
  (objectif : diviser fortement les temps actuels ; câble ~800 ha/20 km ≈ 20 min).
- **Reproductibilité** : `renv` pour les dépendances R, toolchain Rust épinglée, données
  d'exemple versionnées, seeds si aléatoire.
- **Qualité** : `R CMD check` sans NOTE/ WARNING bloquant, `testthat`, `lintr` (Python-free) ;
  `clippy` + `cargo test` pour la crate ; couverture (`covr`) sur le cœur.
- **Observabilité** : messages via `cli`/`logger` (niveaux) plutôt que `print` ; journal
  d'erreurs structuré.
- **i18n** : messages FR/EN externalisés (ex. `inst/translations` / clés), pas de branchement
  `if (language == ...)` disséminé.
- **Robustesse I/O** : `withr`/`on.exit()` pour la fermeture des ressources, `fs`/`file.path`,
  création de dossiers idempotente, gestion d'erreurs explicite (pas de `try()` silencieux).

---

## 9. Questions ouvertes (à trancher avec l'utilisateur avant lancement)

1. **Backend par défaut** : PostGIS (proposé, cohérent avec Nemeton) ou GeoPackage ?
2. **DFCI beta** dans le **MVP** ou lot post-MVP ?
3. **Least-cost** : rester en R (`leastcostpath`/`gdistance`) ou porter aussi en Rust à terme
   pour les grandes emprises ?
4. **Récupération du `.pyx`** comme oracle et base de portage (GPL v3 → compatible) : OK ?
5. **Parcellaire (DESSOPT)** : hors périmètre v1 (simple couche d'entrée future) ?
6. **Forme du livrable** : package R unique `foretaccess` + pipeline `targets` intégré, ou
   package (cœur) + dépôt de pipeline séparé ?
7. **Schéma PostGIS** : base dédiée `foretaccess` avec schéma par run/massif, ou table unique
   + colonne `run_id` (et éventuel partage avec la base Nemeton) ?

---

## 10. Lotissement (roadmap agile — chaque lot → `specs/0XX` + ADR + tests)

| Lot | Nom | Livrables | Critères d'acceptation |
|---|---|---|---|
| **0** | Fondations | Squelette package R (`DESCRIPTION`, `NAMESPACE`, `R/`, `tests/testthat/`), crate Rust via `rextendr` (`src/rust/`, build OK), config (défauts v3.6), interface de stockage (postgis+gpkg), `renv`, CI, **jeu de données jouet** + harnais de non-régression. ADR-001/002/003/004/007. | `devtools::load_all()` + `rextendr::document()` OK ; `R CMD check` vert ; écriture/lecture d'une couche test en PostGIS **et** GPKG ; `testthat` de base passe. |
| **1** | I/O & prétraitement | Lecture IGN (`terra`/`sf`), validation entrées, alignement grille, pente/exposition, rasterisation, masques, exclusion pente. `specs/001`. | Sur le jeu jouet : rasters pente/expo et masques conformes à l'oracle (tolérance définie) ; erreurs d'entrée explicites. |
| **2** | Moteur Skidder | Règles v3.6 + service least-cost + sorties rasters/tableau. `specs/002`. Non-régression. | Distances (treuillage, traînage, totale) et zones vs Sylvaccess v3.6 sous tolérance ; tableau récap correct. |
| **3** | Moteur Porteur | Cône d'azimuts, pentes long/travers, portée. `specs/003`. Non-régression. | Sorties conformes à v3.6 (hors treuillage). |
| **4** | Noyau Câble (Rust) | Crate `cablehelp` (CableHelp + faisabilité + optimisation supports) exposée via `extendr` ; balayage 360°/pixel parallèle. `specs/004`, ADR-005. Non-régression profils. | Sur N profils de référence : trajectoire ≤ 0,1 %, tension ≤ 1,5 % ; base des lignes faisables produite ; speedup mesuré vs mono-thread. |
| **5** | Sélection lignes câble | Sélection multicritère (surface, supports, sens, longueur, volume, IPC). `specs/005`. | Sélection reproductible vs v3.6 sur jeu test ; requêtable en base. |
| **6** | Camion DFCI (beta) | Zone défendable depuis desserte DFCI. `specs/006`. | Sortie beta documentée + testée sur zone échantillon (selon décision §9.2). |
| **7** | Passage à l'échelle | Tuilage + parallélisme (`targets`/`furrr`) + sorties COG. `specs/007`, ADR-005. | Traitement d'un massif complet en tuiles, résultat identique au traitement mono-bloc (raccords corrects). |
| **8** | Base spatiale & agrégation | Schéma PostGIS (DDL), export GPKG, agrégation zonale SQL (massif/parcelle/commune). `specs/008`, ADR-002. | Écriture idempotente ; index spatiaux ; requêtes d'agrégation validées. |
| **9** | Doc & publication | README, vignette d'usage, exemples, `NEWS.md`, `pkgdown`. | Doc à jour ; `pkgdown` build ; exemple reproductible de bout en bout ; version taguée. |

---

## 11. Structure du dépôt proposée (package R + crate Rust via rextendr)

```
foretaccess/
├─ DESCRIPTION                  # métadonnées package R, deps, SystemRequirements: Cargo
├─ NAMESPACE                    # généré par roxygen2
├─ LICENSE                      # GPL v3
├─ README.md
├─ NEWS.md
├─ renv.lock                    # dépendances R épinglées
├─ docs/
│  ├─ foretaccess-brief.md      # ce document
│  ├─ architecture.svg          # schéma cible
│  ├─ PRD.md                    # (à générer)
│  ├─ ROADMAP.md                # (à générer)
│  └─ adr/                      # ADR-001…007
├─ specs/                       # 000-fondations.md, 001-pretraitement.md, …
├─ R/
│  ├─ config.R                  # défauts v3.6, validation
│  ├─ io_read.R                 # lecture IGN (terra/sf)
│  ├─ storage.R                 # backends PostGIS + GeoPackage + COG
│  ├─ preprocessing.R           # pente, expo, rasterisation, masques
│  ├─ routing.R                 # service least-cost partagé
│  ├─ engine_skidder.R
│  ├─ engine_porteur.R
│  ├─ engine_dfci.R
│  ├─ engine_cable.R
│  ├─ selection.R               # sélection multicritère des lignes câble
│  └─ pipeline.R                # orchestration
├─ src/
│  ├─ rust/                     # crate cablehelp (extendr)
│  │  ├─ Cargo.toml
│  │  └─ src/lib.rs             # mécanique CableHelp + balayage
│  ├─ Makevars(.win)           # généré par rextendr
│  └─ entrypoint.c
├─ tests/testthat/              # tests unitaires + non-régression
├─ inst/
│  └─ extdata/                  # jeu jouet + oracles Sylvaccess v3.6
├─ vignettes/
├─ _targets.R                   # pipeline de tuilage / national
└─ .github/workflows/           # R CMD check + cargo test
```

---

## 12. Definition of Done (par lot)

- [ ] Spec `specs/0XX` rédigée et validée ; ADR associé si décision structurante.
- [ ] Code + tests `testthat` ; **non-régression verte** pour tout ce qui reproduit v3.6.
- [ ] `R CMD check`, `lintr`, `testthat` OK ; `clippy`/`cargo test` OK pour la crate.
- [ ] Gestion d'erreurs explicite ; ressources fermées ; messages via `cli` (pas de `print`).
- [ ] Doc `roxygen2` à jour + entrée `NEWS.md`.
- [ ] Branche dédiée + PR + revue ; commits atomiques.

---

## 13. Références

- Sylvaccess v3.6 (INRAE, S. Dupire) — GPL v3, DOI `10.15454/JUBESS`,
  dépôt `forge.inrae.fr/sylvain.dupire/sylvaccess`.
- Dupire et al. 2015, *Revue Forestière Française* n°2015-2.
- Dupire et al. 2015, *J. of Forest Research*, DOI `10.1007/s10310-015-0503-4`.
- RdV Experts « De nouvelles cartes sur l'accessibilité des forêts » (IGN/INRAE/ADEME,
  19 mai 2026) — données nationales, module DFCI, projets DESSOPT & QUALIROAD.
- `extendr`/`rextendr` (pont Rust↔R), `terra`, `sf`, `leastcostpath`, `gdistance`,
  `DBI`/`RPostgres` (PostGIS), `targets`/`furrr`, `testthat`.
```
