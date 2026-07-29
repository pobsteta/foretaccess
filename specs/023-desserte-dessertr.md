# specs/023 — Remplacement d'ALSroads par dessertR (desserte LiDAR)

> **Statut** : **VALIDÉE — GO PRODUCTION** (décisions §7 prises par l'utilisateur
> le 2026-07-28). `dessertR` **remplace** ALSroads comme moteur LiDAR **par défaut
> et de production** ; ALSroads est déprécié (repli de transition puis retrait).
> Fait suite aux specs [020](020-desserte-lidar-alsroads.md) et
> [021](021-qualification-desserte-als.md). Version cible : `1.26.0` (feat) +
> **ADR-009** (swap de dépendance LiDAR). Implémentation : **Phase A**.

## 1. Le problème que ça résout

Le chemin LiDAR de foretaccess (`acquire_desserte_lidar()`, `qualifier_desserte()`)
repose sur **ALSroads** (`r-lidar-lab/ALSroads` v0.2.0), qui est :

- un **proof-of-concept non maintenu** (dernière activité upstream ancienne) ;
- **calibré Québec/MFFP**, pas France — cause documentée d'un faux négatif
  historique (Chastel-Nouvel 0/6 en v1.15.0, cf. spec 020 §6bis et mémoire
  `alsroads-mnt-1m`) ;
- en **repositionnement libre**, il accroche des linéaires parallèles (fossés,
  cloisonnements) — problème connu de la méthode appliquée hors contexte.

