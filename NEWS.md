# foretaccess 1.4.0 (2026-07-18)

## Nouveautés

- **Source du réseau DFCI** — le flag `dfci` (`CL_DFCI`), source du camion DFCI
  (spec 006) laissé vide depuis la phase 1 « faute de source dédiée » (spec 010
  §10.2), est désormais **alimenté automatiquement** par `acquire_inputs()`
  (paramètre `dfci = TRUE`, défaut). Deux stratégies via la nouvelle fonction
  exportée `flag_dfci()` :
  - **Voie A — réseau DFCI OpenStreetMap** : `acquire_dfci()` récupère les pistes
    taguées `ref:FR:DFCI` (+ alias `ref:dfci`/`dfci_ref`), l'identifiant officiel
    d'une piste DFCI (wiki OSM *FR:France/DFCI et DECI*). Les tronçons de desserte
    coïncidant (à tolérance près) sont flaggés.
  - **Voie B — repli géométrique** (si OSM ne couvre pas l'emprise) : on retient
    les pistes soit **traversantes** et d'emprise ≥ 10 m, soit en **cul-de-sac
    muni d'une aire de retournement** (`highway=turning_circle`/`turning_loop`, à
    portée du bout pendant). Heuristique explicitement signalée (faux positifs
    possibles).
- `acquire_desserte()` conserve désormais la **largeur** (emprise) BD TOPO, requise
  par le critère d'emprise du repli.
- Les seuils DFCI d'acquisition sont **pilotables via `foretaccess_config()`**
  (bloc `dfci` : `tol_appariement_m`, `emprise_min_m`, `rayon_retournement_m`) et
  transmis par `acquire_inputs(..., config = )` à `flag_dfci()`.

# foretaccess 1.3.1 (2026-07-17)

## Corrections

- **MNT acquis via LIDAR HD** — `acquire_mnt()` récupère désormais le modèle
  numérique de terrain depuis la couche **LIDAR HD** (`IGNF_LIDAR-HD_MNT`, Lambert-93
  natif), avec repli automatique sur `HIGHRES` puis RGE ALTI si le LIDAR ne couvre
  pas l'emprise. Le WMS RGE ALTI servait sur certaines tuiles un MNT « en blocs »
  dont les marches fabriquaient de fausses pentes en grille (jusqu'à > 350 %),
  faussant l'exclusion « pente d'abattage » (faux `inexploitable` en lignes) et,
  plus généralement, tous les résultats dépendant de la pente. Sur une AOI test,
  la forêt faussement exclue passe de ~33 % à ~0,2 % (conforme à Sylvaccess).

# foretaccess 1.3.0 (2026-07-17)

## Nouvelles fonctionnalités

- **Pondération du tracé par la surface de coût de construction** — option
  `pondere_cout` sur `tracer_desserte()`, `reseau_desserte()` et
  `optimiser_reseau()`. À `TRUE`, le solveur A\* minimise le **coût de construction
  €/m** (surface du Lot 14) au lieu de la seule distance géométrique, en contournant
  les cellules chères et en empruntant les corridors bon marché. L'admissibilité de
  l'heuristique est préservée (remise à l'échelle par le coût minimal de la zone
  franchissable), donc le tracé reste optimal. Défaut `FALSE` = comportement d'origine
  bit-pour-bit (SylvaRoad).
