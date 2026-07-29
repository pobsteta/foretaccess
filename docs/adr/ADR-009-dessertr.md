# ADR-009 — Moteur LiDAR de desserte : `dessertR` remplace `ALSroads`

- **Statut** : accepté (décision utilisateur du 2026-07-28)
- **Date** : 2026-07-28
- **Décideurs** : Pascal Obstetar
- **Sources** : `specs/023-desserte-dessertr.md` ; specs 020 / 021 / 022 ;
  `R/desserte_lidar.R`, `R/desserte_qualif.R` ; ADR-001, ADR-004

## Contexte

Le chemin de correction/qualification de desserte par LiDAR aérien (NDP 1)
reposait sur **`ALSroads`** (`r-lidar-lab/ALSroads` v0.2.0) — proof-of-concept
**non maintenu**, **calibré Québec/MFFP** (faux négatif documenté sur données
françaises, spec 020 §6bis), et dont le repositionnement libre accroche des
linéaires parallèles (fossés, cloisonnements).

`dessertR` (`pobsteta/dessertR` v1.0.0, GPL-3, noyau Rust `extendr`) est une
réimplémentation **française** de la même méthode (Roussel et al. 2022,
`doi:10.1016/j.jag.2022.103020` — base théorique d'ALSroads), **maintenue** (même
auteur que foretaccess), et fonctionnellement **sur-ensemble** du besoin. Décision
utilisateur : dessertR **entre en production** (plus expérimental).

## Décision

- **`dessertR` devient le moteur LiDAR par défaut** de `acquire_desserte_lidar()` /
  `qualifier_desserte()`. `ALSroads` est **déprécié** : gardé en repli explicite
  (`moteur = "alsroads"`) le temps de la Phase B, puis retiré (Phase C).
  **Fait** : Phase B en v1.26.1, Phase C (retrait effectif) en v1.27.0.
- **Dépendance optionnelle, non déclarée en Suggests** (comme ALSroads, spec 020
  §5) : accédée dynamiquement. **Correction v1.26.1** : dessertR n'est publié sur
  aucun r-universe — l'installation passe par `remotes::install_github("pobsteta/dessertR")`,
  et il n'y a donc pas d'`Additional_repositories` à déclarer. Règle 1 : la logique métier LiDAR reste **hors** de foretaccess
  (on consomme dessertR, on ne l'inline pas ; pas de fusion de noyaux Rust).
- **Contrat de colonnes préservé** (`largeur_carrossable_m`, `largeur_plateforme_m`,
  `pente_pct`, `etat_classe`, `score_lidar`) → `places_depot()` et l'aval
  inchangés ; l'adaptateur mappe la sortie dessertR (par station → agrégée par
  tronçon via `resume`) sur ces noms.
- **Entrée `mnh`** ajoutée (via `lidar_mnh`) pour le canal `sigma_surf`.
- **Colonnes bonus dès la Phase A** : `devers`, `fosses`, `rayon_courbure_p05`,
  `apte_grumier`, `motif_inaptitude`.
- **Trafficabilité grumier branchée** : `dsr_trafficability()` alimente
  `qualifier_desserte()` / `CL_SVAC` (spec 022).
- **Repositionnement contraint par défaut** (`dsr_repositionner`, `deviation_max`,
  BD TOPO autoritaire en planimétrie).

## Conséquences

- Gain : calibrage français, maintenance, sur-ensemble fonctionnel (largeur, état,
  devers, fosses, courbure, gabarit libre, aptitude grumier), repositionnement
  contraint qui ne dérive plus vers les parallèles.
- **CI / build** : foretaccess dépend d'un paquet à **crate Rust compilé**. dessertR
  étant optionnel et non déclaré, la CI foretaccess **n'a pas** à le compiler (le
  chemin NDP 1 reste hors CI, comme aujourd'hui) ; l'installation revient à
  l'utilisateur (binaire r-universe ou build source). À réévaluer si on veut un
  test d'intégration dessertR en CI (nécessiterait la toolchain + des dalles).
- **Sémantique d'état** : `etat_classe` provient désormais de `dsr_etat` (4 états
  croisant `sigma_geo` × `sigma_surf`) au lieu du `CLASS` d'ALSroads ; mapping
  documenté (spec 023 §4) pour préserver `qualifier_desserte(etat_disparue = 4L)`.
- **Repli NDP 0 inchangé** (pas de LiDAR/moteur → colonnes `NA`). Le pré-filtre de
  couverture est conservé côté dessertR sous la forme de `.troncons_couverts()`
  (emprise = bbox du MNT) ; `.couverture_dalles()`, qui dérivait l'emprise d'un
  `LAScatalog` lidR, part avec ALSroads en Phase C.
- Phase B (validation de l'intégration) requise avant retrait d'ALSroads.
  **Faite en v1.26.1** : elle a révélé trois défauts d'intégration (trafficabilité
  non branchée, `CONFIANCE_MNT` jamais demandé, extraction d'état cassée) — ce qui
  justifie rétrospectivement d'avoir conditionné la Phase C à un banc réel.

## Alternatives écartées

- **Garder ALSroads** : non maintenu, calibré Québec — dette et faux négatifs.
- **Réimplémenter la méthode dans foretaccess** : viole la règle 1 (logique métier
  LiDAR hors package) et duplique dessertR.
- **Inliner le crate Rust de dessertR** : fusion de noyaux rejetée (ADR-004,
  découplage) ; on dépend du paquet, on ne l'absorbe pas.
