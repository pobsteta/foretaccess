# specs/020 — Desserte corrigée LiDAR (ALSroads, NDP 1) — étude de faisabilité

> **Statut** : **Phase A implémentée** (`acquire_desserte_lidar()`, v1.14.0,
> 2026-07-22) — enveloppe fine + repli NDP 0, **validée bout-en-bout** sur les
> données d'exemple d'ALSroads (§2). **Phase B** (validation sur donnée française,
> CA-20.5) reste à faire avant tout usage de production.
> **Type** : acquisition/enrichissement, en amont du prétraitement. Complète le
> Lot Acquisition (`specs/010`) et le chantier 3 (`places_depot` aveugle sans
> largeur mesurée).
> **Origine** : chantier 4 du brief desserte nemetonshiny (`~/brief-foretaccess.md`,
> rév. 2026-07-22).
> **Dépend de** : `acquire_desserte()` (BD TOPO), `acquire_mnt()`, le nuage LiDAR HD
> (déjà téléchargé côté app : `download_ign_lidar_hd(product = "nuage")`),
> **ALSroads** (r-lidar-lab) et **lidR**.
> **Règles strictes** : 1 (logique métier dans foretaccess ; ici on *consomme*
> ALSroads, on ne le ré-implémente pas), 2 (rasters/nuages jamais commités).

---

## 1. Le problème que ça résout

La cause racine des chantiers 1 et 3 est en partie la **qualité de la desserte
BD TOPO** : **pas de largeur carrossable mesurée** (→ `places_depot()` ne peut pas
discriminer l'accès camion, d'où des centaines de départs lâches, cf. `specs/004`
et la section *Performance et sélectivité* de `places_depot`), position parfois
approximative, routes déclassées/disparues non signalées.

**ALSroads** corrige exactement ça à partir du **LiDAR aérien** : géométrie
recalée + **largeur de plateforme** + **largeur carrossable** + pente + **état**
(existante / déclassée / disparue). La largeur carrossable alimenterait
directement `largeur_min_m` de `places_depot()` — le levier de sélectivité qui
manque aujourd'hui.

---

## 2. Ce qu'est ALSroads (vérifié)

