# specs/019 — Acquisition du volume sur pied (MNH LiDAR → P1 → `pre$volume`)

> **Statut** : **validé** (décisions §10 tranchées le 2026-07-22). Le passthrough ForêtAccess
> (§6) est à implémenter ; la partie Nemeton (§5–6) reste descriptive (règle 6).
> **Type** : lot **dédié**, en amont du prétraitement (alimente `specs/001` via `pre$volume`).
> Complète le Lot Acquisition (`specs/010`), dont il lève l'écart « Phase 2 (MNH LiDAR →
> volume) reste hors périmètre ».
> **Dépend de** : `volume_depuis_p1()` (v1.7.0, livré), `acquire_inputs()` (v0.11.0),
> l'indicateur **P1** de **Nemeton** (`nemeton::indicateur_p1_volume()`).
> **Prépare** : le volet câble (`specs/004`/`005`) — sans volume, `volume_m3` et l'IPC des
> lignes valent `NA` et la sélection neutralise ces critères (CA-5.2).
> **ADR liés** : ADR-001 (frontière R↔Rust ; ici frontière **inter-paquets** ForêtAccess↔Nemeton),
> ADR-002 (stockage/cache), ADR-004 (découplage, pas de reprojection implicite), ADR-003 (config).
> **Règles strictes** : 1 (la logique métier reste chez son propriétaire — le **calcul** du
> volume est un indicateur d'inventaire, domaine de **Nemeton**), 6 (aucune écriture dans un
> repo frère).

---

## 1. Contexte

Le moteur câble et la sélection (Lot 5) lisent `pre$volume`, un **raster de volume sur pied
en m³/ha** aligné sur la grille du MNT. `potentiel_cable()` le somme sur les cellules
forestières qu'une ligne couvre pour en tirer **Vtot** (volume de la ligne) et l'**IPC**
(indice de production câble = Vtot / longueur, `src/rust/src/cable/scan.rs`). ForêtAccess ne
**calcule pas** ce volume : c'est une entrée.

`volume_depuis_p1()` (v1.7.0) pose la **dernière brique géométrique** : projeter sur la grille
du MNT un `sf` d'unités portant un volume en m³/ha. Reste à **produire ce `sf`**, c'est-à-dire
la chaîne d'acquisition :

```
MNH LiDAR HD  ──►  CHM assaini  ──►  P1 (volume m³/ha par unité)  ──►  raster  ──►  pre$volume
 (IGN, dalle)      sanitize_chm      indicateur_p1_volume            volume_depuis_p1
```

**Tout le milieu de chaîne vit déjà chez Nemeton** (constat §2). Ce lot ne consiste donc
**pas** à ré-implémenter l'acquisition MNH ni le calcul P1 dans ForêtAccess — ce serait
dupliquer Nemeton et violer la règle 1. Il consiste à **câbler proprement l'injection** du
volume dans ForêtAccess, et à trancher **où** chaque maillon vit.

---

## 2. Constat : ce qui existe déjà (audit du 2026-07-22)

### Côté ForêtAccess
- `acquire_mnt()` télécharge le **MNT LIDAR HD** (couche `IGNF_MNT-LIDAR-HD`, le **sol**) fin
  puis l'agrège, sur l'**emprise bufferisée** (AOI + `buffer_m`, défaut 100 m). Cache :
  `lidar_mnt_aoi_buffer.tif`.
- `acquire_inputs()` **n'a pas** de slot `volume` : sa sortie est
  `{mnt, desserte, foret, obstacles, parcellaire, aoi, meta}`. `preprocess()` **accepte** déjà
  `volume=` (facultatif) — le maillon manquant est côté acquisition, pas prétraitement.

### Côté Nemeton (lecture seule)
- `nemetonshiny` télécharge le **MNH LiDAR HD** (couche `IGNF_MNH-LIDAR-HD`, la **canopée**)
  via `download_ign_lidar_hd(bbox, cache_dir, product = "mnh")`, cache `lidar_mnh/chm.tif`,
  avec repli `lasR` sur le nuage de points quand les dalles pré-rasterisées manquent.
- `nemeton::sanitize_chm()` assainit le CHM (5 passes de masquage).
- `nemeton::indicateur_p1_volume()` calcule **P1 = volume sur pied m³/ha** par unité, depuis
  un inventaire (espèce IFN, DBH, densité, tarif) **ou depuis le CHM** (`chm=`, hauteur
  dominante → allométrie → auto-remplissage densité).
- `nemetonshiny/R/service_accessibility.R` **orchestre déjà ForêtAccess** : il appelle
  `foretaccess::acquire_mnt/desserte/foret`, `preprocess()`, puis les moteurs terrestres.