**`dessertR`** (`pobsteta/dessertR`, v1.0.0, GPL-3, noyau Rust extendr) est une
**réimplémentation française de la même méthode** (Roussel et al. 2022,
`doi:10.1016/j.jag.2022.103020` — la base théorique d'ALSroads), **maintenue**,
et fonctionnellement **sur-ensemble** de ce que foretaccess consomme d'ALSroads.

## 2. Ce que foretaccess consomme d'ALSroads (périmètre à remplacer)

`acquire_desserte_lidar(desserte, las_source, mnt, …)` (`R/desserte_lidar.R`)
wrappe `ALSroads::measure_road` par tronçon et produit, en plus des colonnes de
`acquire_desserte()` :

| Colonne foretaccess | Source ALSroads |
|---|---|
| `largeur_carrossable_m` | `DRIVABLEWIDTH` |
| `largeur_plateforme_m` | `ROADWIDTH` |
| `pente_pct` | calculée dans foretaccess (`.pente_en_long_geom`) |
| `etat_classe` (entier 4 classes) | `CLASS` |
| `score_lidar` | `SCORE` |

Repli **NDP 0** (pas de LiDAR/ALSroads) : géométrie BD TOPO inchangée, ces
colonnes à `NA`. Consommateurs : `places_depot()` (largeur roulable discriminante)
et `qualifier_desserte()` (spec 021 : `etat_disparue = 4L` retire les tronçons de
`CLASS >= seuil`).

## 3. Correspondance ALSroads → dessertR (vérifiée sur les signatures)

| Besoin | dessertR |
|---|---|
| Largeur roulable (chaussée) | `dsr_measure(trace, mnt, methode_largeur = "chaussee")$stations$LARGEUR_ROULABLE` ; résumé `resume$LARGEUR_ROULABLE_MED` |
| Largeur plateforme | `dsr_measure(…, methode_largeur = "planeite")` (plateforme entière) |
| Pente longitudinale | `dsr_measure()$stations$PENTE_LONG` / `resume$PENTE_LONG_MOY|MAX` (plus besoin de `.pente_en_long_geom`) |
| État (4 classes) | `dsr_etat(sigma_geo, sigma_surf)` → `en_service` / `abandonnee` / `trouee` / `hors_route` (croisement des deux canaux, plus fin que `CLASS`) |
| Recalage centerline | `dsr_repositionner(reseau, sigma_geo, deviation_max = 10)` — **BD TOPO autoritaire**, aucun tronçon perdu |
| Catalogue / DTM fin | `dsr_catalog(laz, mnt, mnh)`, `dsr_grille_reference(mnt, res = 1)`, `dsr_layers_dtm()` |
| Canaux conductivité | `dsr_conductivite()` (→ `sigma_geo`), `dsr_layers_pc()` + `dsr_sigma_surf()` (→ `sigma_surf`) |
| *(au-delà)* praticabilité grumier | `dsr_trafficability(stations, dsr_seuils_grumier())` → `APTE_GRUMIER`, motif + localisation, gabarit vertical **et** latéral |
| *(au-delà)* détection hors-BD TOPO | `dsr_detecter()`, `dsr_reseau()` |

**Grandeurs bonus non fournies par ALSroads** et directement utiles : `DEVERS`,
`FOSSES` (0/1/2), `RAYON_COURBURE` (+ `_P05`), `SINUOSITE`, gabarit libre vertical,
`CONFIANCE_MNT`, `DEPLACEMENT`.

## 4. API proposée (si go) — contrat de colonnes PRÉSERVÉ

Pour minimiser le rayon d'impact, **on garde les noms de colonnes actuels** ;
l'adaptateur mappe la sortie dessertR dessus. `acquire_desserte_lidar()` gagne un
argument `mnh` optionnel et un moteur sélectionnable.

```r
acquire_desserte_lidar(
  desserte, las_source, mnt,
  mnh = NULL,                    # NOUVEAU : MNH (lidar_mnh) pour sigma_surf ; sinon derive du nuage
  moteur = c("dessertr", "alsroads"),  # NOUVEAU : dessertR par defaut si installe
  crs = 2154, cache_dir = tempdir(), dtm_res = 1, long_min_m = ..., deviation_max = 10)
# -> sf : geometrie RECALEE (dsr_repositionner) + colonnes INCHANGEES
#    largeur_carrossable_m, largeur_plateforme_m, pente_pct, etat_classe, score_lidar
#    (+ NOUVELLES colonnes optionnelles : devers, fosses, rayon_courbure_p05,
#     apte_grumier, motif_inaptitude — si moteur = "dessertr")
```

**Agrégation station → tronçon.** dessertR mesure par **station** (points le long
du tracé) ; foretaccess porte un attribut **par tronçon**. L'adaptateur agrège via
`resume` (médiane de largeur, pente moy/max, rayon P05) — dessertR fournit déjà ces
résumés par tracé.

**Remapping d'état (spec 021).** `etat_classe` passe de `CLASS` (1–4) aux 4 états
dessertR. Mapping proposé (à valider) :

`dsr_etat` produit un **raster catégoriel** à 4 niveaux (codes NATIFS dessertR,
vérifiés dans `R/state.R`) ; l'adaptateur l'échantillonne le long du tronçon
(classe dominante) → `etat_classe`, et expose aussi le libellé brut `etat_dessertr` :

| Code natif dessertR | `etat` | `sigma_geo` × `sigma_surf` | Sens |
|---|---|---|---|
| 1 | `en_service` | fort × fort | route active, emprise dégagée |
| 2 | `abandonnee` | fort × faible | **route recolonisée** (empreinte présente, surface fermée) |
| 3 | `trouee_sans_route` | faible × fort | trouée sans empreinte de route |
| 4 | `hors_route` | faible × faible | ni empreinte ni emprise |

**Attention sémantique** : l'ordinal dessertR n'est **pas** le « de plus en plus
disparue » d'ALSroads. Pour `qualifier_desserte()`, la « disparition » d'une route
= `abandonnee` (2) et/ou `hors_route` (4), pas un simple seuil `>=`. On remplace
donc le critère `etat_classe >= etat_disparue` par un **ensemble d'états** :
`etats_disparus = c("abandonnee", "hors_route")` (défaut, sur le libellé
`etat_dessertr`), plus lisible et calibrable en Phase B. L'entier `etat_classe`
reste exposé pour compatibilité/inspection, mais n'est plus le critère.

## 5. Chaîne d'implémentation (adaptateur, `R/desserte_lidar.R`)

Nouveau chemin interne `.desserte_lidar_dessertr()` parallèle à l'actuel :

1. `dsr_catalog(laz = las_source, mnt = mnt, mnh = mnh)` + `dsr_grille_reference(mnt, res = dtm_res)`.
2. `sigma_geo <- dsr_conductivite(dsr_layers_dtm(mnt, grille))` ;
   `sigma_surf <- dsr_sigma_surf(dsr_layers_pc(dalle, grille))`.
3. `recale <- dsr_repositionner(desserte, sigma_geo, deviation_max = deviation_max)`.
4. par tronçon (≥ `long_min_m`, sous couverture de dalle — garde
   `.couverture_dalles()` réutilisée) : `m <- dsr_measure(recale[i,], mnt, methode_largeur = "chaussee")`.
5. `etat <- dsr_etat(sigma_geo, sigma_surf)` échantillonné le long du tronçon → `etat_classe`.
6. `apte <- dsr_trafficability(m$stations, dsr_seuils_grumier())` (colonnes bonus).
7. Assemble le contrat de colonnes §4 ; **repli NDP 0 inchangé**.

Sélection du moteur : `moteur = "dessertr"` si `requireNamespace("dessertR")`,
sinon repli `"alsroads"` (transition), sinon NDP 0. Les deux moteurs restent des
**dépendances optionnelles non déclarées** (comme aujourd'hui, cf. spec 020 §5).

## 6. Décisions structurantes (→ ADR-009)

1. **Swap de dépendance** : `ALSroads` + `lidR` (optionnelles, hors-CRAN,
   non maintenues) → `dessertR` (optionnelle, r-universe, **maintenue par le même
   auteur**, noyau Rust propre). Règle 1 respectée : la logique métier LiDAR reste
   **hors** de foretaccess (on consomme le paquet), comme pour ALSroads.
2. **Contrat de colonnes préservé** → `places_depot()` et le reste inchangés ;
   seule la source des valeurs change.
3. **Repositionnement contraint par défaut** (`deviation_max`, BD TOPO autoritaire)
   → corrige le défaut d'accroche aux parallèles d'ALSroads.
4. **Transition douce** : ALSroads gardé en repli le temps d'une phase B de
   validation ; dépréciation ensuite.
5. **Noyau Rust** : foretaccess dépend d'un paquet à crate compilé — implication CI
   (binaire r-universe ou build source). À traiter dans l'ADR-009.

## 7. Décisions (prises le 2026-07-28)

**GO PRODUCTION.** `dessertR` devient le moteur LiDAR **par défaut** ; ALSroads est
gardé en repli de transition (Phase A) puis retiré.

| # | Question | Décision |
|---|---|---|
| 1 | Statut | **Production** — dessertR n'est plus traité comme expérimental ; il **entre en production** comme moteur par défaut. ALSroads déprécié. |
| 2 | Entrée `mnh` | **OK** — `mnh` (via `lidar_mnh`) devient une entrée de `acquire_desserte_lidar()`. |
| 3 | Colonnes bonus | **Oui, dès la Phase A** — `devers`, `fosses`, `rayon_courbure_p05`, `apte_grumier`, `motif_inaptitude` exposées immédiatement. |
| 4 | Trafficabilité grumier | **Branchée** — `dsr_trafficability()` alimente `qualifier_desserte()` / `CL_SVAC` (spec 022), pas seulement en sortie brute. |

**Nuance de périmètre.** dessertR *l'outil* est en production ; l'**adaptateur
foretaccess** est neuf → il reste une **Phase B de validation de l'intégration**
(banc, non un doute sur dessertR) avant de retirer ALSroads.

- **Phase A (implémentation)** : adaptateur `.desserte_lidar_dessertr()` **moteur par
  défaut**, colonne `mnh`, colonnes bonus + `apte_grumier`, contrat préservé, repli
  NDP 0 ; ALSroads en repli explicite (`moteur = "alsroads"`).
- **Phase B (validation de l'intégration)** : banc dessertR sur dalle réelle
  (Meisenthal / Chastel-Nouvel) → largeurs, état, `apte_grumier` vs invariants
  (spec 020 §6bis) ; publier les chiffres. **FAITE en v1.26.1** sur la dalle
  `LHD_FXX_0737_6385` (Chastel-Nouvel), banc `data-raw/phaseB_dessertr.R` :
  39/44 mesurés, 0 échec, largeurs 1,68-7,66 m ; **trois défauts d'intégration
  trouvés et corrigés** (`apte_grumier`, `score_lidar`, `etat_classe` tous `NA`) ;
  21/21 invariants verts dont 9 de complétude.
- **Phase C** : retrait d'ALSroads (`moteur` et code) une fois B publiée.
  **FAITE en v1.27.0** : chemin NDP 1 ALSroads, `.alsroads_dispo()` et le banc
  `validation_desserte_lidar.R` supprimés ; `moteur` conservé en
  `c("auto", "dessertr")` (bump **minor**, pas major : `moteur = "alsroads"`
  comme option publique n'a existé que dans la v1.26.0, jamais releasée).

## 8. Critères d'acceptation (si go)

- `acquire_desserte_lidar(moteur = "dessertr")` produit le **même contrat de
  colonnes** que l'actuel (types, NA en NDP 0), + colonnes bonus optionnelles.
- Repli NDP 0 et pré-filtre de couverture (`.couverture_dalles()`) **inchangés** ;
  pas de segfault (spec 020 §6quater).
- `qualifier_desserte(etat_disparue = 4L)` fonctionne sur le nouvel `etat_classe`
  (mapping §4) sans changement d'API.
- Banc Phase B : accord largeur borné (cible RMSE < un seuil à fixer avec l'oracle),
  matrice de confusion d'état publiée.
- ADR-009 rédigé ; `dessertR` en `Additional_repositories` (r-universe), non déclaré
  en Suggests (comme ALSroads).

## 9. Ce que ça n'est PAS

- Pas une fusion de noyaux Rust : foretaccess **consomme** dessertR, ne l'inline pas.
- Pas un changement des moteurs terrestres / câble / DFCI (règle 1).
- `dessertR` *l'outil* est **en production** (décision §7.1) ; seule l'**intégration
  foretaccess** (adaptateur neuf) passe une Phase B de validation avant retrait
  d'ALSroads. Le gain : **calibrage français + maintenance + sur-ensemble
  fonctionnel** (largeur, état, devers, fosses, courbure, gabarit, aptitude grumier).

## 10. Sources

- Roussel et al. (2022), *ISPRS J. Appl. Earth Obs. Geoinf.*,
  `doi:10.1016/j.jag.2022.103020` (base commune ALSroads / dessertR).
- `pobsteta/dessertR` v1.0.0 (README, signatures `R/measure.R`, `R/state.R`,
  `R/pathfinder.R`, `R/trafficability.R`, `R/catalog.R`, `R/conductivity.R`).
- foretaccess : `R/desserte_lidar.R`, `R/desserte_qualif.R`, specs 020 / 021 / 022.
