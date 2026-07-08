# ForêtAccess — PRD (Product Requirements Document)

> **Statut** : proposé — en attente de validation.
> **Version** : 0.1 (2026-07-08).
> **Source de vérité** : [`docs/foretaccess-brief.md`](foretaccess-brief.md). Ce PRD dérive
> du brief §1–§10 et intègre les décisions tranchées avec l'utilisateur (voir §8).
> **Licence** : GPL v3 (travail dérivé de Sylvaccess © S. Dupire / INRAE).
> **Stack actée** : package **R** (cœur + orchestration + moteurs terrestres + least-cost)
> avec **noyau câble en Rust** via `extendr`/`rextendr`.

---

## 1. Contexte & problème

**Sylvaccess** (INRAE — S. Dupire, v3.6, GPL v3, DOI `10.15454/JUBESS`) cartographie
automatiquement l'accessibilité des forêts selon le mode d'exploitation. Son code actuel
(Python 3 + Cython, hérité de Python 2.7) est **monolithique et couplé à une UI PyQt** :
logique métier appelée depuis l'interface, ~80 variables globales, 59 `except:` nus, I/O
raster « à la main ». Conséquences : impossible de l'utiliser en CLI/batch, de le réutiliser
(plugin QGIS, service), ou de le tester automatiquement.

**ForêtAccess** est une réimplémentation moderne : un **cœur métier pur, découplé de toute
UI**, testable, performant, réutilisable, avec **sorties dans une base spatiale**
(PostGIS / GeoPackage) directement exploitable dans l'écosystème SIG.

---

## 2. Objectifs (outcomes)

1. **Cartographier l'accessibilité** pour 4 modes d'exploitation (skidder, porteur, câble,
   camion DFCI).
2. **Cœur découplé et testable** : fonctions pures (config + données → résultats), sans
   dépendance UI, sans variable globale.
3. **Fidélité vérifiée** à Sylvaccess v3.6 via un **harnais de non-régression** (oracle).
4. **Sorties en base spatiale** requêtables (PostGIS / GeoPackage) + rasters COG.
5. **Passage à l'échelle** du massif au national par tuilage + parallélisme.

**Non-objectifs (v1)** : fournir une UI graphique, un plugin QGIS, ou intégrer la logique
DESSOPT (voir §7).

---

## 3. Utilisateurs & usage

| Persona | Besoin | Usage ForêtAccess |
|---|---|---|
| Gestionnaire / expert forestier | Cartes d'accessibilité par mode, potentiel câble | CLI/batch, lecture des sorties SIG |
| ONF / coopérative | Planification débardage à l'échelle massif | Pipeline batch, agrégation zonale |
| Chercheur / INRAE | Réimplémentation testable, comparable à v3.6 | Package R, non-régression |
| Collectivité / SDIS (DFCI) | Zone défendable depuis dessertes DFCI | Lot 6 (beta), post-MVP |

**Forme du livrable (actée)** : **package R** (bibliothèque de fonctions exportées + noyau
Rust) **pilotable en CLI/batch via `Rscript`**. Shiny, `targets` clés-en-main et plugin QGIS
sont hors périmètre v1 (extensions ultérieures / repos frères).

---

## 4. Périmètre MVP

**Dans le MVP** :
- **Prétraitement commun** (§4.1 du brief) : validation entrées, alignement grille MNT,
  pente %, exposition, rasterisation, masques d'obstacles, exclusion pente > seuil abattage.
- **Moteur Skidder** (§4.2) : règles v3.6, service least-cost, sorties rasters + tableau.
- **Moteur Porteur** (§4.3) : cône d'azimuts, pentes long/travers, portée grue.
- **Noyau Câble Rust** (§4.4) : CableHelp (caténaire élastique + frottement), faisabilité
  360°/pixel, optimisation supports, base des lignes faisables.
- **Sélection multicritère** des lignes câble (surface, supports, sens, longueur, volume, IPC).
- **Stockage** : interface `StorageBackend` avec **PostGIS et GeoPackage au même niveau**
  (aucun défaut privilégié) ; rasters GeoTIFF/COG hors base.
- **Parcellaire** : accepté comme **couche d'entrée optionnelle dès v1** (pour agrégation par
  parcelle), sans logique DESSOPT.

**Post-MVP** :
- **Camion DFCI (beta)** — Lot 6.
- **Passage à l'échelle** (tuilage/parallélisme national) — Lot 7.
- **Base spatiale & agrégation zonale avancée** — Lot 8.
- **Doc & publication** — Lot 9.