- **`classes_debardage()`** — expose le raster « classes de débardage » de Sylvaccess
  à partir de la sortie du skidder : bandes de distance
  (`config$skidder$classes_distance_m` : 0-250 … > 2000 m) + `inaccessible` +
  `inexploitable` (pente d'abattage locale dépassée) + `hors_foret`. Raster catégoriel
  avec table de couleurs, directement cartographiable et compatible `recapituler()`.

## Documentation

- Nouveaux articles pkgdown : *Conception d'un réseau de desserte*, *Architecture &
  feuille de route*, et *Choix de conception : ForêtAccess vs Sylvaccess* (analyse des
  choix d'ingénierie face à Sylvaccess).
- **Attribution complète** des travaux dérivés (Sylvaccess, SEILAPLAN, SylvaRoad,
  Forest Road Designer, ForestRoadNetwork) dans le README et `CITATION.cff` ; nouveau
  schéma d'architecture couvrant les deux épics (`man/figures/architecture.svg`).
- Note de performance dédiée `docs/performance-coldupre.md` : câble re-chronométré à
  isopérimètre `c_sup = 3` (~40 s, ~5× plus rapide que le Cython grâce à `rayon`).
- Référence exacte de la source Sylvaccess figée (forge INRAE, commit `372abaf`,
  ADR-006 et README).

# foretaccess 1.2.0 (2026-07-16)

## Conception de desserte forestière (épic Lots 14 → 18)

Nouvelle chaîne complète pour **concevoir** un réseau de desserte forestière (et
plus seulement cartographier l'accessibilité), portage propre de **SylvaRoad**
(Dupire/ONF), **Forest Road Designer** (PANOimagen) et **ForestRoadNetwork**
(Klemet), tous GPL v3. De la surface de coût au réseau typé et optimisé :

- **Coût de construction (Lot 14)** — `surface_cout_construction()` produit un
  `foretaccess_cout_construction` (deux `SpatRaster` : `cout` €/m additif et
  `franchissable`), paramétré par `config$desserte$cout`.
- **Solveur de tracé A\* (Lot 15, noyau Rust)** — `tracer_desserte()` trace une
  route de moindre coût sous contraintes de constructibilité (pente longitudinale,
  dévers, épingles, rayon de braquage, contrôle de profil), à voisinage disque,
  via le crate `cablehelp` ; sortie `foretaccess_trace` (`sf` LINESTRING).
  Paramètres dans `config$desserte$trace`.
- **Réseau multi-cibles (Lot 16)** — `reseau_desserte(..., mode =)` connecte N
  parcelles au réseau existant au moindre coût cumulé, en réutilisant les troncs
  (arborescence). Deux modes : `"glouton"` (MTAP→STAP séquentiel) et `"steiner"`
  (arbre couvrant de poids minimal). Sortie `foretaccess_reseau` (`sf` + raster),
  vérifiée connexe et desservant toutes les parcelles.
- **Flux de bois & typage (Lot 17)** — `vectoriser_reseau()` transforme le réseau
  en graphe topologique (`foretaccess_reseau_graphe`) ; `calculer_flux()` sème des
  sources et accumule le volume vers les exutoires ; `typer_desserte()` classe les
  tronçons par seuils de flux (primaire/secondaire/tertiaire) avec conversion
  temporaire optionnelle. Sortie `foretaccess_desserte_typee`, persistable via le
  socle spatial (GeoPackage/PostGIS).
- **Optimisation du réseau (Lot 18, noyau Rust)** — `optimiser_reseau(...,
  strategie =)` explore l'espace des ordres d'insertion pour améliorer le glouton,
  sans jamais faire pire : `"multistart"` (K ordres perturbés en parallèle,
  `rayon`), `"recuit"` (recuit simulé, Akay 2004) et `"riprute"` (rip-up & reroute,
  avec garde-fou de connexité). Sortie `foretaccess_reseau` enrichie d'un journal
  de convergence.

Travail dérivé de Sylvaccess et des outils cités ci-dessus, distribué sous GPL v3.

# foretaccess 1.1.0 (2026-07-16)

## Optimisation de la hauteur des supports câble façon SEILAPLAN (spec 013)

Nouvelle méthode de placement des supports du câble-mât, activable par
`cable$methode_supports = "seilaplan"` (défaut `"sylvaccess"`). Elle transcrit
l'algorithme de **Bont & Heinimann (2012)** du plugin QGIS **SEILAPLAN** — un
**graphe + plus court chemin (Dijkstra)** qui optimise **position et hauteur** des
supports — en réutilisant la mécanique caténaire Newton/Irvine déjà validée
(noyau Rust `cablehelp`), et non la mécanique de Zweifel de SEILAPLAN.

- **Fidélité** : confrontée cellule à cellule à l'oracle Sylvaccess
  `c_option_h=true` sur ColduPre, la méthode monte l'accord de **93,2 % à
  94,7 %**, récupère du trop-conservateur (faux-négatifs 1915 → 1465) sans excès
  d'optimisme (faux-positifs 25 → 29), pour un gain en fenêtre **+454 ≈ le +470**
  de l'oracle.
- **Perf** : ~**2,8×** le `_NoH` (pré-filtre géométrique des arêtes, amorçage
  Newton partagé par travée, portée prolongée au pas raster).
- **Défaut inchangé** : `"sylvaccess"` (variante `_NoH`, fidélité ColduPre
  garantie) reste le défaut, bit-pour-bit identique.

Le portage direct de `OptPyl_Up2` de Sylvaccess (tenté puis shelvé, buggé et
lent) et le flag expérimental `optimiser_hauteur_fixation` ont été **retirés** au
profit de cette voie. Voir `specs/013-seilaplan-hauteur.md` et
`docs/comparaison-cable-seilaplan.md`.

# foretaccess 1.0.0 (2026-07-15)

Première version **majeure**. Le sens du bump est celui décidé au Lot 11 : `v1.0.0` signifie
« **validée contre le vrai moteur Sylvaccess** », non « périmètre atteint ». Ce préalable est
désormais tenu sur les **quatre moteurs**, confrontés cellule à cellule au jeu officiel ColduPre
(sorties Sylvaccess v3.6 produites en propre, aucun oracle n'étant livré avec le dépôt amont) :

| Moteur | Accord | Trop optimistes | Trop conservateurs |
|---|---|---|---|
| Skidder | **99,95 %** | 0,04 % | 0,01 % |
| Porteur | **99,72 %** | 0,22 % | 0,06 % |
| Câble | **98,36 %** | 1,24 % | 0,40 % |
| Camion DFCI | **99,87 %** | 0,00 % | 0,13 % |

Et **toutes les distances collent**, décomposition comprise (débusquage, traînage en forêt et sur
piste, total) : écart médian à l'arrondi près, la pondération de la piste dans l'arbitrage
(`d_foret + 0,5·d_piste` en propagation, `+ 0,1·d_piste` en arbitrage route/piste) comprise.

## Camion DFCI — moteur radial transcrit de Sylvaccess (Lot 12a.4)

La spec 006 reposait sur une hypothèse fausse (« Sylvaccess n'a pas de module DFCI ») : le moteur
beta a été **jeté et réécrit** en transcription à la lettre de `debusq_dfci`. Ce n'est pas un plus
court chemin (le Dijkstra `calc_dist_dfci` existe dans le `.pyx` mais y est désactivé) mais un
**lancer de rayons radial** : depuis chaque pixel du réseau DFCI (flag `CL_DFCI`), une lance est
tirée dans les 360 azimuts (pas 1°), épouse le relief (longueur 3D cumulée), plafonnée à
`dfci_lmax = 440 m`, arrêtée par la pente (> `dfci_slope_max = 110 %`), un obstacle ou le bord.
Boucle chaude portée en **Rust** (`dfci_scan`), comme le câble ; sortie à **6 classes** de
défendabilité (`inaccessible` / `non_defendable_pente` / `defendable_c1/c2/c3` / `hors_foret`) plus
longueur de lance, dénivelé, lien forêt↔réseau et pente pompier. Accord **99,87 %**, longueur de
lance et dénivelé à 0,0 m d'écart médian.

## Périmètre

Les quatre moteurs terrestres et câble, la sélection de lignes câble, le passage à l'échelle
(tuilage), la base spatiale et l'agrégation, l'acquisition depuis une AOI (IGN / OSM), la
documentation et la publication (pkgdown). Dettes assumées, sans effet sur ColduPre et documentées
dans `PLAN.md` : optimisation de la hauteur de fixation du câble (`c_option_h = 1`, hors défaut
v3.6) et sélection des lignes câble tamponnées (corollaire du Lot 5).

# foretaccess 0.14.0 (2026-07-15)

## Lot 12a — affinage de fidélité (câble, porteur, skidder)

Sur le socle de confrontation à l'oracle du Lot 11, quatre écarts résiduels traités, mesure
à l'appui sur le jeu officiel ColduPre (411 309 cellules forestières). Principe directeur :
**fidélité avant optimisation** — chaque changement est mesuré sur l'oracle avant d'être retenu.

Accord cellule à cellule après le lot :

| Moteur | Accord | Trop optimistes | Trop conservateurs |
|---|---|---|---|
| Skidder | **99,95 %** | 0,04 % | 0,01 % |
| Porteur | **99,72 %** | 0,22 % | 0,06 % |
| Câble | **98,36 %** | 1,24 % | 0,40 % |

### Câble — pêchage latéral (`c_l_hor`) — 96,58 % → 98,36 %

La couverture d'une ligne faisable n'est plus son seul axe mais le **rectangle** de demi-largeur
`c_l_hor` (40 m) autour du segment desserte → bout de ligne, comme `create_rast_couv` chez
Sylvaccess : un **tampon perpendiculaire inconditionnel** (la charge décrochée à côté de la ligne,
pas dessous). `build_lat_rays()` dans le noyau Rust ; ajouté à la seule couverture, pas à la
surface/volume de la ligne. Ferme ~86 % du reliquat trop conservateur (2,79 % → 0,40 %). La
contrepartie (trop optimiste 0,63 % → 1,24 %) tient à ce qu'on tamponne *toute* ligne candidate,
là où Sylvaccess ne retient qu'une sélection (`Tab_result`) — corollaire du Lot 5, pas du tampon.

### Porteur — fusion plat/radial et héritage du grappin

Le porteur arbitre désormais entre propagation **sur terrain plat** et desserte **radiale** comme
Sylvaccess (radial l'emporte si `Dforet_radial < Dforet_plat + 0,1·Dpiste_plat`, asymétrique et
strict), puis fait **hériter le grappin** de la rampe conduite (`Dforet = Dbras + Dforet_rampe`).
Les distances collent alors, décomposition comprise : traînage sur piste −3,0 m, forêt +1,2 m,
total +0,5 m d'écart médian.

### Skidder — pondération de la piste dans l'arbitrage (veto)

Transcription **à la lettre** du mécanisme de Sylvaccess : ce n'est pas un moteur de coût mais un
**veto** imbriqué (`pyx:3712`), avec deux coefficients — `0,5` dans la propagation entre pistes,
`0,1` dans l'arbitrage piste/route. Propagation par **correction d'étiquettes** (le veto brise la
monotonie d'un Dijkstra). Accord skidder maintenu à 99,95 %.

### Banc — angle mort des distances porteur fermé

`oracle_compare.R` compare désormais aussi les **distances** du porteur (traînage piste, forêt,
total), pas seulement la carte binaire d'accessibilité : une carte peut coïncider alors que les
distances divergent. C'est ce banc élargi qui a révélé puis validé le correctif 12a.2b.

# foretaccess 0.13.0 (2026-07-14)

## Lot 11 — confrontation à l'oracle Sylvaccess réel

Sylvaccess v3.6 tourne désormais en local et produit son oracle sur son propre jeu de
test officiel (`test/ColduPre`, 411 309 cellules forestières), qui ne livre aucune sortie
de référence — il faut l'exécuter. Banc : `data-raw/oracle_coldupre.R` (ForêtAccess sur
les mêmes entrées) et `data-raw/oracle_compare.R` (comparaison cellule à cellule).

Accord cellule à cellule après correctifs :

| Moteur | Accord | Trop optimistes | Trop conservateurs |
|---|---|---|---|
| Skidder | **99,95 %** | 0,04 % | 0,01 % |
| Porteur | **99,72 %** | 0,22 % | 0,06 % |
| Câble | **96,58 %** | 0,63 % | 2,79 % |

Les distances collent, **décomposition comprise** : débusquage à 0,0 m d'écart médian, traînage
en forêt à 0,2 m, traînage sur piste à 0,4 m, distance totale à 0,2 m. Le reliquat est l'arrondi
(Sylvaccess stocke ses distances en `int16`), borné par la demi-cellule.

### Divergences corrigées (moteurs terrestres)

* **`.masque_vecteur()` perdait les géométries non-polygonales** : `terra::vect()` sur une
  couche `sf` hétérogène ne retient qu'un seul type et abandonne les autres sans erreur.
  Rasterisation par famille (surface / ligne / point) puis union.
* **Rasterisation `ALL_TOUCHED`** : Sylvaccess rasterise chacune de ses couches vectorielles
  avec `ALL_TOUCHED=TRUE` ; toute cellule effleurée compte. Aligné (`.masque_vecteur()`,
  `.rasteriser_desserte()`), avec priorité `route < piste < dfci < reseau_public`.
* **Nouvelle classe de desserte `reseau_public`** : la route ouverte à la circulation est le
  point de chargement du camion, pas une place de dépôt — et pour les engins de débardage,
  une barrière. Exclue des sources de balayage et de la zone roulable, versée aux obstacles
  du porteur.
* **Le traînage sur piste ne paie plus le surcoût d'obstacle** : une route n'est pas un
  obstacle à la circulation sur elle-même (`Pond_pente` réseau vs `Pond_pente2` forêt).
* **Le seuil d'abattage porte sur le maximum local 3 × 3 de la pente**, pas sur la pente de
  la cellule (`slopes_skid()`) : la zone d'exclusion est dilatée d'une cellule.
  `pre$slope_max_local` ajouté.
* **Troisième passe de treuillage du skidder** (`skid_debusq_contour`) : la machine entre en
  forêt, s'arrête au bord du terrain roulable et treuille **de là**, en emportant sa distance
  déjà parcourue. `treuiller(depart_cout = )`.
* **Porteur** : grappin depuis la seule forêt conduite (`Dforet > 0`), propagation
  **Dijkstra sur terrain plat** qui manquait entièrement (`terrain_plat()`,
  `zone_plate_connectee()`), et passe contour symétrique (`conduire(sources=, depart_cout=)`).

### Câble

* **`potentiel_cable(departs = )`** : les lignes ne partent plus de toute cellule de desserte
  mais d'une couche de **places de dépôt** (attribut `cable`) — 2 tronçons sur 125 à ColduPre.

## Lot 4 — clôture du noyau câble (supports intermédiaires)

* **Placement des supports intermédiaires** (`OptPyl_Up_NoH`, recherche en faisceau
  `get_Tabis`, jusqu'à `c_sup = 3`), avec coupe de la ligne au point le plus lointain atteint.
  La dette « zéro support » du Lot 4 est soldée.
* **`check_line()`** — validité géométrique de la ligne : elle finit en forêt, ne traverse pas
  plus de 75 m de non-forêt d'affilée, et ne court pas en travers d'un versant raide.
* **Ligne « machine en bas »** (`OptPyl_Down_init_NoH` / `OptPyl_Down_NoH`) : le balayage
  traite désormais les deux sens de débardage et choisit par dominance mât / ancrage.

Balayage câble : **79 s** contre 198 s à Sylvaccess, à périmètre désormais égal (3 supports).

## Défauts de configuration alignés sur Sylvaccess

Audit complet de `foretaccess_config()` contre `dic_AllParam.json` (règle : Sylvaccess fait foi).

* Câble : `c_E` 160 000 → **100 000**, `c_q2`/`c_q3` 0,9 → **0,5**, `c_angle` 20 → **30°**,
  `c_safe` 2 → **2,5** (il divise `Tmax`).
* Porteur : `pente_descente_max_pct` 25 → **40**.
* DFCI : `distance_defense_max_m` 100 → **440**, `pente_defense_max_pct` 40 → **110**,
  classes `0;120;280;440`. `Sylvaccess_5_dfci.py` existe — `specs/006` supposait l'inverse.
* Bornes de pente du câble **dérivées** du type de chariot/câble et du sens de débardage
  (`bornes_pente_cable()`), et précision du balayage gouvernée par `c_precision`
  (`precision_cable()`).

# foretaccess 0.12.0 (2026-07-13)

## Portage Rust du balayage câble (point chaud)

* **`potentiel_cable()` porté dans le noyau Rust** (`cablehelp`, `cable_scan`) :
  l'orchestration 360°/pixel — extraction du profil, recherche de la plus longue
  travée faisable, accumulation couverture/lignes — vit désormais dans le crate,
  parallélisée sur les cellules de desserte via **`rayon`**. R prépare les entrées
  et réassemble les sorties SIG ; la frontière reste minimale et typée (ADR-001).
* **Non-régression bit-pour-bit** vis-à-vis de l'ancienne double boucle R
  (accessibilité, longueur/azimut, table des lignes candidates) : arrondi
  demi-au-pair (`round()` R / IEC 60559) et séquences `seq()` reproduits à
  l'identique. Gain mesuré **~5×** (grille 60 × 60, 60 départs : 36 s → 6 s), avec
  passage à l'échelle sur les grandes emprises grâce au parallélisme.

## Article « Cartes de sortie sur une AOI réelle » (site pkgdown)

* Le pipeline complet exécuté sur `data-raw/aoi.gpkg` (massif des Cévennes), chaque
  sortie cartographiée sur **fond OpenStreetMap** (entrées MNT/desserte/forêt,
  sorties skidder/porteur/DFCI en raster, câble et agrégation zonale en vecteur).
  Cartes pré-rendues par `data-raw/cartes.R` (acquisition IGN + tuiles OSM via
  `maptiles`), embarquées en images (aucun calcul ni réseau à la construction).

# foretaccess 0.11.0 (2026-07-12)

## Lot 10 — Acquisition des entrées depuis une AOI

Télécharge automatiquement les couches du pipeline à partir d'un simple polygone
d'emprise (AOI), au lieu de les fournir à la main (étend EF-1). Approche
**config-driven** (patron nemeton) : endpoints et couches déclarés dans
`inst/datasources/FR.json`, jamais codés en dur.

* **`acquire_inputs(aoi, sources, cache_dir, res_m, crs, buffer_m, ...)`** :
  orchestre l'acquisition de MNT (RGE ALTI), desserte (BD TOPO), forêt (BD Forêt
  v2), obstacles (OpenStreetMap) et parcellaire cadastral (optionnel). Sortie
  `foretaccess_inputs` **directement consommable par `preprocess()`**.
* **Fonctions par source** : `acquire_mnt()`, `acquire_desserte()` (dérive le champ
  `classe` route/piste depuis BD TOPO), `acquire_foret()`, `acquire_cadastre()`
  (IGN via `happign`), `acquire_obstacles()` (bâti / eau / voies ferrées /
  falaises via `osmdata`).
* **Résolveur config-driven** : `get_country_config()`, `get_data_source()`,
  `get_layer_service()`, `get_national_crs()`, `list_countries()` lisent le JSON
  par pays. Changer un endpoint ne touche pas au code.
* **Robustesse** : cache idempotent (`cache_dir/layers/<couche>/`, réutilisé sauf
  `overwrite`) ; `happign`/`osmdata` en **Suggests** avec message d'installation
  ciblé ; **verrou CRS** strict sur l'AOI ; buffer 100 m par défaut pour capter la
  desserte hors emprise. Les appels réseau sont isolés (wrappers mockables) : les
  tests unitaires tournent **hors-ligne** ; un test d'intégration réseau est
  **opt-in** (`FORETACCESS_RUN_ONLINE_TESTS=TRUE`).
* **Vignette** « Acquérir les entrées depuis une AOI » + `specs/010`.

# foretaccess 0.10.0 (2026-07-12)

## Lot 9 — Documentation & publication

Rend le paquet utilisable par un tiers (DoD produit). Clôt le périmètre v1
fonctionnel (Lots 0–5, 7–9 ; DFCI Lot 6 en beta).

* **Vignette `foretaccess`** : le **pipeline complet** de bout en bout sur le jeu
  jouet — prétraitement, moteurs skidder / porteur, camion DFCI, câble (potentiel
  + sélection), agrégation zonale, persistance GeoPackage. **Exécutée** à la
  compilation : elle documente *et* teste le pipeline (`vignette("foretaccess")`).
* **README** à jour : section *Démarrage rapide*, statut réel des lots, renvoi à la
  vignette et à la roadmap, attribution Sylvaccess (GPL v3) conservée.
* **Site pkgdown** : index de référence groupé par thème/lot + article, listant
  tous les exports.
* `DESCRIPTION` : `knitr` / `rmarkdown` en `Suggests`, `VignetteBuilder: knitr`.
* `specs/009-publication.md` fige les décisions (vignette exécutée, pas de CLI
  shell, `NEWS.md` tient lieu de changelog).

# foretaccess 0.9.0 (2026-07-12)

## Lot 8 — Base spatiale & agrégation zonale

Rend les sorties **exploitables en base** (EF-9, EF-12) : écriture indexée et
agrégation par entité de gestion. Complète le socle `StorageBackend` du Lot 0.

* **`agreger_zones(classes, zones, volume, id)`** : agrège n'importe quel raster
  catégoriel d'accessibilité (skidder, porteur, DFCI, couverture câble) en
  **surfaces** (ha) et **volumes** (m³) **par zone** (massif / parcelle / commune)
  et par classe. Pendant zonal de `recapituler()`. Sortie `sf` à colonnes larges
  `surface_<classe>_ha` (+ `volume_<classe>_m3`), directement persistable et
  requêtable. Croisement raster **vectorisé** ; verrou CRS strict ; propriété de
  **partition** (somme zonale = récap global) vérifiée en test.
* **Index spatial PostGIS** : `sb_write_layer()` crée désormais un **index GiST**
  sur la géométrie après l'écriture idempotente (idempotent lui-même,
  `spatial_index = TRUE` par défaut). Côté GeoPackage, le R-tree est créé
  automatiquement — équivalence acquise.
* **`specs/008-base-spatiale.md`** fige les décisions ; l'agrégation est en
  R/terra, backend-agnostique (testable sans base, persistable dans les deux
  backends).

# foretaccess 0.8.0 (2026-07-12)

## Lot 6 — Camion DFCI (beta) : zone défendable

Sortie **beta** de défense de la forêt contre les incendies (EF-8). Cartographie
la **zone défendable** — la forêt qu'un camion peut atteindre et défendre depuis
les dessertes DFCI. Conception propre (le module DFCI n'est pas dans les sources
Sylvaccess de référence), cohérente avec l'architecture des moteurs terrestres.

* **`camion_dfci(pre, config, write_dir, bord)`** : signature identique à
  `skidder()` / `porteur()`, directement branchable sur `traiter_par_tuiles()`.
  La zone défendable est un **tampon au terrain** — un plus court chemin pondéré
  par la pente (`propager_cout()` + `surface_cout_skidder()`) depuis les dessertes
  DFCI, plafonné à la portée de défense et coupé au-delà de la pente
  d'intervention. Aucun nouveau noyau : réutilise le service partagé du Lot 2.
* **Sorties** : raster catégoriel `accessibilite` (`defendable` /
  `non_defendable` / `hors_foret`), `distance_defense` (m), `allocation`, `recap`
  surfaces/volumes, écriture COG optionnelle.
* **Configuration `config$dfci`** : portée de défense (100 m), pente
  d'intervention max (40 %), classes de desserte-source (`"dfci"`). Hypothèses de
  travail explicites, non Sylvaccess (surchargeables, validées au chargement).
* **Tuilage** : sortie certifiée, identique au mono-bloc sur les cellules
  certifiées. Le réseau DFCI étant clairsemé, une tuile sans source reste
  indéterminée (le halo grandit) ; l'absence de source au niveau top-level lève
  une erreur ciblée.
* **Limites (beta)** documentées (`specs/006-dfci.md`, roxygen) : ni combustible,
  ni vent, ni physique de lance ; carrossabilité des dessertes non qualifiée
  (QUALIROAD). Sortie de **première hiérarchisation**, pas de dimensionnement.

# foretaccess 0.7.0 (2026-07-12)

## Lot 5 — Sélection multicritère des lignes câble

Sortie **décisionnelle** du volet câble (EF-7). Parmi les lignes faisables du
balayage 360°/pixel (Lot 4), on sélectionne un sous-ensemble non redondant
maximisant la couverture selon des critères pondérés. Porté de
`select_best_lines` / `create_best_table` (Sylvaccess v3.6, GPL v3).

* **Table des lignes candidates** : `potentiel_cable()` émet désormais `$lignes`,
  une candidate par couple (départ, azimut) faisable, avec surface forêt
  couverte, longueur, sens (amont/aval), nombre de supports, et — si un raster de
  volume est fourni — volume total et **IPC** (= volume / longueur).
* **`selectionner_lignes()`** : filtrage par limites min/max, score pondéré
  normalisé (maximiser → `valeur / p98` ; minimiser → `1 − valeur / max`),
  classement déterministe, **sélection gloutonne** (une ligne retenue apporte au
  moins 60 % de surface nouvelle). Sortie **`sf`** des lignes (LINESTRING, CRS
  strict) et **raster de couverture**.
* **Configuration** de la sélection dans `config$cable$selection` (poids, limites,
  sens préféré, contribution minimale). Les critères volume/IPC sont neutralisés
  automatiquement en l'absence de donnée de volume.

Six critères MVP (surface, supports, sens, longueur, volume, IPC) ; VAM×10 et
coût €/m³ de v3.6 repoussés. La reproductibilité vis-à-vis de v3.6 sur le jeu
test reste à confronter à un oracle réel ; le déterminisme est verrouillé.

# foretaccess 0.6.0 (2026-07-12)

## Lot 4 — Noyau câble (Rust, CableHelp)

Premier moteur **non terrestre**, et point où le portage `extendr`/`rextendr`
prend son sens. La mécanique de câble-mât (caténaire élastique) est portée depuis
le code source Sylvaccess v3.6 (`sylvaccess_cython3.pyx`, GPL v3) dans le crate
Rust `cablehelp`, exposée via `extendr` ; l'orchestration SIG reste en R.

* **Caténaire élastique + Newton-Raphson** (`cable_f_x`, `cable_f_z`,
  `cable_calcul_xs`, `cable_calcul_zs`, `cable_newton_thtv`,
  `cable_find_thtv_tmax`). Le terme `Lo/EAo` (allongement sous tension) distingue
  le modèle d'une caténaire idéale. Résolution par Jacobien analytique, repli sur
  grille.
* **Faisabilité d'une travée** (`cable_check_droite`, `cable_check_hlinemin`) :
  la charge balaie la travée, on résout les tensions à chaque position et on
  vérifie la garde au sol dans `[hauteur_cable_min_m, hauteur_cable_max_m]` et la
  tension sous la limite admissible.
* **Optimisation de travée** (`cable_find_lomin`, `cable_test_span`) : longueur à
  vide minimale à tension = Tmax, pente bornée, contrainte d'angle au support
  intermédiaire. Amorçage par grille grossière (substitut aux tables `Tabmesh`).
* **Orchestration** (`potentiel_cable()`) : balayage 360°/pixel depuis la
  desserte, extraction du profil MNT, test d'une ligne **0 support** jusqu'à la
  longueur maximale, couverture des cellules forestières. Sortie
  `foretaccess_cable`.
* **Configuration câble** complétée avec les matériels v3.6 (`config$cable`).

Extensions prévues (voir `specs/004-cable.md`) : placement de supports
intermédiaires (`OptPyl_Up`, avec oracle réel), pêchage latéral, portage Rust de
l'orchestration.

# foretaccess 0.5.1 (2026-07-12)

## Conformité du porteur — zone de conduite

Relecture de `Sylvaccess_3_forwarder.py` (construction de `Zone_OK` /
`Pente_ok_forwarder`). Deux corrections à `.zone_conduite()` :

* **Bug de borne de pente.** La zone bornait la pente par
  `min(travers, montée, descente)` = 15 %, alors que Sylvaccess la borne par le
  **maximum** = 30 %, le balayage affinant ensuite par le sens et le dévers. Le `min`
  excluait à tort les cellules roulables en montée dans le sens de la pente.
* **Saut hors forêt** (`distance_hors_desserte_max_m`, 200 m). Le porteur peut couper par
  un terrain récoltable non forestier, depuis le contour de la forêt, pour rejoindre un
  massif isolé — l'analogue de `zone_roulable_connectee()` du skidder. Le halo suffisant du
  tuilage intègre désormais ce saut.

La **double passe** réseau/contour reste une dette assumée : sans sortie Sylvaccess de
référence, son modèle de distance en composantes séparées ne peut être validé sur les
fixtures synthétiques. Voir `specs/003-porteur.md`.

# foretaccess 0.5.0 (2026-07-11)

## Lot 3 — Moteur Porteur (forwarder)

Deuxième moteur terrestre, `porteur()`. Rédigé sur le code source Sylvaccess v3.6
(`Sylvaccess_3_forwarder.py`, `sylvaccess_cython3.pyx`), qui renverse l'hypothèse
« porteur = skidder aux seuils différents ».

* La conduite est un **balayage radial** depuis le réseau de desserte
  (`fwd_azimuts_forest_roadnet`), non un plus court chemin. Nouvelle fonction exportée
  `conduire()`, qui partage la géométrie de rayons du treuillage mais s'en distingue par
  trois filtres, tous sur la pente du terrain **en degrés** :
  - **pente en long signée par l'altitude** : une cellule plus haute que la route relève
    de la descente (le porteur y ramène le bois chargé en descendant), plus basse de la
    montée ;
  - **dévers dépendant de l'azimut** : `pente_travers / cos(90 - Δ)`, nul dans le sens de
    la pente, maximal en travers — le basculement latéral de la machine ;
  - **accumulateur de distance en pente forte**, plafonné à `distance_pente_forte_max_m`.
* Pas de treuil, mais un **grappin** de `portee_grue_m` (8 m) : une extension géométrique
  bornée du terrain récoltable, reproduisant `fwd_add_hoist`.
* La distance retenue est **3D**.

Le porteur se tuile mieux que le skidder : sa portée étant bornée (conduite 300 m,
grappin 8 m), le halo suffisant est petit et connu. `traiter_par_tuiles(moteur = porteur)`
donne un résultat identique au mono-bloc.

## Généralisation du tuilage

`traiter_par_tuiles()` accepte un argument `couches` : il n'est plus lié aux couches du
skidder et sert n'importe quel moteur.

## Dette assumée

Le saut hors forêt du porteur (`f_dmax_outfor`, l'équivalent de `zone_roulable_connectee()`
du skidder) et la double passe réseau/contour ne sont pas encore implémentés. Voir
`specs/003-porteur.md`.

# foretaccess 0.4.0 (2026-07-10)

## Lot 7 — Passage à l'échelle (tuilage, certificat, parallélisme)

Le brief exige un résultat tuilé **identique** au traitement mono-bloc. Un halo fixe ne le
donne pas : le traînage est un plus court chemin sans portée bornée, et la connexité d'un
massif à la desserte peut passer par un détour arbitrairement long. Un halo trop court produit
des artefacts de bordure — distances trop grandes, cellules faussement inaccessibles — que
rien ne signale.

* `certifier_propagation()` **prouve** l'exactitude cellule par cellule. Deux propagations sur
  la fenêtre : `d_R` depuis les sources, `d_∂` depuis le bord ouvert pris à coût nul. Si
  `d_R(v) ≤ d_∂(v)`, aucun chemin extérieur ne peut faire mieux. L'allocation est exacte si
  l'inégalité est stricte ; `∞ ≤ ∞` certifie l'inaccessibilité ; la connexité n'est que le cas
  `coût ≡ 0`.
* `decouper_emprise()` découpe en fenêtres d'écriture **disjointes** avec halo. Le halo ne sert
  qu'au calcul : la recomposition est une mosaïque, sans règle de fusion.
* `traiter_par_tuiles()` double le halo tant que des cellules restent non certifiées. Au
  plafond, elles sortent en `indetermine` avec un avertissement — jamais rangées dans
  `non_accessible`, jamais tronquées en silence. Une cellule non certifiée ne publie rien :
  ni classe, ni distance, ni allocation.
* Parallélisme par tuile via **`mirai`** (nouvelle dépendance). `workers = 1` s'exécute sans
  démon. Le résultat ne dépend pas du nombre de workers.
* Sorties en COG recomposé.

### Le halo, et ce qu'il coûte

Le certificat n'est satisfait que si le halo dépasse la plus longue distance qui peut entrer
dans la tuile, et le surcoût surfacique croît comme `(1 + 2·halo/tuile)²`. Mesuré : 2,5× le
mono-bloc avec `tuile = 4 × halo`, mais **27×** quand le halo dépasse la tuile.

`distance_trainage_piste` atteint 4 km sur données réelles et aurait imposé des tuiles de
16 km. Elle vit pourtant sur le réseau de desserte — unidimensionnel et creux : une seule
propagation globale la donne exactement. `traiter_par_tuiles()` la précalcule, et elle cesse
d'être un moteur de halo.

## Nouvelles fonctions

`decouper_emprise()`, `fenetre_tuile()`, `certifier_propagation()`, `traiter_par_tuiles()`.
`skidder()` accepte `bord` et certifie alors ses sorties.

# foretaccess 0.3.1 (2026-07-10)

## Conformité à Sylvaccess v3.6

Première exécution sur données réelles (AOI de 7,2 km², RGE ALTI + BD TOPO). Elle a
révélé deux écarts au code source que le jeu jouet ne pouvait pas exposer.

* `distance_hors_desserte_max_m` **ne plafonne pas la distance de débardage**. C'est la
  distance maximale que le skidder peut parcourir **hors forêt**, sur du terrain roulable,
  pour rejoindre un massif qu'aucune desserte ne touche. Nouvelle fonction exportée
  `zone_roulable_connectee()`, qui reproduit la construction en trois temps de
  `Pente_ok_skidder` (connexité depuis la desserte, saut borné hors forêt, recollement),
  et `terrain_roulable()`, son critère de pente sans le critère forêt.
* La `distance_trainage_piste` est désormais pondérée par la pente, comme le traînage en
  forêt (`Dfwd_flat_forest_tracks(f, Lien_Piste, Pond_pente, …)`), et non propagée à coût
  uniforme.

Sur l'AOI de test, la surface parcourable augmente de 1,9 ha.

## Performance

* Le tas binaire du Dijkstra était recopié à chaque opération (sémantique de copie de R
  sur un vecteur porté par une liste) : **357×** sur une sonde de 200 000 insertions.
* Le balayage radial de treuillage portait des vecteurs pleine longueur sous un masque de
  rayons vivants : compacter les survivants le rend **2,2×** plus rapide, à sortie
  identique bit à bit.

`skidder()` traite désormais 7,2 km² en 22 s CPU (3,05 s/km²) sur un cœur.

# foretaccess 0.3.0 (2026-07-10)

## Lot 2 — Moteur Skidder (+ service least-cost partagé)

Les règles sont **dérivées du code source Sylvaccess v3.6** (GPL v3,
`forge.inrae.fr/sylvain.dupire/sylvaccess`), et non de l'article — qui n'en donne
pas les équations. Trois d'entre elles contredisaient nos hypothèses initiales.

* **`propager_cout()`** et **`chemin_optimal()`** : service de plus court chemin
  sur grille, partagé avec le porteur (Lot 3) et le camion DFCI (Lot 6). Dijkstra
  8-connexe, coût porté par la **cellule d'arrivée** (et non la moyenne des deux
  cellules, comme `terra::costDist()`), diagonale × `sqrt(2)`, plafond de coût, et
  raster d'**allocation** identifiant la source atteinte. Aucune dépendance nouvelle.
  Le tas binaire vit dans des vecteurs mutés en place : le passer en liste ferait
  recopier le vecteur à chaque opération (sémantique de copie de R), rendant le
  Dijkstra quadratique — mesuré à 357× plus lent sur 200 000 insertions.
* **`surface_cout_skidder()`**, **`ponderation_pente()`** : la fonction de coût est
  `sqrt(1 + (p/100)^2)`, le facteur d'allongement 3D de la traversée d'une cellule.
  Elle ne dépend que de la pente **absolue** : la propagation est **isotrope**.
* **`treuiller()`** : le treuillage n'est **pas** un plus court chemin, mais un
  balayage radial 360° au pas de 1°, en ligne droite, avec une distance **3D** et
  une contrainte de dégagement du câble (la corde reste entre le sol et
  `hauteur_degagement_max_m`, attachée à `hauteur_attache_treuil_m`). Les rayons
  vivants sont compactés à chaque pas : la plupart meurent en quelques cellules,
  et le travail s'effondre (2,2× sur terrain réel).
* **`distance_treuillage_max()`**, **`coefficients_bascule()`** : la loi de bascule
  est affine en **dénivelé**, pas en pente. À plat, la distance admissible vaut
  **80,23 m** — ni 50 (plafond amont), ni 100 (plafond aval).
* **`skidder()`** : orchestrateur. Classes d'accessibilité, distances de treuillage,
  de traînage (forêt et piste) et de débardage, allocation, trajets optionnels,
  écriture GeoTIFF/COG.
* **`recapituler()`** : surfaces et volumes par classe, avec une ligne
  `indetermine` explicite — les bordures ne sont jamais rangées silencieusement
  dans une classe métier.
* **`zone_roulage()`**, **`zone_treuillable()`** : les obstacles **partiels**
  bloquent le roulage mais pas le treuillage ; les obstacles **complets** reçoivent
  un surcoût additif prohibitif mais **fini** (1000), et ne sont pas `NA`.

## Changements

* `preprocess()` conserve désormais le **MNT** dans son résultat (`$mnt`) : les
  moteurs en ont besoin, le treuillage raisonnant sur les altitudes. Ajout additif.
* Nouveaux paramètres `config$skidder`, aux défauts v3.6 lus dans le `.pyx` :
  `hauteur_attache_treuil_m`, `hauteur_degagement_max_m`,
  `surcout_obstacle_complet`, `option_modelisation`, `classes_distance_m`.

## Limites connues

* Seule l'**option de modélisation 1** (privilégier le treuillage) est implémentée ;
  l'option 2 lève une erreur explicite.
* Le plafond `distance_hors_desserte_max_m` n'est pas appliqué, et la hiérarchie
  route / piste est réduite à deux niveaux. Voir `specs/002-skidder.md`.

# foretaccess 0.2.0 (2026-07-09)

## Lot 1 — I/O & prétraitement

* **`preprocess()`** : socle commun aux quatre moteurs. Produit un objet
  `foretaccess_preprocessing` dont tous les rasters partagent exactement la
  grille du MNT (pente, exposition, masque forêt, desserte catégorielle, masques
  d'obstacles, masque d'exclusion de pente, volume aligné).
* **`valider_entrees()`** : validation **stricte** des entrées — CRS commun,
  alignement de grille, champ `classe` de la desserte, géométries non vides et
  valides, emprises se recouvrant. Aucune reprojection ni rééchantillonnage
  silencieux ; chaque manquement lève une erreur ciblée.
* **`calculer_terrain()`** : pente en pourcentage et exposition en degrés depuis
  le nord (plat = `NA`), via `terra`. Méthode configurable
  (`config$general$methode_pente` : `"Horn"` par défaut, ou `"Evans"`).
* Écriture GeoTIFF/**COG** optionnelle (`preprocess(write_dir = )`) et relecture
  par **`lire_rasters()`**.
* Chaque entrée est acceptée comme **chemin de fichier** ou comme objet déjà
  chargé (`SpatRaster` / `sf`), conformément à l'ADR-004.
* Non-régression sur oracle **analytique** : le MNT jouet (plan incliné à 20 %)
  valide pente, exposition et masques via `compare_to_oracle()`.

## Divers

* Ajout des badges README (R-CMD-check, version, pkgdown, couverture Codecov,
  lifecycle, licence) et du site pkgdown + job de couverture en CI.

# foretaccess 0.1.0 (2026-07-09)

## Lot 0 — Fondations

* Squelette de **package R** + **crate Rust `cablehelp`** liée par `extendr`
  (`cablehelp_version()` comme preuve de chaîne R ↔ Rust).
* **Configuration** métier validée (`checkmate`), défauts **Sylvaccess v3.6**,
  chargement/écriture YAML.
* Interface **`StorageBackend`** : implémentations **PostGIS** et **GeoPackage**,
  sans backend par défaut (ADR-002).
* **Jeu de données jouet** (`inst/extdata/toy/`) + **harnais de non-régression**
  (`compare_to_oracle()`).
* **CI** (lint/tests/`R CMD check`/`cargo test`/`clippy`) et **infrastructure de
  versionnage** (`release.yml`, garde-fou `version-consistency`).

# foretaccess 0.0.1 (2026-07-08)

* Jalon **documentaire** d'amorçage : PRD, backlog, roadmap (§10), ADR-001…007.
  Aucun code (voir `docs/`).