- **Fonction** : `measure_road(ctg, centerline, dtm = NULL, ...)` — `ctg` =
  `LAScatalog` (lidR), `centerline` = vecteur `sf` d'**une** route, `dtm` = MNT
  (`RasterLayer`). Rend la **géométrie recalée** + attributs. **Colonnes réelles
  vérifiées** (exécution sur les données d'exemple du paquet) : `ROADWIDTH`,
  **`DRIVABLEWIDTH`**, `PERCABOVEROAD`, `SHOULDERS`, `SINUOSITY`, `CONDUCTIVITY`,
  `SCORE`, **`CLASS`** (= l'**état de la route en 4 classes** ; il n'y a **pas** de
  champ `STATE`). Exemple mesuré : `ROADWIDTH=8.5`, `DRIVABLEWIDTH=8.2`,
  `SCORE=100`, `CLASS=1`.
  → Mapping ForêtAccess : `largeur_carrossable_m` ← `DRIVABLEWIDTH`,
  `largeur_plateforme_m` ← `ROADWIDTH`, `etat_classe` ← `CLASS`, `score_lidar` ←
  `SCORE`, `pente_pct` calculée par nous sur la géométrie recalée.
- **Dépendance** : **lidR requis** (`readLAScatalog()`), + `sf`, `raster`.
- **Maturité** : **v0.2.0 (oct. 2022)**, *« experimental … proof of concept »*,
  maintenance faible (dernier release oct. 2022).
- **Calibrage** : développé avec le **MFFP du Québec**, calibré sur les routes
  forestières québécoises. **Pas de garantie sur la France.**
- **Perf** : **non documentée** dans le dépôt.
- **`vecnet`** (même labo) est écarté : il *vectorise* un réseau depuis un raster
  de probabilité ML, ne corrige pas un vecteur et ne produit pas de largeur.

---

## 3. Faisabilité : l'infrastructure existe déjà

Les briques d'entrée sont **toutes disponibles**, la plupart déjà dans l'écosystème :

| Entrée `measure_road` | Source | État |
|---|---|---|
| `ctg` (nuage LAS) | `download_ign_lidar_hd(product = "nuage")` → `lidar_nuage/*.copc.laz` | **déjà** téléchargé/caché côté nemetonshiny |
| `road` (vecteur) | `acquire_desserte()` (BD TOPO) | livré |
| `dtm` (MNT) | `acquire_mnt()` (LIDAR HD MNT) | livré |
| `lidR` | déjà `nemeton` **Suggests** `lidR (>= 4.0)` (+ `lasR`), repo `r-lidar.r-universe.dev` | **déjà** dans l'écosystème |

Nemeton lit déjà des dalles COPC avec lecture bufferisée par AOI et parallélisme
(`compute_dtm_chm_from_laz`, `pai_depuis_nuage`, `lasR`). **La dépendance lidR
d'ALSroads n'ajoute donc pas un poids nouveau** à l'écosystème — elle y est déjà.

**Verdict technique** : faisable. Aucun verrou d'infrastructure.

---

## 4. Les vrais risques (ce qui gate le go/no-go)

1. **Calibrage Québec → France non validé.** C'est le risque #1. Les seuils
   d'ALSroads (largeur, réflectance, densité de points) sont calés sur le Québec.
   Sortie potentiellement fausse sur forêt/routes françaises **sans recalibrage**.
   → **validation obligatoire sur un site français** (Chastel-Nouvel, LiDAR HD
   dispo) **avant** tout usage en production.
2. **Expérimental + non maintenu** (POC 2022). Risque de rupture (API lidR a
   évolué vers 4.x), pas de support. → épingler une version, tester en CI *opt-in*.
3. **Coût de traitement non documenté, par tronçon.** `measure_road` sur 3 299
   tronçons (Chastel-Nouvel) peut être lourd. → **benchmarker** + **cache** par
   tronçon (comme le reste de l'acquisition).
4. **lidR vs lasR.** ALSroads impose **lidR** ; l'écosystème nemeton vise plutôt
   **lasR** (plus rapide, COPC-natif). Cohabitation nécessaire (les deux sont déjà
   en Suggests nemeton) — pas de portage lasR d'ALSroads envisageable (POC figé).

---

## 5. API proposée (si go)

Cohérente avec `places_depot()` / `volume_depuis_p1()` : **consommer, ne pas
fetcher**. ForêtAccess enveloppe `ALSroads::measure_road` ; l'orchestrateur (app /
nemeton) fournit le nuage.

```r
acquire_desserte_lidar(desserte, las_source, mnt, crs = 2154,
                       cache_dir = tempdir(), ...) -> sf
#  desserte   : sf BD TOPO (sortie de acquire_desserte())
#  las_source : chemin de dalles .laz/.copc.laz OU un LAScatalog lidR
#  mnt        : SpatRaster / chemin (meme grille/CRS, ADR-004)
#  -> sf desserte : geometry RECALEE + champs largeur_carrossable_m,
#     largeur_plateforme_m, pente_pct, etat_classe (CLASS ALSroads : etat en 4
#     classes), score_lidar ; MEME format que acquire_desserte() + ces colonnes.
#     Repli NDP 0 (desserte inchangee, colonnes NA) si pas de LiDAR / ALSroads.
```

**Implémenté (Phase A)** : `R/desserte_lidar.R`. lidR + ALSroads accedés
**dynamiquement** (`getExportedValue`), **non declares** en Suggests (POC hors
CRAN, dep lourde) pour ne pas peser sur la CI ; le repli NDP 0 est le cœur testé.
Le chemin NDP 1 a été **exécuté de bout en bout** sur les données d'exemple
d'ALSroads (sortie : `largeur_carrossable_m=8.2`, `largeur_plateforme_m=8.5`,
`etat_classe=1`, `score_lidar=100`, géométrie recalée) — pas de code
plausible-mais-faux. Reste la validation **française** (Phase B).

