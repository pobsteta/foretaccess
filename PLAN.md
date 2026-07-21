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
  forêt, puis éclaircissement à `espacement_min_m`). Explicitement heuristique : une place de dépôt
  reste un fait de terrain, et Sylvaccess la traite en donnée d'entrée.
- **Dette assumée du câble** : optimisation de la hauteur de fixation. Le portage de
  `c_option_h = 1` (Sylvaccess `OptPyl_Up`/`Up2`) a été **tenté puis abandonné le 16/07** (bugué,
  ~20× plus lent, code d'origine lui-même planté). **Voie retenue à la place** : transcrire
  l'algorithme **SEILAPLAN** (Bont & Heinimann 2012, graphe + plus court chemin), plus sain et
  validé — voir `specs/013-seilaplan-hauteur.md` et `docs/comparaison-cable-seilaplan.md`. Le `_NoH`
  (défaut) reste intact. Phase 2 acquisition : MNH LiDAR → volume, BD Forêt v3.

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

Le spec `specs/004-cable.md` est validé (2026-07-12). Implémenter le **Lot 4 — noyau
câble (Rust)** par incréments :

- **4a** — caténaire élastique (`f_x`, `f_z`, Jacobien analytique) + Newton-Raphson
  (`newton_ThTv`, `find_ThTvTmax`) en Rust, `cargo test` contre les valeurs de référence
  du `.pyx`, binding `extendr`, test d'intégration R. Le cœur numérique.
- **4b** — faisabilité d'une travée : tension ≤ `Tmax`, garde au sol via `calcul_zs`.
- **4c** — optimisation des supports intermédiaires (0…3), `rayon`.
- **4d** — balayage 360°/pixel, orchestration R (`potentiel_cable()`), tuilage (Lot 7).

Chaque incrément est mergeable seul ; 4a livre la mécanique, 4d la carte. Release
visée `v0.6.0` (nouveau moteur).

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
