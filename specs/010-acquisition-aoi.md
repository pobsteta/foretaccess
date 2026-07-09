# specs/010 — Lot Acquisition : téléchargement des entrées depuis une AOI

> **Statut** : proposé — en attente de validation.
> **Type** : lot **dédié**, en **amont** du prétraitement (alimente `specs/001`). Peut être
> développé en parallèle (le prétraitement se valide sur le jeu jouet).
> **Numérotation** : `010` pour ne pas entrer en collision avec les lots 2–9 déjà mappés
> (skidder…). C'est un **identifiant**, pas un ordre : logiquement ce lot précède le Lot 1.
> **Exigence** : étend EF-1 (entrées) — acquisition automatique au lieu de fichiers fournis.
> **ADR liés** : ADR-002 (stockage/interface), ADR-004 (découplage), ADR-003 (config).
> **Réutilise** le patron de **nemeton** (happign + osmdata + config JSON par pays).
> **Ne rien coder avant validation de cette spec** (+ questions §10).

---

## 1. Contexte

Le brief supposait les couches IGN **déjà fournies**. Ce lot ajoute leur **acquisition
automatique à partir d'une simple `AOI.gpkg`** (polygone d'emprise). L'approche est celle,
éprouvée, de **nemeton** : clients **IGN Géoplateforme** (`happign`, anonyme) pour WFS/WMS,
**`osmdata`** pour OpenStreetMap, endpoints/couches **jamais en dur** (config JSON par pays),
sortie en **EPSG:2154**, cache local `cache/layers/<couche>/`.

Les sorties de ce lot sont exactement les **entrées** attendues par `preprocess()` (Lot 1).

---

## 2. Périmètre

### Phase 1 (ce lot) — dépendances légères (happign + osmdata, CRAN)
| Source | Fournisseur | Couche / service | Sortie |
|---|---|---|---|
| **MNT** | RGE ALTI (IGN WMS) | `ELEVATION.ELEVATIONGRIDCOVERAGE` @ **5 m** | raster `mnt.tif` |
| **Desserte** | BD TOPO (IGN WFS) | `BDTOPO_V3:troncon_de_route` | `desserte.gpkg` (+ champ `classe`) |
| **Forêt** | BD Forêt **v2** (IGN WFS) | `LANDCOVER.FORESTINVENTORY.V2:formation_vegetale` | `foret.gpkg` |
| **Obstacles** | OpenStreetMap | `osmdata` : `building`, `water`/`waterway` | `obstacles.gpkg` |
| **Parcellaire** | Cadastre (IGN WFS) | `CADASTRALPARCELS.PARCELLAIRE_EXPRESS:parcelle` | `parcellaire.gpkg` (optionnel) |

### Phase 2 (hors ce lot — notée pour la roadmap)
- **MNH LiDAR HD** (dalles `IGNF_MNH-LIDAR-HD:dalle`) → **estimation de volume sur pied**
  (modélisation hauteur→volume via allométrie / indice de station) ; dépendances lourdes
  `lasR`/`lidR`/`lidarHD` (hors CRAN) et repli « dériver depuis les nuages LAZ ».
- **MNT LiDAR HD** (0,5–1 m) : **non requis** à résolution 5 m (RGE ALTI suffit) ; source
  optionnelle si un jour on travaille plus fin que 5 m.
- **BD Forêt v3** : dès que la couche Géoplateforme est confirmée/testée, avec **repli v3→v2**.

### Hors périmètre
- Tout traitement (pente, masques…) → Lot 1.
- Le tuilage / gros volumes → Lot 7 (ici : AOI de taille massif, requêtes bbox directes).

---

## 3. Entrées / sorties

### Entrée
- **AOI** : chemin d'un `AOI.gpkg` (ou objet `sf`/`sfc` polygonal). CRS quelconque en entrée
  → **reprojeté en interne** en EPSG:2154 pour l'écriture, et en WGS84 (4326) pour les
  requêtes OSM/bbox. Buffer optionnel (`buffer_m`) pour capter le voisinage de la desserte.

