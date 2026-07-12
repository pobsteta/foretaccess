# ForêtAccess — Backlog (epics → user stories → critères d'acceptation)

> **Statut** : proposé — en attente de validation.
> Dérivé du périmètre fonctionnel ([`PRD.md`](PRD.md) §5) et du lotissement
> ([`ROADMAP.md`](ROADMAP.md), brief §10). Un epic ≈ un lot. Chaque user story (US) porte
> des **critères d'acceptation** vérifiables. Format : *En tant que … je veux … afin de …*.

**Conventions**
- `US-<epic>.<n>` : identifiant de story. `EF-x` : exigence fonctionnelle du PRD.
- Toute story reproduisant Sylvaccess v3.6 a un critère **non-régression** explicite.
- « Oracle » = sorties de référence figées depuis Sylvaccess v3.6 (brief §7).

---

## EPIC 0 — Fondations *(Lot 0)*
Couvre EF-9, EF-10 (socle). Objectif : socle de dépôt, config, stockage, CI, harnais de
non-régression, squelette Rust — **sans logique métier**.

### US-0.1 — Squelette de package R + crate Rust
*En tant que* développeur, *je veux* un package R installable avec une crate Rust liée par
`rextendr`, *afin de* bâtir le reste dessus.
- **CA1** : `R CMD INSTALL .` (ou `devtools::install()`) réussit.
- **CA2** : `rextendr::document()` compile la crate et génère les bindings ; une fonction
  Rust triviale (ex. `cablehelp_version()`) est appelable depuis R.
- **CA3** : `DESCRIPTION`, `NAMESPACE`, `Cargo.toml`, `src/rust/` en place ; `Cargo.lock` versionné.

### US-0.2 — Configuration métier (défauts v3.6)
*En tant qu*'utilisateur, *je veux* une config validée dont les défauts sont ceux de
Sylvaccess v3.6, *afin de* paramétrer les moteurs sans toucher au code.
- **CA1** : un objet/liste de config expose tous les paramètres du brief §6 avec **défauts v3.6**.
- **CA2** : validation au chargement (types, bornes) avec message d'erreur ciblé si invalide.
- **CA3** : chargement depuis fichier (YAML) testé ; valeurs par défaut couvertes par test.

### US-0.3 — Interface `StorageBackend` (PostGIS + GeoPackage)
*En tant que* développeur, *je veux* une interface de stockage unique à deux implémentations,
*afin d*'écrire/lire les vecteurs indifféremment en PostGIS ou GeoPackage.
- **CA1** : interface commune (write_layer / read_layer / list_layers) documentée.
- **CA2** : écriture puis relecture d'une couche test **en PostGIS** et **en GeoPackage** →
  géométries et attributs identiques (round-trip).
- **CA3** : aucun backend n'est « par défaut » ; le choix est un paramètre explicite (§9.1).

### US-0.4 — Jeu de données jouet + harnais de non-régression
*En tant que* mainteneur, *je veux* un petit jeu jouet et un harnais comparant nos sorties à
l'oracle v3.6, *afin de* garantir la fidélité dès qu'un moteur existe.
- **CA1** : jeu jouet versionné (MNT synthétique + desserte + forêt + quelques profils câble).
- **CA2** : mécanisme figeant les oracles Sylvaccess v3.6 et comparant avec tolérance paramétrable.
- **CA3** : un test de non-régression « à blanc » (comparaison oracle vs oracle) passe au vert.

### US-0.5 — CI + qualité
*En tant que* mainteneur, *je veux* une CI qui lint, teste et compile R + Rust, *afin de*
bloquer les régressions.
- **CA1** : CI exécute `lintr`, `testthat`, `R CMD check`, `cargo test`, `clippy`.
- **CA2** : la CI est verte sur le squelette.
- **CA3** : versions R et Rust épinglées (`renv` / `Cargo.lock`).

### US-0.6 — ADR fondateurs
*En tant qu*'équipe, *je veux* les ADR-001…007 rédigés, *afin de* tracer les décisions.
- **CA1** : `docs/adr/ADR-001…007-*.md` présents et cohérents avec le PRD.

---

## EPIC 1 — I/O & prétraitement *(Lot 1)*
Couvre EF-1, EF-2, EF-3.

### US-1.1 — Lecture des entrées IGN
*…je veux* lire MNT (raster) et desserte/forêt/obstacles/parcellaire (vecteur), *afin de*
disposer des données d'entrée.
- **CA1** : lecture raster (`terra`) et vecteur (`sf`) des formats IGN du jeu jouet.
- **CA2** : parcellaire lu comme couche **optionnelle** (absence tolérée).