---

## 5. Exigences fonctionnelles (EF)

> Traçabilité : chaque EF est couverte par un ou plusieurs epics/US du backlog
> ([`BACKLOG.md`](BACKLOG.md)) et un lot de la roadmap ([`ROADMAP.md`](ROADMAP.md)).

- **EF-1 — Entrées** : lire MNT (raster), desserte (polylignes classées route/piste/DFCI),
  forêt (polygones), obstacles complets/partiels (vecteur), volume sur pied (raster,
  optionnel), parcellaire (vecteur, optionnel). Formats IGN nationaux (MNT 5 m, BD Forêt
  V2/V3, BD Topo).
- **EF-2 — Validation** : CRS commun, alignement de grille sur le MNT, présence des champs
  attributaires requis ; messages d'erreur explicites et ciblés (pas d'échec silencieux).
- **EF-3 — Prétraitement** : pente %, exposition, rasterisation des vecteurs à la résolution
  du MNT, masques d'obstacles, exclusion des pentes > seuil d'abattage manuel (défaut 100 %).
- **EF-4 — Skidder** : circulation libre si pente ≤ 30 % ; treuillage depuis desserte
  (50 m amont / 100 m aval par défaut) avec bascule distance max selon pente. Sorties :
  zones (accessible / parcourable / non accessible), distances (treuillage, traînage piste
  et forêt, totale de débardage), trajet optimal vers place de dépôt, tableau récap
  surfaces/volumes par classe.
- **EF-5 — Porteur** : circulation libre si pente en travers ≤ 15 % ; sinon portage en ligne
  droite dans un cône d'azimuts (pente travers max, pente long ≤ 30 % montée / ≤ 25 %
  descente, portée ≤ 300 m, grue 8 m). Sorties identiques au skidder **sans** treuillage.
- **EF-6 — Câble** : pour chaque pixel de route, 360 lignes (pas 1°) ≤ longueur max câble ;
  test de faisabilité (hauteur porteur ∈ [4 m, 30 m], tension ≤ rupture / coeff. sécurité)
  via CableHelp ; optimisation nombre/placement supports, raccourcissement, longueur ≥ min.
  Sorties : base des lignes faisables (table géométrique), raster zones accessibles, tableau.
- **EF-7 — Sélection câble** : sélection multicritère (max surface, min supports, sens
  amont/aval, longueur, max volume, max IPC = volume/longueur), reproductible et requêtable.
- **EF-8 — DFCI (beta, post-MVP)** : zone défendable depuis les dessertes DFCI.
- **EF-9 — Stockage** : écrire/lire vecteurs via `StorageBackend` (PostGIS **ou** GeoPackage,
  au choix par run) ; rasters en GeoTIFF/COG ; écriture idempotente ; index spatiaux (PostGIS).
- **EF-10 — Configuration** : tous les paramètres métier configurables, **défauts = Sylvaccess
  v3.6** (brief §6), validés au chargement.
- **EF-11 — CLI/batch** : lancer prétraitement + moteurs depuis `Rscript` avec un fichier de
  config, sur un massif, jusqu'à l'écriture en base.
- **EF-12 — Agrégation zonale** : agréger surfaces/volumes par massif / parcelle / commune
  (SQL en PostGIS, équivalent en GeoPackage).

---

## 6. Exigences non-fonctionnelles (ENF)

- **ENF-1 Performance** : moteurs terrestres rapides (réf. v3.6 : PNR Morvan 3290 km² →
  ~18 min skidder / ~1h23 porteur au 5 m). Câble = point chaud → noyau Rust + parallélisme
  (`rayon`), objectif de réduction forte des temps (réf. câble ~800 ha / 20 km ≈ 20 min).
- **ENF-2 Fidélité** : erreur ≤ **0,1 %** sur la trajectoire de charge et ≤ **1,5 %** sur la
  tension (valeurs de validation publiées) ; tolérances définies par moteur pour les sorties
  terrestres, validées contre l'oracle v3.6.
- **ENF-3 Reproductibilité** : environnement épinglé (R via `renv`, Rust via `Cargo.lock`),
  build `rextendr`, données d'exemple versionnées, seeds si aléatoire.
- **ENF-4 Qualité** : `lintr` + `testthat` (edition 3) côté R ; `clippy` + `cargo test` côté
  Rust ; couverture minimale sur le cœur ; `R CMD check` sans ERROR/WARNING.
