# specs/020 — Desserte corrigée LiDAR (ALSroads, NDP 1) — étude de faisabilité

> **Statut** : **Phases A et B validées** (`acquire_desserte_lidar()`, v1.14.0–v1.16.0) —
> enveloppe fine + repli NDP 0, validée bout-en-bout sur l'exemple d'ALSroads (§2)
> **et sur donnée française** (Chastel-Nouvel, avec MNT ≥ 1 m).
> **Phase B validée (v1.16.0)** sur donnée française réelle (Chastel-Nouvel, LiDAR
> HD IGN) : **résultat POSITIF** — avec un **MNT ≥ 1 m**, ALSroads mesure bien les
> pistes forestières françaises (**22/22**, largeurs 1,1–8,1 m). Le **0/6 initial
> de la v1.15.0 était un artefact** : MNT à 5 m (grille d'accessibilité) 10× trop
> grossier pour les profils à 0,5 m. `acquire_desserte_lidar()` dérive désormais un
> MNT 1 m des points sol si besoin. **Go** (expérimental, largeurs à recouper). Cf. §6bis.
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

## 6bis. Phase B — validation française : **NÉGATIVE en v1.15.0, POSITIVE en v1.16.0**

Protocole : dalle LiDAR HD IGN `LHD_FXX_0737_6385` (Chastel-Nouvel, Lambert-93,
260 Mo, ~40 M points, ~45 pts/m², classes ASPRS 1/2/3/4/5/6) + desserte **IGN BD
TOPO `troncon_de_route`** (sortie d'`acquire_desserte()` : axes de routes/pistes,
champ `largeur` vide). `acquire_desserte_lidar()` lancé sur les tronçons
**entièrement dans la dalle**.

### Le faux négatif de la v1.15.0 (0/6) et sa cause

Le premier passage rendait **0/6** (largeurs toutes `NA`). Confondants écartés un à
un — mauvaise emprise de dalle (`_6385` = bord **haut**, ymin = 6384000), `st_crop`
fragmentant les routes sous les 40 m d'ALSroads, géométrie `MULTILINESTRING` vs
`LINESTRING` (testée : toujours 0/6). J'en avais conclu à tort à un **défaut de
calibrage Québec**.

La vraie cause était le **MNT**. Le guide utilisateur d'ALSroads
([ilythiamorley.github.io/ALSroads_Guide](https://ilythiamorley.github.io/ALSroads_Guide/))
l'énonce : **DTM « at least 1 m »**. ALSroads construit ses profils de détection de
bord à `profile_resolution = 0.5 m` ; le MNT que je passais était la **grille
d'accessibilité à 5 m**, 10× trop grossière → profils inexploitables → largeurs `NA`.
Ce n'était **pas** la donnée ni le calibrage, c'était **ma résolution de MNT**.

### La validation positive (v1.16.0)

MNT dérivé à **1 m** des points sol (classe ASPRS 2) de la dalle
(`lidR::rasterize_terrain(res = 1, tin())`), nuage décimé à ~10 pts/m² (reco du
guide). **22/22 pistes ≥ 60 m mesurées** (6 premières en exemple) :

| route | long. | ROADWIDTH | DRIVABLE | CLASS | SCORE |
|------:|------:|----------:|---------:|------:|------:|
| 1 | 328 m | 7,3 m | 7,2 m | 1 | 75 |
| 2 | 219 m | 8,8 m | 8,1 m | 1 | 100 |
| 3 | 280 m | 4,3 m | 3,4 m | 1 | 85 |
| 4 |  65 m | 3,4 m | 2,7 m | 2 | 52 |
| 5 | 395 m | 7,8 m | 7,3 m | 2 | 63 |
| 6 | 453 m | 5,4 m | 4,6 m | 2 | 73 |

**22/22 mesurées**, largeurs 1,1–8,1 m, classes 1–4 (les rares classes 4 sont des
pistes réellement dégradées) — cohérent avec des pistes forestières réelles. La
réserve « calibrage Québec → France » du §4.1 est **levée** :
avec un MNT ≥ 1 m, ALSroads mesure la donnée française.

**Correctif code** : `acquire_desserte_lidar()` détecte un MNT plus grossier que
1,5 m et en **dérive un à `dtm_res` m** (défaut 1) depuis les points sol ; il décime
aussi le nuage au-delà de ~15 pts/m². Fournir directement le **MNT LiDAR HD IGN à
0,5 m** évite la dérivation et colle au profil interne d'ALSroads. Script
reproductible : `data-raw/validation_desserte_lidar.R`.

**Leçon** (mémoire) : avant de conclure à un « échec de calibrage » d'un outil tiers,
vérifier d'abord que **mes entrées respectent ses exigences** (ici la résolution du
MNT, écrite noir sur blanc dans le guide). Sur-conclure deux fois au négatif aurait
enterré une fonction qui marche.

### 6ter. Desserte de projet COMPLÈTE (v1.19.0) : géométrie, couverture, tronçons courts

Le 22/22 portait sur **6 routes triées à la main** (longues, sous une dalle bien
couverte), castées en LINESTRING. Sur une **desserte de projet complète** (Chastel-
Nouvel, 806 km / 3 299 tronçons, 4 dalles), l'app mesurait **0/3 299**. Trois causes,
corrigées en 1.19.0 :

1. **Géométrie** (la cause du 0/N) : BD TOPO `troncon_de_route` est en
   **`MULTILINESTRING`**, et `measure_road` **échoue** dessus (« Expecting LINESTRING
   geometry »). Le 22/22 castait en LINESTRING ; l'app passait le MULTI brut. →
   `.troncon_linestring()` ramène chaque tronçon à une LINESTRING unique.
2. **Tronçons courts** : une desserte BD TOPO compte des milliers de segments <
   40 m, instables sous le buffer d'ALSroads. → paramètre `long_min_m` (défaut 40),
   sautés sans appel.
3. **Couverture partielle** : une desserte de projet déborde l'emprise des dalles
   fournies. → attendu que **l'essentiel reste `NA`** ; seuls les tronçons **longs et
   sous une dalle** se mesurent. L'attribut `bilan` décompose l'issue.

Le mismatch de colonnes (`largeur_carrossable_m` vs `largeur`/`largeur_de_chaussee`
lu par `places_depot()`) est aussi levé : `.largeur_desserte` reconnaît la largeur
LiDAR, et `places_depot(largeur_champ=)` nomme la colonne. **Chaîne câble débloquée.**

### 6quater. Segfault sur desserte de projet (v1.19.1) — pré-filtre de couverture

Après le fix géométrie de 1.19.0, `measure_road` était **réellement** appelé sur les
milliers de tronçons **hors couverture** d'une desserte de projet (806 km pour
4 dalles). lidR/ALSroads **segfaulte** sur cette masse de régions sans points (~1 h
puis crash mémoire C++, **non rattrapable** — il tue le worker `future` de l'app).
**Fix** : l'emprise des dalles (union des empreintes du `LAScatalog`, `.couverture_dalles()`)
est calculée une fois ; `.troncons_couverts()` écarte les tronçons hors couverture
**avant** tout appel ALSroads → `NA` propre, jamais de crash, temps effondré. Le
`bilan` gagne `hors_couverture`. Validé : 44/256 couverts, 212 écartés, 0,02 s.

---

## 7. Décision à prendre (go/no-go) — §7 du brief

**Décision (après Phase B, v1.16.0) : GO expérimental.** La validation française
(§6bis) est **positive** dès lors que le MNT est ≥ 1 m : ALSroads mesure les pistes
françaises (6/6, largeurs 2,7–8,1 m). `acquire_desserte_lidar()` garantit désormais
cette condition (dérivation d'un MNT 1 m si besoin). L'app peut exposer les largeurs
LiDAR en France, **en les marquant expérimentales** (à recouper avec une orthophoto
sur site sensible tant qu'un relevé terrain de référence n'a pas quantifié l'écart).
Pas de recalibrage nécessaire.

**Recommandation initiale : GO conditionnel, en deux temps.**

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