### Le vrai trou
`service_accessibility.R` appelle `preprocess(mnt, desserte, foret)` **sans `volume=`**. Donc
même dans l'app, aujourd'hui, `volume_m3`/IPC seraient `NA`. Le MNH est chargé pour d'**autres**
indicateurs, jamais routé vers le câble.

---

## 3. Deux pièges à écarter d'emblée

### 3.1 MNT ≠ MNH — « étendre `lidar_mnt` » ne produit pas de volume
`lidar_mnt` (ce que ForêtAccess charge déjà, AOI+buffer) est le **modèle de terrain (sol)**.
Le volume a besoin de la **hauteur de couvert** — le **MNH** (`IGNF_MNH-LIDAR-HD`), produit
**distinct**. On ne dérive **aucun** volume du MNT. « Réutiliser le LiDAR déjà chargé » ne peut
donc viser que le **MNH** (`lidar_mnh/chm.tif`, côté Nemeton), pas `lidar_mnt`.

### 3.2 P1 est par **unité**, pas par pixel
`indicateur_p1_volume()` rend un `sf` d'**unités** (parcelles / placettes) portant un m³/ha, pas
un raster continu. `volume_depuis_p1()` rasterise ce `sf`. Le cadastre de `acquire_cadastre()`
n'a **pas** les attributs d'inventaire (espèce/DBH/densité) : ForêtAccess ne **peut pas**
calculer P1. Confirme que le calcul reste chez Nemeton.

---

## 4. Décision d'emprise (réponse à « AOI ou AOI+Buffer ? »)

**Le raster de volume doit couvrir l'emprise BUFFERISÉE (AOI + `buffer_m`), pas l'AOI stricte.**

Raison : ForêtAccess calcule sur le halo. Une ligne de câble part de la desserte et sa
couverture (pêchage latéral `c_l_hor` inclus) **déborde dans le buffer** ; le noyau Rust somme
le volume sur **toutes** les cellules forestières couvertes, y compris hors AOI stricte, et
traite un `NaN` comme **0** (`if v[c].is_nan() { 0.0 }`, `scan.rs`). Un volume tronqué à l'AOI
**sous-estime** donc Vtot et l'IPC des lignes de bord — silencieusement.

Conséquence concrète : le MNH doit être fetché, et P1 calculé, sur les unités intersectant
**AOI+buffer**. En pratique le fetch IGN se fait par **dalles de 1 km** : la mosaïque couvrant
la bbox de l'AOI **déborde déjà** largement un buffer de 100 m — « étendre » le téléchargement
est le plus souvent un **no-op sur les tuiles fetchées**. Ce qui doit changer n'est pas le
volume téléchargé mais le **découpage** : cropper le volume sur **AOI+buffer**, cohérent avec
`acquire_mnt()` (même emprise, ADR-004 exige d'ailleurs CRS + grille identiques).

> Règle d'or : le volume s'aligne sur `pre$mnt` (même CRS, même grille, même emprise
> bufferisée). `volume_depuis_p1()` le garantit déjà en rasterisant **sur `mnt`**.

---

## 5. Décision d'architecture : où vit chaque maillon

Deux options, une retenue.

**Option A — ForêtAccess acquiert et calcule.** `acquire_inputs()` fetche le MNH, appelle
Nemeton pour P1, rasterise. → crée une dépendance **dure** ForêtAccess→Nemeton, **duplique** le
fetch MNH que l'app fait déjà, et met du calcul d'inventaire dans ForêtAccess (contre règle 1).
**Rejetée.**

**Option B — Nemeton produit, ForêtAccess consomme (RETENUE).**
- **Nemeton / nemetonshiny** garde le MNH → CHM → P1 (déjà en place) et le calcule sur
  **AOI+buffer** (§4).
- **ForêtAccess** expose `volume_depuis_p1()` (fait) et ouvre un **passthrough** : un argument
  `volume` sur `acquire_inputs()`, simplement relayé dans la sortie et transmis à `preprocess()`.
  Aucune dépendance Nemeton, aucun fetch MNH côté ForêtAccess.
- **Le raccord** vit dans l'orchestrateur (`service_accessibility.R`, côté Nemeton, **hors de
  ce dépôt** — règle 6) : une ligne
  `preprocess(..., volume = foretaccess::volume_depuis_p1(p1_sf, mnt))`.

Répartition = frontière inter-paquets d'ADR-001 transposée : Nemeton calcule l'indicateur,
ForêtAccess consomme un vecteur/raster typé, personne n'empiète.

---

## 6. Périmètre

### Dans le périmètre (ForêtAccess, ce dépôt)
- **`acquire_inputs(volume = NULL)`** : nouvel argument facultatif. Accepte `NULL` (défaut,
  comportement actuel), un `SpatRaster`/chemin de raster **déjà en m³/ha** (aligné ou
  réaligné sur `pre$mnt`), ou un `sf` d'unités **+ un champ** → passé à `volume_depuis_p1()`.
  Relayé dans `out$volume`, documenté comme devant couvrir l'emprise bufferisée.