- **lidR et ALSroads en `Suggests`** (message d'installation ciblé sinon) : le
  cœur du paquet s'installe sans eux, comme happign/osmdata.
- **Cache par tronçon** (id BD TOPO → mesure) sous `cache_dir/desserte_lidar/`.
- Consommée telle quelle par `places_depot()` (accès camion **enfin
  discriminant** via `largeur_carrossable_m` → départs réalistes, cf. chantier 3),
  `preprocess()` et les moteurs (axes justes, routes existantes/disparues).

---

## 6. Critères d'acceptation (si go)

- **CA-20.1** `acquire_desserte_lidar()` sans LiDAR / sans ALSroads → **repli NDP 0**
  (rend `desserte` inchangée + colonnes à `NA`), message clair. Jamais d'échec dur.
- **CA-20.2** Avec LiDAR : sortie `sf` au format `acquire_desserte()` + `largeur_m`,
  `largeur_carrossable_m`, `pente_pct`, `etat` ; CRS = MNT (ADR-004).
- **CA-20.3** `places_depot(desserte_lidar, mnt, largeur_min_m = 4)` retient
  **nettement moins** de départs que sur la BD TOPO brute (mesuré) — la valeur
  ajoutée doit être quantifiée.
- **CA-20.4** Cache : un 2ᵉ appel réutilise les mesures par tronçon.
- **CA-20.5 (validation France)** Sur un site français, comparer les largeurs
  ALSroads à un relevé/orthophoto : accord suffisant, **sinon documenter le
  recalibrage nécessaire** (go/no-go production).
- **CA-20.6** Tests `testthat` **opt-in** (comme `FORETACCESS_RUN_ONLINE_TESTS`) —
  jamais de LiDAR en CI standard.

---

## 7. Décision à prendre (go/no-go) — §7 du brief

**Recommandation : GO conditionnel, en deux temps.**

1. **Phase A (bas risque, réversible)** — livrer `acquire_desserte_lidar()` comme
   **enveloppe fine** d'`ALSroads::measure_road`, lidR + ALSroads en **Suggests**,
   **repli NDP 0** par défaut. Rien n'est imposé au cœur ; l'app l'active en
   « NDP 1 » opt-in. Coût de dev modéré, aucun risque pour l'existant.
2. **Phase B (bloquante avant production)** — **valider sur un site français**
   (CA-20.5). Tant que ce n'est pas fait, l'app expose la fonction en
   **« expérimental »** et ne s'appuie pas sur ses largeurs pour une décision
   ferme. Si le recalibrage s'avère nécessaire et hors budget → **no-go
   production**, la fonction reste un utilitaire de recherche.

**À trancher avant de coder :**
- **Q1 — Où vit la fonction ?** foretaccess (produit un *input* desserte, cohérent
  avec `places_depot`/`volume_depuis_p1`) **ou** nemeton (qui possède déjà l'infra
  LAS) ? Proposé : **foretaccess**, en consommant un `las_source` fourni (pas de
  fetch), lidR/ALSroads en Suggests.
- **Q2 — Vaut-il le coup sans validation France ?** Si le calibrage Québec est
  jugé trop incertain, on peut **différer** entièrement (le chantier 3 a déjà
  d'autres leviers : couche `retournements`, `espacement_min_m`).
- **Q3 — Dépendance ALSroads** (GitHub, non CRAN, POC figé) : acceptable en
  Suggests avec version épinglée, ou risque de maintenance rédhibitoire ?

---

## 8. Ce que ça n'est pas

- Pas un remplacement de BD TOPO : un **enrichissement** opt-in (NDP 1), avec repli
  NDP 0 systématique.
- Pas un portage d'ALSroads : on **consomme** le paquet tel quel (règle 1 — la
  mécanique LiDAR n'est pas de la logique métier ForêtAccess).
- Pas `vecnet` (§2) : autre usage (vectorisation ML, sans largeur).

---

## 9. Sources

- ALSroads : <https://github.com/r-lidar-lab/ALSroads> (v0.2.0, 2022, POC,
  `measure_road(ctg, road, dtm)`, dépend de lidR, calibré MFFP Québec).
- vecnet : <https://github.com/r-lidar-lab/vecnet> (v0.1.0, 2022) — écarté.
- Roussel et al. 2022/2023, *Int. J. Applied Earth Observation and Geoinformation*.
- Infra LiDAR existante : nemetonshiny `download_ign_lidar_hd(product = "nuage")`,
  nemeton `compute_dtm_chm_from_laz` / `pai_depuis_nuage` (lasR), Suggests
  `lidR (>= 4.0)` + `lasR (>= 0.10)`.