### Sortie
Objet **`foretaccess_inputs`** (liste) + fichiers en cache :
- `mnt` (chemin raster), `desserte` (`sf`), `foret` (`sf`), `obstacles` (`sf`),
  `parcellaire` (`sf` ou `NULL`), `aoi` (`sf`), et `meta` (source, couche, date, CRS).
- Cache : `cache_dir/layers/<couche>/…` (réutilisé si présent, sauf `overwrite = TRUE`).
- Ces sorties sont **directement consommables par `preprocess()`** (Lot 1).

---

## 4. Algorithme / API

**Config-driven** (patron nemeton) : `inst/datasources/FR.json` déclare services et couches ;
un résolveur R (`get_data_source()`, `get_layer_service()`) lit ce JSON — **aucun endpoint en
dur**.

Point d'entrée :
```
acquire_inputs(aoi,
               sources   = c("mnt", "desserte", "foret", "obstacles", "cadastre"),
               cache_dir = tempdir(),
               res_m     = 5,
               crs       = 2154,
               buffer_m  = 0,
               overwrite = FALSE,
               country   = "FR")
```
Fonctions par source (appelées par l'orchestrateur, testables isolément) :
- `acquire_mnt(aoi, res_m, ...)` → `happign::get_wms_raster(layer = <dem>, res = res_m, crs)`.
- `acquire_desserte(aoi, ...)` → `happign::get_wfs(layer = <roads>)` + **mapping `classe`**
  (voir §10 Q2) → valeurs {route, piste, dfci} attendues par `preprocess()`.
- `acquire_foret(aoi, version = "v2", ...)` → `happign::get_wfs(layer = <bdforet_v2>)`.
- `acquire_obstacles(aoi, ...)` → `osmdata::opq(bbox_wgs84) |> add_osm_feature("building") |>
  osmdata_sf()` (+ eau) → polygones obstacles.
- `acquire_cadastre(aoi, ...)` → `happign::get_wfs(layer = <cadastre>)`.

Chaque fonction : reproj EPSG:2154, re-clip sur l'AOI (`sf::st_intersection` — les WFS ne
filtrent que par bbox), écriture cache, dégradation **explicite** si indisponible (erreur ou
`NULL` documenté, pas de silence).

**Dépendances** : `happign` et `osmdata` en **Suggests** (vérif `requireNamespace()` avec
message d'aide si absent) — le cœur reste installable sans elles ; l'utilisateur qui fournit
ses fichiers n'en a pas besoin.

---

## 5. Critères d'acceptation

- **CA-A.1** `acquire_inputs()` sur une petite AOI réelle produit MNT + desserte + forêt +
  obstacles (+ cadastre) en EPSG:2154, écrits en cache et réutilisés au 2ᵉ appel.
- **CA-A.2** MNT à **5 m** via RGE ALTI, aligné sur l'AOable ; desserte porte un champ `classe`
  ∈ {route, piste, dfci} ; forêt = polygones BD Forêt v2 ; obstacles = polygones OSM.
- **CA-A.3** Config-driven : changer un endpoint/couche dans `FR.json` (sans toucher au code)
  modifie la source utilisée (test sur le résolveur).
- **CA-A.4** Sorties **directement acceptées par `preprocess()`** (Lot 1) sans adaptation.
- **CA-A.5** Robustesse : source indisponible → message ciblé ; `happign`/`osmdata` absents →
  message d'installation clair (pas d'erreur obscure).
- **CA-A.6** Idempotence du cache : présence détectée, pas de re-téléchargement sauf `overwrite`.

---

## 6. Tests (`testthat`)

- **Unitaires (hors-ligne, déterministes)** : résolveur `FR.json` (couches/endpoints),
  mapping `classe` de la desserte, logique de cache/idempotence, reprojection/clip — via
  `testthat::local_mocked_bindings()` pour simuler les retours `happign`/`osmdata` (petits `sf`
  fixtures), sans réseau.