- **Contrat d'emprise** vérifié : si un raster de volume est fourni, avertir (pas abort) quand
  il ne couvre pas toute l'emprise bufferisée (bords à `NA` → volume sous-estimé, §4).
- **Doc** : vignette d'acquisition + `?acquire_inputs` montrant le branchement P1 de bout en
  bout (`\dontrun`, pas de dépendance Nemeton en dur).

### Hors périmètre (Nemeton, autre dépôt — spec **descriptive** seulement)
- Le fetch MNH sur **AOI+buffer**, l'assainissement CHM, le calcul P1 : **restent chez Nemeton**.
- Le one-liner de raccord dans `service_accessibility.R`. **À implémenter par une session
  Nemeton**, jamais depuis une session ForêtAccess (règle 6). Ce lot le **spécifie**, ne le code pas.

---

## 7. Critères d'acceptation

- **CA-19.1** `acquire_inputs(volume = NULL)` : sortie **identique** à l'existant (non-régression).
- **CA-19.2** `acquire_inputs(volume = <raster m³/ha>)` : `out$volume` est un `SpatRaster`
  aligné sur `out$mnt` (CRS + grille), nommé `volume`, prêt pour `preprocess()`.
- **CA-19.3** `acquire_inputs(volume = <sf>, champ_volume = "P1")` : rasterise via
  `volume_depuis_p1()` sur la grille du MNT bufferisé.
- **CA-19.4** Un volume ne couvrant pas toute l'emprise bufferisée **avertit** (message `cli`
  chiffré : % de cellules à `NA`), sans échouer — l'utilisateur décide.
- **CA-19.5** CRS du volume ≠ MNT → **abort** (pas de reprojection implicite, ADR-004).
- **CA-19.6** Bout-en-bout documenté : `acquire_inputs(volume=)` → `preprocess()` →
  `potentiel_cable()` rend des `volume_m3`/IPC **non-`NA`** sur le jeu jouet.

---

## 8. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Volume tronqué à l'AOI → IPC de bord sous-estimé | Emprise bufferisée imposée (§4), CA-19.4 avertit. |
| Confusion MNT/MNH | §3.1 ; le passthrough n'accepte qu'un volume **m³/ha**, jamais un MNS/MNT. |
| Double fetch MNH (app + ForêtAccess) | Option B : ForêtAccess ne fetche **rien**, consomme le P1 de Nemeton. |
| Unité fausse (m³ absolu au lieu de m³/ha) | `volume_depuis_p1()` documente et suppose m³/ha ; CA à ajouter côté Nemeton (P1 est déjà m³/ha). |
| Dépendance croisée ForêtAccess↔Nemeton | Aucune dep dure : le raccord vit dans l'orchestrateur (nemetonshiny). |

---

## 9. Definition of Done

- [ ] `acquire_inputs(volume=, champ_volume=)` livré, CA-19.1→19.6 couverts.
- [ ] Tests `testthat` (passthrough raster, passthrough sf, avertissement couverture, garde CRS).
- [ ] `R CMD check` OK en CI ; couverture ≥ `main` ; chaînes ASCII.
- [ ] Vignette d'acquisition : section « Volume via P1 (Nemeton) » avec l'emprise bufferisée.
- [ ] `NEWS.md` + `PLAN.md` ; `specs/010` : écart « Phase 2 volume » marqué **levé**.
- [ ] **Note pour Nemeton** (dans ce fichier, §5–6) : fetch MNH + P1 sur **AOI+buffer**, raccord
      `volume = foretaccess::volume_depuis_p1(...)` dans `service_accessibility.R`. À porter par
      une session Nemeton.

---

## 10. Décisions (tranchées 2026-07-22)

1. **Signature** : un seul argument `volume` **polymorphe** (raster `SpatRaster` | chemin de
   raster | `sf` d'unités), + `champ_volume = "P1"` utilisé **seulement** quand `volume` est un
   `sf` (délégué à `volume_depuis_p1()`). Une porte d'entrée, pas deux.
2. **Réalignement** : CRS différent du MNT → **abort** (ADR-004, CA-19.5). Même CRS mais grille
   différente → **rééchantillonnage** sur la grille du MNT (le volume est une densité m³/ha,
   `terra::resample` bilinéaire acceptable) **avec avertissement** `cli`. CA-19.2 étendu.
3. **Pas d'`acquire_volume()` natif** pour l'instant : l'inventaire reste le domaine de Nemeton.
   À rouvrir seulement si un usage ForêtAccess pur (hors app) le réclame. Question 3 de §6 close.