### US-1.2 — Validation des entrées
*…je veux* une validation stricte, *afin d*'échouer tôt et clairement.
- **CA1** : contrôle CRS commun, alignement de grille sur le MNT, champs attributaires requis
  (dessertes classées route/piste/DFCI).
- **CA2** : chaque cas d'erreur produit un message ciblé et actionnable (test par cas).

### US-1.3 — Pente & exposition
*…je veux* des rasters pente % et exposition depuis le MNT.
- **CA1** : pente % et exposition calculées ; **non-régression** vs oracle v3.6 sous tolérance.

### US-1.4 — Rasterisation & masques
*…je veux* rasteriser les vecteurs à la résolution du MNT et produire les masques.
- **CA1** : rasterisation alignée sur la grille MNT.
- **CA2** : masques d'obstacles (complets/partiels) et exclusion pente > seuil abattage ;
  conformes à l'oracle sous tolérance.

---

## EPIC 2 — Moteur Skidder *(Lot 2)*
Couvre EF-4. Dépend d'EPIC 1 + service least-cost.

### US-2.1 — Service de propagation least-cost (partagé)
*…je veux* un service de coût-distance depuis la desserte (R : `leastcostpath`/`gdistance`),
*afin de* le partager entre skidder/porteur/DFCI.
- **CA1** : distances et trajets least-cost calculés depuis la desserte.
- **CA2** : la fonction de coût reproduit `calcul_distance_de_cout` de v3.6 ; **non-régression**
  sous tolérance (sinon, déclencher l'option portage Rust — ADR-001).

### US-2.2 — Règles skidder v3.6
*…je veux* appliquer les règles (pente ≤ 30 % libre ; treuillage 50 m amont / 100 m aval ;
bascules de pente §6).
- **CA1** : zones accessible / parcourable / non accessible produites.
- **CA2** : distances treuillage, traînage (piste + forêt), totale de débardage ; trajet vers
  place de dépôt.
- **CA3** : **non-régression** distances & zones vs v3.6 sous tolérance.

### US-2.3 — Tableau récapitulatif
*…je veux* un tableau surfaces/volumes par classe d'accessibilité.
- **CA1** : tableau récap correct vs oracle (surfaces ; volumes si raster volume fourni).

---

## EPIC 3 — Moteur Porteur *(Lot 3)*
Couvre EF-5. Réutilise le service least-cost.

### US-3.1 — Cône d'azimuts & contraintes de pente
*…je veux* le portage en ligne droite dans un cône respectant pente travers ≤ 15 %, long
≤ 30 % (montée) / ≤ 25 % (descente), portée ≤ 300 m, grue 8 m.
- **CA1** : zones et distances produites selon ces règles.
- **CA2** : **non-régression** vs v3.6 (sorties identiques au skidder **sans** treuillage).

### US-3.2 — Tableau récapitulatif porteur
- **CA1** : tableau récap conforme à l'oracle.

---

## EPIC 4 — Noyau Câble (Rust) *(Lot 4)*
Couvre EF-6. Crate `cablehelp` via `extendr`.

### US-4.1 — Portage CableHelp (mécanique)
*…je veux* la caténaire élastique + frottement aux supports portés en Rust depuis le `.pyx`,
*afin de* calculer trajectoire de charge et tension.
- **CA1** : sur N profils de référence, **trajectoire ≤ 0,1 %** et **tension ≤ 1,5 %** vs oracle.
- **CA2** : `cargo test` couvre les fonctions mécaniques ; tests d'intégration R les appellent.

### US-4.2 — Faisabilité 360°/pixel
*…je veux* balayer 360 lignes (pas 1°) par pixel de route avec test de faisabilité (hauteur
∈ [4 m, 30 m], tension ≤ rupture/coeff.).
- **CA1** : base des lignes techniquement faisables (table géométrique) produite.
- **CA2** : raster des zones accessibles + tableau récap.

### US-4.3 — Optimisation des supports & parallélisme
*…je veux* optimiser nombre/placement des supports (0…N), raccourcissement, longueur ≥ min,
en parallèle (`rayon`).
- **CA1** : résultats conformes à l'oracle sur les profils de référence.
- **CA2** : **speedup mesuré** vs mono-thread, reporté.

---

## EPIC 5 — Sélection lignes câble *(Lot 5)*
Couvre EF-7.

### US-5.1 — Sélection multicritère
*…je veux* sélectionner les lignes selon surface / supports / sens / longueur / volume / IPC.
- **CA1** : chaque critère implémenté et documenté (IPC = volume / longueur).
- **CA2** : sélection **reproductible** vs v3.6 sur le jeu test ; résultat requêtable en base.

---

## EPIC 6 — Camion DFCI (beta) *(Lot 6, post-MVP)*
Couvre EF-8.

### US-6.1 — Zone défendable ✅ (`v0.8.0`)
*…je veux* cartographier la zone défendable depuis les dessertes DFCI.
- **CA1** : sortie **beta** documentée (limites explicites) et testée sur une zone échantillon. ✅

---

## EPIC 7 — Passage à l'échelle *(Lot 7)*
Couvre ENF-1.

### US-7.1 — Tuilage + parallélisme + COG
*…je veux* traiter un massif par tuiles en parallèle et écrire des rasters COG.
- **CA1** : résultat tuilé **identique** au traitement mono-bloc (raccords corrects, pas
  d'artefact de bordure).
- **CA2** : rasters de sortie en GeoTIFF/COG.

---

## EPIC 8 — Base spatiale & agrégation *(Lot 8)*
Couvre EF-9, EF-12.

### US-8.1 — Schéma PostGIS (base dédiée, schéma par run/massif) ✅ (`v0.9.0`)
*…je veux* un DDL PostGIS (base `foretaccess`, un schéma par run/massif) + export GPKG.
- **CA1** : schéma par run/massif (backend, Lot 0) ; **index spatiaux** (GiST à l'écriture,
  Lot 8) ; écriture **idempotente**. ✅
- **CA2** : export GeoPackage équivalent (R-tree auto). ✅

### US-8.2 — Agrégation zonale ✅ (`v0.9.0`)
*…je veux* agréger surfaces/volumes par massif / parcelle / commune.
- **CA1** : agrégation validée (`agreger_zones()`, R/terra backend-agnostique ; partition =
  récap global) ; parcellaire optionnel pris en compte quand fourni. ✅

---

## EPIC 9 — Doc & publication *(Lot 9)*
Couvre la DoD produit.

### US-9.1 — Documentation d'usage + exemple de bout en bout ✅ (`v0.10.0`)
- **CA1** : README + doc d'usage à jour ; **exemple reproductible** de bout en bout sur le jeu
  jouet (vignette `foretaccess`, exécutée à la compilation). ✅

### US-9.2 — Packaging & release ✅ (`v0.10.0`)
- **CA1** : `NEWS.md` à jour (tient lieu de changelog) ; version taguée (via `release.yml`) ;
  attribution Sylvaccess présente (README, `CITATION.cff`, GPL v3). ✅

---

## EPIC 10 — Acquisition depuis AOI *(Lot 10, amont du Lot 1)*
Étend EF-1. Téléchargement automatique des entrées à partir d'une `AOI.gpkg`, patron nemeton
(`happign`/`osmdata`, config JSON par pays). Voir `specs/010-acquisition-aoi.md`.

### US-10.1 — Résolveur de sources config-driven
*…je veux* des endpoints/couches déclarés dans `inst/datasources/FR.json` (pas en dur), *afin de*
changer de source sans toucher au code.
- **CA1** : `get_data_source()`/`get_layer_service()` lisent le JSON ; test sur le résolveur.

### US-10.2 — Acquisition des couches (phase 1)
*…je veux* télécharger MNT (RGE ALTI 5 m), desserte (BD TOPO), forêt (BD Forêt v2), obstacles
(OSM) et cadastre depuis l'AOI.
- **CA1** : `acquire_inputs()` produit ces couches en EPSG:2154, mises en cache et idempotentes.
- **CA2** : `happign`/`osmdata` en Suggests ; absence → message d'installation ciblé.

### US-10.3 — Compatibilité avec le prétraitement
*…je veux* que les sorties alimentent directement `preprocess()` (Lot 1).
- **CA1** : enchaînement `acquire_inputs()` → `preprocess()` démontré sur une micro-AOI.
- **CA2** : tests unitaires **mockés** (hors-ligne) verts en CI ; intégration réseau opt-in.

### US-10.4 — Phase 2 (différée)
MNH LiDAR HD → volume estimé (`lasR`/`lidR`) ; BD Forêt v3 (repli v3→v2) ; MNT LiDAR HD (si
résolution < 5 m un jour). *Hors périmètre de la première livraison.*

---

## Traçabilité EF → Epics

| EF | Epics |
|---|---|
| EF-1, EF-2, EF-3 | 1 |
| EF-4 | 2 |
| EF-5 | 3 |
| EF-6 | 4 |
| EF-7 | 5 |
| EF-8 | 6 |
| EF-9 | 0, 8 |
| EF-10 | 0 |
| EF-11 | 2–5 (CLI consolidée en 9) |
| EF-12 | 8 |