- **Intégration (réseau, opt-in)** : sur une **micro-AOI** versionnée, appels réels IGN/OSM,
  `skip_if_offline()` + garde `FORETACCESS_RUN_ONLINE_TESTS=TRUE` (comme le garde-fou PostGIS) ;
  ne tourne pas en CI par défaut (ou job dédié « online »).
- Enchaînement `acquire_inputs()` → `preprocess()` (Lot 1) sur les fixtures.

---

## 7. Fichiers (proposition)

```
inst/datasources/FR.json     → services (ign_wfs, ign_wms) + couches (dem, roads, bdforet_v2,
                                cadastre) ; endpoints IGN Géoplateforme
R/datasources.R              → résolveur (get_country_config/get_data_source/get_layer_service)
R/acquire.R                  → acquire_inputs() (orchestrateur) + classe foretaccess_inputs
R/acquire-ign.R              → acquire_mnt / acquire_desserte / acquire_foret / acquire_cadastre
R/acquire-osm.R              → acquire_obstacles (osmdata)
tests/testthat/test-datasources.R, test-acquire-*.R (mocks), test-acquire-online.R (opt-in)
```

---

## 8. Risques & mitigations

| Risque | Impact | Mitigation |
|---|---|---|
| Indispo/latence Géoplateforme ou OSM | Acquisition échoue | Messages ciblés ; cache ; retries ; tests réseau opt-in (pas en CI par défaut) |
| Mapping `classe` desserte (BD TOPO → route/piste/dfci) | Desserte mal classée | Règles explicites documentées (§10 Q2) ; **DFCI** peut nécessiter une source dédiée |
| `happign`/`osmdata` hors du cœur | Install cassée si Imports | Mettre en **Suggests** + `requireNamespace()` |
| Volume depuis MNH (phase 2) | Modélisation non triviale | Repoussé ; cadré dans une spec ultérieure |
| BD Forêt v3 non confirmée | Couche inexistante | v2 d'abord ; v3 avec repli v3→v2 quand validée |
| Tests réseau flaky en CI | CI rouge intermittente | Unitaires mockés en CI ; intégration réseau opt-in/manuelle |

---

## 9. Definition of Done

- [ ] Spec validée (ce fichier) + questions §10 tranchées.
- [ ] `FR.json` + résolveur + `acquire_inputs()` et fonctions par source implémentés.
- [ ] Tests unitaires mockés verts en CI ; test d'intégration réseau opt-in documenté.
- [ ] `lintr`/`testthat`/`R CMD check` OK ; `happign`/`osmdata` en Suggests.
- [ ] Enchaînement `acquire_inputs()` → `preprocess()` démontré sur une micro-AOI.
- [ ] Doc d'usage (roxygen + article pkgdown « Acquérir depuis une AOI ») ; `NEWS.md`.
- [ ] Branche dédiée + PR + revue ; commits atomiques.

---

## 10. Questions ouvertes (à trancher avant codage)

1. **Cadastre** : source IGN WFS `PARCELLAIRE_EXPRESS` (proposé, cohérent avec le reste happign)
   ou API **Etalab** `cadastre.data.gouv.fr` (comme le fait aussi nemeton) ?
2. **Mapping `classe` de la desserte** (BD TOPO `troncon_de_route`) vers {route, piste, dfci} :
   quelles règles ? (p. ex. `nature`/`importance` → route vs piste ; **DFCI** rarement
   distinguable dans BD TOPO → source/attribut dédié ou classe optionnelle au départ ?)
3. **Obstacles OSM** : quel jeu de features par défaut ? (proposé : `building` + surfaces d'eau
   `natural=water`/`waterway`) — en ajouter (falaises, voies ferrées) ?
4. **Emprise des requêtes** : buffer par défaut autour de l'AOI (`buffer_m`) pour capter la
   desserte hors emprise stricte — valeur par défaut (p. ex. 0 vs 100 m) ?