- **ENF-5 Observabilité** : journalisation par niveaux (`cli`/`logger`), pas de `print`
  disséminés ; journal d'erreurs structuré.
- **ENF-6 i18n** : messages FR/EN externalisés (dictionnaire), pas de branchements
  `if (langue == …)` disséminés.
- **ENF-7 Robustesse I/O** : chemins via `fs`/`file.path`, création de dossiers idempotente,
  fermeture systématique des ressources, gestion d'erreurs ciblée (aucun `tryCatch` fourre-tout
  masquant les causes ; équivalent R du « zéro `except:` nu »).
- **ENF-8 Découplage** : cœur pur sans UI, I/O et orchestration en couches séparées, aucune
  variable globale mutable.

---

## 7. Hors-périmètre (v1)

- UI graphique / **Shiny** (extension ultérieure, éventuellement repo frère type `nemetonshiny`).
- **Plugin QGIS** / service web.
- **Logique DESSOPT** (le parcellaire est accepté en entrée, mais aucune optimisation de
  desserte DESSOPT n'est implémentée).
- **QUALIROAD** (qualification fine des dessertes) — le DFCI beta s'appuie sur les dessertes
  fournies telles quelles.
- Pipeline `targets` clés-en-main (les fonctions restent orchestrables ; un pipeline packagé
  pourra venir plus tard).

---

## 8. Décisions actées (questions ouvertes §9 du brief)

| # | Question | Décision |
|---|---|---|
| 9.1 | Backend par défaut | **PostGIS et GeoPackage au même niveau** — aucun défaut privilégié, choix par run |
| 9.2 | DFCI dans le MVP | **Non — Lot 6 post-MVP** (reste beta) |
| 9.3 | Least-cost R ou Rust | **R d'abord** (`leastcostpath`/`gdistance`/`terra`) ; portage Rust ultérieur si la perf l'exige |
| 9.4 | `.pyx` comme oracle | **Oui — récupération du `.pyx` (GPL v3) pour oracle ET portage** des équations |
| 9.5 | Parcellaire (DESSOPT) | **Couche d'entrée optionnelle dès v1** (agrégation par parcelle), sans logique DESSOPT |
| — | Forme du livrable | **Package R + CLI `Rscript`** |
| 9.6 | Schéma PostGIS | **Base dédiée `foretaccess`, un schéma par run/massif** |
| — | Stack | **R (package) + Rust `extendr`/`rextendr`** |

Ces décisions sont formalisées dans les ADR ([`docs/adr/`](adr/)).

---

## 9. Contraintes & risques

- **Licence** : GPL v3 imposée (dérivé de Sylvaccess) ; toute diffusion cite Sylvaccess
  (brief §1).
- **Oracle** : la fidélité dépend de la disponibilité de Sylvaccess v3.6 exécutable et du
  `.pyx` (forge.inrae.fr). Risque : difficulté à faire tourner v3.6 → mitigation : figer des
  oracles sur jeu jouet dès le Lot 0.
- **Équations câble** : l'article ne donne pas toutes les équations mécaniques ; elles sont
  **récupérées du `.pyx`** (CableHelp, coût least-cost, unités de vidange, pas de recherche
  supports). Risque de contresens de portage → mitigation : non-régression profil par profil.
- **Least-cost R** : `leastcostpath`/`gdistance` doivent reproduire la fonction de coût
  Sylvaccess (`calcul_distance_de_cout`) sous tolérance ; sinon portage Rust anticipé.

---

## 10. Critères de succès (Definition of Done globale)

Un lot est « fait » quand (cf. brief §12) :
- [ ] Spec `specs/0XX` validée ; ADR associé si décision structurante.
- [ ] Code + tests unitaires ; **non-régression verte** pour tout ce qui reproduit v3.6.
- [ ] `lintr`/`testthat` et `clippy`/`cargo test` OK en CI ; `R CMD check` propre.
- [ ] Gestion d'erreurs ciblée ; I/O robustes ; journalisation (pas de `print`).
- [ ] Doc d'usage à jour + entrée `NEWS.md`/`CHANGELOG`.
- [ ] Branche dédiée + PR + revue ; commits atomiques.

Le produit v1 est livrable quand les Lots 0–5 et 7–9 sont « faits » (DFCI Lot 6 = beta,
livrable indépendamment).
