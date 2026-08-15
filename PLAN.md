# PLAN.md — walking skeleton ForêtAccess

> **Source unique de vérité** de l'avancement (règle 5 de `CLAUDE.md`).
> Mise à jour à chaque étape terminée. Ne jamais clore un lot sans la release
> correspondante.

## État courant

- **Lot 11 (confrontation à l'oracle Sylvaccess réel) livré en `v0.13.0`**, et **Lot 4 clos**
  (supports intermédiaires du câble). Décidé le 2026-07-13 : **l'oracle passe avant `v1.0.0`**,
  pour que la version majeure signifie « validée contre le vrai moteur » et non « périmètre
  atteint ». Accord cellule à cellule sur le jeu officiel ColduPre (411 309 cellules
  forestières) : **skidder 99,95 %**, **porteur 99,72 %**, **câble 96,58 %** — porté à **98,36 %**
  par le Lot 12a.3 (pêchage latéral, cycle dev, non encore publié).
- **Lot 12a (affinage de fidélité) livré en `v0.14.0`** : câble porté à **98,36 %** (pêchage
  latéral `c_l_hor`, 12a.3), distances porteur fidèles (fusion plat/radial + héritage grappin,
  12a.2b), veto de pondération piste du skidder (12a.1), banc élargi aux distances porteur (12a.2).
- **`v1.0.0` posée** (2026-07-15) : première version **majeure**, sens du bump = « validée contre
  le vrai moteur ». Préalable tenu sur les **quatre moteurs** (skidder 99,95 %, porteur 99,72 %,
  câble 98,36 %, **DFCI 99,87 %**), distances collées décomposition comprise. Publie le **Lot 12a.4
  (DFCI)** : moteur radial `debusq_dfci` transcrit (noyau Rust `dfci_scan`), spec 006 réécrite,
  6 classes de défendabilité, lance à 0 m d'écart médian.
- **`v1.4.0` posée** (2026-07-18) : **source du réseau DFCI**. Le flag `dfci` (`CL_DFCI`), source
  du camion DFCI laissée vide depuis la phase 1, est alimenté par `flag_dfci()` — réseau OSM
  `ref:FR:DFCI` (`acquire_dfci()`, Voie A) puis repli géométrique (piste traversante ≥ 10 m, ou
  cul-de-sac + aire de retournement, Voie B). Câblé dans `acquire_inputs(dfci = TRUE)`. Comble
  spec 010 §10.2.
- **`v1.1.0` posée** (2026-07-16) : **optimisation de la hauteur des supports câble façon
  SEILAPLAN** (spec 013, `cable$methode_supports = "seilaplan"`) — graphe + Dijkstra de Bont &
  Heinimann réutilisant notre caténaire. Confrontée cellule à cellule à l'oracle `c_option_h=true` :
  accord **93,2 → 94,7 %**, fidèle à l'oracle (+454 ≈ +470 en fenêtre), perf **×2,8**. Défaut
  `"sylvaccess"` (`_NoH`) inchangé, bit-pour-bit. `OptPyl_Up2` shelvé et le flag
  `optimiser_hauteur_fixation` retirés. **Dette câble (optimisation de hauteur) : résolue.**
- **Épic « conception de desserte » (Lots 14-18) ouvert** (2026-07-16, `docs/ROADMAP-desserte.md`).
  Objectif : concevoir un **réseau de desserte forestière** (et non plus seulement carter
  l'accessibilité d'un réseau existant). Chemin critique 14 → 15 → 16 → 17, optimisation en 18.
  **Lot 14 (surface de coût de construction) livré en cycle dev** : `surface_cout_construction()`
  (R pur) rend un coût €/m additif (base + pente par barème + sol + pont/buse + surcoût libre) et
  une couche de franchissabilité, aligné sur la grille du MNT. Config `desserte$cout` + validation
  (CA-14.6). 32 tests (CA-14.1 à 14.6). **Lot 14 mergé (#58).**
- **Lot 15a (voisinage étendu + heuristique inverse) en cycle dev** : premier incrément du **portage
  Rust** du solveur de tracé (ADR-001 déclenché). Module `src/rust/src/desserte/` : `neighborhood.rs`
  (table de voisinage disque filtrée par la pente en long, portage de `build_NeibTable` /
  `build_Tab_neibs` de SylvaRoad) et `heuristic.rs` (distance-de-cout inverse depuis la cible =
  heuristique `h` admissible, portage de `calcul_distance_de_cout`). Binding `desserte_dist_to_end`
  exposé. 11 tests cargo + 9 tests R. Sources SylvaRoad/FRD clonées et transcrites (la lettre) ;
  **l'oracle `meisenthal2` n'est pas publié** (scripts seuls) → validation par invariants
  (CA-15.1-15.6, 15.8, 15.9), sans l'accord géométrique CA-15.7 tant que l'oracle manque. Suite :
  **15b** (A* complet) puis **15c** (orchestration R, sortie `foretaccess_trace` en `sf`). **15a
  mergé (#59).**
- **Lot 15b (solveur A* complet) en cycle dev** : `src/rust/src/desserte/` complété par `geom.rs`
  (`connect2` DDA, `get_intersect`, `check_profile`) et `solver.rs` (portage de `Astar_force_wp` /
  `calc_init` / `basic_calc` : coût de transition géométrique + pénalités paraboliques direction/pente,
  épingles avec rayon de braquage et angle limite, anti-croisement, file secondaire de finition,
  enchaînement des points de passage). Binding `desserte_trace` exposé. 19 tests cargo + 10 tests R
  (CA-15.1/15.4/15.6/15.9). **15b mergé (#60).**
- **Lot 15c (orchestration R) en cycle dev** : `tracer_desserte(pre, cout, waypoints, config)`
  (`R/desserte_trace.R`) rend un objet `foretaccess_trace` (une `sf` LINESTRING de la route, coût,
  faisabilité). R aplatit MNT/franchissabilité/pente, dérive dévers (`obs2`) et fraction locale de
  fort dévers (`local_slope` par focale disque), convertit les waypoints (sf/cellules) en indices,
  appelle `desserte_trace`, reconstruit la polyligne (centres de cellules). Config `desserte$trace`
  ajoutée (paramètres SylvaRoad) + validation. 18 tests. **Lot 15 clos** (15a→15c, #59/#60/#61) ;
  oracle `meisenthal2` non publié → validé par invariants.
- **Lot 16 (réseau MTAP glouton + Steiner + connexité) livré, en cycle dev** : `reseau_desserte(pre,
  cout, parcelles, desserte_existante, heuristique, mode, skidding_m, ...)` (`R/desserte_reseau.R`)
  rend un objet `foretaccess_reseau` (`sf` LINESTRING des routes créées avec `longueur` + `SpatRaster`
  du réseau + coût total + `connexe` + `desservies`). Portage du MTAP→STAP glouton de
  ForestRoadNetwork (Klemet) : chaque parcelle est raccordée au **réseau courant** par le solveur Lot
  15 (variante **multi-cible** : A* qui s'arrête sur toute cellule de réseau), la route créée grossit
  le réseau (réutilisation → arborescence). Pré-élagage par distance de débardage. Trois heuristiques
  d'ordre (plus proche, plus gros volume, aléatoire reproductible). Nouveau Rust :
  `heuristic::dist_to_end_multi`, `solver::solve_network` + `build_network`, binding `desserte_reseau`.
  **16b (`mode = "steiner"`, Chung & Sessions)** : graphe complet des terminaux (réseau + un nœud
  d'accès par parcelle, cellule la plus proche du réseau), arêtes = coûts du solveur Lot 15
  (`desserte_reseau` réseau↔parcelle, `desserte_trace` parcelle↔parcelle, N² tracés), **MST Prim**,
  puis **matérialisation avec réutilisation** (chaque parcelle, dans l'ordre racine→feuilles de
  l'arbre, se greffe sur le réseau courant → fusion des cellules partagées, élagage des doublons).
  Tout en R au-dessus des bindings existants (pas de nouveau Rust). CA-16.4 (Steiner ≤ glouton)
  vérifié. **16c** : raster réseau continu (rasterisation des géométries `touches=TRUE`), `connexe`
  (`terra::patches`, CA-16.5), `desservies` par parcelle (CA-16.1), `longueur` par tronçon.
  24 tests cargo + 20 tests R. **Lot 16 clos**.
- **Lot 17a (vectorisation en graphe) en cycle dev** : `vectoriser_reseau(reseau)`
  (`R/desserte_flux.R`) transforme le réseau du Lot 16 en graphe topologique `foretaccess_reseau_graphe`
  (`noeuds` + `troncons` en `sf`). Graphe **base R** (indices de cellule = nœuds, contraction des
  chaînes de degré 2), pas `igraph`/`sfnetworks`. **17b** : `calculer_flux()` sème des sources
  (≥ 1/parcelle) et accumule le volume vers l'exutoire le plus proche (Dijkstra multi-source sur
  l'arbre) → colonne `flux` sur les `troncons`. **17c** : `typer_desserte()` classe les tronçons par
  seuils de flux (primaire/secondaire/tertiaire), option de conversion temporaire (part de longueur,
  zones prioritaires), sortie `foretaccess_desserte_typee` persistable via le Lot 8 (GeoPackage/PostGIS).
  CA-17.1→17.6 couverts. 41 tests R. **Lot 17 clos**.
- **Lot 18a (optimisation multi-start) en cycle dev** : `optimiser_reseau(..., strategie = "multistart",
  n_start, graine)` (`R/desserte_optim.R`) lance le glouton sous K ordres perturbés et retient le
  moins cher. Noyau Rust `desserte_reseau_multistart` : table bâtie une fois, essais en parallèle
  (`rayon`), essai 0 = ordre de base (jamais pire que le glouton, CA-18.1), permutations reproductibles
  (SplitMix64, CA-18.2). **18b** : `strategie = "recuit"` (recuit simulé, Akay 2004) — énergie = coût
  total, voisin = échange dans l'ordre, acceptation de Metropolis, refroidissement géométrique ;
  `journal` = meilleur coût par itération (monotone, CA-18.4). Noyau Rust `desserte_reseau_recuit`.
  **18c** : `strategie = "riprute"` (rip-up & reroute) — retire tour à tour chaque chemin, re-route
  sa source vers le reste du réseau, garde le déplacement s'il baisse le coût *et* laisse toutes les
  sources connectées (garde-fou BFS `all_sources_connected`, CA-18.5). Noyau Rust `desserte_reseau_riprute`.
  Refactor R : `.reseau_preparer`/`.reseau_assembler` partagés. 3 tests cargo + 15 tests R.
  **Lot 18 clos → épic desserte (14→18) complet.** Prochaine étape : couper une **release stable**.
- **Extension « surface de coût dans le solveur » (post-1.2.0, en cycle dev)** : le solveur A* consomme
  désormais la surface €/m du Lot 14 (jusque-là elle ne fournissait que le masque d'obstacles). Option
  `pondere_cout = FALSE` sur `tracer_desserte`/`reseau_desserte`/`optimiser_reseau` : à `TRUE`, la
  contribution distance de chaque segment est multipliée par le coût moyen de ses deux cellules
  (`CostGrid` côté Rust), le tracé minimise donc l'euro et non plus la seule géométrie. Admissibilité
  préservée sans toucher `heuristic.rs` : l'heuristique géométrique est remise à l'échelle par `cmin`
  (coût minimal sur la zone franchissable), qui reste une borne inférieure du coût restant → A* optimal.
  Défaut `FALSE` = comportement SylvaRoad bit-pour-bit. 1 test cargo (`cost_weighting_scales_and_diverts`)
  + 3 tests R (`test-desserte-pondere.R`). **Branche `feat/desserte-pondere-cout`.**
- **Branche** : cycle dev
- **Version `DESCRIPTION`** : `1.3.1.9000` (cycle dev après release `v1.3.1`)
- **Les distances collent, décomposition comprise** (mesuré sur les sorties courantes) :
  débusquage **0,0 m** d'écart médian, traînage **en forêt 0,2 m** (120,2 contre 124,0),
  traînage sur piste **0,4 m**, distance totale **0,2 m**. Le reliquat est l'**arrondi** :
  Sylvaccess stocke ses distances en `int16` (`int(dist + 0.5)`), nous en flottant — l'écart est
  borné par la demi-cellule. *(Le « traînage en forêt à 0 m contre 124 m » du journal du 13/07
  était le symptôme de la 3ᵉ passe de treuillage manquante ; il a disparu avec elle. Voir
  l'entrée du 14/07 ci-dessous.)*
- **Pondération de la piste dans l'arbitrage — FAIT** (`v0.14.0`, Lots 12a.1 skidder + 12a.2b
  porteur). Sylvaccess ne minimise pas la seule distance en forêt : il pèse la piste dans le choix
  de desserte, `d_foret + 0,5 · d_piste` dans la propagation (`pyx:3714`, transcrit comme un **veto**
  imbriqué, pas un moteur de coût — `R/skidder.R:.propager_trainage`) et `d_foret + 0,1 · d_piste`
  dans l'arbitrage route/piste (`pyx:4283`, `R/skidder.R:.arbitrer_desserte`, `R/porteur.R` pour le
  radial). Coefficients `ponderation_piste_propagation = 0,5` / `ponderation_piste_arbitrage = 0,1`
  (ADR-003). Sur un massif où une piste longue jouxte une route forestière plus lointaine, les deux
  moteurs choisissent désormais la route dès que la piste est longue à remonter — cas exercé par
  `tests/testthat/test-skidder-distances.R:199` (ColduPre ne peut pas l'exhiber, réseau trop dense).
  Accord skidder maintenu à 99,95 %. *(Le paragraphe « pondération 0, à traiter avant v1.0.0 » qui
  figurait ici était un reliquat du journal du 14/07, antérieur à 12a.1 : corrigé le 15/07.)*
- **Fait (0.12.0)** : **portage Rust du balayage câble** (`cable_scan` dans `cablehelp`).
  L'orchestration 360°/pixel de `potentiel_cable()` — profil, plus longue travée faisable,
  couverture/lignes — vit dans le crate, parallélisée sur les départs via `rayon`. R prépare
  les entrées et réassemble les sorties SIG (frontière minimale et typée, ADR-001).
  **Non-régression bit-pour-bit** vis-à-vis de l'ancienne double boucle R (arrondi demi-au-pair
  et `seq()` reproduits). Gain **~5×** (60 × 60, 60 départs : 36 s → 6 s), passage à l'échelle
  par le parallélisme. Ancien helper R `.ligne_cable()` retiré. 18 tests cargo, 728 tests R verts.
- **Article carto** (livré avec 0.12.0) : **« Cartes de sortie sur une AOI réelle »** — pipeline
  complet sur `data-raw/aoi.gpkg` (Cévennes), chaque sortie sur fond OSM, cartes pré-rendues
  (`data-raw/cartes.R`) et embarquées. Benchmark des durées par étage sur 721 ha documenté
  (terrestre ~1 min 35 s ; câble = goulot avant portage — désormais accéléré et parallèle).
- **Lots 0–10 livrés** : prétraitement, moteurs skidder / porteur, noyau câble (Rust) +
  sélection, camion DFCI (beta), passage à l'échelle (tuilage), base spatiale & agrégation,
  doc & publication, et **acquisition depuis AOI** (Lot 10). Périmètre v1 fonctionnel atteint.
- **Lot 10 (acquisition depuis AOI)** : `acquire_inputs()` télécharge MNT/desserte/forêt/
  obstacles/cadastre depuis une AOI (IGN Géoplateforme via `happign`, OSM via `osmdata`),
  config-driven (`inst/datasources/FR.json` + résolveur), sorties consommables par
  `preprocess()`. Appels réseau isolés en wrappers mockables : tests unitaires hors-ligne
  (57 tests), intégration réseau opt-in. `happign`/`osmdata` en Suggests. Vignette
  d'acquisition. `specs/010`.
- **`v1.0.0` posée** (2026-07-15, bump majeur confirmé par l'utilisateur). Tous les préalables qui
  la justifiaient étaient levés : la validation contre le vrai moteur (Lot 11), la décomposition
  des distances (écart médian 0 m, pondération de piste comprise), et le **Lot 6 (DFCI)** confronté
  à l'oracle (12a.4, 99,87 %). Suite possible : dettes câble (hauteur de fixation, sélection de
  lignes tamponnées) et Phase 2 acquisition (MNH LiDAR → volume, BD Forêt v3), en `1.x`.
- **`v1.6.0` posée** (2026-07-21) : **`places_depot()`**. Le moteur câble exigeait une couche de
  places de dépôt (`potentiel_cable(departs = )`) sans aider à la produire ; `places_depot()` en
  dérive des **candidates** de la desserte (accès camion → demi-tour → planéité → proximité de la
  forêt). Explicitement heuristique : une place de dépôt reste un fait de terrain, et Sylvaccess la
  traite en donnée d'entrée.
- **`v1.6.1` posée** (2026-07-21) : **`places_depot()` confrontée à l'oracle ColduPre** — la v1.6.0
  retrouvait **0 des 2** vraies places (attribut relevé `CABLE`). Trois erreurs de modèle corrigées
  (planéité mesurant le **versant** au lieu de la route ; rejet sur `classe`/`dfci` alors qu'une
  vraie place est une piste non DFCI ; éclaircissement inter-tronçons évinçant les deux). Après
  correction : **rappel 2/2**, 54 tronçons sur 125, **précision ~4 %** — la fonction est requalifiée
  en **pré-filtre grossier**, pas un relevé. Banc `data-raw/oracle_places_depot.R`.
  **Règle qui en découle** : toute heuristique se confronte à ColduPre **avant** la PR ; les
  fixtures synthétiques ne testent que la cohérence interne.
- **`v1.12.0` posée** (2026-07-22) : **perf du glouton de desserte** (chantier 1). A* borné au
  couloir de raccordement (`solver.rs`) : **200 s → 20 ms/tracé**, bit-identique ; `skidding_m`
  documenté comme le levier du nombre de tracés (6 parcelles en 7,7 s réglé sur le débardage).
  Glouton **~11,5 min → dizaines de s**.
- **`v1.13.0` posée** (2026-07-22) : **chantier 1 volet 2**. Optimiseurs tractables (multistart
  n_start=16 → 10,5 s), bornes documentées ; **crash latent de Steiner corrigé** (garde `came_from`
  dans `basic_calc`, jamais vu car Steiner jamais exécuté à l'échelle). Steiner tourne mais reste
  O(N²).
- **`v1.14.0` posée** (2026-07-22) : **chantier 4** — `acquire_desserte_lidar()` (ALSroads, NDP 1,
  spec 020). Enveloppe fine, lidR/ALSroads dynamiques (repli NDP 0 testé), chemin NDP 1 **validé
  bout-en-bout** sur les données d'exemple d'ALSroads (colonnes réelles : `DRIVABLEWIDTH`, `CLASS`=état
  4 classes). **Phase B validée en `v1.16.0`** (Chastel-Nouvel, MNT ≥ 1 m → 22/22 pistes mesurées ;
  le 0/6 de v1.15.0 était un faux négatif dû à un MNT à 5 m). **Brief desserte : 5 chantiers bouclés**
  (1, 2, 3 livrés ; 4 Phases A+B ; 5 résolu de fait). Chantier 4 : **GO expérimental**.
- **`v1.7.0` posée** (2026-07-22) : **`volume_depuis_p1()`**, pont entre l'indicateur **P1** de
  Nemeton (volume sur pied m³/ha, inventaire ou MNH LiDAR) et le raster `pre$volume` que somment le
  câble et la sélection (→ volume de ligne, IPC). Rasterise un `sf` d'unités sur la grille du MNT ;
  **aucune dépendance à Nemeton** (consomme la sortie déjà calculée) → règle stricte 1 respectée,
  aucune écriture dans le repo frère (règle 6).
- **`v1.8.0` posée** (2026-07-22) : **`acquire_inputs(volume=)`** — le volume `P1` (Nemeton) est
  relayé dans `out$volume`, aligné sur le MNT bufferisé, prêt pour `preprocess()`. Passthrough
  polymorphe sans dépendance Nemeton (spec 019, Option B). Constat d'audit : nemetonshiny charge
  déjà le MNH et orchestre ForêtAccess mais ne passait pas `volume=` — trou comblé côté ForêtAccess ;
  le raccord P1 côté nemetonshiny reste à porter par une session Nemeton (règle 6). L'écart
  « Phase 2 volume » de `specs/010` est **levé**.
- **`v1.9.0` posée** (2026-07-22) : **validation ACCESSFOR (IGN), §3 élucidé**. `accessfor_correspondance()`
  fige le crosswalk `class` ACCESSFOR ↔ `classes_debardage()`, vérifié au WFS sur le dép. 48 (domaine
  identique terme pour terme, skidder et porteur, jusqu'à la bande ouverte > 2000 et l'inexploitable
  pente). `classes_debardage()` généralisée au porteur.
- **`v1.10.0` posée** (2026-07-22) : **validation ACCESSFOR §5**. `comparer_accessfor()` (rasterisation
  near, intersection des masques, matrice de confusion) confronte skidder/porteur à ACCESSFOR sur
  Chastel-Nouvel : **accord agrégé 81 % (skidder) / 86 % (porteur)**, stable au masque. `docs/comparaison-accessfor.md`.
  **Brief ACCESSFOR clos.** Prochain brief nemeton reçu (`brief-foretaccess.md`, 4 chantiers : perf desserte,
  connexité, câble/places de dépôt, `$lignes` contracté) — chantiers 2+3 d'abord.
- **Dette assumée du câble** : optimisation de la hauteur de fixation. Le portage de
  `c_option_h = 1` (Sylvaccess `OptPyl_Up`/`Up2`) a été **tenté puis abandonné le 16/07** (bugué,
  ~20× plus lent, code d'origine lui-même planté). **Voie retenue à la place** : transcrire
  l'algorithme **SEILAPLAN** (Bont & Heinimann 2012, graphe + plus court chemin), plus sain et
  validé — voir `specs/013-seilaplan-hauteur.md` et `docs/comparaison-cable-seilaplan.md`. Le `_NoH`
  (défaut) reste intact. Phase 2 acquisition : MNH LiDAR → volume, BD Forêt v3.
- **Cycle dev ouvert sur `v1.28.0.9000`** (dernière release `v1.28.0`, 2026-07-29). Quatre specs
  y sont mergées et **non encore releasées** : **025** (intégrité du réseau, #136), **027**
  (provenance des caches, #139), **028** (OSM source complémentaire, #139) et **026**
  (desserte détectée sur MNT, #140, **partielle**). Release visée : **`1.29.0`** sur la spec 027,
  qui est la seule complète.
- **`v2.0.1` posée** (2026-08-10) : correctif de compatibilité interne à la v2.0.0.
  `preprocess()` rejetait les `hors_desserte` que `acquire_desserte()` produit par défaut —
  chaîne acquisition → prétraitement cassée pour tout appelant. Filtrage explicite en amont de
  chaque rasterisation (la sentinelle `-2147483648` de `terra::rasterize()` écrasait sinon les
  cellules de **jonction**). `preprocess()` est désormais **invariant** sous
  `garder_hors_desserte`. Le consommateur topologique réel est `verifier_integrite_desserte()`
  (spec 025), maintenant nommé dans la doc.
- **`v2.0.2` posée** (2026-08-11) : version de **documentation**, aucun changement de code
  depuis `2.0.1`. Fige la validation du correctif `hors_desserte` sur le cache DABO réel
  (0 sentinelle, invariance sur les 5 couches, 3 couches de desserte) et la mesure du glouton
  (`docs/brief-nemetonshiny-skidding-desserte.md`) : 309 726 cellules-source sur DABO, et
  `skidding_m = 0` (le défaut) = pire cas documenté — > 22 min contre 70-174 s à distance de
  débardage réaliste.
- **`v2.1.0` posée** (2026-08-12) : version **mineure**, trois exports de plus, aucune rupture.
  Publie le **coût de terrassement** (spec 029, `cout_terrassement()`, `methode_pente`,
  `largeur_m`, `pente_max_pct`) — écrit, testé, **non activé**, le banc DABO ayant montré que
  basculer *agrandit* l'ensemble des cellules constructibles (+4,45 %) et déplace la moitié du
  tracé. Publie aussi les **quatre formes de `specs`** de `detecter_desserte()` (dont `"auto"`,
  qui calibre sur place) et `specs_depuis_calibration()`. Corrige deux silences : `pondere_cout`
  qui jetait la surface de coût sans le dire, et `verifier_integrite_desserte()` dont le verdict
  vide se lisait comme « aucune infraction » (champs `disponible`/`raison`, `dessertR_disponible()`).
  **`dessertR` reste non déclarable** : `rlas` est archivé sur le CRAN, la déclaration cassait
  l'installation pour tous.
- **`v2.2.0` posée** (2026-08-13) : client Overpass unifié (`osm_overpass()`, ADR-010 — pire cas
  borné, obstacles 5→1, dfci 3→1, `osmdata` retiré) et **résultat des deux premières campagnes
  d'annotation terrain**. Le CA-26.5 est enfin instruit : rappel 0 % → 75–78 % après correction
  d'un veto `vesselness` compté deux fois, validé en leave-one-out sur `wsfi` (montagne) ET
  `ltcp` (plaine). **La précision plafonne à 23–36 %** et les limites parcellaires sont détectées
  à chaque fois — c'est le chantier restant.
- **`v2.3.0` posée** (2026-08-14) : **profil en travers au clic** (spec 030, `profil_travers()`) —
  la coupe transversale d'un tronçon à une station, **points LiDAR compris**, ce qu'aucun moteur ne
  rendait (`dsr_profils()` échantillonne le MNT, `dsr_layers_pc()` ne rend que des rasters). Cinq
  familles de bords **emboîtées par construction** (`drivable ⊆ road ⊆ rescue ⊆ right_of_way`),
  0,42 s par clic à froid sur dalle réelle, `road` = 3,58 m contre 3,58 m pour `dsr_measure()` au
  même endroit. **L'emprise se lit sur les troncs (0,5–5 m), pas sur le couvert** : sous futaie
  fermée les houppiers se referment au-dessus de la piste, et le critère « couvert » rend une
  emprise égale à la plateforme. Publie aussi `classer_desserte()`, qui solde la dette de
  dépendance de `nemetonshiny` (appel direct à `dessertR::dsr_classer()` derrière un `tryCatch`
  muet).
- **`v2.4.0` posée** (2026-08-14) : `comparer_desserte_osm()` rend la **géométrie hors corridor**
  (`$osm_hors_corridor`, `$bdtopo_hors_corridor`), qu'elle calculait déjà et jetait. Ajout
  strictement additif — trois tables, classe et coût de calcul inchangés. Géométrie **clippée**
  (un tronçon à moitié dans le corridor n'est rendu que pour sa moitié dehors), attributs d'origine
  plus `hors_m`, type homogène en `MULTILINESTRING` (seul piège réel : sans le cast la couche part
  en GeoPackage avec deux types), couche vide en `sf` à 0 ligne. Débloque le calque « pistes OSM
  hors BD TOPO » de `nemetonshiny`, qui écrivait jusqu'ici la couche OSM **brute**, doublons de la
  BD TOPO compris. **CA-28.3 clos le 2026-08-15** : la table du §1 de la spec 028 est
  reproduite cellule pour cellule (`data-raw/ca_28_3_table_sec1.R`) ; l'écart apparent
  venait de la classe `hors_desserte`, conservée par défaut depuis le 2026-07-30, qui
  élargit le corridor (spec 028 §1.3). Restent ouverts sur la spec 028 : **CA-28.1**
  (couvert par les tests de `test-desserte-osm.R`, jamais coché) et **CA-28.4**
  (invariant « aucun tronçon OSM dans `desserte_existante` sans qualification »).
- **Spec 026 bloquée sur le CA-26.5**, pas sur du code. `detecter_desserte()` et
  `detecter_desserte_balayage()` sont livrés (`R/desserte-detectee.R`) avec le tarif de réouverture
  (`config$desserte$cout$fraction_reouverture`) ; **l'injection dans `reseau_desserte()` est
  délibérément non faite** tant que le CA-26.5 n'est pas tranché — sans quoi on ajouterait du
  réseau fantôme à un modèle qu'on vient de rendre conforme à ACCESSFOR. Le banc est **`wsfi`**
  (MNT 0,50 m), Chastel-Nouvel étant disqualifié pour cause de MNT à 5 m.

## Avancement par lot

| Lot | Nom | Spec | État | Release |
|---|---|---|---|---|
| 0 | Fondations | `specs/000-fondations.md` | ✅ terminé | `v0.1.0` |
| 1 | I/O & prétraitement | `specs/001-pretraitement.md` | ✅ terminé | `v0.2.0` |
| 2 | Moteur Skidder | `specs/002-skidder.md` | ✅ terminé | `v0.3.0`, `v0.3.1` |
| 3 | Moteur Porteur | `specs/003-porteur.md` | ✅ terminé | `v0.5.0`, `v0.5.1` |
| 4 | Noyau Câble (Rust) | `specs/004-cable.md` | ✅ terminé (3 supports) | `v0.6.0`, `v0.13.0` |
| 5 | Sélection lignes câble | `specs/005-selection.md` | ✅ terminé | `v0.7.0` |
| 6 | Camion DFCI (radial) | `specs/006-dfci.md` | ✅ terminé (12a.4, oracle 99,87 %) | `v0.8.0`, `v1.0.0` |
| 7 | Passage à l'échelle | `specs/007-passage-echelle.md` | ✅ terminé | `v0.4.0` |
| 8 | Base spatiale & agrégation | `specs/008-base-spatiale.md` | ✅ terminé | `v0.9.0` |
| 9 | Doc & publication | `specs/009-publication.md` | ✅ terminé | `v0.10.0` |
| 10 | Acquisition depuis AOI | `specs/010-acquisition-aoi.md` | ✅ terminé | `v0.11.0` |
| 11 | Oracle Sylvaccess réel | *(journal 2026-07-13/14)* | ✅ terminé | `v0.13.0` |
| 12 | Fidélité fine & performance | `specs/012-fidelite-performance.md` | 📋 proposé | `v0.14.0`, `v0.15.0` |
| 13 | Hauteur supports câble (SEILAPLAN) | `specs/013-seilaplan-hauteur.md` | ✅ terminé (oracle 94,7 %, perf ×2,8) | `v1.1.0` |
| 14 | Coût de construction de desserte | `specs/014-cout-construction.md` | ✅ terminé (R pur, 32 tests) | *(cycle dev)* |
| 15 | Solveur de tracé (A*) | `specs/015-solveur-trace-astar.md` | ✅ terminé (15a→15c, invariants ; oracle non publié) | *(cycle dev)* |
| 16 | Réseau MTAP | `specs/016-reseau-mtap.md` | ✅ livré (16a glouton, 16b Steiner, 16c connexité) | *(cycle dev)* |
| 17 | Flux & typage | `specs/017-flux-typage.md` | ✅ livré (17a vectorisation, 17b flux, 17c typage) | *(cycle dev)* |
| 18 | Optimisation du réseau | `specs/018-optimisation-multistart.md` | ✅ livré (18a multi-start, 18b recuit, 18c rip-up) | *(cycle dev)* |

Chemin critique MVP : 0 → 1 → (2 ∥ 3 ∥ 4) → 5 → 7 → 8 → 9.

## Décisions structurantes

Les ADR font foi (`docs/adr/`). Rappel des décisions qui contraignent le code en cours :

- **ADR-002** : le vectoriel va en PostGIS/GeoPackage, le raster sur disque
  (GeoTIFF/COG). Jamais de raster en base.
- **ADR-003** : aucune valeur métier codée en dur ; tout seuil vient de
  `foretaccess_config()` (défauts Sylvaccess v3.6).
- **ADR-004** : découplage de l'I/O — chaque entrée est acceptée soit comme chemin
  de fichier, soit comme objet déjà chargé (`SpatRaster` / `sf`).
- **ADR-006** : non-régression via `compare_to_oracle()`. Au Lot 1 l'oracle est
  **analytique** (MNT jouet = plan incliné à 20 %) ; les oracles réels Sylvaccess
  v3.6 viendront plus tard.
- **Lot 1, §10** : politique CRS/grille **stricte** (erreur, pas de reprojection ni
  de rééchantillonnage silencieux) ; pente/exposition via `terra`/Horn, méthode
  **configurable** ; rasters en mémoire, écriture COG **optionnelle**.
- **Aucune couche sans CRS** n'est admise dans le projet : `valider_entrees()`
  rejette toute entrée dont le CRS est absent, sans jamais le compléter par
  défaut. Verrouillé par un test de non-régression.
- **Code R portable** : `R CMD check` interdit le non-ASCII dans les *chaînes*
  littérales (les commentaires et le roxygen le tolèrent). Les messages `cli`
  s'écrivent donc translittérés (é→e, à→a, ç→c).

## Lot 1 — état détaillé

Lot **terminé** et publié en `v0.2.0` (PR #7). Definition of Done intégralement
satisfaite : `preprocess()`, `valider_entrees()`, `calculer_terrain()` et
`lire_rasters()` livrés, critères d'acceptation CA-1.1 à CA-1.6 tous couverts par
des tests verts (oracle analytique du MNT jouet), CI verte sur les sept checks,
couverture globale à **97,91 %** (`R/io.R`, `R/validate.R`, `R/terrain.R` et
`R/preprocess.R` à 100 %).

### Effets de bord assumés

- `slope_pct`, `aspect_deg` et `exclusion_mask` valent `NA` sur la couronne de
  bordure : le calcul de pente exige les 8 voisins. Documenté (roxygen) et testé.
- `aspect_deg` vaut `NA` sur les cellules plates, là où `terra` renvoie 90.
- Le raster de desserte relu depuis un COG voit sa colonne de catégories renommée
  d'après la couche (`desserte` et non `classe`) : c'est GDAL. Les libellés sont
  préservés.

## Prochaine étape

*(Section réécrite le 2026-07-31. Elle décrivait encore le Lot 4 — noyau câble —, clos depuis
`v0.13.0`. Une « prochaine étape » périmée est pire qu'absente : elle envoie rejouer un chantier
déjà livré.)*

1. **Re-vérifier l'invariance contre l'API amont.** La preuve tenue (indice `p` à 0,092 % des deux
   côtés) a été obtenue avec notre contournement, pas avec `dsr_c_vessel()` /
   `dsr_calibrer_specs(bornes = TRUE)`. ~30 min.
2. **Sonder le vectoriseur `agent`.** Depuis dessertR 1.1.0, `methode = "auto"` résout vers
   **`agent`** et non plus vers le squelette, et le poids du canal de surface passe de 2 à 0,5.
   **Aucune de nos mesures ne porte sur cette chaîne** — ni résultat, ni temps. Sonder avant
   d'engager un balayage complet.
3. **Réécrire le protocole du CA-26.5**, qui balayait `seuil` en tenant l'emprise pour neutre.
4. **Couper la release `1.29.0`** sur la spec 027, complète depuis que le CA-27.1 est
   effectivement tenu. Elle emporte aussi 025 et 028, déjà mergées.
5. **Selon le verdict du CA-26.5** : injection dans `reseau_desserte()` au tarif de réouverture
   (spec 026 §5.4) → `1.30.0`, ou troisième banc plus vaste (bloc `ltcp`, 25 dalles) si `wsfi`
   ne tranche pas.

**Question de fond non tranchée** : la calibration de référence est figée sur **un** massif
(Chastel-Nouvel, 1 km², Lozère). C'est ce qui rend `seuil` comparable entre sites, mais une dalle
de montagne n'est pas un jeu national — et elle recouvre `wsfi` à 54 %, donc `wsfi` n'est pas un
banc indépendant. dessertR 1.1.0 calibre sur **deux** massifs.

Le portage Rust des moteurs **terrestres** reste **après le tuilage** : à l'échelle du
département, le Lot 7 suffit (cf. § performance).

### Dette assumée du Lot 2

- Seule l'**option de modélisation 1** (privilégier le treuillage) est implémentée ;
  l'option 2 lève une erreur explicite.
- La hiérarchie route / piste est réduite à deux niveaux (`route` et `dfci` comptent
  comme routes).
- Le Dijkstra et le balayage radial sont en R pur (cf. § performance ci-dessous).
  La frontière est au bon endroit : `propager_cout()` ne connaît aucune règle métier.

## Performance — mesures sur AOI réelle (2026-07-10)

AOI de 7,2 km² (294 130 cellules à 5 m, pente médiane 34 %), MNT RGE ALTI, forêt BD
TOPO. **Temps CPU** (`user.self`), la machine étant chargée : le temps écoulé valait
alors le double, et ne mesurait que la contention.

| Étage | CPU |
|---|---|
| `zone_roulable_connectee()` | 6,62 s |
| `treuiller()` (balayage radial) | 10,99 s |
| `propager_cout()` (roulage) | 6,29 s |
| **`skidder()` complet** | **21,97 s** |

Soit **3,05 s/km²** sur un cœur. Extrapolation : massif de 100 km² → 5 min ; département
de 2 000 km² → 1,7 h ; région de 20 000 km² → 17 h ; France (170 000 km²) → 6 jours.
Divisé par 8 sur 8 cœurs, le département tombe à 13 min et la France à 18 h.

**Verdict Rust** : le portage n'est pas justifié à l'échelle du massif ni du département —
le Lot 7 y suffit. Il l'est pour la région et la France. Et le candidat au portage est
**le Dijkstra** (12,9 s CPU cumulés, 59 %), non le balayage radial (11,0 s, 50 % — les
deux se recouvrent, le total inclut aussi le prétraitement). C'est l'inverse de ce que
la première mesure suggérait : elle précédait `zone_roulable_connectee()`, qui ajoute un
Dijkstra. Deux réserves : l'AOI est **raide**, donc les rayons de treuil y meurent vite —
un plateau doux inverserait le rapport ; et le Dijkstra bénéficierait aussi d'un tuilage,
pas seulement d'un changement de langage.

### Ce que coûte le tuilage (Lot 7, 2026-07-10)

Le certificat n'est satisfait que si le **halo dépasse la plus longue distance qui peut
entrer dans la tuile**, et le surcoût surfacique croît comme `(1 + 2·halo/tuile)²`.
Mesuré sur une grille synthétique de 2 km (160 000 cellules, dessertes tous les 400 m) :

| Configuration | CPU | Surcoût |
|---|---|---|
| mono-bloc | 11,2 s | — |
| tuiles 1000 m, halo 250 m | 28,1 s | **2,5×** (prédit 2,25×) |
| tuiles 250 m, halo → 500 m (1 km d'emprise) | 87,0 s | **27×** |

D'où la règle `tuile_m ≥ 4 × halo_m`, et surtout : ne jamais laisser une propagation
kilométrique piloter le halo. `distance_trainage_piste` en était une (4 030 m sur l'AOI
réelle) ; elle est désormais **précalculée globalement** sur le réseau de desserte, qui
est unidimensionnel et creux. Elle a cessé d'être un moteur de halo.

**Le parallélisme n'a pas pu être mesuré ici.** La machine de développement injecte de
l'idle (`idle_inject/*`, throttling thermique du noyau) : la charge affichée est de 6 à
10 sur 8 cœurs sans qu'aucun processus utilisateur ne tourne, et le temps écoulé vaut
systématiquement le double du temps CPU. Le gain des workers est donc à re-mesurer sur
une machine non bridée. L'exactitude, elle, est vérifiée : `workers = 4` donne un
résultat identique bit à bit à `workers = 1`.

*(Correction : j'avais d'abord attribué cette charge à des workers `workRSOCK` orphelins
laissés par `covr`. C'était faux — ce sont des threads noyau.)*

### Bogues de performance corrigés (Lot 2)

Deux bogues de performance corrigés en cours de route, tous deux dans du code à moi :

- **Tas binaire recopié** : passé de fonction en fonction dans une liste, chaque
  `tas$cle[i] <- x` recopiait le vecteur entier (sémantique de copie de R). Sonde isolée :
  96,44 s contre 0,27 s pour 200 000 insertions, soit **357×**. Corrigé par des vecteurs
  locaux mutés via `<<-`.
- **Rayons de treuil non compactés** : le balayage portait des vecteurs pleine longueur
  sous un masque `vivant`, alors que la plupart des rayons meurent en quelques cellules.
  Compaction des survivants : 34,7 s → 16,1 s, distances et allocations **bit à bit
  identiques**.

### Le `.pyx` est public

Le dépôt `forge.inrae.fr/sylvain.dupire/sylvaccess` est **public** : l'API GitLab
répond sans authentification (c'est la page HTML qui affiche un écran de connexion
trompeur). `scripts/sylvaccess_cython3.pyx` a été lu, et il **contredit deux
hypothèses** de la première rédaction de la spec :

- la **fonction de coût est isotrope** (`√(1 + (p/100)²)`, facteur d'allongement 3D) :
  il n'y a aucun Tobler dans Sylvaccess ;
- le **treuillage n'est pas un least-cost** mais un balayage radial 360° au pas de 1°,
  en ligne droite, avec une contrainte de dégagement du câble (0–30 m au-dessus du sol,
  attache à 10 m) et une distance **3D** ;
- la **loi de bascule** est affine en **dénivelé**, pas en pente : à plat,
  `Dmax = 80,23 m` (ni 50 ni 100). Une interpolation linéaire en pente — l'hypothèse
  naturelle — aurait donné 62 m au lieu de 50 m à 30 % de pente, soit **20 % d'erreur
  silencieuse**.

Backend retenu : **Dijkstra maison**. `terra::costDist()` accumule la friction
**moyenne** des deux cellules (9,5 au lieu de 10 sur dix cellules à friction 1) et
diverge donc systématiquement ; ni lui ni `leastcostpath` ne renvoient l'allocation.

---

## Journal

### 2026-08-15 — CA-28.3 clos : la table du §1 tombe au centième, et pourquoi elle a bougé

`comparer_desserte_osm()` reproduit la table du §1 de la spec 028 **cellule pour
cellule** sur l'AOI Chastel-Nouvel (`data-raw/ca_28_3_table_sec1.R`) : `track`
13,522 contre 13,52 km hors corridor, `path` 14,090 contre 14,09, `unclassified`
1,058 contre 1,06, `tertiary` 3,792 contre 3,79, part déjà couverte **55,7 %**
contre 55,7 %. Le §1.2 tombe juste sans rien retirer : `piste` 5,4006 km,
`reseau_public` 0,0099 km.

**Le premier passage ne tombait pas juste, et c'est ça qui était intéressant.**
La BD TOPO acquise aujourd'hui rend **214 tronçons / 55,77 km** contre 169 / 44,64
en juillet. L'écart n'est ni une dérive de la fonction ni une édition amont : c'est
la classe **`hors_desserte`** (sentiers, ronds-points, liaisons, `CL_SVAC = 0`),
conservée par défaut depuis le 2026-07-30 — 45 tronçons, 11,13 km, exactement
l'écart. Ces tronçons **élargissent le corridor**, donc rabotent le linéaire OSM
compté dehors : `track` 13,52 → 12,07 km, `path` 14,09 → 9,30. Retirer la classe
rend les 169 tronçons et 44,64 km au tronçon près, et la table entière avec.

Le resserrement va dans le bon sens : un `track` OSM qui suit un sentier déjà
présent en BD TOPO n'est pas une découverte. La spec porte désormais un §1.3 qui
donne les deux colonnes — la mesure historique, et ce qu'un appelant obtient
aujourd'hui sans argument particulier.

**Ce que la 2.4.0 a permis de vérifier en plus des nombres** : la longueur de
chaque géométrie clippée **égale `hors_m` à 0 m près** (67 tronçons), et
`tracktype` est renseigné sur **13 `track` sur 26** — les 50 % du CA-28.2,
retrouvés deux semaines plus tard sur un tirage indépendant. On ne vérifie plus
seulement une table : on ouvre la couche qu'elle compte.

Nuance conservée : sur les entrées du §1, les `track` hors corridor sont
aujourd'hui 28 pour 13,52 km, là où l'annotation du CA-28.5 en couvrait 24 pour
13,41 km. Les 4 de plus pèsent 0,11 km, mais le taux de 92,9 % porte sur les 24.

### 2026-08-14 — `v2.4.0` : la géométrie qu'on calculait puis jetait

Brief reçu de la session `nemetonshiny`
(`specs/brief-foretaccess-comparer-osm-geometries.md`), et il tenait en une
observation : l'helper `hors()` de `comparer_desserte_osm()` calculait
`st_difference(troncon, corridor)` — exactement le gisement, géométrie comprise —
puis en prenait la longueur et **jetait l'objet**. Les 104 s du recoupement
étaient déjà payées ; seul le résultat le plus utile ne sortait pas.

**Ce n'était donc pas un arbitrage coût/valeur, mais une fuite.** `hors()` rend
maintenant `list(long, parts)`, et `.sf_hors()` assemble les morceaux non vides en
une `sf` — attributs d'origine plus `hors_m`, colonnes de travail exclues. Les
trois tables, `resume` et la classe `foretaccess_osm_compare` ne bougent pas :
c'est le test de non-régression qui compte, et les quatre valeurs déjà assertées
tiennent au 1e-6 près.

**Le seul piège est le type de géométrie.** `st_difference` rend un `LINESTRING`
quand le corridor ne coupe rien et un `MULTILINESTRING` quand il coupe le tronçon
en deux ; l'`sfc` assemblé porte alors **deux types** et l'écriture GeoPackage en
aval devient hasardeuse. `st_cast(g, "MULTILINESTRING")` homogénéise. Vérifié
aller-retour sur GeoPackage, couche vide comprise (0 ligne typée, CRS conservé,
jamais `NULL`).

**Le clip n'est pas cosmétique** : rendre le tronçon entier afficherait comme
« absent de la BD TOPO » un linéaire qui y figure. Un test dédié prend un tronçon
perpendiculaire coupé en deux par le corridor — 200 m d'origine, 170 m rendus.

Ce que ça vaut est mesuré, pas espéré : le juge de paix CA-28.5 (annotation du
2026-07-31 sur ortho IGN, 24 tronçons, 13,41 km) donne **92,9 % du linéaire hors
corridor en desserte réelle** pour 4,4 % de faux positifs. La réserve du §1.1 de
la spec 028 reste juste et le `print()` la répète mot pour mot — mais on ne
refusait pas du bruit à l'utilisateur, on lui refusait un résultat.

**CA-28.3 reste ouvert** : reproduire la table du §1 demande l'AOI oracle
Chastel-Nouvel et un appel Overpass, hors de portée d'une session hors ligne. Les
géométries donnent désormais de quoi le clore proprement — vérifier la table *et*
inspecter ce qu'elle compte.

### 2026-08-14 — `v2.3.0` : le profil en travers, et ce que la vraie dalle a corrigé

Brief reçu de la session `nemetonshiny`
(`specs/BRIEF-profil-travers-desserte.md`) : un clic sur la carte, le profil en
travers du tronçon le plus proche. Le brief posait lui-même la seule vraie
question (§4) — *le nuage, ou le MNT ?* — et il avait raison de la poser :
`dsr_profils()` échantillonne le **MNT**, `dsr_layers_pc()` ne rend du nuage que
des **rasters**. Rendre les **points** demandait une extraction, qui n'existait
nulle part. Le reste (accrochage, station, chaînage, profil du terrain) est de la
géométrie ; l'écrire coûtait moins cher que de plier `dsr_profils()`, qui
travaille par tronçon entier, à une station unique.

**La conception qui a changé après mesure — et elle n'aurait pas changé sur des
fixtures.** L'emprise (`right_of_way`) se définit intuitivement comme *« la plage
sans écho à plus de 2 m du sol »*. Passée sur la dalle d'exemple `dessertR`
(Lozère, futaie fermée, piste de 3,6 m), cette définition rend une trouée
**nulle** : les houppiers se referment **au-dessus** de la piste. L'emprise
tombait donc exactement sur la plateforme, à toutes les stations — une famille
qui ne dit plus rien, et qu'aucun test synthétique n'aurait dénoncée (un nuage de
synthèse « raisonnable » ne met pas de couvert au-dessus de la route). Les
**troncs**, eux, s'écartent : 23 m de couloir libre à la même station. La bande
de mesure est donc 0,5–5 m, et le jeu de synthèse porte désormais un couvert
fermé **au-dessus** de la route, en test de non-régression de conception.

**Ce que la dalle réelle a aussi confirmé** : `road` = 3,58 m, soit la valeur de
`dsr_measure()` (`LARGEUR_ROULABLE_MED`, méthode chaussée) au même endroit, et
`drivable` = 3,29 m contre 3,11 m à la station la plus proche. 10 stations sur
10 rendues le long du tronçon, emboîtement respecté partout, **0,42 s par clic**
à froid (0,08 s en cache) — le budget « quelques secondes » tient parce qu'on lit
un rectangle, jamais une dalle.

**L'ordre des familles est construit, pas espéré.** `drivable` est écrêté par
`road`, `rescue` part de `road` et s'arrête au talus, `right_of_way` est une union
avec `road`. Un test vérifie l'emboîtement des **bords**, pas seulement des
largeurs.

**Dette de dépendance soldée dans le même lot** (brief §7) : `classer_desserte()`
enveloppe `dsr_classer()`. L'app l'appelait directement, derrière un
`tryCatch(NULL)`, sans jamais déclarer `dessertR` — le classement disparaissait en
silence sur un poste sans le moteur. L'indisponibilité est désormais un
avertissement et un attribut `disponible`, pas une absence.

### 2026-08-10 — `v2.0.1` : les deux moitiés de la v2.0.0 étaient incompatibles

Brief reçu de la session `nemetonshiny`
(`BRIEF-foretaccess-hors-desserte-preprocess.md`) : **l'onglet Accessibilité est
entièrement bloqué**, tous chemins, tous projets. `acquire_desserte()` conserve
les `hors_desserte` par défaut depuis le 2026-07-30, et `preprocess()` les
**rejette**. Aucun appelant ne pouvait consommer le nouveau défaut ;
`valider_entrees()` étant exportée, le blocage valait pour tout code utilisateur.
Le brief est exact sur tous les points vérifiables, y compris le diagnostic du
piège ci-dessous.

**Le correctif évident était faux, et silencieusement.**
`terra::rasterize(field = ...)` grave la sentinelle `-2147483648` dans les
cellules atteintes par une géométrie à champ `NA` — et elle **survit à
`fun = "max"`**, écrasant la classe valide d'une cellule partagée. Se reposer sur
le `NA` de `match()` aurait amputé le réseau **à ses jonctions**, là où un sentier
rejoint une route : 440 cellules sur 24 259 mesurées sur DABO à 5 m, et **95
cellules à la sentinelle, 3 valides écrasées, sur le seul jeu jouet** (vérifié
ici avant de coder). On aurait transformé une erreur bruyante en amputation
silencieuse, dans le sens **inverse** de l'intention de la bascule.

Correctif : **filtrer en amont, pas seulement tolérer**. Vocabulaire d'entrée
(`.classes_desserte_connues()`) séparé du vocabulaire de débardage
(`.classes_desserte()`) ; `.sans_hors_desserte()` appliqué avant *chaque*
rasterisation. Deux consommateurs que le brief n'avait pas identifiés y passent
aussi : `.rasteriser_dfci_source()` (un `CL_SVAC = 0` apparié à une piste DFCI
par la voie OSM de `flag_dfci()` serait devenu cellule-source du camion) et
`places_depot()` (un sentier n'est pas une place de dépôt).

**Invariant désormais garanti et testé** : les sorties de `preprocess()` sont
identiques avec et sans `garder_hors_desserte`. Le paramètre ne change plus que
ce que voit le diagnostic d'intégrité.

**Question ouverte du brief (§4.4) — tranchée.** La doc v2.0.0 disait les
`hors_desserte` conservés « pour la topologie » sans nommer le consommateur. Ce
consommateur existe bien : `verifier_integrite_desserte()` (spec 025) construit
son graphe sur la couche `sf` **sans filtrer `classe`** (`.troncons_linestring_tous()`),
ces tronçons y soudent les composantes. Le bénéfice est donc réel, mais **en
amont** de `preprocess()`, et la doc d'`acquire_desserte()` le dit maintenant.

Le test de non-régression existant (`test-acquire-ign.R:356`) était **vacant** :
il ne contrôlait que `levels()` et `sum(!is.na())`, et son commentaire affirmait
l'hypothèse fausse (« `match()` leur donne NA »). Corrigé, et doublé d'un fichier
dédié qui contrôle la sentinelle explicitement.

**Confronté au cache DABO réel après la release** (1032 tronçons, 320
`hors_desserte`, MNT 5 m), sur les trois couches — `desserte.gpkg`,
`desserte_corrigee` (NDP 1, 710) et `desserte_origine`. Le correctif naïf y
aurait gravé **10 812 cellules à la sentinelle et écrasé 450 cellules valides sur
24 228 (1,86 %)** ; le correctif livré en grave **0**, rend une couche **identique
au bit près** à la desserte strictement filtrée, et `preprocess()` s'exécute de
bout en bout avec **invariance sur les cinq couches**. Les chiffres du brief
(440 / 24 259, 310 / 19 957) sont reproduits à ~2 % près — écart de grille, pas
de nature. La répartition des classes est identique au brief.

**Côté app** : rien à corriger dans `nemetonshiny`, qui appelait conformément au
contrat documenté. Le plancher `foretaccess (>= 1.20.0)` de son `DESCRIPTION` est
à bumper en `>= 2.0.1` une fois cette release publiée (point annexe du brief).

### 2026-07-31 — `v2.0.0` : les résultats antérieurs ne sont plus reproductibles

**Deuxième version majeure.** Le sens du bump suit la tradition de `v1.0.0`
(« validée contre le vrai moteur ») : il ne dit pas « périmètre atteint » mais
**« purgez vos caches »**. Deux commits `!` le justifient, tous deux des défauts
d'acquisition capables de fausser un banc entier sans rien signaler :

- **le WFS perdait des tronçons sur les grandes emprises** — 86 features contre
  245 en pavant la même AOI, soit **110 tronçons intérieurs disparus en
  élargissant l'emprise**. Corrigé par pavage + déduplication ;
- **le RGE ALTI par WMS est banni** — MNT *blocky*, médiane de pente 18,89 %
  contre 40,99 % pour le LiDAR HD, maximum à 382 %. Il a fait tourner le banc
  oracle deux semaines sur un terrain fictif.

Bump majeur **confirmé par l'utilisateur** (règle CLAUDE.md). Ni l'un ni l'autre
ne retire d'API — le `NAMESPACE` est inchangé ou enrichi — mais tous deux cassent
la **reproductibilité des résultats**, ce qui pour un paquet scientifique est la
rupture qui compte.

La release emporte **025** (intégrité du réseau), **027** (provenance des
caches), **028** (desserte OSM, CA-28.5 atteint à 92,9 %) et **026** en état
partiel assumé. Cohérence à relever : **la spec 027 existe à cause des deux
ruptures** — les caches produits par le WFS amputé et par le RGE ALTI blocky
étaient indiscernables des bons. La release corrige les défauts et livre en même
temps le mécanisme qui les aurait détectés.

### 2026-07-31 — CA-27.1 **complété** (deux `acquire_*` sans contrôle), banc `wsfi` désigné

**Le trou.** La première livraison de la spec 027 (`v1.28.0.9000`, PR #139) déclarait le CA-27.1
tenu — « toute fonction `acquire_*` écrit un sidecar de provenance ». Elle ne l'était pas :
`acquire_mnt_rgealti()` et `acquire_cadastre()` servaient leur cache **sans aucun contrôle**.
L'ironie tient à la première : elle a été écrite *en réponse* à l'incident du MNT blocky. Un cache
à 5 m aurait été servi à qui demande 1 m — le même scénario, à la résolution près. Pour
`acquire_cadastre()`, `country` change la couche source : un cache FR servi à un appel CH aurait
rendu du parcellaire du mauvais pays, sans rien pour le signaler.

**La cause n'est pas l'oubli, c'est la forme du test.** `test-cache-provenance.R` vérifiait
**quelques** fonctions ; un test qui vérifie « la plupart » ne peut pas détecter un trou. Il
**énumère** désormais la liste des fonctions d'acquisition en cache et échoue sur toute fonction
sans `politique_cache`. C'est la garde qui rend le CA-27.1 vérifiable, pas la correction elle-même.

**Décisions §7 de la spec 027 tranchées** (2026-07-30) : défaut `"reacquerir"` (un avertissement se
noie dans la sortie d'un banc — c'est exactement ce qui s'est produit avec le MNT) ; bancs de
`data-raw/` en `"echouer"` ; **empreinte `sha256` non retenue** — coûteuse sur un MNT de 250 Mo et
elle détecterait une corruption, pas le défaut visé, qui est un cache *intact* produit avec
d'autres paramètres (aucun des cinq incidents du §1 n'aurait été pris par une empreinte) ;
**pas de purge de migration** — un cache sans sidecar est déjà traité comme divergent (CA-27.3),
donc ré-acquis au défaut. Choix conforté par la perte irréversible d'une entrée de banc le
2026-07-31 : **le code ne supprime pas de données d'entrée.**

**Spec 026 — trois explications successives du 0/0, les deux premières fausses.**

1. « Le corridor de 15 m ne laisse plus de surface à explorer » — **réfuté** : hors corridor, il
   reste 6,03 km² sur 7,21, soit **83,7 %**. (La densité invoquée, « 44 tronçons sur 1 km² »,
   mélangeait le linéaire — 44,64 km — et un décompte d'objets ; la valeur réelle est 197 objets
   sur 7,21 km².)
2. « La cause est la résolution du MNT à 5 m, 3,3× le seuil du garde-fou » — **non confirmé**.
   Le banc `wsfi` (MNT **0,50 m**, canal de surface, bloc de calibrage de dessertR) rend **zéro
   aux cinq seuils** en 82 min. Dix fois plus fin, et moins de détections qu'à 5 m.
3. **La cause réelle : la détection dépendait de l'emprise qu'on lui passait.** La même fenêtre de
   0,25 km² rend **116 m** analysée seule et **0 m** analysée dans 4 km². Deux mécanismes
   indépendants, aucun suffisant seul — `dsr_appartenance()` dérive ses bornes des quantiles de la
   donnée reçue (aucune spec par défaut ne les fournit), et `dsr_frangi()` dérive son `c` du
   maximum de norme de Hessien **de l'image**, en amont des appartenances, donc hors de portée de
   toute borne. Le `seuil` n'était pas une quantité absolue mais un **rang dans l'emprise**.

**Ce que ça invalide.** Le protocole du CA-26.5 balaye `seuil` de 0,4 à 0,8 en tenant l'emprise
pour neutre : il mesurait un artefact. Les 82 min de balayage, le balayage `long_min` et la
comparaison Chastel-Nouvel / `wsfi` « au même seuil » **ne sont pas commensurables** et sont à
refaire. Le protocole lui-même est à réécrire.

**Corrigé en amont le jour même.** L'audit a été porté à dessertR, qui a livré la **1.1.0** :
`dsr_calibrer_specs(bornes = TRUE)` rend désormais les bornes, `dsr_c_vessel()` + `dsr_layers_dtm(
c_vessel = )` exposent le `c` de Frangi par échelle. Le commit amont crédite « un audit
ForêtAccess sur le commit `cb9376c` ». Notre contournement (`.vesselness_ancree()`, bornes codées
à la main) est **retiré** : `specs_desserte_calibrees()` ne porte plus que la calibration de
référence produite par l'amont, sur Chastel-Nouvel. Trace d'audit :
`docs/brief-dessertR-ancrage-emprise.md`.

**Deux erreurs de méthode à retenir.** (a) J'ai diagnostiqué sur un **extrait** pour économiser du
temps de calcul, et l'extrait n'était pas transposable — c'était précisément la variable en cause.
(b) J'ai travaillé contre `dessertR` **1.0.0 installé** sans vérifier que la source était en
1.0.0.9000, puis 1.1.0 : une partie du travail (détection du sens, rejet de canaux, poids)
**réimplémentait `dsr_calibrer_specs()`**, qui existait déjà et fait mieux — 11 canaux mesurés
contre mes 4, dont `densite_sol` (AUC 0,796) que je n'avais pas vu. **Vérifier la version d'un
dépendant avant de l'auditer**, et chercher l'API existante avant d'en écrire une.

### 2026-07-29 — CA-24.5 atteint, RGE ALTI par WMS **banni**, deux diagnostics

**CA-24.5 atteint** (spec 024). Accord vs ACCESSFOR sur l'AOI, 608,5 ha comparés :
skidder **81,5 %** en 9 classes (contre 77,1 % en v1.20.0) et **88,3 %** en
agrégé (contre ~81 %) ; porteur 89,3 % / 92,0 %. Le gain est plus fort sur
l'agrégé : faire de 49 tronçons une barrière change d'abord la décision
accessible/inaccessible. L'**artefact de masque est écarté** — 0,3 pt entre les
deux variantes, alors que l'emprise change beaucoup.

**Diagnostic 1 — hypothèse des composantes orphelines : confirmée.** Sur les 6
composantes du réseau, **3 sont orphelines** ; 7 tronçons en infraction aux
contraintes de l'annexe p. 51 (0,9 km sur 46,9 km), et **32,3 ha** de forêt à
moins de 250 m d'un tronçon en infraction — à comparer aux 22,3 ha du bloc
`inaccessible` × `500-1000 m`. Même ordre de grandeur avec un buffer généreux :
corroboration, pas preuve. Ça chiffre l'enjeu de la **spec 025**. Première mise
en œuvre réelle de `dsr_reseau()`.

**Diagnostic 2 — le MNT est disculpé.** Contre les **vraies dalles
départementales** RGE ALTI (443 Mo, dép. 48, annexe p. 50), notre LiDAR HD donne
une pente quasi superposable : médiane 40,99 % contre 39,96 %, écart d'altitude
médian +0,19 m (p95 2,88 m). Au seuil du porteur (15 %), le désaccord est
**symétrique** : 8,7 ha côté LiDAR contre 10,4 ha côté RGE. Trop petit et du
mauvais sens pour porter les 29,7 ha de flips porteur. L'écart n° 4 est assumé
**et chiffré** ; le conservatisme du porteur vient d'ailleurs (pente en travers,
distance hors desserte, portée de grue).

**Le RGE ALTI par WMS est banni.** Le premier passage du diagnostic 2 utilisait
`ELEVATION.ELEVATIONGRIDCOVERAGE` par WMS et annonçait 213 ha d'écart — **25 fois
la vraie valeur**. Cause : le WMS sert une pyramide web-mercator reprojetée qui
rend un MNT *blocky*, Q1 de pente à 1,92 % pour une médiane à 18,89 % et un
**maximum à 382 %**. Un premier quartile à 3 % pour une médiane à 26 % n'a aucun
sens physique — l'erreur était détectable dans les chiffres eux-mêmes.

Pire : `data-raw/oracle/aoi/cache/layers/mnt/mnt.tif`, **daté du 14 juillet**,
était ce MNT-là — statistiques et taille de fichier identiques à l'octet près.
Le banc `aoi` a donc tourné **deux semaines sur un terrain fictif**, et les runs
Sylvaccess de la journée aussi (`input/mnt.tif` en est une copie). Corrigé :

- `fallback_layers` vidé dans `inst/datasources/FR.json` ;
- `.verifier_couches_mnt()` **lève** si une couche WMS interdite entre dans la
  chaîne — garde-fou testé, pas seulement documenté ;
- hors couverture LiDAR HD, `acquire_mnt()` **échoue bruyamment** en renvoyant
  vers la bonne source, au lieu de basculer en silence ;
- **`acquire_mnt_rgealti(aoi, dep, res_m)`** — dalles départementales depuis
  Géoservices, l'identifiant de livraison étant résolu via le flux Atom (sa date
  varie par département). C'est le produit que prescrit l'annexe ACCESSFOR.

**Troisième occurrence du jour** du même motif : un cache annule silencieusement
une correction (desserte le matin, landes l'après-midi, MNT le soir). Les trois
fois, le nom du fichier ne portait aucune trace de ce qui l'avait produit. Un
marqueur de provenance dans le cache réglerait la classe entière — à spécifier.

**Spec 026 ouverte** : desserte **détectée** sur le MNT comme amorce de
conception. `dsr_detecter()` rend caduc le jalon « CNN » de la spec 021 §5. Les
tronçons détectés forment une couche **candidate**, qualifiée avant tout usage,
avec un coût de **réouverture** distinct du coût de création. Le CA-26.5 (taux de
faux positifs sur orthophoto) est bloquant : le micro-relief rend aussi les
drains, limites parcellaires et traces fossiles.

### 2026-07-29 — banc `aoi-ugf` **abandonné**, `oracle_compare.R` prend le dernier run

**Abandon d'`aoi-ugf`.** En nettoyant les sorties des bancs pour une relance
propre, j'ai supprimé `data-raw/oracle/aoi-ugf/input/` — or `area.gpkg` y était
l'**entrée** du script, pas une sortie : la seule source de l'emprise de ce banc,
un `MultiPolygon` non reconstructible depuis le MNT en cache (qui n'en donne que
la bbox bufferisée). Aucune sauvegarde ne la contenait. Décision : abandonner ce
banc plutôt que lui substituer une bbox qui en aurait fait un banc *différent*
sous le même nom. `data-raw/oracle_aoi_ugf.R` est retiré, `aoi` et ColduPre
restent.

Deux leçons, la seconde plus large que la première :

1. Un répertoire `input/` peut contenir des **entrées irremplaçables** ; « sortie
   régénérable » se vérifie fichier par fichier, pas au nom du dossier. Je le
   savais — je l'avais écrit en tête du script le matin même — et je l'ai quand
   même effacé en classant le dossier en bloc.
2. Un banc dont l'emprise n'est **pas versionnée** est un banc fragile. `aoi`
   tient parce que `data-raw/aoi.gpkg` est dans le dépôt ; `aoi-ugf` n'avait sa
   géométrie que dans un répertoire gitignoré. Tout futur banc doit versionner
   son emprise.

**`oracle_compare.R` prend le dernier run Sylvaccess.** Sylvaccess n'écrase pas
ses sorties : il **incrémente** (`Skidder_1`, `_2`, `_3`…). Le script lisait
`_1` en dur, c'est-à-dire la toute première exécution — potentiellement très
ancienne, sur des entrées qui n'ont plus cours. Nouvel argument positionnel
`run`, défaut `"last"`, résolu **par module** (les modules peuvent avoir été
relancés un nombre différent de fois). Le suffixe reste forçable.

C'est ce qui explique que la comparaison lancée sur ColduPre rendait 99,95 % :
elle confrontait les moteurs à leur oracle historique, sans rapport avec la
classification du jour. Le défaut du script pointe d'ailleurs sur ColduPre, pas
sur `aoi` — il faut lui passer les deux répertoires explicitement.

### 2026-07-29 — `v1.28.0` : la classification suit la règle ACCESSFOR publiée (spec 024)

Décisions utilisateur : suivre **absolument** la table publiée, ajouter la route
forestière nommée, **conserver** le MNT LiDAR HD et les zonages INPN comme écarts
assumés, et renvoyer les contraintes d'intégrité en spec dédiée.

`classification = "accessfor"` devient le défaut. La table se lit sur `nature`
**seul** — `importance` n'y figure pas, ce qui était l'erreur de fond de
`clsvac`. Sur l'AOI oracle **108/256 tronçons (42 %) changent de classe** : les
49 « Route à 1 chaussée » deviennent du **réseau public** (barrière/terminus) là
où nous n'en avions aucun, et les 59 « Sentier » quittent la desserte.

Deux points d'implémentation qui méritent d'être retenus :

- **Appariement sur la modalité entière**, pas par mots-clés : un motif « route »
  trop large attraperait « Route à 1 chaussée » et la rendrait forestière. La
  leçon *Sylvaccess : la lettre, pas l'intention* s'applique mot pour mot.
- **`hors_desserte` n'entre PAS dans `.classes_desserte()`.** La rasterisation
  code les classes par leur **rang** et prend le `max` pour que la barrière
  l'emporte ; une 5ᵉ classe passerait devant `reseau_public`. Les tronçons sont
  donc retirés à l'acquisition — ce que fait aussi ACCESSFOR, dont la couche ne
  contient que les classes 1/2/3.

La route forestière nommée vient de la couche liée `route_numerotee_ou_nommee`
(`type_de_route`), jointe par `liens_vers_route_nommee` — un `cleabs` simple,
170/263 renseignés sur l'AOI. Vide sur cette emprise, donc sans effet ici.

**Spec 025 ouverte** pour les contraintes d'intégrité, automatisées :
`dsr_reseau()` de dessertR fait déjà collage de nœuds, composantes connexes et
`connecte_public` (règle 1 : on consomme). Le levier du buffer est formalisé en
**élargissement adaptatif** — mesurer la longueur en infraction *sur l'AOI
stricte* pendant qu'on élargit l'emprise ; ce qui disparaît était un effet de
bord, ce qui résiste est topologique ou réel. La remédiation est graduée en 4
niveaux, avec le niveau 3 (suppression) explicitement **non** recommandé par
défaut : c'est ce qu'ACCESSFOR a fait à la main, et l'automatiser retirerait de
la desserte réelle dès que le diagnostic se trompe.

### 2026-07-29 — conformité ACCESSFOR : écarts mécaniques corrigés, spec 024 ouverte

Le rapport final ACCESSFOR (`docs/rapport_final_accessfor_vf_fev2025.pdf`) a été
versé au dépôt. Son **annexe p. 50-52** est la notice opérationnelle de
préparation des données — elle publie ce que la spec 022 §3.4 croyait non publié.
Confrontation complète de nos entrées à cette notice.

**Conforme** : MNT (5 m ; nous sommes sur LiDAR HD, que le rapport lui-même p. 16
annonce comme futur référentiel national en remplacement du RGE Alti).

**Écarts mécaniques corrigés** (cycle dev, pas de bump) :

- **Masque forêt** — ACCESSFOR pose `FORET = 0` pour `CODE_TFV` ∈ {LA4 landes
  ligneuses, LA6 landes herbacées}. Nous comptions **tous** les polygones BD
  Forêt : 13 polygones de lande sur l'AOI comptés à tort en forêt.
  `acquire_foret(exclure_landes = TRUE)` par défaut.
- **Obstacles — 4 couches sur 9 manquaient** : `piste_d_aerodrome`, `cimetiere`,
  `reservoir`, `terrain_de_sport`. Ajoutées.
- **Obstacles — filtres attributaires absents** : `PERSISTANC = "Permanent"` sur
  l'hydro (nous bloquions les cours d'eau **intermittents**), `POS_SOL >= 0` sur
  routes et voies ferrées (nous traitions les **tunnels** en obstacles),
  `NATURE != "sans objet"` sur les voies ferrées. Et la couche hydro était
  `cours_d_eau` au lieu de `troncon_hydrographique`.
- **Routes principales** — ACCESSFOR filtre `cpx_classement_administratif` ∈
  {Autoroute, Départementale, Nationale, Route européenne, Route intercommunale}.
  Nous filtrions `importance <= 3`. **Les deux ne coïncident pas** : sur l'AOI
  oracle notre règle retenait **0** tronçon, la leur en retient **11** (des
  départementales d'importance 4). `importance` devient un repli, utilisé
  seulement si la colonne de classement manque du flux.

**Ambiguïté du rapport laissée en l'état** : le corps §2.3.4 cite les APB et la
réserve intégrale de parc national parmi les zonages ; l'annexe ne retient que
`PARC_OU_RESERVE` filtré sur `NAT_DETAIL` ∈ {RBI, RBD, RNN, RNR}. Nous suivons le
corps (APB + PN inclus, via l'INPN). À trancher, ce n'est pas un bug.

**Écart majeur renvoyé en spec** : `specs/024` — la table `NATURE` → CL_SVAC de
l'annexe p. 51 diverge de notre `clsvac` sur **108 / 256 tronçons (42 %)** de
l'AOI. Les « Route à 1 chaussée » sont du **réseau public (3)**, pas de la route
forestière ; les « Sentier » sont **hors desserte (0)**, pas des pistes. Notre
`reseau_public` piloté par `importance <= 3` n'attrape rien ici. Trop structurant
pour un correctif mécanique : décisions §6 de la spec à prendre (dont le bump).

**Piste incidente** : la BD TOPO expose des attributs DFCI natifs (`piste_dfci`,
`aire_de_retournement_dfci`, `gabarit_dfci`…), potentiellement bien meilleurs
qu'OSM pour `flag_dfci()`. **Tous vides sur l'AOI** — à vérifier sur un
département méditerranéen avant d'y investir.

### 2026-07-29 — cycle dev : garde-fou MNT, banc Phase B paramétré, banc `aoi-ugf` réparé

Trois suites de la Phase C, sans bump (cycle dev `1.27.0.9000` ; l'entrée `NEWS.md`
viendra avec la release).

**Garde-fou `res(mnt) > 1.5`.** Jusqu'à la v1.26.x, ALSroads rattrapait un MNT trop
grossier en dérivant un MNT 1 m des points sol. Ce rattrapage est parti avec lui :
un MNT à 5 m rend désormais des largeurs `NA` **en silence**, indiscernables d'un
« hors couverture » dans le `bilan` — exactement le mode d'échec qui avait fait
conclure à tort à un défaut de calibrage en v1.15.0. `.avertir_mnt_grossier()`
avertit sans rattraper. Le seuil 1,5 est repris tel quel de `.mnt_alsroads()` :
c'est une marge qui laisse passer LiDAR HD (0,5 m) et RGE ALTI (1 m) même quand une
reprojection rend `res()` = 1.0000001.

**Banc Phase B paramétré** (`Rscript data-raw/phaseB_dessertr.R [res]`), cache et
sorties suffixés — les runs coexistent. Comparaison **0,5 m vs 1 m** sur les 39
tronçons mesurés : RMSE **0,313 m**, MAE 0,222, biais **−0,076 m** (le 0,5 mesure
très légèrement plus étroit), corrélation 0,978 ; 3/39 au-delà de 0,5 m d'écart.
Mais l'**état bouge sur 5/44** (`en_service` → `abandonnee`, `hors_route` →
`abandonnee`), alors que la grille morphométrique reste à 1 m dans les deux runs :
`dsr_layers_dtm()` dérive `sigma_geo` du **MNT**, pas de la grille. `apte_grumier`
d'accord 39/39. **Décision : on reste à 1 m** — gain dans le bruit sur les
largeurs, instabilité d'état en face, et aucune vérité terrain pour arbitrer. C'est
aussi la position de `?dsr_grille_reference`.

**Banc `aoi-ugf` réparé.** Il n'avait aucun script de construction et ses entrées
Sylvaccess étaient figées sur la classification `heuristique` d'avant v1.20.0 :
23/23 en `CL_SVAC=1`, `CABLE=0` partout, donc **aucun point de départ câble**.
`data-raw/oracle_aoi_ugf.R` régénère `input/` depuis le cache (17 piste / 6 route,
**6 départs câble**). `results/` reste **périmé** : les sorties Sylvaccess ont été
calculées avec l'ancien réseau, les recalculer est manuel.

### 2026-07-29 — `v1.27.0` : **Phase C — ALSroads retiré** (spec 023, ADR-009)

La Phase B ayant validé l'adaptateur, le moteur de transition part comme prévu.
Suppression du chemin NDP 1 ALSroads (~160 lignes : `.lidar_catalogue()`,
`.mnt_alsroads()`, `.decimer_ctg()`, `.couverture_dalles()`,
`.desserte_lidar_mesurer()`, `.fusionner_mesure()`), du garde `.alsroads_dispo()`
et du banc `data-raw/validation_desserte_lidar.R` (remplacé par
`data-raw/phaseB_dessertr.R`). `lidR`, `ALSroads` et `raster` ne sont plus
touchés nulle part.

**Bump minor, pas major** (décision utilisateur) : `moteur = "alsroads"` comme
option publique n'a existé que dans la v1.26.0, jamais releasée. `moteur` reste
dans la signature en `c("auto", "dessertr")` — les deux valeurs convergent, la
surface d'API tient si un autre moteur arrive. `"alsroads"` lève désormais une
erreur de `match.arg()`.

**Effet de bord à connaître** : la dérivation automatique d'un MNT 1 m depuis les
points sol disparaît — c'était une béquille pour rattraper un MNT trop grossier
pour ALSroads. Il faut désormais **fournir un MNT à 1 m ou plus fin**, sinon les
largeurs sortent `NA`. Le repli NDP 0 est inchangé et reste le seul chemin
exercé en CI.

### 2026-07-29 — `v1.26.1` : **Phase B jouée et verte** — trois défauts d'intégration dessertR

Banc Phase B (spec 023 §7) exécuté sur la dalle du protocole spec 020 §6bis :
`LHD_FXX_0737_6385` (Chastel-Nouvel, 259,9 Mo, 44,6 M points, 44,6 pts/m²),
MNT LiDAR HD à **1 m**, desserte BD TOPO de l'emprise (44 tronçons). Script
reproductible : `data-raw/phaseB_dessertr.R` (la dalle et les sorties vivent
sous `data-raw/oracle/`, gitignoré).

Le volet **largeur** passait déjà — **39/44 mesurés, 0 échec**, 1,68-7,66 m
(médiane 2,83), pente en long 0,25-32 %. Mais **trois colonnes sortaient
entièrement `NA`**, toutes par désaccord avec l'API réelle de dessertR 1.0.0,
aucune par défaut de dessertR :

1. `apte_grumier`/`motif_inaptitude` — lecture de `traf$APTE_GRUMIER` alors que
   `dsr_trafficability()` rend `list(stations, resume)`. La trafficabilité
   grumier n'était donc pas branchée (point 4 du §7 de la spec 023).
2. `score_lidar` — `CONFIANCE_MNT` n'est émis que si `dsr_measure(confiance=)`
   est fourni. `densite_sol` de `dsr_layers_pc()` était calculé puis jeté ; il
   est désormais transmis. **`score_lidar` change de sémantique** : densité de
   points sol (pts/m², 2-34), plus un score 0-100 façon ALSroads.
3. `etat_classe`/`etat_dessertr` — `terra::extract()[, 2]` sur une **matrice**
   de coordonnées (pas de colonne `ID` → erreur avalée par `tryCatch`), plus un
   raster **catégoriel** rendant le libellé. Corrigé par dernière colonne +
   remappage sur la table des niveaux.

**21/21 invariants verts**, dont **9 de complétude** — ajoutés parce que la
première série (9/9) était verte *avec* les trois colonnes vides : un invariant
de domaine passe à vide sur du tout-`NA`. Leçon à retenir pour tout banc.

État publié : 23 `en_service`, 13 `trouee_sans_route`, 6 `hors_route`,
2 `abandonnee` ; `apte_grumier` 1 apte / 38 inaptes (motifs largeur, pente,
rayon). Doc d'installation corrigée au passage (dessertR n'est publié sur aucun
r-universe → `remotes::install_github("pobsteta/dessertR")`).

**Phase C (retrait d'ALSroads) est débloquée** au sens de l'ADR-009 : B est
jouée et publiée. Reste à décider si on la coupe maintenant.

### 2026-07-28 — `v1.26.0` : desserte LiDAR — `dessertR` remplace `ALSroads` (spec 023, ADR-009)

Swap du moteur LiDAR de desserte : `dessertR` (pobsteta, GPL-3, noyau Rust,
réimplémentation **française maintenue** de la méthode Roussel 2022) devient le
**moteur par défaut** ; ALSroads (POC non maintenu, calibré Québec) passe repli de
transition déprécié. Phase A livrée : adaptateur `.desserte_lidar_dessertr()`
(pipeline `dsr_catalog`→`dsr_conductivite`/`dsr_sigma_surf`→`dsr_etat`→
`dsr_repositionner`→`dsr_measure`→`dsr_trafficability`), dispatch `.moteur_lidar()`
(auto : dessertR > ALSroads > NDP 0), `acquire_desserte_lidar(mnh, moteur,
deviation_max)`, **contrat de colonnes préservé** + colonnes bonus (etat_dessertr,
devers, fosses, rayon_courbure_p05, apte_grumier, motif_inaptitude),
`qualifier_desserte()` critère d'état par libellé (`etats_disparus`) +
trafficabilité grumier (`retirer_inaptes_grumier`). Décisions utilisateur : GO
**production** (§7 spec 023). Chemin dessertR en `# nocov` (comme ALSroads), CI sur
repli NDP 0 ; **Phase B** (validation sur dalles réelles Meisenthal/Chastel-Nouvel)
puis **Phase C** (retrait d'ALSroads) à suivre. dessertR = dépendance optionnelle
non déclarée (r-universe), règle 1 respectée (on consomme, on n'inline pas).

### 2026-07-26 — `v1.25.0` : pré-calcul CVAT sur emprise AOI + buffer (spec 021)

`build_cvat_precomputed(aoi, cache_dir, buffer_m, mnt_existant, out, ...)` matérialise
le CVAT 8 bits couvrant l'**emprise de travail** (AOI + buffer), avec **garantie de
couverture** : `.emprise_couverte()` vérifie que le MNT fourni englobe l'emprise ET a
≥ `seuil` (0,9) de cellules finies ; sinon (mosaïque LiDAR trop courte / dalles
manquantes) ré-acquisition via `acquire_mnt` (WMS, couvre la bbox) puis recalcul
`vat_combined(as_byte=TRUE)`. Motivation : un CVAT sur mosaïque partielle laisserait
des trous / bords tronqués dans le fond du comparateur de desserte (nemetonshiny).
foretaccess ne télécharge pas de dalles `.copc.laz` (acquisition WMS) — la
ré-acquisition couvre l'emprise par construction ; garder la mosaïque native
(meilleure) si elle couvre, ne ré-acquérir que si trop courte. Câblage nemetonshiny
(pré-calcul async au chargement de projet + notification bas-droite) : brief v3 dans
`/home/pascal/cvat-nemetonshiny-handoff/` (session repo frère, règle 6).

### 2026-07-25 — `v1.24.0` : composite CVAT (VAT combiné du plugin QGIS RVT, spec 021)

Suite de `v1.23.0` : porte le **CVAT** (Combined VAT), la combinaison **par défaut**
du plugin QGIS RVT (fichier `*_CVAT_8bit.tif`). `vat_combined()` =
`0,5·VAT_general + 0,5·VAT_flat`, deux VAT calculés avec les presets terrain
`general`/`flat` (transcrits de `default_terrains_settings.json` : SVF r=10/noise 0
vs r=20/noise 3, pentes [0,50] vs [0,15], openness [68,93] vs [85,93], soleil 35° vs
15°), fusionnés puis `byte_scale`. SVF/openness du noyau Rust (rayons en pixels) ;
**pente, ombrage, byte_scale portés au mot près** de `rvt/vis.py` (différences
centrales 2-cellules + edge padding + `roll_fill_nans`, ≠ Horn de terra). Transcrit
du wrapper CVAT de `qrvt.py`. Oracle depuis le PLUGIN `rvt-qgis` (fonctions
numpy-pures extraites, section 5 de `data-raw/oracle_rvt.R` → `cvat_oracle.rds`) :
**8 bits identique à 100 %** en synthétique. Confronté au produit réel du plugin sur
un MNT LiDAR HD (Meisenthal, 4000×4000, 0,5 m) : **99,998 % de pixels strictement
identiques**, \|Δ\| ≤ 1 sur 100 %, biais nul (résidu float32 RVT vs float64). Perf :
~350 s (2 balayages SVF) vs 123 s pour le plugin — optimisable, sans effet sur le
résultat. Export autonome ; câblage nemetonshiny (fond CVAT des onglets « Terrain
accessible ») à faire dans une session du repo frère (règle 6).

### 2026-07-25 — `v1.23.0` : composite VAT archéo (fusion RVT en R, spec 021)

Prolonge le portage RVT (`v1.18.0`, noyau Rust SVF/openness) côté fusion : `vat_archeo()`
assemble le **VAT** (Visualization for Archaeological Topography, Kokalj & Somrak 2019) à
partir d'un MNT — 4 canaux (SVF + openness+ via `micro_relief()`, pente + ombrage via
`terra`) fusionnés par `blend_rvt()`. La fusion (`R/vat_archeo.R`) est transcrite **au mot
près** de `rvt/blend_func.py` : normalisation `value` (+ inversion d'échelle pour la pente,
comme `normalize_image`), modes `normal`/`multiply`/`screen`/`overlay`/`soft_light`/
`luminosity`, repli bas→haut de `render_all_images`. Point non trivial révélé par la
transcription : `blend_overlay`/`blend_soft_light` **mutent `background` en place**, ce qui
**neutralise l'opacité** de ces couches (l'Openness+ « Overlay 50 % » du preset vaut 100 %) —
reproduit tel quel pour un rendu identique à RVT. Défauts épinglés au preset livré
`settings/blender_VAT.json` et validés **pixel à pixel** contre RVT_py (oracle
`data-raw/oracle_rvt.R` → `fixtures/vat_oracle.rds`, écart ~1,6e-7). Choix R (pas Rust) :
compositing élément-par-élément, aucun gain de perf, frontière R↔Rust minimale (règle 3).
Non encore câblé dans `qualifier_desserte()` ni côté nemetonshiny : export autonome.

### 2026-07-24 — `v1.22.0` : porteur iso-paramètre ACCESSFOR (pente descente 40 → 25)

Dernière divergence de paramètre machine vs ACCESSFOR corrigée : `pente_descente_max_pct`
du porteur passe de 40 à **25 %**. Diagnostic : le 40 venait du `def_value` de
`dic_AllParam.json`, mais les DEUX références réelles retiennent 25 — le scénario de
test officiel ColduPre (`Tab_Param_test.csv`, notre oracle de non-régression, qui
utilise déjà 25 explicitement — donc la non-régression 99,72 % est INCHANGÉE) ET
ACCESSFOR (rapport 2025 §2.2). Corrige aussi une incohérence : le roxygen documentait
déjà 25. Divergence de dic_AllParam **assumée et justifiée en commentaire** (mémoire
`params-sylvaccess-fait-foi`). Surchargeable. **Résultat : tous les paramètres machine
(skidder + porteur) sont désormais identiques à ACCESSFOR.**

### 2026-07-24 — `v1.21.0` : obstacles conformes ACCESSFOR (spec 022 volet B)

`acquire_obstacles_bdtopo()` : assemble la couche obstacles ACCESSFOR (rapport §2.3.4)
— obstacles BD Topo (cours d'eau, hydro, voies ferrées, bâtis, routes principales) +
zonages réglementaires INPN/Patrinat (APB, RNN, RNR, réserves biologiques, et parc
national **seulement sa réserve intégrale** via filtre `zone`, jamais le parc entier)
— en un `sf` pour `preprocess(obstacles_complets=)`. Lignes tamponnées. Effet mesuré
(validé) sur Chastel-Nouvel : accord agrégé ACCESSFOR **+1,6 pt** (81,5 → 83,1 %), le
flip dominant réduit ; ici les zonages sont vides (Lozère), l'apport viendra surtout
d'un massif à réserves. Validé bout-en-bout (5 751 cellules obstacle) + 16 tests
mockés. `acquire_desserte(clsvac)` (v1.20.0) + obstacles = spec 022 close.

### 2026-07-24 — `v1.20.0` : desserte CL_SVAC alignée ACCESSFOR (spec 022 volet A)

Implémentation du volet A de la spec 022, **validé empiriquement** (le juge de paix).
`acquire_desserte(classification = "clsvac")` (nouveau défaut) : la BD Topo est classée
en piste / route forestière (terminus) / réseau public, au lieu de l'ancienne
heuristique 2-classes qui rangeait la **Route empierrée carrossable en piste** (→
traînage le long → distances gonflées). **Résultat mesuré sur Chastel-Nouvel : accord
9-classes ACCESSFOR 30 % → 77 %, biais +1,26 → +0,02 bande** (supprimé). Confirme
définitivement que la classification desserte était LE driver de la divergence (params
+ MNT déjà prouvés identiques via le rapport ACCESSFOR 2025). Rétro-compat
`"heuristique"` bit-pour-bit. Volet B (obstacles/zonages Patrinat) laissé en suite.

### 2026-07-24 — `docs` : spec 022 (desserte CL_SVAC + obstacles conformes ACCESSFOR)

Diagnostic de la divergence `classes_debardage()` vs la couche **ACCESSFOR** de
l'IGN (édition 2025, `hal-04988956`), sur Chastel-Nouvel. Accord 81 % agrégé / 31 %
9-classes, biais systématique **+1,26 bande** (nous plus loin). **Écarté, preuves à
l'appui** : paramètres skidder **identiques** (rapport §2.2 = notre `config`), MNT
**identique** (RGE Alti 5 m ; test 1 m→5 m négligeable, +0,11 bande). **Driver
confirmé** : la couche desserte — `acquire_desserte()` classe **82 % du linéaire en
piste** et **n'assigne jamais `reseau_public`** (0 km), alors que Sylvaccess/ACCESSFOR
utilise 3 classes CL_SVAC (piste=1 / route forestière=2 / réseau public=3, terminus
du traînage). Le traînage-piste-jusqu'à-route gonfle donc nos distances. Secondaire :
obstacles + zonages réglementaires (rapport §2.3.4) absents de notre run (→ flips
accessible↔inaccessible). **Sources obstacles/zonages confirmées récupérables** (WFS
`BDTOPO_V3:{cours_d_eau, surface_hydrographique, troncon_de_voie_ferree, batiment,
parc_ou_reserve}` + INPN ; happign dispo) — avec filtrage des zonages (ne pas exclure
tout un parc national). **Spec 022 posée** (2 volets : desserte CL_SVAC + obstacles),
CA-22.5 = l'accord ACCESSFOR doit remonter. Non implémenté (proposé).

### 2026-07-23 — `v1.19.1` : `qualifier_desserte()` ne segfaulte plus (pré-filtre de couverture)

Brief `~/brief-foretaccess-segfault-qualifier.md` (nemetonshiny, foretaccess 1.19.0).
Sur une desserte de projet complète (806 km / 4 dalles), `qualifier_desserte()`
**segfaultait** (~1 h puis crash mémoire C++, non rattrapable → tue le worker `future`
de l'app). Cause : après le fix géométrie 1.19.0, `measure_road` était appelé sur les
**milliers de tronçons hors couverture** (desserte ≫ emprise dalles) ; lidR/ALSroads
dérape sur cette masse de régions sans points. **Fix** : `.couverture_dalles()` (union
des empreintes du catalogue) + `.troncons_couverts()` écartent les tronçons hors
couverture **avant** tout appel ALSroads → `NA` propre, plus de crash, temps effondré.
`bilan` gagne `hors_couverture`. Validé sur donnée réelle (44/256 couverts, 0,02 s).
Règle celui-ci les 3 premières demandes du brief (crash / mémoire / perf) d'un coup.

### 2026-07-23 — `v1.19.0` : desserte LiDAR sur desserte de projet réelle + domaine glouton (brief app)

Brief `~/brief-foretaccess.md` (v3, émis par nemetonshiny sur foretaccess 1.18.0).
**Chantier B (débloque le câble)** : `qualifier_desserte()` mesurait **0/3 299** sur
une desserte de projet complète (vs 22/22 sur 6 routes triées à la main en 1.16).
Trois causes confirmées **sur donnée réelle** (test décisif MULTI/LINESTRING) :
1. **Géométrie** — BD TOPO = `MULTILINESTRING`, `measure_road` **échoue** dessus
   (« Expecting LINESTRING »). Le 22/22 castait ; l'app passait le MULTI brut.
   → `.troncon_linestring()` (fusion parties contiguës, sinon la plus longue).
2. **Tronçons courts** — des milliers < 40 m, instables. → param `long_min_m` (40).
3. **Couverture partielle** — une desserte de projet déborde les dalles : l'essentiel
   reste NA, seuls les tronçons longs+sous dalle se mesurent. → attribut `bilan`.
**B2 mismatch colonnes** : `.largeur_desserte` reconnaît `largeur_carrossable_m` en
priorité + `places_depot(largeur_champ=)`. `qualifier_desserte`/`acquire_desserte_lidar`
et `places_depot` **composent** désormais.

**Chantier A (perf glouton)** : le speedup 1.12 ne se reproduit pas à `skidding_m=0`
(17 min mesurées, pire que 1.9). Cause : à `skidding_m=0` chaque cellule de parcelle
engendre son propre tracé A\* ; le bornage au couloir n'aide que si les extrémités
sont proches. **Domaine de validité documenté** (section *Performance* de
`?reseau_desserte`) : « dizaines de secondes » suppose `skidding_m` > 0 **et**
parcelles pas toutes éloignées. Pas de re-profil complet (coûteux) — la mécanique est
concluante depuis le code.

**Chantier C (bundlé)** : `contracter_lignes(reseau)` — sortie vecteur propre du réseau
conçu (contraction topologique partagée avec `vectoriser_reseau` via
`.troncons_contractes_sf`), sans monter le graphe de flux. Remplace le contournement
raster `$reseau` de l'app pour l'affichage.

### 2026-07-23 — `docs` (cycle dev) : contrat d'unité du volume desserte (brief nemeton spec 040)

Brief `040-volume-mobilisable-desserte` (émis par la session nemeton, adressé à
l'app nemetonshiny) : câbler `nemeton::volume_mobilisable()` dans le typage de
desserte. **Côté foretaccess, rien à coder** — les consommateurs existent, marchent
et sont testés (`calculer_flux` CA-17.3 conservation ; `reseau_desserte` heuristique
`plus_gros_volume`). Le seul manque était le **piège d'unité (§3)** : `calculer_flux`
veut un **total m³/parcelle** (réparti puis accumulé), `reseau_desserte` une
**densité m³/ha** (rasterisée par cellule) — unités **opposées**, erreur silencieuse
si inversées. Documenté sur les deux fonctions (roxygen, renvoi croisé + valeurs
`unite` de nemeton) et dans `specs/017` §3. L'orchestration (2 appels de package)
vit dans **nemetonshiny** (règle 6, non touché) : diff fourni à la session app.

### 2026-07-23 — `v1.18.0` : portage RVT en Rust (spec 021 J3, micro-relief)

**Canaux de micro-relief RVT portés en Rust.** `rvt_svf_opns()` (noyau
`src/rust/src/rvt/mod.rs`) + `micro_relief()` (enveloppe terra) : **sky-view
factor** et **openness ±**, translittérés au mot près de `horizon_shift_vector` +
`sky_view_factor_compute` de `rvt/vis.py` (pas réimplémentés). Balayage
`roll`+`fmax` parallélisé par pixel (Rayon), NoData reproduit (réflexion de bord =
`np.pad(reflect)`, `f64::max` = `np.fmax`). SVF (hémisphère) + openness (sphère) du
même balayage ; openness négative = calcul sur `-MNT`. **Non-régression pixel à
pixel contre RVT_py** (oracle gelé `data-raw/oracle_rvt.R`, fixture) : écart
**~2·10⁻⁶ SVF / ~2·10⁻⁴ ° openness** (résiduel float32 de RVT). 6 tests cargo + 14
tests R, en CI sans Python.

**Portée honnête.** SVF + openness ± seulement. LRM, pente (déjà via
`terra::terrain`) et les **halos** au raccord de tuiles restent à câbler avec le
prétraitement du CNN (J4) — jalon de recherche suspendu à la vérité terrain DESSOPT
(pas de CNN fabriqué sans données). Ces canaux serviront aussi les moteurs
(places de retournement DFCI, filtrage des ancrages câble). Licence : conserver
l'attribution RVT (Kokalj, Zaksek, Ostir, Coz et al.), Apache 2.0 → GPL v3 OK.

### 2026-07-23 — `v1.17.0` : `qualifier_desserte()` (spec 021 Lot 19, étape 1)

**Correction géométrique déterministe de la desserte.** La desserte n'est jamais
calculée : elle est **déclarée** (BD TOPO), et ses erreurs de position
(pluri-métriques au GPS/tablette) + largeur vide se propagent aux 4 moteurs sans être
vues par la non-régression (qui valide la fidélité à Sylvaccess, pas la justesse
terrain). `qualifier_desserte()` = enveloppe déterministe sur `acquire_desserte_lidar()`
(spec 020) : géométrie **relocalisée** sur l'axe ALSroads + **`largeur` renseignée**
depuis la largeur carrossable mesurée. Sortie **conforme au contrat de `preprocess()`**
→ moteurs et non-régression **inchangés**. Repli NDP 0 gracieux testé en CI. Retrait
des « disparus » en **option OFF par défaut** (sur données FR, classes basses =
pistes dégradées réelles, sémantique non recoupée à une vérité terrain — rôle DESSOPT).

**Scope honnête de la spec 021.** Seule l'**étape 1** est livrée (la spec la chiffre à
« ~80 % du problème d'intrant réglé »). Les **étapes 2+** (portage RVT en Rust J3, CNN
de détection des pistes absentes J4, vectorisation topologique, validation DESSOPT J5)
restent des **jalons de recherche** : ils exigent la vérité terrain DESSOPT (non
publique) et des arbitrages amont (contacts §9). **Portage RVT en Rust démarré à part**
(autonome, testable contre RVT_py, sans dépendance DESSOPT).

**Doc.** Statuts specs 014–018 (épic desserte) rafraîchis « proposé » → « implémenté ».

### 2026-07-23 — `v1.16.0` : chantier 4 Phase B **renversée en POSITIF** (MNT ≥ 1 m)

**Le 0/6 de la v1.15.0 était un FAUX NÉGATIF.** Piste donnée par l'utilisateur : le
guide utilisateur d'ALSroads (`ilythiamorley.github.io/ALSroads_Guide`) exige un
**MNT « at least 1 m »** — ALSroads construit ses profils de détection de bord à
`profile_resolution = 0.5 m`. Or je passais la **grille d'accessibilité à 5 m**,
10× trop grossière → largeurs `NA`. Ce n'était ni la donnée ni le calibrage Québec,
c'était **ma résolution de MNT**. Rejoué avec un MNT **1 m** dérivé des points sol
(classe ASPRS 2) de la dalle (`lidR::rasterize_terrain(tin())`) + nuage décimé à
~10 pts/m² : **22/22 pistes mesurées** (carrossable 1,1–8,1 m, classes 1–4). Réserve
« calibrage Québec → France » **levée**, verdict spec 020 **NÉGATIF → POSITIF**, GO
expérimental.

**Correctif** : `acquire_desserte_lidar()` détecte un MNT > 1,5 m et en dérive un à
`dtm_res` m (nouveau paramètre, défaut 1) depuis les points sol ; décime aussi le
nuage au-delà de ~15 pts/m². Fournir le MNT LiDAR HD IGN à 0,5 m évite la dérivation.
Confondants confirmés innocents avant de trouver la vraie cause : géométrie
`MULTILINESTRING` vs `LINESTRING` (testée, toujours 0/6). **Leçon (mémoire)** : avant
de conclure à un échec de calibrage d'un outil tiers, vérifier que **mes entrées
respectent ses exigences documentées** (ici la résolution du MNT). Sur-conclure au
négatif — ce que j'avais failli faire deux fois — aurait enterré une fonction qui
marche. Spec 020 §6bis, `data-raw/validation_desserte_lidar.R`.

### 2026-07-23 — `v1.15.0` : bornage de `solve` + chantier 4 Phase B (0/6 — faux négatif, cf. v1.16.0)

**Bornage `solve`** (single-cible) : le couloir de recherche de 1.12.0 (glouton)
étendu à chaque segment de `solve` → `tracer_desserte` et tracés parcelle↔parcelle
de Steiner. Bit-identique. Steiner **~860 → ~650 s** (4 parcelles) — gain modeste :
ses segments relient des parcelles éloignées → fenêtres larges, reste O(N²).
Le bornage brille pour extrémités proches (glouton, waypoints rapprochés).

**Chantier 4 Phase B — validation française exécutée, résultat NÉGATIF.** Dalle
LiDAR HD IGN téléchargée pour Chastel-Nouvel (260 Mo, classes ASPRS standard),
`acquire_desserte_lidar()` lancée sur 6 routes forestières **longues (398-911 m),
entières dans la dalle** : **0/6 mesurées**. Le pipeline tourne (CRS 2154 OK,
catalogue lu, `measure_road` ~95 s/tronçon) mais ALSroads (calibré Québec) ne
détecte pas les routes françaises. L'exemple **québécois** du paquet, lui, se
mesure sans peine (8,2 m, CLASS 1) → la différence est la **donnée**, pas le code.
Deux faux départs corrigés au passage (mauvaise emprise de dalle — le nom `_6385` =
bord haut ; `st_crop` fragmentant les routes sous les 40 m d'ALSroads). **Verdict :
no-go production sans recalibrage** de `alsroads_default_parameters` sur des routes
françaises — recherche hors lot. `acquire_desserte_lidar()` reste livrée (utile
sur donnée québécoise / après recalibrage). Protocole : `data-raw/validation_desserte_lidar.R`,
spec 020 §6bis. Chemin NDP 1 marqué `# nocov` (validé hors CI).
**⚠ Verdict renversé en v1.16.0 : le 0/6 venait d'un MNT à 5 m, pas d'un défaut de
calibrage. Avec un MNT ≥ 1 m → 22/22. Voir l'entrée v1.16.0 ci-dessus.**

**Brief desserte : entièrement traité et bouclé** (1 perf + volet 2, 2 connexité,
3 places_depot, 4 LiDAR Phase A+B, 5 résolu de fait). `solve` borné = le dernier
optionnel. Seul reliquat = recalibrage ALSroads FR (recherche, hors périmètre).

### 2026-07-22 — `v1.14.0` : chantier 4 — desserte corrigée LiDAR (ALSroads, NDP 1)

Dernier chantier du brief desserte. Étude de faisabilité (`specs/020`) **puis**
Phase A implémentée.

**Faisabilité** : l'infra LiDAR existe déjà (nemetonshiny télécharge le nuage
`product="nuage"`, nemeton Suggests lidR + lasR, lit du COPC). ALSroads =
`measure_road(ctg, centerline, dtm)` → géométrie recalée + largeurs + état.
Risques : calibrage **Québec → France non validé**, POC expérimental non maintenu.

**Phase A livrée** : `acquire_desserte_lidar(desserte, las_source, mnt, ...)`
(`R/desserte_lidar.R`), enveloppe fine. lidR + ALSroads accédés **dynamiquement**
(`getExportedValue`), **non déclarés** en Suggests (POC hors CRAN, dép lourde →
CI protégée) ; **repli NDP 0** (desserte inchangée, colonnes NA) = cœur testé.

**Validation anti-« plausible-mais-faux »** : ALSroads étant installé localement,
le chemin NDP 1 a été **exécuté de bout en bout** sur les données d'exemple du
paquet. Correction clé trouvée ainsi : la sortie réelle n'a **pas** de champ
`STATE` (mon 1er jet), l'état est dans **`CLASS`** (« state in four classes »).
Colonnes réelles vérifiées : `ROADWIDTH`, `DRIVABLEWIDTH`, `SCORE`, `CLASS`.
Sortie mesurée : largeur carrossable 8,2 m, plateforme 8,5 m, etat_classe 1,
score 100, géométrie recalée. Mapping figé sur cette vérité terrain.

**Reste** : Phase B (valider les largeurs sur un site français, CA-20.5) avant
usage de production ; la fonction est « expérimentale » d'ici là.

### 2026-07-22 — `v1.13.0` : chantier 1 volet 2 — bornes optimiseurs + crash Steiner corrigé

Suite du chantier 1. Benchmark sur Chastel-Nouvel (après le bornage du glouton en
1.12.0) :
- **Optimiseurs tractables** : glouton 8 parcelles 7,2 s ; multistart **n_start=4
  → 7,0 s**, **n_start=16 → 10,5 s** (table réutilisée + `rayon` parallèle). Défauts
  exposables : n_start 8-32, n_iter 100-300, sans cap dur. Section *Performance* de
  `optimiser_reseau`.
- **Steiner : crash latent trouvé et corrigé.** En exécutant enfin Steiner à
  l'échelle réelle (jamais fait — brief : « estimé > 5 h »), plantage
  `index out of bounds ... usize::MAX` : le lookback des épingles / anti-croisement
  de `basic_calc` remontait `came_from` jusqu'à la source (`-1`) et indexait hors
  bornes. Gardes `came_from >= 0` ajoutés (`solver.rs`) — près de la source la
  double-épingle et l'anti-croisement s'arrêtent proprement. Bit-identique ailleurs
  (suite verte), test de non-régression ajouté. Steiner tourne (4 parcelles = 859 s)
  mais reste **O(N²)** (tracés parcelle↔parcelle via `solve`, non borné) → réservé
  aux petits N.

Reste ouvert : **borner `solve`** (rendrait Steiner *rapide* ET accélèrerait
`tracer_desserte`, mais user-facing → à décider) ; chantiers **4** (LiDAR ALSroads,
faisabilité) et **5** (`$lignes` contracté — largement résolu par `skidding_m`, cf.
1.12.0 : `$lignes` a un feature par route, les « 10 640 » du brief étaient
l'over-connection à `skidding_m=0`).

### 2026-07-22 — `v1.12.0` : brief desserte chantier 1 — perf du glouton (~11,5 min → dizaines de s)

Profilage sur Chastel-Nouvel (340k cellules, cache `/tmp/accessfor-cache`),
instrumenté en Rust (chrono stderr). Diagnostic en trois temps :
1. **Naïf (30 parcelles dispersées)** : > 1h33 — le coût explose avec la distance
   parcelle↔réseau (A* plein-emprise par parcelle). Inexploitable comme profil.
2. **Borné (1/3 parcelles proches)** : **1 parcelle = 201 s, 3 = 569 s** → ~185 s/parcelle.
   Chaque parcelle = **un tracé A* plein-emprise**.
3. **Instrumenté** : `d2e` (Dijkstra plein-emprise, heuristique) ≈ **380 ms**, l'A*
   ≈ **200 s** (explore tout, heuristique en ligne droite non focalisée). ET
   `.desserte_cellules_parcelles` renvoie **toutes** les cellules d'une parcelle
   (100×100 m = 400 sources) → à `skidding_m=0`, ~400 tracés/parcelle.

**Corrections :**
- **A* borné au couloir** (`solver.rs::solve_network`) : boîte englobant
  (source, cible la plus proche) + marge proportionnelle, repli plein-emprise si
  aucune cible atteinte. Mesuré : A* **200 s → 20 ms**. Résultat **bit-identique**
  (toute la suite verte). Le tracé reste un alignement optimal, dans le couloir de
  raccordement le plus proche (cohérent avec le glouton, qui est déjà une
  approximation du réseau global).
- **`skidding_m` = levier dominant du nombre de tracés**, documenté. Réglé sur la
  distance de débardage : **6 parcelles = 7,7 s** (1 route, 6/6 desservies) vs des
  centaines de s à `skidding_m=0`.

Net : glouton **~11,5 min → dizaines de secondes** (fenêtre + `skidding_m` réaliste).
Section *Performance* de `?reseau_desserte`. **Ne casse pas la promesse « tracé
optimal »** (question utilisateur) : chaque piste est un vrai alignement de moindre
coût — le glouton assemble ces optimaux localement, l'optimum GLOBAL du réseau
restant l'affaire de Steiner / `optimiser_reseau`.

Reste du brief : **4** (desserte LiDAR ALSroads, NDP 1 — faisabilité), **5**
(`$lignes` contracté, optionnel), et le **benchmark Steiner/optimiseurs + bornes
exposables** (2e volet du chantier 1).

### 2026-07-22 — `v1.11.0` : brief desserte nemetonshiny — chantiers 2 (connexe) + 3 (perf places_depot)

Nouveau brief consolidé reçu (`~/brief-foretaccess.md`, session app nemetonshiny,
5 chantiers desserte, mesuré sur 1.9.0). Traités ici : **2 (connexité)** et
**3 (perf `places_depot`)**.

**Chantier 3 — perf `places_depot` (762 s app → intraitable).** Profilé sur la
vraie desserte (60 km en cache) : **19,3 s, dont 73 % dans `CPL_crs_parameters`**,
appelé par `sf::st_line_sample` **par point** dans `.pente_en_long` /
`.altitude_sur_ligne`, et **par ligne** dans `.points_le_long` — chaque appel
re-parse le CRS (piège sf classique). Réécrit les deux en **interpolation de
coordonnées** (sommets `st_coordinates` une fois par ligne, `.sommets_ligne` /
`.interp_le_long` partagés, un seul `terra::extract`, points bâtis en un seul
`st_as_sf`). Résultat : **19,3 s → 0,47 s (41×), sortie bit-identique** (103
places / 86 tronçons, mêmes pentes). À l'échelle app (806 km) ça repasse de ~762 s
à quelques secondes. Reste la **sélectivité** (trop de départs sans entrées
riches) : documentée en *recette* (couche `retournements` + largeur mesurée =
plus gros leviers), pas un bug — dépend du chantier 4 (largeur LiDAR).

**Chantier 2 — sémantique `connexe`.** Diagnostic : `.reseau_connexe()` mesure une
seule composante 8-connexe de *(existant ∪ créé)* ; sur une desserte réelle il est
dominé par la **fragmentation de l'existant** (Chastel-Nouvel : 3 299 tronçons
disjoints → `connexe = FALSE` alors que `desservies = 30/30`). Ce **n'est pas un
défaut**. Ajouté **`raccorde`** = les routes créées n'ajoutent aucune composante
vs l'existant seul (⇔ aucune route isolée) — le booléen à afficher. `connexe`
conservé et **documenté précisément** (`?reseau_desserte` section *Connectivity*,
`print` mis à jour). Test : existant fragmenté → `connexe=FALSE`, `raccorde=TRUE`,
`desservies` complet.

**Clarification chantier 3 (câble)** : `config$cable$pas_angulaire_deg` est
**inerte** (validé mais jamais lu) — le pas de balayage vient de `precision`. Doc
`potentiel_cable()` section *Performance* + commentaire config. Le brief croyait
`pas_angulaire_deg` actif.

Reste du brief : **1** (perf glouton/Steiner/optimiseurs — profiler puis
optimiser), **4** (desserte corrigée LiDAR ALSroads, NDP 1 — étude de
faisabilité), **5** (`$lignes` contracté, optionnel).

### 2026-07-22 — `v1.10.0` : validation ACCESSFOR §5 — matrice de confusion

Livrable §5 du brief nemeton. `comparer_accessfor(cl, accessfor)` (`R/accessfor.R`)
rasterise ACCESSFOR en **plus proche voisin** sur la grille de `cl` (vérification
que l'ensemble des codes obtenus ⊆ codes d'entrée — pas de classe fabriquée),
traduit via `accessfor_correspondance()`, croise **sur l'intersection des masques**
et rend accord global, accord agrégé (accessible/non), matrice en ha, surfaces
exclues. Fonction **pure et testée hors ligne** (un test a attrapé un vrai bug :
`table()` 1×1 → fausse diagonale à 100 %, corrigé par facteurs à niveaux fixes).

Chiffres réels sur Chastel-Nouvel (~610 ha, `data-raw/accessfor_compare.R`, les
DEUX variantes de masque) :

| engin | masque | accord global | **accord agrégé** |
|---|---|---|---|
| skidder | défaut / V3 | 30,6 / 30,9 % | **81,4 / 81,2 %** |
| porteur | défaut / V3 | 65,8 / 66,5 % | **86,0 / 86,2 %** |

Lecture (`docs/comparaison-accessfor.md`) : accord accessible/non **solide et
stable au masque** (l'artefact de masque redouté au §4a est borné, < 1 pt) ; le
désaccord fin du skidder est un **décalage de bande** (notre modèle plus optimiste
sur la portée, ~86 ha access. vs inaccess. ACCESSFOR contre ~28 en sens inverse),
imputable surtout à la **desserte de référence différente** — piste à instruire,
pas alerte. Validation = constat de cohérence, pas non-régression (ACCESSFOR est
un modèle, pas une vérité terrain). **Brief ACCESSFOR (§3+§5) clos.**

### 2026-07-22 — `v1.9.0` : validation ACCESSFOR (IGN) — §3 élucidé, crosswalk + porteur

Ouverture de la **validation externe** des moteurs terrestres contre la couche
**ACCESSFOR** de l'IGN (WFS `data.geopf.fr`, projet ACCESSFOR, édition 2025-01-01,
couches polygonales `acces_skidder`/`acces_porteur`). Brief émis par la session
nemeton (`nemeton/specs/brief-foretaccess-accessfor.md`). On commence par le §3
« à élucider avant tout chiffre ».

**Les trois points du §3, tranchés au WFS (département 48, Chastel-Nouvel) :**
1. `class = 2` = **« Zone non exploitable (pente trop élevée) »** = notre
   `inexploitable`. Les classes 7 et 8 **existent** (l'échantillon national du
   brief — dép. 01/08/09 — était trompeur, il lui manquait 2, 7, 8).
2. ACCESSFOR **ne s'arrête pas à 1500 m** : bande 5 (1500-2000, code 7) et bande
   ouverte **> 2000** (code 8) présentes. Comparaison terme pour terme 0 → >2000,
   aucune troncature à décider.
3. **Crosswalk figé et testé** (`accessfor_correspondance()`, `R/accessfor.R`) :
   `class 3..8 → nos bandes 1..6`, `class 1 → inaccessible (7)`,
   `class 2 → inexploitable (8)`, `hors_foret (9)` sans code ACCESSFOR (ses
   polygones *sont* la forêt). Jointure sur l'entier, jamais sur `cat`. Un test
   ancre la table à la sortie réelle de `classes_debardage()` — pas de dérive
   silencieuse. Domaine **identique skidder ET porteur** (même schéma, `class=2`
   au même compte 38 032 → exclusion pente indépendante de l'engin, comme notre
   `pre$exclusion_mask`).

**Prérequis levé** : `classes_debardage()` accepte désormais un `foretaccess_porteur`
(assert élargi), condition pour chiffrer le porteur contre `acces_porteur`.

**Deux verrous notés pour le §5 (avant chiffres)** : (a) passer `pre` à
`classes_debardage()` sinon la classe `inexploitable` manque ; (b) seuil « pente
trop élevée » d'ACCESSFOR non publié → un écart sur `class=2` serait un artefact
de paramètre (notre `pente_skidder_max_pct = 30`), pas un bug. **Décision §4a
(masque) prise avec l'utilisateur : comparer les DEUX variantes** (défaut ET
`MASQUE-FORETV3`), l'écart entre elles bornant l'artefact de masque. Reste à
faire : le livrable §5 (rasterisation `near` sur la grille de `pre`, intersection
des masques, matrice de confusion) sur l'AOI Chastel-Nouvel.

### 2026-07-22 — `v1.8.0` : `acquire_inputs(volume=)`, injection du volume (spec 019)

Dernier maillon de la chaîne volume, après `volume_depuis_p1()` (v1.7.0).
`acquire_inputs()` gagne un argument `volume` (+ `champ_volume`) qui **relaie** un
volume sur pied jusque dans `out$volume`, prêt pour `preprocess(volume=)` → câble.

**Audit croisé ForêtAccess ↔ Nemeton (2026-07-22).** Vérifié : nemetonshiny charge
déjà le **MNH LiDAR** (`download_ign_lidar_hd(product="mnh")`, `lidar_mnh/chm.tif`),
calcule P1, et **orchestre déjà ForêtAccess** (`service_accessibility.R`) — mais
appelle `preprocess()` **sans `volume=`** : c'était le vrai trou. Deux pièges levés
dans la spec 019 :
1. **MNT ≠ MNH.** Ce que ForêtAccess charge (`lidar_mnt`, AOI+buffer) est le **sol** ;
   le volume a besoin de la **canopée** (`lidar_mnh`), produit IGN distinct. « Étendre
   `lidar_mnt` » ne produit aucun volume.
2. **Emprise.** Le volume doit couvrir **AOI+buffer** (le câble somme jusque dans le
   halo, un `NaN` compte pour 0 → sous-estimation de bord). Mais le fetch IGN se fait
   par dalles de 1 km : « étendre le téléchargement » est un no-op sur les tuiles — ce
   qui compte est le **découpage** sur AOI+buffer, garanti par l'alignement sur `pre$mnt`.

**Décision de couplage (Option B, tranchée avec l'utilisateur).** Le calcul MNH→P1
reste chez Nemeton (domaine inventaire, règle 1) ; ForêtAccess consomme via un
passthrough **sans dépendance Nemeton** ; le raccord `volume = volume_depuis_p1(p1, mnt)`
vit dans nemetonshiny (spécifié, non codé — règle 6). Pas d'`acquire_volume()` natif
(question tranchée : non).

Passthrough polymorphe (raster | chemin | sf), garde CRS (abort ADR-004),
rééchantillonnage même-CRS avec avertissement, avertissement de couverture partielle.
16 tests (`test-acquire-volume.R`, CA-19.1→19.6). Spec `019-acquisition-volume.md`
**validée** ; l'écart « Phase 2 volume » de `specs/010` est **levé**.

### 2026-07-22 — `v1.7.0` : `volume_depuis_p1()`, pont vers l'indicateur P1 de Nemeton

Le moteur câble et la sélection (Lot 5) lisent `pre$volume`, un **raster de volume
sur pied en m³/ha** : `potentiel_cable()` le somme sur les cellules forestières
qu'une ligne couvre → volume de la ligne et **IPC** (= volume / longueur,
`scan.rs:559`). ForêtAccess ne calcule pas ce volume ; c'est une **entrée**, et
jusqu'ici il fallait la rasteriser à la main.

Sa source naturelle est l'indicateur **P1** de Nemeton
(`nemeton::indicateur_p1_volume()`, `nemeton/R/indicators-productive.R`) : un `sf`
d'unités portant un volume en **m³/ha**, dérivé d'un inventaire (espèce IFN, DBH,
densité, tarif) **ou d'un MNH LiDAR** (`chm=`). Les unités tombent juste — P1 est
déjà en m³/ha, ce que le câble attend.

`volume_depuis_p1(p1, mnt, champ = "P1")` (`R/volume.R`) projette ce champ sur la
grille du MNT et rend un `SpatRaster` `volume` prêt pour `preprocess(volume = )`.
Rasterisation par **centre de cellule** (densité, pas quantité → pas de gonflement
des bords) ; hors unité → `NA` (pas de bois, pas zéro). Garde-fous : CRS identique
au MNT sans reprojection implicite (ADR-004), champ numérique/positif/non tout-NA.

**Décision de couplage (tranchée avec l'utilisateur).** L'adaptateur vit dans
ForêtAccess mais **ne dépend pas de Nemeton** : il consomme l'`sf` déjà calculé,
d'où qu'il vienne (P1, BD Forêt, relevé). Respecte la règle stricte 1 — le calcul
du volume est un indicateur d'inventaire (domaine de Nemeton) ; ForêtAccess se
borne à consommer sa sortie. Aucune écriture dans le repo frère (règle 6).

19 tests (`test-volume.R`) : alignement, unités, bout-en-bout via `preprocess()`,
garde-fous. `@seealso` croisés `potentiel_cable()` ↔ `preprocess()` ↔
`volume_depuis_p1()`. Entrée pkgdown (Prétraitement).

> Reste ouvert (non entamé) : l'**acquisition** de bout en bout MNH LiDAR → CHM →
> P1 → raster, câblée dans `acquire_inputs()` (Phase 2, dépendance Nemeton +
> happign). `volume_depuis_p1()` en est la dernière brique, déjà posée.

### 2026-07-21 — `v1.6.1` : `places_depot()` confrontée à l'oracle — 0/2 → 2/2

**La v1.6.0 avait été publiée sans confrontation à ColduPre.** 24 tests verts,
`R CMD check` vert, CI verte — mais tous vérifiaient que *chaque critère fait ce
qu'il annonce*, jamais que *le résultat ressemble à une vraie couche*. Confrontée
à l'attribut relevé `CABLE` du réseau ColduPre (**2 places sur 125 tronçons**),
elle n'en retrouvait **aucune**, à tous les seuils. Trois erreurs de modèle :

1. **La planéité mesurait le versant.** Pente omnidirectionnelle du MNT au point :
   à 5 m, la banquette d'une route (4-5 m) n'est pas résolue. Les 2 vraies places
   sont sur des versants à **24 %** et **65 %** — la seconde est le tronçon le plus
   raide du réseau (percentile 100). Le critère éliminait la montagne, c'est-à-dire
   le terrain où l'on câble. → **pente en long** (dénivelé le long de l'axe sur
   `fenetre_plateforme_m`) : les 2 vraies y sont à **1,1 %** et **3,2 %**
   (percentiles 19 et 31). Défaut `pente_max_pct` 15 → **6 %**.
2. **L'accès rejetait sur `classe`/`dfci`.** L'une des deux vraies places est une
   piste forestière à `CL_DFCI = 0`. → ces attributs informent (colonne `acces`)
   mais ne tranchent plus ; seule une largeur **mesurée** insuffisante rejette.
3. **L'éclaircissement inter-tronçons les supprimait.** Le glouton « la plus plate
   d'abord » évinçait les deux, battues par un point à **18 m** et **93 m** sur une
   route voisine. → l'espacement ne vaut plus que le long d'un même tronçon
   (l'échantillonnage le garantissait déjà) ; le glouton est supprimé.

Après correction : **rappel 2/2**, 54 tronçons retenus sur 125. Arbitrage mesuré
(`pente_max_pct` 4 % → 34 % du réseau, marge 0,6 pt ; **6 % → 43 %, marge 2,6 pt** ;
8 % → 57 %, marge 4,6 pt), table reportée dans la doc.

**La précision reste ~4 %**, et c'est structurel : l'attribut `CABLE` encode du
savoir de terrain que la géométrie ne porte pas. `places_depot()` est requalifiée
en **pré-filtre grossier** — dans sa doc (section *Validation*), dans son message
de sortie et dans la vignette. Elle divise par deux l'espace de recherche en
gardant les vraies ; elle ne remplace pas un relevé.

Banc reproductible : `data-raw/oracle_places_depot.R`. Tests de non-régression
opt-in sur ColduPre (`SYLVA=…`), plus un test de régression synthétique : une
route **de niveau sur un versant à 60 %** doit être retenue — c'est le cas que la
v1.6.0 rejetait.

> **Leçon de méthode** : une fonction *heuristique* (qui devine une donnée métier
> au lieu de transcrire Sylvaccess) doit être confrontée à ColduPre **avant** la
> PR. Les fixtures synthétiques et le jeu jouet ne prouvent rien sur la fidélité —
> ils ne testent que la cohérence interne.

### 2026-07-21 — `v1.6.0` : `places_depot()`, candidates de places de dépôt pour le câble

Le moteur câble attend une **couche de départ dédiée** (`potentiel_cable(departs = )`,
équivalent du `c_file_departure` de Sylvaccess, filtré sur l'attribut `CABLE` — 2 tronçons
sur 125 à ColduPre). Sans elle, le balayage part de **toute** la desserte : couverture
massivement optimiste (une piste n'accueille pas un câble-mât) et coût proportionnel au
nombre de cellules de départ. Jusqu'ici le package **exigeait** cette couche sans aider à la
produire.

`places_depot(desserte, mnt, foret, retournements, ...)` (`R/depot.R`) en dérive des
**candidates**, par des critères vérifiables sur la donnée disponible, dans l'ordre :

1. **Accès camion** — largeur mesurée (`largeur` / `largeur_de_chaussee`) ≥ `largeur_min_m` ;
   à défaut le flag `dfci` de `flag_dfci()` ; à défaut la `classe` (`route`/`dfci`). La preuve
   la plus forte prime. Sans aucun de ces attributs, le critère est **indéterminable** : tout
   passe, et la fonction le dit.
2. **Demi-tour** — traversante (deux extrémités raccordées) ou cul-de-sac muni d'une aire de
   retournement. Appliqué **uniquement** si une couche `retournements` est fournie : absence
   de preuve n'est pas preuve d'absence. Réutilise `.degres_extremites()` /
   `.retournement_a_portee()` de `flag_dfci()` (pas de duplication).
3. **Plateforme** — pente du terrain au point candidat ≤ `pente_max_pct` (Horn,
   `calculer_terrain()`). Pente indéterminée (bord du MNT) → écartée.
4. **Utilité** — à moins de `distance_foret_max_m` de la forêt, si `foret` est fournie.

Les survivants sont **éclaircis** à `espacement_min_m` (glouton, la plus plate d'abord) :
deux places voisines balaient deux fois la même forêt pour deux fois le prix. Sortie : un `sf`
POINT portant le champ `cable` (lu tel quel par `potentiel_cable()`), ou les tronçons porteurs
(`sortie = "troncons"`). Garde-fous : CRS identique au MNT sans reprojection implicite
(ADR-004), erreur **actionnable** (quel critère a tout éliminé, quel paramètre assouplir)
plutôt qu'une couche vide.

**Ce que la fonction n'est pas** : un relevé. Le message de sortie l'annonce explicitement —
une place de dépôt exige une plateforme et un accès grumier qui se valident sur le terrain.
Sylvaccess la traite en **donnée d'entrée**, et c'est le bon statut ; `places_depot()` ne
comble que le cas où l'on n'en dispose d'aucune. 24 tests (`test-depot.R`), un par critère
plus l'enchaînement de bout en bout dans `potentiel_cable()`.

### 2026-07-18 — Release v1.5.0 : MNT LIDAR HD fin→agrégé + hotfix build (checks rouges de v1.4.0)

Release **mineure `v1.5.0`**. `acquire_mnt()` télécharge la couche primaire (MNT LIDAR HD) à
une résolution **fine** (`res_lidar_m`, défaut 1 m) sur l'emprise → `lidar_mnt_aoi_buffer.tif`,
puis l'**agrège** (moyenne, facteur `res_m/res_lidar_m`) vers le MNT de travail à `res_m`. Le
5 m est ainsi dérivé proprement d'un MNT fin plutôt que demandé directement au WMS (pyramide
plus grossière). Replis HIGHRES/RGE ALTI inchangés (direct à `res_m`). Nouveau `res_lidar_m`
sur `acquire_mnt()`/`acquire_inputs()`. **NB** : décision utilisateur — on **reste sur le
téléchargement WMS** du LIDAR HD MNT, **pas** de dalles brutes (idée initiale abandonnée).

**Hotfix build embarqué** : v1.4.0 avait été taguée avec **R-CMD-check et pkgdown au rouge**
(la protection de branche n'exige que `version-consistency`, d'où l'auto-merge). Causes : (1)
littéraux de chaîne non-ASCII dans `R/dfci-source.R` (messages `cli`) → `\uXXXX` ; (2)
`acquire_dfci`/`flag_dfci` absents de l'index pkgdown → ajoutés. Le cycle dev `1.4.0.9000`
(PR #85) est **sauté** au profit de `1.5.0`. `rcmdcheck --as-cran` local : 0 erreur, 0 warning
de code (warnings restants = local uniquement : checkbashisms, download de crates Rust).
`DESCRIPTION` = `NEWS.md` = `CITATION.cff` = `1.5.0`. Recommandation : rendre R-CMD-check +
pkgdown **requis** en protection de branche.

### 2026-07-18 — Release v1.4.0 : source du réseau DFCI (OSM `ref:FR:DFCI` + repli géométrique)

Release **mineure `v1.4.0`** : le flag `dfci` (`CL_DFCI`), source du camion DFCI, était laissé
vide depuis la phase 1 (spec 010 §10.2, « à alimenter via une source dédiée »). Il est
désormais **posé automatiquement** par `acquire_inputs(..., dfci = TRUE)` via la nouvelle
fonction exportée `flag_dfci()`, en deux voies :
- **Voie A** — réseau DFCI **OpenStreetMap** : `acquire_dfci()` récupère les pistes taguées
  `ref:FR:DFCI` (+ alias `ref:dfci`/`dfci_ref`), l'identifiant officiel d'une piste DFCI (wiki
  OSM *FR:France/DFCI et DECI*). Appariement au réseau BD TOPO par tampon (`tol_appariement_m`).
- **Voie B (repli géométrique)** — si OSM ne couvre pas l'emprise : piste **traversante**
  (degrés d'extrémités ≥ 2/2 sur graphe base-R, cf. Lot 17) et **emprise ≥ 10 m**, *ou*
  **cul-de-sac** (bout pendant deg 1) muni d'une **aire de retournement**
  (`highway=turning_circle`/`turning_loop`) à portée. Heuristique signalée (`cli_inform`).

`acquire_desserte()` conserve désormais la **largeur** BD TOPO (emprise), requise par le repli.
Nouveau `R/dfci-source.R` + `tests/testthat/test-dfci-source.R` (Voie A, repli, degrés
d'extrémités, chaîne flag → masque source du moteur DFCI). `test-acquire.R` rendu hermétique
(mock `acquire_dfci`/`.acquire_retournements`) + test de propagation du flag. `DESCRIPTION` =
`NEWS.md` = `CITATION.cff` = `1.4.0`. Après merge : tag + release auto, retour cycle dev
`1.4.0.9000`.

### 2026-07-17 — Release v1.3.1 : fix MNT LIDAR (artefacts de pente en grille)

Release **patch `v1.3.1`** : `acquire_mnt()` bascule sur le **LIDAR HD** (`IGNF_LIDAR-HD_MNT`,
Lambert-93 natif), repli `HIGHRES` puis RGE ALTI. Diagnostic parti d'un faux `inexploitable`
en lignes horizontales/verticales sur les classes de débardage : le WMS RGE ALTI servait sur
certaines tuiles un MNT « en blocs » (marches -> fausses pentes > 350 %). Confirmé en faisant
tourner Sylvaccess v3.6 sur l'AOI du projet et en comparant les rasters. Sur l'AOI : forêt
faussement exclue ~33 % -> 0,2 % (conforme Sylvaccess), pente max 357 % -> 165 %. Le bug
faussait tous les moteurs dependant de la pente, pas seulement l'affichage (#80). `DESCRIPTION`
= `NEWS.md` = `CITATION.cff` = `1.3.1`. Apres merge : tag + release auto, retour cycle dev
`1.3.1.9000`.

### 2026-07-17 — Release v1.3.0 : pondération coût + `classes_debardage` + doc

Coupe d'une **release stable `v1.3.0`** (bump **mineur** : deux fonctionnalités
rétrocompatibles accumulées depuis `v1.2.0`). `DESCRIPTION` = `NEWS.md` (tête) =
`CITATION.cff` = `1.3.0` (gate CI `version-consistency`). Contenu :

- **`pondere_cout`** (#73) — le solveur A\* consomme la surface de coût €/m du Lot 14 ;
- **`classes_debardage()`** (#76) — expose le raster « classes de débardage » de Sylvaccess
  (bandes de distance + inaccessible + inexploitable + hors_foret) ;
- **doc** (#74, #75, #77) — articles pkgdown desserte/architecture/choix-conception,
  attributions complètes + schéma des deux épics, note de perf ColduPre, référence exacte
  de la source Sylvaccess (commit `372abaf`).

Après merge : `release.yml` pose le tag `v1.3.0` + la release GitHub, puis retour en cycle
dev `1.3.0.9000`.

### 2026-07-17 — Re-chronométrage ColduPre à isopérimètre (`c_sup = 3`) + site pkgdown

Deux ajouts. **(1) Site pkgdown** : deux nouveaux articles — un guide *Conception d'un réseau de
desserte* (bout en bout : coût → tracé → réseau → flux/typage → optimisation → pondération par
coût, exécutable sur terrain synthétique) et une synthèse *Architecture & feuille de route* (tous
les lots, frontière R/Rust, fidélité, perf). `_pkgdown.yml` : navbar `articles` étendu. Les 78
fonctions exportées sont toutes couvertes par l'index de référence. Site construit en local (OK).

**(2) Re-chronométrage** de tous les moteurs sur ColduPre (894 × 1034), la table de perf de la
première mesure câble étant **périmée** : elle datait d'avant le Lot 4d, quand le noyau câble était
à **zéro support intermédiaire** — comparaison biaisée contre un Sylvaccess à `c_sup = 3`. Mesure
propre (2 passes, `workers = 1`, machine au repos, câble à `nb_supports_max = 3`) :

| Moteur | ForêtAccess (écoulé) | CPU | Sylvaccess (réf.) |
|---|---|---|---|
| preprocess | 1,2 s | 1,1 s | — |
| skidder | ~15 s | ~14,5 s | 14 s |
| porteur | ~17–19 s | ~17 s | 14 s |
| câble (`c_sup = 3`) | **~40 s** | ~165 s (`rayon`) | 3 min 18 s (198 s) |
| dfci | ~26–31 s | ~21 s | — |

**Résultat clé** : à isopérimètre supports (3 des deux côtés), le câble ForêtAccess est **~5× plus
rapide** que le Cython — le noyau Rust parallélisé (`rayon`) abat ~165 s CPU en ~40 s écoulé. Les
moteurs terrestres restent séquentiels et à parité (CPU ≈ écoulé, machine réellement au repos cette
fois). Chiffres reportés dans `vignettes/architecture.Rmd`. Harnais : `data-raw/oracle_coldupre.R`.

### 2026-07-17 — Extension : la surface de coût €/m consommée par le solveur A*

Le Lot 14 calculait une surface de coût de construction (€/m) mais le solveur de tracé n'en
utilisait que le **masque de franchissabilité** — le coût lui-même était ignoré. Cette extension
(hors SylvaRoad, propre à ForêtAccess) le branche : nouvelle option `pondere_cout = FALSE` sur
`tracer_desserte`, `reseau_desserte` et `optimiser_reseau`. À `TRUE`, la contribution distance de
chaque segment A* est pondérée par le coût moyen €/m de ses deux cellules (`CostGrid` côté Rust,
5 bindings enrichis d'un paramètre `cost`), si bien que le tracé minimise l'**euro** et non plus la
seule distance géométrique — il contourne les cellules chères (fort dévers, pente, ouvrages d'art)
et emprunte les corridors bon marché.

Point délicat : pondérer les segments **casse l'admissibilité** de l'heuristique géométrique. Résolu
sans toucher `heuristic.rs` — on remet l'heuristique à l'échelle par `cmin` (coût minimal sur la zone
franchissable) : comme chaque segment coûte au moins `d · cmin`, `h_geo · cmin` reste une borne
inférieure du coût restant, donc l'A* demeure optimal quel que soit le champ de coût. Défaut `FALSE`
= comportement d'origine bit-pour-bit (grille neutre `CostGrid::neutral()`, `w = None`, `cmin = 1`).

Validation : 1 test cargo (`cost_weighting_scales_and_diverts` — coût uniforme ×2 → même tracé plus
cher ; corridor bon marché → le tracé pondéré remonte s'y coller) + 3 tests R (`test-desserte-pondere.R`).
79 tests cargo verts, suite desserte R verte, lint 0. Branche `feat/desserte-pondere-cout`, cycle dev
`1.2.0.9000` (pas de release : fonctionnalité rétrocompatible, publiée à la prochaine mineure).

### 2026-07-16 — Release v1.2.0 : épic « conception de desserte » (Lots 14→18)

Coupe d'une **release stable `v1.2.0`** regroupant tout l'épic desserte accumulé en cycle dev
depuis `v1.1.0` (13 PRs, #58→#70). `DESCRIPTION` = `NEWS.md` (tête) = `CITATION.cff` = `1.2.0`
(gate CI `version-consistency`). `NEWS.md` documente la chaîne complète : `surface_cout_construction`
(14) → `tracer_desserte` (15) → `reseau_desserte` (16) → `vectoriser_reseau`/`calculer_flux`/
`typer_desserte` (17) → `optimiser_reseau` (18). Bump **mineur** (fonctionnalités rétrocompatibles).
Après merge : `release.yml` pose le tag `v1.2.0` + la release GitHub, puis retour en cycle dev
`1.2.0.9000`.

### 2026-07-16 — Lot 18c : rip-up & reroute + clôture du Lot 18 et de l'épic desserte

`optimiser_reseau(..., strategie = "riprute", max_passes)` ajoute l'**amélioration locale
« rip-up & reroute »** et clôt le Lot 18. Noyau Rust `desserte_reseau_riprute` : part du réseau
glouton, puis retire tour à tour chaque chemin et **re-route sa source vers le reste du réseau**
(réutilisation) ; un déplacement est retenu s'il **baisse le coût total** *et* laisse **toutes les
sources connectées**. Répète jusqu'à stabilité ou `max_passes`.

**Garde-fou de connexité** : sur un arbre, ripper un chemin peut déconnecter un dépendant (une
parcelle greffée en aval). Avant d'accepter un déplacement, `all_sources_connected` fait un BFS
depuis le réseau existant sur les segments des chemins et vérifie que chaque source reste atteinte —
sinon le déplacement est rejeté (CA-18.5 garantie). Déterministe (pas de RNG) ; coût total non
croissant → journal monotone (CA-18.1, CA-18.4).

**Lot 18 clos** (18a multi-start, 18b recuit, 18c rip-up) → **épic desserte (Lots 14→18) complet**.
Trois stratégies d'optimisation exposées par `optimiser_reseau`. 3 tests cargo + 15 tests R (module
optim). Prochaine étape : **couper une release stable** de tout l'épic (accumulé en cycle dev depuis
`v1.1.0`) — à cadrer avec Pascal (version + NEWS + CITATION).

### 2026-07-16 — Lot 18b : recuit simulé sur l'ordre d'insertion (Akay 2004)

`optimiser_reseau(..., strategie = "recuit", n_iter, temp0, refroidissement, graine)` ajoute le
**recuit simulé** au-dessus du glouton. Noyau Rust `desserte_reseau_recuit` :
**énergie** = coût total du réseau ; **voisin** = échange de deux positions dans l'ordre
d'insertion ; **acceptation de Metropolis** (`exp(-Δ/T)`), **refroidissement géométrique**. Part de
l'ordre de base et renvoie le **meilleur réseau rencontré** → jamais pire que le glouton (CA-18.1).
Température initiale automatique (fraction de l'énergie de base) si `temp0 <= 0`. La table de
voisinage est bâtie une seule fois ; tirages via SplitMix64 (déterminisme, CA-18.2).

Le `journal` est le **meilleur coût par itération** (monotone décroissant, **CA-18.4**). PRNG
factorisé (`splitmix_next`) partagé avec le multi-start. 2 tests cargo (18a+18b) + 12 tests R.
Reste **18c** (rip-up & reroute) pour clore le Lot 18 et l'épic desserte.

### 2026-07-16 — Lot 18a : optimisation multi-start du réseau (noyau Rust, `rayon`)

Ouverture du Lot 18 (optimisation, Akay 2004). `optimiser_reseau(pre, cout, parcelles,
desserte_existante, strategie = "multistart", n_start, graine, ...)` (`R/desserte_optim.R`) coiffe
le glouton du Lot 16 d'une couche d'exploration : il lance le réseau glouton sous **K ordres
d'insertion perturbés** et retient le réseau de moindre coût total. Sortie `foretaccess_reseau`
(même type que Lot 16) enrichie de `strategie` + `journal` (coût par essai).

**Noyau Rust `desserte_reseau_multistart`** : la table de voisinage est bâtie **une seule fois** et
partagée entre les essais, qui tournent en **parallèle** (`rayon`, `par_iter`). L'essai 0 est
l'ordre de base (heuristique) → le résultat n'est **jamais pire** que le glouton simple (CA-18.1).
Les essais 1.. sont des permutations Fisher-Yates reproductibles (PRNG SplitMix64 sans dépendance,
graine fixée → déterminisme, CA-18.2). Refactorisation R : `.reseau_preparer` (prep commune) et
`.reseau_assembler` (assemblage `foretaccess_reseau`) extraits de `reseau_desserte` et partagés avec
l'optimiseur. Nouveau Rust : `build_network_with_table` (cœur réutilisant la table),
`build_network_multistart`. CA-18.1/18.2/18.5 couverts (le réseau optimisé reste desservi/connexe).
1 test cargo (parallèle correct + reproductible) + 7 tests R. Reste **18b** (recuit simulé) et
**18c** (rip-up & reroute). `recuit`/`riprute` renvoient une erreur informative pour l'instant.

### 2026-07-16 — Lot 17c : typage des routes & conversion temporaire + persistance (Lot 17 clos)

`typer_desserte(graphe, seuils_flux, conversion_temporaire)` (`R/desserte_flux.R`) porte le « Road
Type Determination » de ForestRoadNetwork. Chaque tronçon est classé par **seuils de flux** (bornes
nommées croissantes : flux fort → primaire, … , faible → tertiaire ; `findInterval`). Option
**conversion temporaire** : convertit une part (`proportion`) de la longueur d'un type en routes
temporaires/hivernales, **en priorité dans les zones dédiées** (`zones`), glouton par longueur
décroissante. Sortie `foretaccess_desserte_typee` : `troncons` (`sf` avec `type`), `noeuds`,
`sources`, `recap` (longueur par type).

**Persistance (Lot 8)** : la sortie est un `sf` standard, écrit/relu via le socle spatial
(`storage_gpkg` + `sb_write_layer`/`sb_read_layer`), testé en GeoPackage. **CA-17.5** (typage
respecte les seuils), **CA-17.6** (part convertie respectée ± un tronçon) vérifiés. 41 tests R (15
ajoutés). **Lot 17 clos** (17a vectorisation, 17b flux, 17c typage). Reste l'épic : Lot 18
(optimisation multi-start), dernier lot.

### 2026-07-16 — Lot 17b : sources & accumulation de flux (Wood Flux Determination)

`calculer_flux(graphe, parcelles, volume_champ, densite_sources)` (`R/desserte_flux.R`) porte le
« Wood Flux Determination » de ForestRoadNetwork. Des **points sources** sont semés dans chaque
parcelle (échantillonnage régulier, **≥ 1 par parcelle** quelle que soit la densité — CA-17.2),
chacun injectant sa part du volume ; le volume **descend** le réseau vers l'**exutoire le plus
proche** en s'accumulant sur chaque tronçon.

Le réseau étant **arborescent**, le routage est un **Dijkstra multi-source depuis les exutoires**
(`.flux_router`) donnant, par nœud, le premier saut vers l'exutoire ; l'accumulation remonte les
pointeurs parent (sous-arbre). Sortie : colonne `flux` ajoutée aux `troncons`, `sf` `sources`
stocké. **CA-17.3** (conservation : volume semé = volume aux exutoires) et **CA-17.4** (le flux
croît de l'amont vers l'aval, max au tronçon-exutoire = volume total) vérifiés. 26 tests R (11
ajoutés). Reste **17c** (typage par seuils + conversion temporaire + persistance Lot 8).

### 2026-07-16 — Lot 17a : vectorisation topologique du réseau en graphe (base R)

Ouverture du Lot 17 (flux de bois & typage, portage de ForestRoadNetwork — Klemet, GPL v3).
`vectoriser_reseau(reseau)` (`R/desserte_flux.R`) transforme le réseau raster/polylignes du Lot 16
en un **graphe topologique propre** : objet `foretaccess_reseau_graphe` avec `noeuds` (`sf` POINT :
`id`, `cell`, `degre`, `type` ∈ exutoire/jonction/feuille) et `troncons` (`sf` LINESTRING : `id`,
`de`, `vers`, `longueur`).

**Choix d'archi — graphe base R, pas `igraph`/`sfnetworks`** (cf. mémoire `lot17-graphe-base-r`) :
`igraph` ne s'installe pas en local (binaire noble incompatible) et ajouterait une dépendance
compilée lourde + risque CI. Or le réseau est **arborescent** (rooted sur la desserte existante),
donc le flux (17b) sera une simple **accumulation en sous-arbre**, sans Dijkstra externe. Astuce
clé : les **indices de cellule raster** (`terra::cellFromXY`) servent d'**identifiants de nœud
exacts** — les cellules partagées (tronçons réutilisés) deviennent le même nœud sans collage
flottant. La vectorisation **contracte les chaînes de degré 2** en tronçons entre nœuds
remarquables (exutoire, jonction deg ≥ 3, feuille deg 1).

`reseau_desserte` (Lot 16) stocke désormais `desserte` (le réseau existant) dans sa sortie, pour
que `vectoriser_reseau(reseau)` soit auto-suffisant (identification des exutoires). Helpers R
`.graphe_aretes_fines`, `.graphe_contracter`. **CA-17.1** (jonctions deg ≥ 3, exutoire sur le
réseau, pas d'arête pendante) couvert. 15 tests R. Reste **17b** (sources + accumulation de flux)
et **17c** (typage + conversion temporaire + persistance Lot 8).

### 2026-07-16 — Lot 16c : raccordement / connexité + sortie affinée (Lot 16 clos)

Sortie `foretaccess_reseau` complétée pour clore le Lot 16 :

- **`reseau` (raster) continu** : le voisinage disque du solveur (Lot 15) avance par sauts ; les
  cellules de passage sont donc espacées. On rasterise désormais les **géométries** (routes créées
  + réseau existant, `touches = TRUE`) plutôt que les seules cellules-jalons → réseau raster sans
  trous, prêt pour le Lot 17 (flux).
- **`connexe`** (logique, **CA-16.5**) : `terra::patches` (voisinage 8) sur le raster continu — une
  seule composante ⇒ aucune route isolée. Vrai par construction (l'A* multi-cible s'arrête sur une
  cellule de réseau) mais désormais **vérifié**.
- **`desservies`** (logique par parcelle, **CA-16.1**) : chaque parcelle a-t-elle une cellule sur le
  réseau ou à distance de débardage (`skidding_m`) d'une route ? Couvre le cas « desservie par
  proximité, sans route construite ».
- **`lignes$longueur`** : longueur planimétrique (m) par tronçon (`sf::st_length`, CRS projeté).
- `print.foretaccess_reseau` affiche parcelles desservies + connexité.

Nouveaux helpers R `.reseau_connexe`, `.reseau_desservies`. **20 tests R** (4 ajoutés : CA-16.5
glouton+steiner, CA-16.1 desserte, desserte par débardage, longueur). **Lot 16 clos** (16a glouton,
16b Steiner, 16c connexité). Reste l'épic : Lot 17 (flux/typage), Lot 18 (optimisation multi-start).

### 2026-07-16 — Lot 16b : mode Steiner (MST des terminaux + matérialisation avec réutilisation)

`reseau_desserte` gagne un argument `mode = c("glouton", "steiner")`. Le mode **Steiner**
(Chung & Sessions, « qualité ») est implémenté **entièrement en R** au-dessus des bindings du
Lot 15/16a — aucun nouveau code Rust :

1. **Terminaux** : le réseau existant (racine) + un nœud d'accès par parcelle (la cellule de la
   parcelle géométriquement la plus proche du réseau, `terra::distance`).
2. **Graphe complet** : poids d'arête = coût du plus court chemin contraint du Lot 15 —
   réseau↔parcelle via `desserte_reseau` (source unique, arrêt sur réseau), parcelle↔parcelle via
   `desserte_trace` (waypoint à waypoint). N² tracés.
3. **MST Prim** enraciné sur le réseau (`.steiner_prim`) : Prim ajoute chaque terminal après son
   parent, donc l'ordre des arêtes est déjà un parcours racine→feuilles valide.
4. **Matérialisation avec réutilisation** : chaque parcelle, dans cet ordre, se **re-raccorde au
   réseau courant** (existant + tronçons déjà posés) via `desserte_reseau`. C'est ce re-solve qui
   **fusionne les cellules partagées** (coût abaissé à ~0, comme le glouton) et **élague** les
   doublons — une greffe mi-parcours plutôt qu'un chemin parallèle.

Le point subtil : un MST « brut » qui somme les coûts d'arêtes indépendants **surestime** (pas de
fusion) et peut dépasser le glouton ; c'est la matérialisation avec réutilisation qui garantit
CA-16.4 (Steiner ≤ glouton). Sur le plan incliné du banc, les liaisons purement latérales sont
infaisables (pente longitudinale nulle < `pente_long_min`), donc Steiner reproduit la réutilisation
du glouton et égale son coût. `print.foretaccess_reseau` affiche le `mode`. **16 tests R** (4
ajoutés : desserte + connexité + CA-16.4 + mode invalide). Reste **16c** (connexité formelle,
sortie affinée).

### 2026-07-16 — Épic « conception de desserte » ouvert ; Lot 14 (coût de construction) livré

Nouvel épic (Lots 14-18, `docs/ROADMAP-desserte.md`, ADR-008) : passer de la **cartographie**
d'accessibilité à la **conception** d'un réseau de desserte forestière. Sources GPL v3
transposées : ForestRoadNetwork (Klemet), SylvaRoad (Dupire/ONF), Forest Road Designer
(PANOimagen). Specs 014-018 déposées, chemin critique 14 → 15 → 16 → 17, optimisation en 18.

**Lot 14 — surface de coût de construction** (`specs/014`, R pur, sur le chemin critique) :
`surface_cout_construction(pre, config, plan_eau, cours_eau, sol, interdit, surcout)` rend un objet
`foretaccess_cout_construction` (deux `SpatRaster` alignés MNT : `cout` €/m, `franchissable`).
Coût **additif** inspiré du « Cost Raster Creator » de ForestRoadNetwork : base + surcoût de pente
par barème `[min,max) → surcout` + surcoût de sol (table classe → €/m) + franchissements ponctuel
(pont sur plan d'eau) et linéaire (buse ∝ densité de cours d'eau) + surcoût libre. Un surcoût de
pente `Inf` (non constructible), un obstacle complet ou une zone interdite ferment la cellule
(`franchissable = FALSE`, `cout = NA`). Couches optionnelles acceptées en `SpatRaster` **ou** `sf`,
réalignées sur la grille ; absentes, elles n'ajoutent rien (jamais d'erreur — CA-14.1).
Config `desserte$cout` ajoutée à `foretaccess_config()` avec fusion imbriquée et validation
(barème contigu/couvrant, coûts finis ≥ 0 — CA-14.6). 32 tests (`test-desserte-cout.R`, CA-14.1
à 14.6), fixture légère pour piloter la pente cellule à cellule. **Prochaine étape : Lot 15**
(solveur de tracé A* sur ce coût — déclenche un portage Rust, ADR-001).

### 2026-07-16 — `v1.1.0` : optimisation de la hauteur des supports câble (SEILAPLAN)

Release mineure (feat) : spec 013 bouclée en quatre incréments (13a brique mécanique, 13b graphe +
Dijkstra, 13c intégration + confrontation, 13d validation + nettoyage). `cable$methode_supports =
"seilaplan"` optimise position **et** hauteur des supports à la Bont & Heinimann (2012), en
réutilisant notre caténaire. Confrontée cellule à cellule à l'oracle `c_option_h=true` : accord
**93,2 → 94,7 %**, fidèle à l'oracle (+454 ≈ +470 en fenêtre), perf **×2,8**. Défaut `"sylvaccess"`
(`_NoH`) inchangé, bit-pour-bit. `OptPyl_Up2` shelvé et le flag `optimiser_hauteur_fixation` retirés.
`DESCRIPTION` / `NEWS.md` / `CITATION.cff` alignés sur `1.1.0` ; `release.yml` pose le tag `v1.1.0` au
merge. Retour en cycle dev `1.1.0.9000` juste après.

### 2026-07-16 — SEILAPLAN 13d : validation cellule à cellule à l'oracle `c_option_h=true`

Dernier incrément de `specs/013`. La réserve de 13c.2 (le +3619 dépasse le gain oracle +470) est
**levée** : confronté **cellule à cellule** à l'oracle Sylvaccess `c_option_h=true`
(`sylvaccess_hopt`) sur **sa propre fenêtre câble** (28336 cellules forestières calculées), le
graphe SEILAPLAN **colle à l'oracle**, il ne sur-couvre pas.

| comparaison (fenêtre oracle) | accord | faux+ (sur-couvre) | faux− (sous-couvre) |
|---|---|---|---|
| FA `_NoH` vs oracle-hopt | 93,15 % | 25 | 1915 |
| **FA seilaplan vs oracle-hopt** | **94,73 %** | **29** | **1465** |

- **En fenêtre**, seilaplan gagne **+454** cellules (26399 → 26853) — quasi le **+470** de l'oracle —
  avec l'accord qui **monte** (93,15 → 94,73 %) et **quasi aucun faux-positif nouveau** (25 → 29).
  Donc le CA-13.5 est tenu : seilaplan **reproduit fidèlement** `c_option_h=true`, il récupère du
  trop-conservateur sans devenir trop-optimiste.
- Le **+3619** de tête (grille entière) est **dominé par le hors-fenêtre** (~3165) : c'est l'écart
  **de fenêtrage** FA/Sylvaccess (Sylvaccess ne calcule le câble que dans un buffer autour des
  places de départ ; nous balayons toute la grille), **déjà connu** et présent aussi sur le `_NoH` —
  **pas** un défaut d'optimisation de hauteur. Il se réduira avec la sélection de lignes (Lot 5).

**Conclusion** : la voie SEILAPLAN **tient CA-13.3 (couverture ↑, fidèle à l'oracle), CA-13.4 (perf
×2,8) et CA-13.5 (accord cellule à cellule ↑)**. Reste le nettoyage : retrait d'`OptPyl_Up2` et du
flag `optimiser_hauteur_fixation`, superseded.

### 2026-07-16 — SEILAPLAN 13c (câblage) : `methode_supports = "seilaplan"` de bout en bout

Troisième incrément de `specs/013` — l'intégration du graphe (13b) dans le balayage `cable_scan`.

- **Config** (`R/config.R`) : `cable$methode_supports = "sylvaccess"` (défaut) `| "seilaplan"`, plus
  les réglages du graphe (`hauteur_support_{min,max}_m`, `pas_hauteur_support_m`,
  `distance_min_support_m`, `nb_pas_pretension`), avec validateurs.
- **Rust** (`scan.rs`, `lib.rs`) : la branche `seilaplan` de `scan()` appelle `optimize_supports`
  sur le profil au demi-mètre (`zs`). Positions candidates = crêtes (`peak_positions`) **∪ grille
  régulière** au pas `Min_Dist_Mast` — les crêtes seules ne suffisent pas sur terrain lisse (il faut
  des points où couper la ligne / poser un support, l'équivalent de la coupe d'`OptPyl`). Le graphe
  étant **symétrique**, un seul passage : plus de gymnastique machine-en-haut/bas ni de profil
  retourné. Portée du graphe → dernier index couvert du profil aller.
- **Bindings** regénérés (`rextendr::document()`), doc `potentiel_cable` §Écarts complétée.
- **Tests** : R bout-en-bout (`methode_supports = "seilaplan"` tourne, couvre des cellules
  forestières dans l'enveloppe, longueur dans `[lmin, lmax]`) ; méthode inconnue refusée à la
  validation. 52 tests cargo intacts. Défaut `"sylvaccess"` : non-régression garantie.

**Confrontation ColduPre (16/07)** — deux optimisations perso d'abord (commit `bc5ed3d`, sans
changer les résultats) : **pré-filtre `check_droite`** avant `calc_sta` (écarte les travées dont la
corde passe sous la garde, sans Newton) et **suppression de la bissection `maxSTA`** (dans notre
mécanique `MaxSTA = tmax` toujours, l'effort ne borne qu'à `tmax`). Résultats confrontés au `_NoH` :

- **Perf (CA-13.4)** : config **fine** (6 niveaux de hauteur, supports à 30 m) **~9× le `_NoH`**
  et croissant — **échoue** la cible (< 5×). L'explosion vient du produit position² × hauteur²
  d'appels `calc_sta` (chacun marchant `Lo` par Newton). Config **légère** (2 niveaux 6/12 m,
  supports à 60 m) : **×1,3** seulement — donc le coût est bien dans la densité de nœuds.
- **Couverture (CA-13.3)** : config légère → seilaplan **25170** cellules vs `_NoH` **31275**,
  soit **−6105** (gagne 1995, **perd 8100**). **Mauvaise direction** (la cible est ↑, +470 vers
  l'oracle) — même symptôme que le port `OptPyl_Up2` shelvé. La config fine (trop lente à mesurer)
  ferait sans doute mieux, mais la perte est trop massive pour n'être qu'un effet de config.

**Cause probable** : la **portée du graphe est quantifiée aux positions candidates** (coupe la
ligne au dernier support atteint, granularité 30–60 m), là où `OptPyl_NoH` coupe au **pixel** près
et prolonge la dernière travée jusqu'à sa vraie limite. D'où ~8100 cellules perdues en bout de
ligne. C'est un **écart de modèle** ForêtAccess (balayage : « jusqu'où porte la ligne ? ») vs
SEILAPLAN (conception : « ligne vers un point d'arrivée **connu** »).

**13c.2 — passe de correction (choisie par l'utilisateur), RÉUSSIE** :

1. **Prolongation de portée** (`seilaplan::extend_reach`) : le graphe s'arrête au dernier support
   candidat, mais le câble porte encore jusqu'à un ancrage terminal plus loin. On place l'ancrage au
   pas raster le plus lointain encore faisable (comme la coupe d'`OptPyl`). → recouvre les ~8100
   cellules de bout de ligne perdues. Effet mesuré (config légère) : **−6105 → −1791**.
2. **Partage de l'amorçage** (`seed_for_span` / `calc_cable_seeded`) : `seed_grid` (grille 40×40
   = 1600 évals de caténaire) était refait à **chaque** tension de la bissection `calc_sta`, alors
   qu'il ne dépend que de la géométrie (même `Lo` de départ). Calculé **une fois** par travée. →
   ~3× moins cher. Résultat inchangé (l'amorçage n'affecte pas la racine). 52 tests cargo verts.

**Confrontation ColduPre finale** (config `4/8/12 m`, supports à 40 m, `n_sk=12`) :
**seilaplan = 34894 cellules vs `_NoH` = 31275 → +3619** (gagne 3943, **perd 324**), **perf ×2,8**.
→ **CA-13.3 (couverture ↑) et CA-13.4 (perf < 5×) tenus.** Défauts config alignés sur ces valeurs.

**Réserve (→ 13d)** : +3619 **dépasse** le gain net de l'oracle `c_option_h=true` (+470) — signe d'un
possible **excès d'optimisme** (prolongation trop permissive et/ou absence de sélection de lignes,
Lot 5). À trancher par la **validation ligne à ligne vs SEILAPLAN** (CA-13.5) et la comparaison
cellule à cellule à l'oracle `sylvaccess_hopt`. Puis retrait de `OptPyl_Up2` et du flag
`optimiser_hauteur_fixation`.

### 2026-07-16 — SEILAPLAN 13b : graphe + Dijkstra (optimisation position + hauteur)

Deuxième incrément de `specs/013`. Le cœur de l'algorithme de **Bont & Heinimann 2012**, transcrit
de `core/main_opti.py::optimization`, en Rust dans `cable::seilaplan` — **sans** dépendance scipy.

- **`optimize_supports(di, zi, candidats, GraphParams, CableMat)`** : optimise **position et
  hauteur** des supports. Nœuds = (position candidate × niveau de hauteur `δh`), extrémités à
  hauteur fixe (mât/ancrage). Arêtes forward soumises à `Min_Dist_Mast` (exceptions départ/arrivée) ;
  chaque arête = **une travée**, sa faisabilité étant la plage `[MinSTA, MaxSTA]` de `calc_sta` (13a)
  — c'est là que le graphe réutilise notre mécanique. Coût `KostStue` (`kost_stue`) : ≥ 10000/support
  (minimise le nombre), croissant en `(h+100)²` (minimise la hauteur), ×5 au-delà de l'arbre naturel.
- **Balayage de pré-tension + Dijkstra maison** (`BinaryHeap`) : pour chaque `sk` (n_sk pas), on
  active les arêtes où `MinSTA < sk < MaxSTA`, plus court chemin, on retient la pré-tension qui
  **maximise la portée** puis **minimise le coût**. **Coupe native** : si l'arrivée n'est jamais
  atteinte, on garde la ligne partielle la plus longue.
- **`peak_positions`** : port de `peakdetect` (crêtes du profil = positions candidates).
- **Tests** : 6 tests `cargo` (52 au total) — CA-13.1 (support posé quand le span direct échoue,
  corde sous la crête), pas de support inutile quand le direct passe, hauteur fixe = optimisation de
  position seule + déterminisme (CA-13.2, esprit), coupe à la portée max, coût `KostStue`,
  `peakdetect`.

**Reste** : 13c (câblage `cable_scan` / config `methode_supports`, extrémités mât/ancrage,
confrontation ColduPre — CA-13.3 couverture ↑, CA-13.4 perf), 13d (validation ligne à ligne vs
SEILAPLAN, retrait de `OptPyl_Up2` et du flag `optimiser_hauteur_fixation`).

### 2026-07-16 — SEILAPLAN 13a : brique mécanique à tension imposée (`calc_cable` + `calc_sta`)

Premier incrément de `specs/013` (optimisation de la hauteur des supports à la Bont & Heinimann,
en remplacement du `c_option_h`/`OptPyl_Up2` shelvé). Objectif : la **brique mécanique** dont le
graphe (13b) aura besoin, **sans** encore de graphe ni de câblage `cable_scan`.

- **`cable::supports::calc_cable(SpanGeom, t_impose) → (converged, garde_ok, effort_ok, sag, lo)`** :
  évalue une travée à une **tension imposée**. On garde **notre** mécanique (Newton/Irvine,
  oracle-validée) — décision spec 013 §4.1a, pas la mécanique de Zweifel de SEILAPLAN. Adaptation de
  `find_lomin` : on marche `Lo` jusqu'à ce que la tension (charge centrée) atteigne `t_impose` au
  lieu de `Tmax`, en réutilisant `seed_grid`, `newton_centre` et `check_hlinemin` inchangés. Garde au
  sol et effort admissible sont rendus **séparément** (comme `calcCable`/`checkCable` de SEILAPLAN).
- **`cable::seilaplan::calc_sta(SpanGeom, t_min, t_max, detail) → [MinSTA, MaxSTA]`** : transcription
  fidèle de `core/opti_sta.py::calcSTA` (deux bissections max/min partageant un cache `Speicher`).
  C'est le **modèle de pré-tension globale** de SEILAPLAN : chaque travée fournit une plage de
  pré-tension, pas une tension propagée.
- **Tests** : 7 tests `cargo` (46 au total, les 39 d'avant inchangés) — flèche croissante quand la
  tension baisse, garde violée si sol trop haut, effort refusé au-delà de `tmax`, plage `[MinSTA,
  MaxSTA]` bornée ou infaisable. `_NoH` (défaut ColduPre) intact.

**Reste** : 13b (graphe + Dijkstra maison, positions `peakdetect`, coût `KostStue`), 13c
(intégration `cable_scan` / `methode_supports`, confrontation ColduPre), 13d (validation ligne à
ligne vs SEILAPLAN, retrait de `OptPyl_Up2` et du flag `optimiser_hauteur_fixation`).

### 2026-07-16 — Câble `c_option_h` : portage tenté, mis en attente (bug + perf)

Chantier « optimisation de la hauteur de fixation » (`c_option_h`), dette assumée du Lot 4.
**Décisions prises en cours** : régénérer un oracle (ColduPre est à `c_option_h=false`),
périmètre `test_hfor=0` (plafond uniforme).

**Infrastructure produite (saine, conservée)** :
- **Régénération d'oracle Sylvaccess** : env conda `sylvaccess` recréé, `.so` recompilé (ABI numpy),
  params redirigés hors du repo frère (`data-raw/oracle/coldupre/params_cable_hopt.json`). Procédure
  en mémoire (`regenerer-oracle-sylvaccess.md`).
- **Bug trouvé dans Sylvaccess** : son propre chemin `c_option_h=true` **plante** sur ColduPre
  (`OptPyl_Up2`, `IndexError` — tampon `Tab` sous-dimensionné `100·nbconfig` face au double balayage
  `Hg×Hd`). Ce chemin n'a jamais été exercé sur un vrai jeu, d'où le défaut v3.6 `false`. Corrigé
  dans la copie scratchpad (`×100`→`×2000`) : purement du dimensionnement, résultats identiques.
- **Gain mesuré de la fonctionnalité** : sur ColduPre, l'oracle `c_option_h=true` couvre **+517/−47**
  cellules vs `false` (~1,7 %), en fermant du trop-conservateur.

**Portage Rust (derrière le flag `optimiser_hauteur_fixation`, défaut `FALSE`)** :
`optpyl()` généralisé (`optim_h` : hauteur terminale abaissée + supports intermédiaires balayés) et
nouvelle `optpyl_up2()` (machine en bas : ancrage balayé). Le **`_NoH` (défaut) est bit-pour-bit
inchangé** — 38 tests cargo d'origine verts, +1 nouveau.

**Pourquoi mis en attente** : confronté au nouvel oracle, le chemin `optim_h=true` **part dans le
mauvais sens** — il *réduit* la couverture (net **−999** cellules) là où Sylvaccess l'*augmente*
(net **+470**) ; sur les +517 cellules gagnées par l'oracle, on n'en couvre que 207. Bug de fidélité
restant, probablement dans `optpyl_up2` (lignes trop courtes). S'ajoute une **perf prohibitive**
(**46 min pour 2 départs**, ~20× le `_NoH`) et une **boucle de validation à 46 min/itération**.
Coût/bénéfice défavorable (gain ~1,7 %, opt-in) : chantier **shelvé**, code conservé derrière le flag
pour reprise, avec avertissement `cli` à l'activation et doc explicite.

### 2026-07-15 — `v1.0.0` : première version majeure (validée contre le vrai moteur)

Bump majeur posé, confirmé par l'utilisateur. Le sens de la `1.0.0` est celui décidé au Lot 11 :
**« validée contre le vrai moteur Sylvaccess »**, non « périmètre atteint ». Préalable tenu sur les
**quatre moteurs** (skidder 99,95 %, porteur 99,72 %, câble 98,36 %, DFCI 99,87 % sur ColduPre),
distances collées décomposition comprise (pondération de piste incluse). La release publie le
**Lot 12a.4 (DFCI radial)**, resté en cycle dev depuis `v0.14.0`. `DESCRIPTION` / `NEWS.md` /
`CITATION.cff` alignés sur `1.0.0` ; `release.yml` pose le tag `v1.0.0` et la release au merge sur
`main`. Retour en cycle dev `1.0.0.9000` juste après.

### 2026-07-15 — Correction de l'« État courant » : la pondération de piste était déjà faite

En voulant « attaquer » la pondération de la piste dans l'arbitrage — que l'« État courant »
listait comme un écart assumé à traiter avant `v1.0.0` — j'ai constaté qu'elle est **déjà
implémentée et livrée** en `v0.14.0`. Le veto de propagation (`0,5`, `R/skidder.R:.propager_trainage`)
et l'arbitrage route/piste (`0,1`, `.arbitrer_desserte` + `R/porteur.R`) datent des Lots **12a.1**
(skidder, #38) et **12a.2b** (porteur), avec coefficients en config (`ponderation_piste_propagation`
/ `ponderation_piste_arbitrage`) et tests dédiés (`test-skidder-distances.R:199`, cas « piste longue
vs route lointaine » que ColduPre ne peut pas exhiber). Le paragraphe « pondération 0 / à traiter
avant v1.0.0 » de l'« État courant » était un **reliquat du journal du 14/07**, antérieur à 12a.1,
jamais purgé. `État courant` et le bullet « prochain jalon v1.0.0 » corrigés : plus aucun blocage
technique connu à `v1.0.0`. Leçon : rapprocher `NEWS.md` (qui, lui, documentait bien le veto) de
`PLAN.md` avant d'ouvrir un chantier.

### 2026-07-15 — Lot 12a.4 : moteur DFCI radial (spec fausse corrigée, 99,87 %)

**La spec 006 reposait sur une hypothèse fausse.** Elle affirmait « Sylvaccess n'a pas de module
DFCI » et livrait une *conception propre* : un plus court chemin pondéré par la pente (Dijkstra).
Faux — `Sylvaccess_5_dfci.py` (`debusq_dfci`) existe. Le moteur beta a donc été **jeté et
réécrit** en transcription à la lettre.

**Le vrai moteur est un lancer de rayons radial.** Depuis chaque pixel du réseau DFCI (flag
`CL_DFCI`, orthogonal aux classes de desserte), une lance est tirée dans les 360 azimuts (pas 1°)
et **épouse le relief** (`Lcum += sqrt(dh² + ddist²)`), plafonnée à `dfci_lmax = 440 m`, arrêtée
par la pente (> `dfci_slope_max = 110 %`), un obstacle ou le bord. Le chemin Dijkstra
(`calc_dist_dfci`) existe dans le `.pyx` mais y est **désactivé** — nous avions implémenté la
mauvaise branche. Sortie : zone de défendabilité **5 classes** (inaccessible / non-défendable-pente
/ 3 bandes de lance `0-120 / 120-280 / 280-440`), plus `Longueur_lance`, `Denivele_sur_piste`,
`Lien_foret_reseau`, `Pente_OK_pompier`.

**Architecture** : boucle chaude portée en **Rust** (`src/rust/src/dfci/`, `dfci_scan`), comme le
câble. Modèle de données étendu : `preprocess()` rasterise `pre$dfci_source_mask` depuis le flag
`CL_DFCI`. Arrondis fidèles (half-up cm, half-away dénivelé, pente seuil simple par cellule). Le
**bug de masquage du dénivelé** (pyx:4807) est corrigé sciemment.

**Le bug qui coûtait 20 points.** Première confrontation : 79 % seulement, 20,9 % trop conservateur,
0 % trop optimiste — sous-couverture en blocs pleins à 45 m des sources. Diagnostic (carte ASCII) :
un **décalage à un cran** dans le classement (`2L + bande` au lieu de `3L + bande`) codait la bande
la plus proche (0-120 m, l'essentiel de la couverture) comme *non-défendable*. Corrigé.

**Confrontation à l'oracle (ColduPre, 532 016 cellules)** : zone défendable **99,87 %** (0 % trop
optimiste, 0,13 % trop conservateur), longueur de lance **écart médian 0,0 m**, dénivelé **0,0 m**.
Le reliquat (0,13 %) est de la discrétisation de rayon en bordure. Banc étendu :
`oracle_coldupre.R` + `oracle_compare.R` (bloc DFCI, sauté si l'oracle absent). Perf : ~76 s
séquentiel (parallélisation `rayon` reportée au Lot 12c).

### 2026-07-15 — Lot 12a.3 : pêchage latéral du câble (96,58 % → 98,36 %)

**Diagnostic (12a.3 amont).** Le reliquat câble était **asymétrique** : 2,79 % de cellules trop
conservatrices (Sylvaccess accessible, nous non) contre 0,63 % trop optimistes. Caractérisation en
mémoire : 96,4 % des manquées à ≤ 40 m d'un couloir traçable, sur pentes **plus douces** que la
forêt (26,8° contre 33,1°) — signature d'un **pêchage latéral** manquant, pas d'un déficit de portée
(qui frapperait le raide) ni de la hauteur de fixation (`c_option_h`, hors périmètre).

**Mécanique lue à la lettre.** `create_rast_couv` (Sylvaccess) rasterise la `Zone_accessible` comme
l'**union de rectangles** de demi-largeur `c_l_hor = 40 m` autour du segment de chaque ligne
(`pt_emprise` + `ALL_TOUCHED`). C'est un **tampon perpendiculaire inconditionnel** : aucune
contrainte de dénivelé, de pente latérale ni de visibilité. La supposition initiale « sous contrainte
de dénivelé latéral » (spec) était **fausse** — corrigée.

**Réalisation.** `build_lat_rays(res, lmax, l_hor)` (Rust, `cable/scan.rs`) précalcule par azimut les
cellules du tampon avec leur distance *le long* de la ligne ; au balayage, une ligne faisable de
longueur `L` couvre celles dont `dalong ≤ L`. Ajouté à la seule **couverture**, pas à la
surface/volume de la ligne (qui restent sur l'axe, pour ne pas perturber la future sélection). Câblé
`cable_scan` → `ct$l_hor` (`distance_laterale_max_m`). Tests `cargo` + R verts.

**Résultat (ColduPre).** Accord câble **96,58 % → 98,36 %**. Trop conservateur **2,79 % → 0,40 %**
(~86 % de l'écart fermé). Contrepartie **0,63 % → 1,24 %** de trop optimiste : on tamponne *toute*
ligne candidate faisable, là où Sylvaccess ne tamponne que les lignes **retenues** (`Tab_result`).
Cette sur-couverture est le corollaire de l'**absence de sélection de lignes** (Lot 5), pas du tampon.

### 2026-07-13 — Lot 11 : confrontation à l'oracle Sylvaccess réel

**Décision de séquencement** : l'oracle passe **avant** `v1.0.0`. La raison d'être du projet
est la fidélité à Sylvaccess ; une `v1.0.0` qui ne l'a jamais vérifiée est une promesse non
tenue. Périmètre : les 3 moteurs (skidder, porteur, câble).

**Le banc.** Le dépôt `forge.inrae.fr/sylvain.dupire/sylvaccess` est clone en lecture seule
sous `~/dev/sylvaccess-upstream` (hors du repo, jamais commité). Sylvaccess **tourne** ici :
`.so` Cython précompilé pour Linux/py3.9, environnement conda (`sylvaccess_environment.yml`),
lanceur headless `0_Lance_sylvaccess.py -file <param>`. Scripts du banc :
`data-raw/oracle_coldupre.R` (fait tourner ForêtAccess sur les entrées de l'oracle) et
`data-raw/oracle_compare.R` (comparaison cellule à cellule).

**Il n'existe aucun oracle livré.** Le jeu de test officiel `test/ColduPre` ne contient qu'un
`Input/` — pas de sortie de référence. L'oracle doit être **produit** en exécutant Sylvaccess.
Fait : 44 fichiers de sortie, 3 moteurs + sélection de lignes.

**Résultats sur ColduPre** (894 × 1034, 411 309 cellules forestières), après correctifs :

| Moteur | Accord | Trop optimistes | Trop conservateurs |
|---|---|---|---|
| Skidder | **99,95 %** | 177 cellules (0,04 %) | 38 cellules (0,01 %) |
| Porteur | **99,72 %** | 892 cellules (0,22 %) | 244 cellules (0,06 %) |
| Câble | **96,58 %** | 0,63 % | 2,79 % |

Le cœur des moteurs est fidèle, et **toutes les distances collent** : débusquage à **0,2 m**
d'écart médian, traînage sur piste à **7,3 m** (max 1 407,6 contre 1 376,0), distance totale à
**1,9 m** (max 1 464,6 contre 1 440,0). Le Dijkstra, le balayage radial et la loi de bascule
reproduisent la source.

**Quatre bugs trouvés, tous invisibles sur le jouet ET sur l'AOI des Cévennes** — c'est
l'argument qui justifiait de roder le banc sur le jeu de l'auteur avant l'AOI réelle :

1. **`.masque_vecteur()` perdait les géométries non-polygonales** (`R/preprocess.R`).
   `terra::vect()` sur une couche `sf` hétérogène ne retient qu'un seul type de géométrie et
   **abandonne les autres sans erreur**. Sur ColduPre : 1 676 obstacles en entrée, 1 467
   rasterisés — les 209 lignes (cours d'eau, réseau public) disparaissaient. Corrigé :
   rasterisation par famille (surface / ligne / point) puis union, `touches = TRUE` pour les
   lignes (un cours d'eau ne passe pas par le centre des cellules). Test de non-régression
   ajouté.
2. **Le traînage sur piste payait le surcoût d'obstacle** (`R/skidder.R`). Le réseau public
   est à la fois **desserte** (on y livre le bois) et **obstacle du skidder** (on ne débarde
   pas au travers). Notre propagation *le long du réseau* utilisait la surface de coût
   complète : elle payait 1000 par cellule de route publique empruntée, d'où des distances de
   **198 529 m** (Sylvaccess plafonne à 1 376 m). Une route n'est pas un obstacle à la
   circulation sur elle-même. Sylvaccess sépare les deux surfaces : `Pond_pente` (pente pure)
   pour `Link_RF_res_pub`/`Link_tracks_res_pub` — les distances réseau, calculées **avant**
   que les obstacles n'existent — et `Pond_pente2` (pente + 1000 × obstacles) pour la seule
   propagation en forêt. Corrigé.

3. **Le `reseau_public` manquait au modèle de desserte** (`R/validate.R`, `R/cout.R`,
   `R/skidder.R`, `R/porteur.R`). Nos classes étaient `route` / `piste` / `dfci` : la route
   ouverte à la circulation était comptée comme une route forestière. Or c'est le point de
   chargement du **camion**, pas une place de dépôt, et pour les engins de débardage une
   **barrière**. Sylvaccess l'exclut des sources (`from_rast[Res_pub==1]=0`), de la zone
   roulable (`zone_rast[Res_pub==1]=0`, trois fois) et le verse aux obstacles du porteur
   (`Obstacles_forwarder[Res_pub==1]=1`). Quatrième classe ajoutée, plus `.classes_livraison()`
   et `.cellules_livraison()`.
4. **Le skidder roulait sur la route publique au tarif obstacle** (`R/cout.R:160`).
   `zone_roulable_connectee()` **forçait** toutes les cellules de desserte dans la zone
   roulable (`z1[desserte_cel] <- TRUE`), réseau public compris — lequel porte le surcoût
   d'obstacle de 1000. Le skidder roulait donc le long de la route publique à 1000 par
   cellule : **1 646 174 m** de distance de débardage, soit 1 646 km. Invisible dans la
   comparaison, qui est bornée au masque forêt de Sylvaccess — il a fallu regarder le raster
   entier. Après correctif : max 1 466 m, zéro cellule au-delà de 2 000 m.

5. **Le seuil d'abattage porte sur le MAXIMUM LOCAL de la pente**, pas sur la pente de la
   cellule (`R/preprocess.R`, `R/cout.R`). `slopes_skid()` de Sylvaccess
   (`sylvaccess_cython3.pyx:3417-3424`, docstring : « Calcule le maximum local sur un
   raster ») teste `max(pente)` sur la fenêtre **3 × 3** : une cellule est écartée dès qu'une
   seule de ses huit voisines dépasse `g_slope_mharv`. La zone d'exclusion est donc **dilatée
   d'une cellule** — et c'est le seul critère dilaté (`Pente_ok_skid`, juste au-dessus, teste
   bien la cellule elle-même). Sans la dilatation, notre zone d'abattage était **1,7× trop
   large**, et les rayons de treuillage traversaient des trous que Sylvaccess referme (le rayon
   `break` dès qu'il sort de `Zone_OK`). Gain mesuré : **+1,4 point** d'accord skidder
   (91,5 → 92,9 %). `pre$slope_max_local` ajouté ; le seuil reste appliqué à l'appel (ADR-003).
   *Vérifié par expérience contrôlée* : en injectant le `Pente_OK_bucheronnage_manuel.tif` de
   Sylvaccess à la place de notre masque, on obtient **exactement** le même chiffre (20 826
   cellules en litige) — notre réimplémentation reproduit son raster à la cellule près.

**Ce que ce n'est PAS** (hypothèses testées et réfutées, pour ne pas les refaire) :
- **la méthode de pente** : `gdaldem slope -p -compute_edges` et `terra::terrain(neighbors=8)`
  donnent des résultats **identiques à 100 %** sur ce MNT (57 858 contre 57 867 cellules
  > 100 %). Notre pente est juste ; c'était le *critère* qui différait, pas le calcul ;
- un artefact de `computeEdges` au bord des zones sans données : les cellules divergentes sont
  à **720 m** d'un trou en médiane ;
- des pistes non reliées au réseau public : les cellules en litige y sont **moins** souvent
  rattachées (2,4 %) que celles où l'on s'accorde (5,5 %) ;
- le balayage de treuillage lui-même : tracé à la main sur cinq cellules litigieuses, la corde
  reste entre 3,5 et 15 m au-dessus du sol (bornes [0, 30]) sur 25 à 59 m — Sylvaccess *devrait*
  les treuiller selon ses propres règles. Nos bornes cumulées `lo = max_j (dz_j − 10)/hd_j` et
  `hi = min_j (dz_j + 20)/hd_j` sont l'équivalent algébrique exact de son test, `dmin` inclus.

**Deux fausses pistes, consignées pour mémoire.** (a) J'ai cru que les 6,8 % de cellules en
litige s'expliquaient par leur allocation au réseau public (85 % y allaient) : c'était un
**symptôme**, pas la cause — les en priver ne change l'accord que de 0,06 point, elles se
rabattent sur une desserte forestière voisine. (b) J'ai déclaré inaccessibles les cellules
servies par des pistes « orphelines » (ne rejoignant aucune route) : l'accord a **chuté de
3 points**. J'avais confondu deux rôles du réseau public — **source** de débardage (exclue) et
**terminus du réseau** sur lequel se mesure la distance (incluse : Sylvaccess passe `Res_pub`
en argument de `Link_tracks_res_pub` et `Link_RF_res_pub`). Le garde-fou « piste injoignable →
inaccessible » est conservé : il est correct sur le principe, et neutre sur ColduPre (zéro
piste orpheline une fois les rôles séparés).

**Piège du harnais, corrigé** : `Foret_accessible.tif` vaut 1 sur les accessibles et
**NoData ailleurs** (pas 0). Lues telles quelles, les cellules inaccessibles arrivent en `NA`
et sortent de la comparaison : on ne mesurait alors que l'accord sur les cellules déjà jugées
accessibles, et l'on ne pouvait **jamais** se voir trop optimiste. Binarisation explicite
`NA → FALSE`.

**Quatre défauts de config faux**, relevés en mappant `dic_AllParam.json` (les valeurs
`def_value` y sont, alors que `specs/004 Q7` les disait introuvables et les avait devinées) :
`c_E` 160 000 → **100 000**, `c_q2`/`c_q3` 0,9 → **0,5**, `c_angle` 20° → **30°**, `c_safe`
2 → **2,5**. Le `c_safe` ne fausse pas la comparaison ColduPre (le scénario y vaut 2, comme
notre défaut) mais touche tout utilisateur qui ne surcharge rien : il divise `Tmax`.

**`specs/006` est faux sur un point de fait** : `Sylvaccess_5_dfci.py` **existe** (356 lignes,
`process_dfci`, `dfci_lmax = 440 m`, `dfci_slope_max = 110 %`, classes `0;120;280;440`). Le
Lot 6 a été construit sur l'hypothèse inverse, avec des défauts (100 m / 40 %) à un facteur 4
de la source. À arbitrer.

**Performance** (temps écoulé, même machine, même jeu, machine au repos) :

| Moteur | Sylvaccess (Cython) | ForêtAccess |
|---|---|---|
| Skidder | 14 s | **14,1 s** (11,2 s avant la passe contour) |
| Porteur | 14 s | 18,8 s |
| Câble | 3 min 18 s (`c_sup = 3`) | **2 min 18 s** (`c_sup = 0`) |

Le skidder est **à parité** avec le Cython, le porteur ~30 % plus lent, le câble plus rapide —
mais à périmètre non égal (0 support contre 3). *(Une première mesure donnait 39,8 s / 47,2 s :
elle était faussée par huit workers `workRSOCK` orphelins laissés par une suite de tests
interrompue. Toujours vérifier la charge avant de chronométrer.)*

> ⚠️ **Table périmée** — mesurée avant le Lot 4d (le câble était à `c_sup = 0`). Re-chronométrée à
> isopérimètre `c_sup = 3` le 2026-07-17 : câble **~40 s** (≈165 s CPU, `rayon`) contre 198 s pour
> Sylvaccess. Voir l'entrée de journal du 2026-07-17.

6. **Le câble partait de toute la desserte** (`R/cable.R`). Sylvaccess ne lance ses lignes que
   depuis un fichier de départ dédié (`c_file_departure`), filtré sur l'attribut `CABLE` :
   **2 tronçons sur 125** à ColduPre. Une place de dépôt de câble-mât exige une aire de
   retournement et un accès camion — ça n'existe pas sur n'importe quelle piste. Or
   `potentiel_cable()` partait de **toute cellule de desserte** : ~60× trop de départs, donc une
   couverture massivement trop optimiste — et un balayage de **plus d'une heure** contre 3 min 18,
   sur un problème pourtant plus facile (0 support contre 3). Corrigé :
   `potentiel_cable(departs = )` prend une couche de places de dépôt, filtrée sur un champ
   `cable` s'il existe ; sans elle, repli sur la desserte entière **avec un message explicite**.
   Le balayage tombe à **138 s** — plus rapide que Sylvaccess (198 s), à périmètre non égal.

**Piège n° 2 du harnais, corrigé.** Sylvaccess n'écrit pas toutes ses sorties sur la même
grille : le moteur câble travaille sur une **fenêtre bufferisée** autour des départs
(`Zone_accessible.tif` = 405 × 380, contre 1034 × 894 pour le skidder). Comparés tels quels,
`terra::values()` rend deux vecteurs de longueurs différentes que **R recycle en silence** —
d'où un taux d'accord parfaitement plausible (93,89 %) et parfaitement faux, dont le seul indice
était un recouvrement **nul** entre les deux couvertures. Le harnais réaligne désormais toute
couche sur la grille de référence. Et le code positif diffère aussi (`Foret_accessible` vaut 1,
`Zone_accessible` vaut **2**) : on teste « non-NA et > 0 », jamais « == 1 ».

7. **Il manquait la troisième passe de treuillage** (`R/skidder.R`, `R/treuillage.R`).
   Sylvaccess treuille **trois fois** : depuis les routes (`skid_debusq_RF`), depuis les pistes
   (`skid_debusq_Piste`), puis depuis le **contour de la zone où l'engin a roulé**
   (`skid_debusq_contour`, `Sylvaccess_1_skidder.py:496-540`). La machine entre en forêt,
   s'arrête au bord du terrain roulable, et treuille **de là**. Nous n'avions que les deux
   premières : une cellule ne pouvait être treuillée que depuis une desserte. La preuve était
   dans les données — la cellule 437961 reçoit 39 m de débusquage alors qu'elle est à **69,5 m**
   de toute desserte forestière, et **12,7 %** des cellules de Sylvaccess ont un débusquage
   *inférieur* à leur distance euclidienne à la desserte (écart médian 17,2 m, max 158,5 m).
   Impossible depuis une route. Détails de la passe : le contour au sens de `get_contour()`
   (cellule de la zone dont la fenêtre 3 × 3 n'est pas entièrement dans la zone), purgé des
   obstacles, du réseau public et des dessertes ; chaque rampe **emporte** sa distance déjà
   parcourue (traînage en forêt + traînage sur piste) et le critère d'amélioration porte sur le
   **total**, non sur la seule longueur de câble ; les cibles excluent la zone déjà roulée ; et
   le remplissage est **purement additif** (`skid_fill_contour` : `if Ddebusquage[y,x] < 0`), il
   ne corrige jamais une cellule que les deux premières passes ont atteinte. `treuiller()` prend
   un argument `depart_cout` ; sans lui, comportement inchangé. Gain : **98,24 → 99,95 %**
   d'accord skidder, les 7 115 cellules trop conservatrices tombent à **38**. C'est la même
   « double passe réseau/contour » (`fwd_azimuts_contour`) qui avait été prototypée pour le
   porteur puis retirée faute d'oracle — elle est maintenant justifiée par la mesure.

8. **Le porteur grappillait depuis la route** (`R/porteur.R`). `fwd_filter_hoist()` ne
   retient comme rampes de grappin que les cellules à `Dforet > 0` — les cellules de
   **forêt effectivement conduites**. Une cellule de desserte est à `Dforet == 0` : elle
   est donc **exclue**. Nous grappillions depuis toute cellule conduite *ou de desserte*,
   ce qui entourait chaque voie d'un halo de forêt « accessible » d'une cellule — y compris
   sur un versant à 90 %, où le porteur ne peut simplement pas se tenir. La signature était
   dans les chiffres : **11 148 cellules de grappin pour 14 319 conduites**, un rapport
   périmètre/surface impossible pour une région compacte. Gain : **97,7 → 99,4 %**, l'excès
   tombe de 7 528 à 499 cellules. *(Fausse piste au passage : j'ai d'abord cru à une zone
   conduite en étoile et ajouté la propagation Dijkstra manquante — voir ci-dessous. Elle
   était bel et bien absente, mais ne pouvait pas expliquer un excès : ajouter une source
   n'enlève jamais de cellule.)*

9. **Le porteur n'avait aucun plus court chemin** (`R/cout.R`, `R/porteur.R`). Sylvaccess le
   propage d'abord en **Dijkstra** sur le terrain plat (`Dfwd_flat_forest_tracks` /
   `Dfwd_flat_forest_road`, zone `Pente_ok_forwarder`), et n'ajoute le balayage radial
   qu'ensuite. Nous n'avions que le balayage — or lui va tout droit : il ne contourne ni un
   ravin ni un rocher. `terrain_plat()` (pente sous le **minimum** des trois seuils, c'est là
   que l'engin roule quelle que soit la direction) et `zone_plate_connectee()` ajoutés ; la
   construction en trois temps est factorisée avec celle du skidder (`.zone_connectee()`).

10. **Le porteur n'avait pas non plus sa passe contour** (`fwd_azimuts_contour`), symétrique
    de celle du skidder : rampes sur le bord de la zone conduite **et sur terrain plat**
    (`contour = (Dforet>=0) * (Pente_ok_forw==1)` — on ne relance pas une machine d'un point
    où elle ne tient déjà plus), coût emporté pondéré `0,1 × d_piste + d_forêt` (la piste
    compte pour un dixième), cibles hors zone déjà conduite, remplissage additif.
    `conduire()` prend `sources` et `depart_cout`, comme `treuiller()`. Gain : **99,4 →
    99,72 %**, les cellules trop conservatrices tombent de 2 119 à **244**.

Au passage, l'accumulateur de distance en pente forte de `conduire()` croissait de
l'incrément **horizontal** ; Sylvaccess l'incrémente de la distance **3D** (`dpt += dist -
dist2`). Corrigé — sans effet mesurable sur ColduPre (les rayons font 300 m et le plafond
aussi : l'accumulateur ne mord jamais), mais il mordra sur un jeu où `f_slope_dmax` est plus
serré.

### 2026-07-14 — Lot 4d : fin du câble (placement des supports)

**La dette du Lot 4 est soldée.** Le noyau câble était à **zéro support intermédiaire**
quand Sylvaccess en pose jusqu'à trois : c'était la cause connue des 5,3 % de cellules où
nous restions trop conservateurs. Porté dans `src/rust/src/cable/optpyl.rs`
(`OptPyl_Up_NoH` + recherche en faisceau `get_Tabis`), avec **coupe de la ligne** au point
le plus lointain atteint quand aucune configuration ne rejoint le terminus.

`c_option_h = 0` est le défaut de v3.6 : ce sont les variantes **`_NoH`** qui tournent, où
la hauteur de fixation n'est pas optimisée (12 m partout). Beaucoup plus simple que les
variantes complètes — il fallait le voir avant de porter 200 lignes de Cython inutiles.

**Trois infidélités du câblage, trouvées en portant** — aucune n'était une dette assumée :
* `scan` passait le profil **au demi-mètre** comme profil de travée, là où Sylvaccess pose
  ses supports **au pixel** (`Line`) ;
* il passait `csize = 0.5` au lieu de la taille de cellule : la position de la charge était
  balayée **10× plus finement** que dans la source ;
* la garde au sol indexait `Alts` en **arrondissant**, là où Sylvaccess **tronque**
  (`int(xcoord * 2)`) — un demi-échantillon de décalage.

**`get_Tabis` dépend de l'ordre de sa table d'entrée.** `idline` ne bouge que sur une
hauteur *strictement* plus basse, et les hauteurs sont uniformes en `_NoH`. Triée (un seul
préfixe alimente la table), la sélection est correcte ; non triée (plusieurs préfixes
concatènent leurs suites), elle peut rendre deux fois la même configuration. Défaut de la
source, reproduit tel quel et figé par un test ; `dedupe` en absorbe le coût.

**Puis le câble a basculé dans l'autre sens** : 5,3 % trop conservateurs → **10,15 % trop
optimistes**. Les supports marchaient trop bien, parce qu'il manquait le garde-fou :

* **`check_line`** (`src/rust/src/cable/ligne.rs`). Avant de savoir si le câble *tient*, il
  faut savoir jusqu'où la ligne a un *sens*. Sylvaccess la coupe sur trois critères
  géométriques : elle **finit en forêt** (on n'installe pas un câble pour desservir un pré),
  elle ne traverse pas plus de 75 m de non-forêt d'affilée, et elle ne **court pas en travers
  d'un versant raide** (`c_angle_transv` 60°, `c_slope_trans` 30 %, `c_l_slope` 75 m,
  `c_prop_slope` 0,15). Sans lui, nos lignes filaient à 750 m à travers n'importe quoi.
  Gain : **89,27 → 96,15 %**, et le balayage tombe de **358 s à 50 s** (Sylvaccess : 198 s).

**Le « traînage en forêt à 0 m contre 124 m » n'était pas un problème de comptabilité.**
Rejouée sur les sorties d'après la 3ᵉ passe, la comparaison donne **120,2 contre 124,0** de
médiane (écart 0,2 m) : la décomposition est juste. Le 0 était le **symptôme** de la passe
contour manquante — nos rasters de distance valent `0` (et non `NA`) sur les cellules non
atteintes, et le sous-ensemble comparé pour le traînage en forêt (`DTrain_foret ∉ {0, -9999}`)
est **exactement** l'ensemble des cellules du contour. On comparait donc nos zéros à ses 124 m.
Que le **total** collât malgré tout n'avait rien de paradoxal : les sous-ensembles sont
**disjoints** — le total est dominé par les 87 685 cellules treuillées des passes 1-2, où nos
trois composantes étaient déjà justes ; 3 920 cellules fausses n'y déplacent pas la médiane.

**Reste un vrai écart, structurel et assumé** : Sylvaccess **pondère la piste** dans son
arbitrage (`d_foret + 0,5 · d_piste` en propagation, `pyx:3714` ; `d_foret + 0,1 · d_piste`
pour l'arbitrage route/piste, `pyx:4283`). Nous minimisons `d_foret` seul et ajoutons la
distance réseau *a posteriori*. Sans effet sur ColduPre, dont le réseau est dense ; à corriger
avant `v1.0.0`.

### 2026-07-14 — Câble : la ligne « machine en bas »

Le balayage ne cherchait que la ligne **« machine en haut »** : mât sur la desserte, câble qui
descend. Sylvaccess traite les deux sens, et choisit par une comparaison de dominance — le mât
(`hauteur_mat_m`) posé sur la desserte domine-t-il le point haut du profil augmenté de l'ancrage
(`hauteur_ancrage_m`) ? Sinon, la machine est **en bas** et le câble monte.

La découverte qui a fait tenir le portage : `OptPyl_Up2_NoH` n'est **pas** un second solveur.
C'est le même, appliqué au profil **retourné**, avec les deux hauteurs d'extrémité échangées
(l'ancrage ouvre, le mât ferme) et les bornes de pente niées. `OptPyl_Down_init_NoH`, lui, est
`OptPyl_Up_NoH` **sans héritage de tension** entre travées — ce n'est pas une vraie ligne, juste
une amorce qui dit jusqu'où porter. Trois fonctions Cython se réduisent donc à un seul
`optpyl()` paramétré par `(h_debut, h_fin, heriter_tension)`.

Une asymétrie compte : une ligne « machine en bas » ne peut pas être **coupée** du côté machine
— c'est elle qui fixe le terminus. Quand rien ne passe, Sylvaccess **rogne l'ancrage** (retire
un pixel en tête du profil retourné) et recommence.

**Accord câble : 96,15 → 96,58 %.** Le gain est modeste, mais il tombe des **deux côtés** :
trop conservateur 3,08 → 2,79 %, trop optimiste 0,77 → 0,63 %. Une simple permissivité
n'aurait fait baisser que le premier ; que le second baisse aussi dit que la passe « en bas »
*remplace* de mauvaises lignes par des bonnes. Coût : le balayage passe de 50 s à **79 s**
(Sylvaccess : 198 s), deux résolutions par ligne descendante.

**Le Lot 4 est clos.** Restent assumés : l'optimisation de la hauteur de fixation
(`c_option_h = 1`, hors défaut v3.6) et le pêchage latéral.

### 2026-07-09
- Lot 0 clos et publié (`v0.1.0`), retour en cycle de dev `0.1.0.9000`.
- Specs des Lots 1 et 10 rédigées, décisions §10 tranchées, mergées sur `main`
  (PR #5 et #6).
- Ouverture de la branche `lot-1-pretraitement` ; `R/io.R` (helpers `.as_raster()`
  / `.as_vector()`) écrit.
- Création de ce `PLAN.md` (manquait alors que la règle 5 l'impose).
- **Lot 1 implémenté** : `R/validate.R`, `R/terrain.R`, `R/preprocess.R` et six
  fichiers de tests (`test-io`, `test-validate`, `test-slope-aspect`,
  `test-rasterize-masks`, `test-grid`, `test-cog`) + `helper-toy.R`. Suite verte.
- Ajout de `general$methode_pente` à la config (défaut `"Horn"`), pour permettre
  la réconciliation ultérieure avec l'oracle Sylvaccess v3.6 sans refonte.
- `DESCRIPTION`/`NEWS.md`/`CITATION.cff` alignés sur `0.2.0` ; spec 001 passée en
  statut « validé » et sa DoD cochée.

### 2026-07-10
- PR #7 : la CI a rattrapé deux défauts que la suite locale ne voyait pas.
  `R CMD check` refusait le non-ASCII dans les chaînes du code R (messages `cli`
  accentués) et signalait `PLAN.md` comme fichier non standard à la racine ;
  Codecov refusait la baisse de couverture (95,21 % → 94,21 %). `covr` a situé
  quatre branches d'erreur non exercées dans `R/validate.R` (résolution
  divergente, emprise décalée, géométrie invalide, couche sans CRS) — le test
  « volume non aligné » n'exerçait en réalité que le contrôle des dimensions.
  Corrigé : couverture à 97,91 %, CI verte sur les sept checks.
- `lintr` et `covr` installés dans la bibliothèque `renv` locale (sans toucher à
  `renv.lock`) : ils manquaient, d'où l'angle mort local.
- **Lot 1 mergé et publié en `v0.2.0`** ; retour en cycle de dev `0.2.0.9000`.
- `specs/002-skidder.md` rédigée (PR #9). Décisions figées : `leastcostpath` comme
  backend least-cost, et coût **anisotrope** de type Tobler (porté par la transition
  orientée `a → b`, pas par la cellule). Lot scindé en 2a (débloqué) et 2b (bloqué).
- Constat de conception : le jeu jouet actuel ne peut pas valider le skidder — sa
  pente vaut 20 % partout, sous le seuil de 30 %, donc **aucun treuillage n'y serait
  jamais déclenché**. Un MNT à pente forte et des obstacles sont à ajouter à
  `data-raw/make_toy.R` au moment du 2b.
- **Le `.pyx` de Sylvaccess est public et a été lu.** Il a renversé trois décisions :
  coût **isotrope** (et non Tobler), **Dijkstra maison** (et non `leastcostpath`), et
  treuillage par **balayage radial** (et non least-cost). La spec 002 est réécrite sur
  la source, pas sur des hypothèses. Les constantes en dur du `.pyx` (attache 10 m,
  dégagement 30 m, surcoût obstacle 1000, `s_option`) deviennent des paramètres de
  config (ADR-003).
- AOI réelle fournie (`data-raw/aoi.gpkg`, 720,9 ha, EPSG:2154) — ignorée par git
  (`*.gpkg`), destinée au Lot 10 et à un test d'intégration, **pas** au jeu jouet, qui
  reste synthétique pour rester un oracle analytique exact.
- **Lot 2 implémenté** (2a puis 2b) : `R/leastcost.R`, `R/cout.R`, `R/treuillage.R`,
  `R/skidder.R`, `R/recap.R` et neuf fichiers de tests. 383 tests verts, couverture
  97,93 %, tous les fichiers du lot à 100 %.
- Deux corrections de la spec, révélées par le code : le critère CA-2.8 supposait
  qu'aucun treuillage n'a lieu sous 30 % de pente, alors que le `.pyx` borne le
  treuillage par la pente d'**abattage** (100 %) — sous l'option 1, une cellule proche
  de la desserte est treuillée même si l'engin pourrait y rouler. Et le carré
  d'obstacles du jeu jouet était traversé par la piste DFCI diagonale (0,0)→(250,250),
  ce qui en faisait des cellules de desserte.
- `preprocess()` conserve désormais le MNT (`$mnt`) : le treuillage raisonne sur les
  altitudes. Ajout additif, sans rupture.
- **Lot 2 mergé et publié en `v0.3.0`** (PR #10).
- **Confrontation aux données réelles** (AOI 7,2 km², RGE ALTI + BD TOPO). Elle a servi
  à trancher le portage Rust, et a d'abord révélé deux bogues de performance dans mon
  propre code (tas recopié, rayons non compactés), puis **deux écarts de conformité** au
  `.pyx` que le jeu jouet ne pouvait pas exposer — d'où `v0.3.1` :
  - `.distance_sur_piste()` propageait à coût uniforme 1 ; Sylvaccess pondère la piste
    par la pente comme le reste (`Dfwd_flat_forest_tracks(f, Lien_Piste, Pond_pente, …)`).
  - `distance_hors_desserte_max_m` n'était pas implémenté. **Il ne plafonne pas la
    distance de débardage** : il autorise le skidder à traverser jusqu'à 50 m de terrain
    roulable **hors forêt** pour rejoindre un massif isolé. Reproduit par
    `zone_roulable_connectee()` (construction en trois temps de `Pente_ok_skidder` :
    connexité, saut borné, recollement), avec `terra::patches()` pour les deux étapes de
    pure connexité et un Dijkstra borné pour le saut.
  - Au passage, ma première explication des 4 km de débardage était **fausse** : je les
    avais imputés au plafond manquant. Ils viennent du `distance_trainage_piste`
    (max 4 030 m, médiane 1 020 m), lui-même faussé par le coût uniforme.
- Effet sur l'AOI réelle : `parcourable` 65 041 → 65 800 cellules (+1,9 ha),
  `non_accessible` 72 438 → 71 679. 395 tests verts, `lintr` 0, ASCII OK.
- L'IGN WFS renvoie du WGS 84 : `valider_entrees()` l'a **rejeté**, exactement le
  comportement voulu. La reprojection a lieu dans le script de benchmark, jamais dans le
  package.
- **Correctif mergé et publié en `v0.3.1`** (PR #11, sept checks verts). Retour en cycle
  de dev `0.3.1.9000`. Lot 2 clos.

### 2026-07-11
- **Lot 7 mergé et publié en `v0.4.0`** (PR #13). Retour en cycle de dev `0.4.0.9000`.
- **Lot 3 (porteur) rédigé sur la source et implémenté.** Comme pour le skidder, la
  lecture du `.pyx` a renversé l'hypothèse de départ : le porteur n'est pas un skidder
  aux seuils différents. Sa conduite est un **balayage radial** depuis le réseau, pas un
  Dijkstra ; il a un **grappin** (8 m) et non un treuil ; ses pentes se comparent **en
  degrés** ; et sa contrainte de **dévers** dépend de l'azimut de conduite.
- Un piège de rédaction, révélé par les tests : j'avais inversé amont et aval. Une cellule
  *plus haute* que la route relève de la **descente** (le trajet chargé descend vers la
  route), pas de la montée. Le `.pyx` le dit, les tests l'ont confirmé.
- **Tuilage généralisé** : `traiter_par_tuiles()` prend un argument `couches` et sert tout
  moteur. Le porteur tuile mieux que le skidder — portée bornée (300 m + 8 m), certificat
  réduit à « le halo couvre-t-il la portée ? ».
- Deux fragilités latentes corrigées : `.distance_sur_piste()` plantait sur une desserte
  non catégorisée ; le grappin lisait un champ inexistant de la propagation.
- `porteur()` livré, `conduire()` exportée. 533 tests verts, `lintr` 0, ASCII OK.
- **Lot 3 mergé et publié en `v0.5.0`** (PR #15). Retour en cycle de dev `0.5.0.9000`.
- **Consolidation du porteur (`v0.5.1`).** Relecture de la construction de `Zone_OK` dans
  `Sylvaccess_3_forwarder.py` : deux corrections a `.zone_conduite()`.
  - **Bug** : la zone bornait la pente par `min(travers, montee, descente)` = 15 %, la
    source la borne par le **maximum** = 30 %. Le `min` excluait a tort les cellules
    roulables en montee dans le sens de la pente.
  - **Saut hors foret** (`distance_hors_desserte_max_m`) ajoute, analogue de
    `zone_roulable_connectee()` du skidder. Le halo suffisant du tuilage l'integre.
  - La **double passe** reseau/contour a ete prototypee puis retiree : fidele en esprit a
    `fwd_azimuts_contour`, elle rend le devers non bloquant pour la portee sur un plan
    uniforme (le porteur zigzague), et sans oracle Sylvaccess reel son modele de distance en
    composantes ne peut etre valide. Gardee en dette documentee plutot que livree
    plausible-mais-fausse — le principe de fidelite du projet prime.
- 543 tests verts, `lintr` 0, ASCII OK.
- `specs/007-passage-echelle.md` rédigée ; ADR-005 passé de « proposé » à **accepté**.
  Décisions : **certificat d'exactitude + halo adaptatif** (le critère « identique au
  mono-bloc » de l'US-7.1 n'est pas atteignable par un halo fixe — le traînage est un plus
  court chemin **sans plafond**) ; **`mirai`** plutôt que `future`/`furrr` ; sortie **COG
  recomposé** seul, les cellules non certifiées tombant dans la classe `indetermine` qui
  existe déjà. Lot découpé en 7a (théorème), 7b (garantie), 7c (vitesse).
- **Lot 7 implémenté** : `R/tuilage.R`, `R/certificat.R`, `R/mosaique.R`, `skidder(bord=)`,
  et trois fichiers de tests. 491 tests verts, `lintr` 0, ASCII OK.
- Trois choses que seuls les tests et la mesure ont révélées, toutes contredisant la
  première rédaction de la spec :
  - une tuile sans desserte ne peut pas publier `hors_foret` pour ses cellules non
    forestières : leur *classe* est un fait local, mais pas leurs distances (la zone de
    traînage déborde de 50 m hors forêt). Elle ne publie donc rien ;
  - le certificat coûte bien plus qu'une propagation de plus : il impose
    `halo ≥ plus longue distance entrante`, et le surcoût croît en `(1 + 2·halo/tuile)²` ;
  - `mirai_map()` traite `...` comme des vecteurs à itérer ; les constantes passent par
    `.args`. Et une erreur de démon revient comme *valeur* (`miraiError`), pas comme
    condition : sans contrôle explicite, elle traverse la boucle en silence.
- Les `SpatRaster` portent des pointeurs C++ : ils ne franchissent pas la frontière de
  processus. Le parent recadre (lecture de fenêtre, sans charger le raster entier), puis
  emballe (`terra::wrap()`) la seule tuile.

### 2026-07-12
- **Lot 10 (acquisition depuis AOI) implémenté et préparé en release `v0.11.0`.**
  `acquire_inputs(aoi, sources, cache_dir, res_m, crs, buffer_m, ...)` télécharge les entrées du
  pipeline depuis un polygone d'emprise : MNT RGE ALTI (WMS), desserte BD TOPO (WFS, avec dérivation
  du champ `classe` route/piste), forêt BD Forêt v2 (WFS), obstacles OSM (bâti/eau/rail/falaise),
  parcellaire cadastral (optionnel). **Config-driven** (patron nemeton) : `inst/datasources/FR.json`
  + résolveur (`get_country_config`/`get_data_source`/`get_layer_service`/`get_national_crs`).
  Sorties `foretaccess_inputs` **directement consommables par `preprocess()`**. Les appels réseau
  sont isolés dans des wrappers internes (`.fetch_wms_raster`/`.fetch_wfs`/`.fetch_osm`) **mockables** :
  57 tests unitaires tournent **hors-ligne** (`local_mocked_bindings`), + un test d'intégration réseau
  **opt-in** (`FORETACCESS_RUN_ONLINE_TESTS=TRUE` + `skip_if_offline`). `happign`/`osmdata`/`jsonlite`
  ajoutés (Suggests / Imports). Verrou CRS strict sur l'AOI ; cache idempotent ; buffer 100 m.
  Vignette « Acquérir les entrées depuis une AOI ». Écart assumé vs spec §10 Q4 : clip sur l'AOI
  bufferisée (conserve la desserte du voisinage). `specs/010` passé en statut implémenté.
- **Lot 9 (doc & publication) implémenté et préparé en release `v0.10.0`.** Vignette
  `vignettes/foretaccess.Rmd` : déroule le pipeline complet (config → prétraitement →
  skidder/porteur → DFCI → câble potentiel/sélection → agrégation zonale → persistance GPKG)
  sur le jouet, **exécutée** à la compilation (< 2 s), donc auto-vérifiante par `R CMD check`.
  README refondu (démarrage rapide + statut réel des lots) ; `_pkgdown.yml` doté d'un index de
  référence groupé (tous les exports) et de l'article ; `knitr`/`rmarkdown` en `Suggests` +
  `VignetteBuilder`. `specs/009` fige les décisions (vignette exécutée, pas de CLI shell,
  `NEWS.md` = changelog). **Périmètre v1 fonctionnel atteint** ; `v1.0.0` reste un bump majeur
  soumis à confirmation. Releases `v0.8.0` (Lot 6) et `v0.9.0` (Lot 8) posées ; le Lot 9
  enchaîne en `v0.10.0` sans cycle-dev intermédiaire.
- **Lot 8 (base spatiale & agrégation) implémenté et préparé en release `v0.9.0`.**
  `agreger_zones(classes, zones, volume, id)` agrège n'importe quel raster catégoriel
  d'accessibilité (skidder, porteur, DFCI, couverture câble) en surfaces (ha) et volumes (m³)
  par zone (massif/parcelle/commune) et par classe — pendant zonal de `recapituler()`.
  Croisement raster **vectorisé** (`table`/`tapply`, pas de boucle par cellule), verrou CRS
  strict, sortie `sf` à colonnes larges `surface_<classe>_ha` (+ `volume_<classe>_m3`)
  directement persistable/requêtable. Test central : **partition** (somme zonale = récap
  global). Côté stockage, `sb_write_layer()` PostGIS crée désormais un **index GiST**
  idempotent sur la géométrie ; le R-tree GPKG est automatique. 25 tests d'agrégation
  (+ index PostGIS skippé sans base) ; suite complète verte. `specs/008-base-spatiale.md`
  fige les décisions (agrégation en R/terra backend-agnostique). Release enchaînée sans
  cycle-dev intermédiaire (Lot 6 → Lot 8 demandés à la suite).
- **Lot 6 (camion DFCI, beta) implémenté et préparé en release `v0.8.0`.** `camion_dfci()`
  modélise la zone défendable comme un tampon au terrain : plus court chemin pondéré par la
  pente (`propager_cout()` + `surface_cout_skidder()`, service partagé du Lot 2) depuis les
  dessertes DFCI, plafonné à `distance_defense_max_m` et coupé au-delà de
  `pente_defense_max_pct`. Aucun nouveau noyau. Config `dfci` (portée 100 m, pente 40 %,
  `classes_source = "dfci"`) — hypothèses de travail explicites, non Sylvaccess (le module
  DFCI n'est pas dans les sources de référence). Sortie catégorielle `defendable` /
  `non_defendable` / `hors_foret` + `distance_defense` + `allocation` + `recap`. **Tuilage** :
  bornée par la portée, donc certifiable ; le réseau DFCI étant clairsemé, une tuile sans
  source reste indéterminée (halo grandit), l'absence de source au top-level lève une erreur.
  22 tests DFCI ; suite complète verte. `specs/006-dfci.md` fige les décisions et les limites
  beta (ni combustible, ni vent, ni physique de lance ; carrossabilité non qualifiée).
- **Release `v0.7.0` posée** (PR #26 mergée, sept checks verts ; tag `v0.7.0` + release GitHub
  posés automatiquement par `release.yml`). Retour en **cycle de dev `0.7.0.9000`** (bump
  `DESCRIPTION` seul ; `NEWS.md`/`CITATION.cff` restent à `0.7.0`).
- **Lot 5 (sélection multicritère des lignes câble) livré et publié en `v0.7.0`** (PR #25).
  `selection.R` à 100 % de couverture (codecov exigeant : sept branches défensives couvertes
  par des tests ciblés). Détail ci-dessous.
- **Lot 5 (sélection multicritère des lignes câble) implémenté** — spec `specs/005` validé sur
  lecture de `select_best_lines`/`create_best_table` (Sylvaccess `Sylvaccess_0_functions.py`).
  **5a** : `potentiel_cable()` émet `$lignes` (une candidate par (départ, azimut) faisable :
  surface forêt couverte, longueur, sens, volume/IPC si `pre$volume`). **5b** :
  `selectionner_lignes()` — filtrage par limites, **score pondéré normalisé** (maximiser →
  `v/p98` ; minimiser → `1−v/max`), tri lexicographique stable (déterminisme), **glouton avec
  contribution** (une ligne retenue apporte ≥ 60 % de surface nouvelle), sortie `sf` LINESTRING
  (CRS strict) + raster de couverture. Config `config$cable$selection` (poids, limites, sens
  préféré). Neutralisation auto des critères volume/IPC sans volume. La reproductibilité vs
  v3.6 (CA2 backlog) reste à confronter à un oracle réel ; le déterminisme est verrouillé.
  6 critères MVP (EF-7) ; VAM×10 et coût €/m³ repoussés. 21 tests R (oracle analytique).
- **Lot 4 (noyau câble) livré de bout en bout et publié en `v0.6.0`** — incréments 4a
  (caténaire + Newton, #19), 4b (faisabilité, #20), 4c (`find_lomin`/`test_span`, #21), 4d
  (`potentiel_cable()`, #22). Le premier moteur non terrestre, et le point où le portage
  `extendr` prend son sens. Trois pièges numériques traversés en 4d (infaisabilité géométrique
  mal diagnostiquée en 4c, repli grille `O(Tmax²)` catastrophique, amorçage `seed_grid`) —
  détaillés dans le journal 4d ci-dessous. Extensions différées : placement multi-supports
  (oracle réel), pêchage latéral, portage Rust de l'orchestration. Retour en cycle dev
  `0.6.0.9000` après la release.
- **Consolidation du porteur mergée et publiée en `v0.5.1`** (PR #17, sept checks verts).
  Retour en cycle de dev `0.5.1.9000`.
- **Lot 4 (noyau câble) — spec rédigée sur la source** (`specs/004-cable.md`). Lecture de
  `Sylvaccess_2_cable.py` et de `sylvaccess_cython3.pyx` (lignes ~1040-1400) : la mécanique
  est une **caténaire élastique** (terme `Lo/EAo`, allongement sous tension), pas une
  caténaire idéale, résolue par **Newton-Raphson à Jacobien analytique** (`f_x`, `f_z`,
  `df_dTh`, `dg_dTh`) avec **repli sur recherche par grille** quand une tension devient
  négative. La faisabilité tient à `√(Th²+Tv²) ≤ Tmax = c_rupt·g/c_safe` et à la garde au
  sol `[c_h_min, c_h_max]` = `[3,5 ; 50]` m via `calcul_zs`.
- Point relevé à la lecture : `c_E` (module de Young, N/mm²), `c_q2`/`c_q3` (masses des
  câbles de traction/retour), `c_angle`, `c_l_span` **ne sont pas** dans `Tab_Param_cable.csv`
  — ils viennent du `paramdict` global (`globals().update(paramdict)`). À porter dans
  `config$cable` avec des défauts documentés.
- Découpage acté : **4a** (caténaire + Newton en Rust, `cargo test` + binding `extendr` +
  test R), **4b** (faisabilité travée), **4c** (optimisation supports, `rayon`), **4d**
  (balayage 360°/pixel + orchestration R + tuilage). Release visée `v0.6.0`.
- **Frontière R↔Rust** (ADR-001) : R passe des scalaires et vecteurs de `f64` (géométrie,
  profil d'altitudes, paramètres câble) ; le crate résout et renvoie `(Th, Tv)`, tension max,
  faisabilité, hauteur au point contraignant. Aucun SIG dans le crate.
- **Incrément 4a implémenté** : `src/rust/src/cable/{catenaire,newton}.rs` portent `f_x`,
  `f_z`, `calcul_xs/zs`, `df_dTh`, `dg_dTh`, `newton_ThTv`, `find_ThTvTmax` ; 6 bindings
  `#[extendr]` (`cable_*`). Oracle **sans exécution Sylvaccess** : *solution manufacturée*
  — on choisit `(Th0, Tv0)`, on en déduit `(D, H) = (calcul_xs(Lo), calcul_zs(Lo))` qui
  annule `f_x`, `f_z` par construction, et Newton la retrouve à ±1 N (fermeture géométrique
  vérifiée). L'identité `calcul_xs(Lo) = f_x + D`, `calcul_zs(Lo) = f_z + H` relie la
  position du câble à la solution : c'est elle l'oracle. 6 tests cargo + 15 tests R verts,
  suite complète 558 PASS. Cycle dev, pas de release (v0.6.0 regroupera 4a-4d).
- `rextendr` est dans la bibliothèque **globale** (`~/R/...-library/4.6`), pas dans le renv
  du projet : `rextendr::document()` se lance avec `.libPaths(c(.libPaths(), <globale>))`.
- **Incrément 4b implémenté** (`src/rust/src/cable/faisabilite.rs`) : port de `check_droite`
  (pré-filtre corde − flèche) et `check_Hlinemin` (balayage de la charge sur toute la travée,
  Newton *chaud* sans repli amorcé de la position précédente, garde au sol
  `zcoord − (alts[ind] + hline_min)` dans `[hline_min, hline_max]`, tension ≤ `tmax + 1000`).
  Renvoie la garde minimale `Hmin_ok`, ou `-1` si infaisable. 2 bindings extendr
  (`cable_check_droite`, `cable_check_hlinemin`), supports omis (0) — ils viennent en 4c.
  Oracle : même *solution manufacturée* qu'en 4a (géométrie déduite de `(Tho, Tvo)` centrés),
  sol plat paramétré pour forcer faisable / trop haut / trop bas. 5 tests cargo + 7 tests R.
- **Deux corrections CI de 4a** (invisibles localement, pas de clippy sur le système) :
  `clippy::too_many_arguments` tu au niveau du crate (les 4 fonctions pures à 8 args), et
  `@param` manquants sur chaque binding exporté (`R CMD check --as-cran`, `error_on=warning`,
  exige un `\arguments` pour tout `\usage`). Règle : **tout binding extendr exporté documente
  chaque argument avec `@param`**.
- **Incrément 4c implémenté** (`src/rust/src/cable/supports.rs`) : port de `Find_Lomin`
  (`find_lomin` : cherche le `Lo` minimal tel que la tension à charge centrée atteigne `Tmax`,
  par marche à pas variable sur `Lo` + Newton, puis garde au sol via `check_hlinemin`) et
  `test_Span` (`test_span` : segment — pré-filtre `check_droite`, pente dans `[slope_min,
  slope_max]`, contrainte d'angle `angle_intsup` au support vis-à-vis du segment précédent,
  puis `find_lomin`). 2 bindings extendr (`cable_find_lomin`, `cable_test_span`).
  - **Amorçage substitué aux tables `Tabmesh`** : `(Th,Tv) = (0,9·Tmax, 0,1·Tmax)` + `Lo =
    corde + réserve`, solveur interne robuste (Newton **à repli sur grille**, `newton_thtv`).
    Choix de performance, pas de correction (§10.9 du spec). Sans cela, la marche sur `Lo`
    pousse `Th` négatif près de la zone tendue.
  - **`OptPyl_Up` (placement multi-supports) différé** : non validable sans oracle Sylvaccess
    réel (§10.10). 4c livre les primitives validables.
  - **Fragilité au bord de tension** relevée : au `Lo` minimal, la tension = `Tmax` matériel
    (~172 kN) rend le câble quasi tendu, et le Newton *chaud* du balayage (`check_hlinemin`,
    sans repli) devient fragile. Tests conduits à `Tmax` modéré (50 kN), bien conditionné ; le
    bord matériel est à traiter en 4d (Tabmesh porté ou solveur à repli dans le balayage).
  - Oracle : solution manufacturée (résidus nuls, `Tcalc ≈ Tmax`, fermeture) + sol/pente
    paramétrés. 5 tests cargo + 6 tests R. Suite complète verte. Cycle dev, pas de release.
- **Incrément 4d implémenté** (`R/cable.R`, `potentiel_cable()`) : balayage 360°/pixel depuis
  la desserte (`.rayons()`), profil MNT interpolé à 0,5 m, `cable_test_span` (0 support) sur
  des longueurs décroissantes (pas = résolution), couverture des cellules forestières. Sortie
  `foretaccess_cable` (accessibilité, longueur/azimut de ligne, nb_supports). Config câble
  complétée avec les matériels v3.6 (`config.R`, `validate_config`, `test-config`). 6 tests R
  sur MNT synthétique (plan incliné), scan en **3,2 s**.
  - **Trois pièges numériques traversés avant d'aboutir** (tous invisibles hors exécution du
    scan complet) :
    1. La « fragilité au bord de tension » de 4c était en réalité une **infaisabilité
       géométrique** (câble tendu depuis un support à 60 m violant `hline_max` = 50 m). Le
       noyau tourne au `Tmax` **matériel** ; tests 4c rebasculés dessus (support 45 m).
    2. Le repli sur grille de `newton_thtv` dans `find_lomin` coûte `O((Tmax/pas)²)` ≈ 3 M
       évaluations par appel — **catastrophique** dans la boucle chaude (scan interminable).
    3. Un Newton chaud nu diverge sans bon amorçage. **Solution** : `seed_grid` (grille
       grossière 40 × 40, coût fixe indépendant de `Tmax`) amorce, Newton chaud raffine, la
       marche sur `Lo` réchauffe. Le repli `solve_charge` prototypé en 4b s'est révélé code
       mort et a été retiré. `faisabilite.rs` est revenu à l'état fidèle (Newton chaud pur).
  - **Portage Rust de l'orchestration livré en `v0.12.0`** (`cable_scan`, `rayon`, non-régression
    bit-pour-bit, ~5×). Restent en extension (spec §11) : placement multi-supports (oracle réel),
    pêchage latéral `distance_laterale_max_m`.
