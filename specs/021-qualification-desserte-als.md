# Lot 19 — Qualification de la desserte forestière par données LiDAR HD

> **Statut** : **Étape 1 implémentée** (`qualifier_desserte()`, v1.17.0) — correction
> géométrique déterministe (relocalisation + largeur mesurée) sur le socle
> `acquire_desserte_lidar()` (spec 020). **Étape 2 (détection IA) et le portage RVT
> en Rust restent des jalons de recherche** (J3–J5, §5–7), conditionnés à la vérité
> terrain DESSOPT et à des contacts institutionnels (§9).
> **Type** : lot autonome, optionnel, en amont du pipeline
> **Dépendances** : aucune sur les moteurs existants (skidder, porteur, DFCI, câble)
> **Produit** : une couche `desserte` enrichie, conforme au contrat d'entrée actuel de `preprocess()`

---

## 1. Contexte et problème

Dans ForêtAccess, tout part de `desserte.gpkg`. Les quatre moteurs en dépendent :

- skidder, porteur et DFCI partagent un service de propagation *least-cost* **depuis la desserte** ;
- le module câble tire ses lignes **par pixel de route**.

Or la desserte n'est jamais calculée : elle est **déclarée**, typiquement importée de la BD Topo IGN. Toute erreur de position, de largeur, de classe ou d'existence se propage intégralement dans les quatre moteurs, sans être détectée par la non-régression (qui valide contre Sylvaccess, c'est-à-dire la **fidélité au modèle**, pas la **justesse terrain**).

Le diagnostic est partagé par les acteurs publics français. Le projet DESSOPT (CNPF-IDF) justifie son existence par le fait que :

- les relevés terrain se font majoritairement au GPS basique / tablette / smartphone, avec des écarts **pluri-métriques** par rapport au RTK ;
- la BD Topo, à précision annoncée métrique, **peut dévier fortement**.

Un décalage de 15 m sur une polyligne représente 15 à 30 % d'un buffer skidder de 50–100 m. C'est le maillon faible actuel de la chaîne.

**Objectif du lot** : produire une desserte *qualifiée* (géométrie relocalisée + attributs mesurés) à partir des données LiDAR HD, sans toucher aux moteurs ni à leur harnais de test.

---

## 2. Verrou levé côté données

L'approche était théorique en France tant que seul le MNT 5 m IGN était disponible. Ce n'est plus le cas : **LiDAR HD couvre désormais le territoire** avec nuages de points classés et MNT 1 m. Les méthodes de caractérisation de desserte par ALS deviennent applicables sur données françaises.

Point d'attention **saisonnalité** : les acquisitions LiDAR HD se font en hiver comme en été. Sous feuillus denses en été, la densité de retours sol s'effondre et le MNT des pistes étroites se dégrade. Conséquence : stratifier tout entraînement / validation par **bloc d'acquisition et par saison**, et remonter la saison comme métadonnée.

---

## 3. Composants réutilisables (état de l'art)

### 3.1 ALSroads — correction et mesure d'une desserte existante
- Package **R** bâti sur **lidR**, intégré à `terra`/`sf` (même stack que ForêtAccess).
- Part d'une carte imprécise et produit par tronçon : géométrie relocalisée, largeur, largeur carrossable, pente, état (en service / abandonnée), classe.
- Erreur de positionnement d'axe annoncée < 3 m dans 95 % des cas.
- Validé au Québec puis sur 8 zones d'étude au Canada (dont Ontario, single-photon LiDAR).
- ⚠️ Se déclare **expérimental / proof of concept**. Calibration **boréale** (chemins larges, graveleux) — à revalider sur terrains français (pentes fortes, pistes étroites, couvert feuillu).
- ⚠️ **Corrige, ne détecte pas** : a besoin d'une carte a priori. Les pistes absentes de la BD Topo resteront absentes.
- Dépôt : https://github.com/r-lidar-lab/ALSroads
- Guide : https://ilythiamorley.github.io/ALSroads_Guide/

### 3.2 Vectorisation topologique (Roussel et al. 2023)
- Produit un réseau vectoriel **topologiquement valide** (connexe, orientable pour le flux) depuis un raster de conductivité ou de probabilité.
- 96 % des routes correctement vectorisées depuis un raster binaire (84 % depuis carte de probabilité), 4 % de faux positifs.
- C'est la brique qui convertit une sortie de CNN (masque) en réseau exploitable par les moteurs.

### 3.3 RVT — visualisations de micro-relief (canaux d'entrée IA)
- **Relief Visualization Toolbox** (ZRC SAZU / Univ. Ljubljana), issu de l'archéologie aérienne : détecte des ruptures linéaires subtiles sous couvert.
- Fournit sky-view factor (SVF), openness ±, local relief model, hillshade multidirectionnel, VAT, dominance locale.
- **Intégralement open source, Apache 2.0** (Python, plugin QGIS, standalone).
- Validé sur terrain français sous couvert (Carnac, Guyot et al. 2018).
- `RVT_py` : https://github.com/EarthObservation/RVT_py — noyau SVF/openness dans `rvt/vis.py`, ~150 lignes utiles.

### 3.4 WhiteboxTools — à écarter pour SVF/openness
- Noyau **open core (MIT)**, écrit en **Rust**, > 450 outils.
- **MAIS** `SkyViewFactor` et `Openness` sont dans le **Whitebox Toolset Extension (WTE), payant et propriétaire**. Inexploitables pour un projet GPL v3 public.
- Restent utiles dans l'open core : `DevFromMeanElev` (z-score local, image intégrale), `MultiscaleTopographicPositionImage`, hillshade, pente, et potentiellement `HorizonAngle` (primitive du SVF — **à vérifier dans l'arbre GitHub**).
- Vérifier le périmètre MIT via l'arbre des sources, jamais via le manuel fusionné `whiteboxgeo.com/manual/`.

### 3.5 Projets institutionnels français — partenaires, pas concurrents
- **DESSOPT** (CNPF-IDF) : détection + optimisation de desserte par LiDAR HD, construit le **jeu de données de référence** (vérité terrain). Aucun livrable public à ce jour. Contact : rubrique DESSOPT sur https://www.cnpf.fr/vos-contacts-l-idf
- **ACCESSFOR** (INRAE + IGN, ADEME, publié 19/06/2026) : cartographie nationale d'accessibilité **s'appuyant sur Sylvaccess**. Territoires dont **PNR Morvan** (recouvrement direct avec le cas de référence ForêtAccess). Cartes publiées sur IGN Ma Carte. Contact : **Sylvain Dupire, LESSEM** (auteur de Sylvaccess). Fournit des **cibles d'agrégation nationales** (skidder 71/8/20/1 ; porteur 59/6/34/1) exploitables comme second oracle.
- **QUALIROAD** : cité en interne (RdV Experts IGN/INRAE/ADEME du 19/05/2026), **aucune trace publique** — à clarifier auprès des intervenants.

---

## 4. Approche recommandée — deux étapes séquentielles

Ne pas commencer par le deep learning. L'étape 1 dé-risque et **finance** l'étape 2 en produisant les labels propres.

### Étape 1 — Correction déterministe (sans apprentissage)
Passer la BD Topo dans un correcteur géométrique type ALSroads sur un massif pilote. Résultat immédiat et exploitable, et surtout : **la géométrie relocalisée devient le jeu de labels** de l'étape 2. Si l'on s'arrête là, ~80 % du problème de qualité d'intrant est déjà réglé.

### Étape 2 — Détection IA de ce qui n'est pas dans la BD Topo
CNN de segmentation entraîné sur les labels de l'étape 1, pour détecter les pistes absentes de la BD Topo.

**Piège méthodologique central** : on ne peut pas entraîner sur des labels BD Topo bruts et espérer battre la BD Topo — le modèle apprendrait ses erreurs systématiques (biais de position). De plus, l'absence dans la BD Topo n'est pas une preuve d'absence de piste → c'est du **positive-unlabeled learning**, pas de la segmentation binaire classique. D'où :
- corriger les labels avant d'entraîner (étape 1), **ou** perte tolérante au décalage (tampon de N m), **ou** vérité terrain RTK réservée à la **validation** (jamais l'entraînement).

**Ne pas faire apprendre la classe route/piste/chemin.** Faire : détection **binaire** (CNN) → **régression d'attributs** (largeur, largeur carrossable, pente, état) → **classification par règles** à partir des attributs. Avantages : auditable (un pompier peut vérifier un classement DFCI), alignable sur les seuils réglementaires français, seuils modifiables sans réentraînement.

---

## 5. Pipeline cible

```
nuage LiDAR HD ──► dérivées (lidR + noyaux RVT, 1 m) ──► CNN (masque de proba)
                                                              │
                                                    vectorisation topologique
                                                      (Roussel et al. 2023)
                                                              │
                                                  mesure d'attributs par tronçon
                                                       (approche ALSroads)
                                                              │
                                              desserte.gpkg qualifiée ──► preprocess()
```

Intégration = un `preprocess()` amont, pas une réécriture :

```r
# Étape 1 — IMPLÉMENTÉE (v1.17.0). Relocalise la géométrie + renseigne la largeur
# depuis le LiDAR ; un MNT grossier est automatiquement raffiné à >= 1 m (spec 020).
desserte_qualifiee <- qualifier_desserte(desserte, las_source = ctg, mnt = mnt)
pre <- preprocess(mnt = mnt, desserte = desserte_qualifiee, foret = foret)
```

---

## 6. Canaux d'entrée du CNN

Le MNT brut donne peu. Ce qui porte le signal, ce sont les dérivées + les canaux issus du nuage :

| Canal | Ce qu'il capte sur une piste | Source |
|---|---|---|
| Sky-view factor | Dépression de la plateforme, sans biais d'azimut | RVT |
| Openness négative | Talus amont (dévers) | RVT |
| Openness positive | Talus aval / banquette | RVT |
| Local relief model (SLRM / TPI) | Écart à la topographie régionale — signal le plus direct | RVT / `DevFromMeanElev` |
| Pente | Rupture de pente en bord de plateforme | lidR / RVT |
| VAT (fusion 4 couches) | Alternative légère (hillshade + pente + openness+ + SVF) | RVT |
| Densité de retours sol | Route = sol nu, forte densité | lidR (nuage) |
| MNH / corridor de trouée | Trouée dans le couvert | lidR (nuage) |
| Intensité | Grave vs litière | lidR (nuage) |

Un modèle 6–8 canaux (MNT + nuage) bat largement un modèle mono-canal MNT.

⚠️ Les visualisations RVT ont des **paramètres d'échelle** (rayon SVF, nombre de directions, fenêtre LRM). Défauts calés sur objets archéo de quelques mètres → compatibles avec des emprises de 3–6 m, mais **balayage de sensibilité** requis sur le massif pilote avant de figer le prétraitement.

---

## 7. Portage RVT en Rust — recommandé et peu coûteux

### Pourquoi maison plutôt qu'appel externe
Le SVF/openness a une **distance de recherche** → exige un **halo** de `radius_max` pixels à chaque bord de tuile. Sans lui, artefacts linéaires sur les raccords = exactement le motif que le CNN doit ignorer. Le moteur de tuilage du lot 7 sait déjà gérer les halos ; un binaire externe non. C'est l'argument décisif.

### Coût réel
- Noyau SVF/openness/ASVF = **2 fonctions**, ~150 lignes (`horizon_shift_vector` + `sky_view_factor_compute`).
- Opération centrale = `roll` + `fmax` (décaler la grille, garder l'angle d'horizon max) → boucle sur tuiles décalées + accumulateur, parallélisable avec **Rayon**, **sans dépendance** (ni BLAS ni GDAL).
- SVF **et** openness ± sortent du **même** balayage (sphère vs hémisphère) → une routine, trois canaux.
- LRM = DEM − moyenne glissante, `mean_filter` déjà en **image intégrale** (temps constant) → ~½ journée.
- Numpy est mono-thread ; une version Rust multi-cœur apporte un gain réel.

### Méthode
- **Translittérer** depuis `rvt/vis.py` (autorisé, cf. §8), pas réimplémenter depuis les articles → évite les bugs sur les cas limites d'angle d'horizon.
- RVT_py devient l'**oracle de non-régression** : même DEM, mêmes paramètres, comparaison pixel à pixel avec tolérance (schéma déjà appliqué ailleurs, cf. ADR-006 / CableHelp).
- Reproduire **exactement** la sémantique NoData : propagation de `NaN`, `fmax` ignorant les NaN, masque restauré en fin de calcul — sinon écarts de bord avec l'oracle (choix de convention, pas bugs).

### R ?
Non, sauf prototypage via `reticulate`. R est inadapté à ces balayages (boucles lentes) ; le package `whitebox` R n'est qu'un frontend, et SVF/openness y sont payants.

### Bénéfice au-delà du CNN
Ces canaux, placés dans `preprocess()`, servent tous les moteurs : l'openness caractérise plateformes et places de retournement → alimente la **qualification DFCI** et le **filtrage des ancrages câble** (réduit le nombre de lignes calculées → gain sur le point chaud Rust).

---

## 8. Licences

| Composant | Licence | Compatibilité GPL v3 | Action |
|---|---|---|---|
| ForêtAccess | GPL v3 | — | — |
| lidR | GPL v3 | ✅ | — |
| ALSroads | **à vérifier avant portage/dépendance** | ? | Confirmer sur le dépôt |
| RVT (py / qgis) | **Apache 2.0** | ✅ (Apache → GPLv3 OK) | Conserver en-tête + NOTICE, mentionner les modifs. Attribution : Kokalj, Zakšek, Oštir, Čož et al. |
| WhiteboxTools open core | MIT | ✅ | OK, mais **SVF/openness hors périmètre** |
| Whitebox Toolset Extension | Propriétaire, payant | ❌ | À écarter |

Précédent utile : Ressources naturelles Canada a sponsorisé l'ouverture de 2 outils WTE vers l'open core. Un financeur public (IGN / DESSOPT) pourrait faire ouvrir `SkyViewFactor`/`Openness` — piste à évoquer, non bloquante.

---

## 9. Décisions ouvertes / actions préalables

Avant de lancer le portage ALSroads, deux contacts conditionnent le choix « porter ALSroads » vs « intégrer un modèle déjà calibré France » :

1. **Sylvain Dupire (LESSEM / ACCESSFOR)** — ForêtAccess réimplémente son modèle en GPL v3 avec attribution : prise de contact naturelle. Saura ce qu'est QUALIROAD.
2. **CNPF-IDF (DESSOPT)** — accès au **jeu de données de référence** (vérité terrain de validation, qui manque aujourd'hui).

Levier institutionnel : convention-cadre INRAE–CNPF de coopération signée en mars 2026 (5 ans) — canal ouvert.

---

## 10. Risques

| Risque | Gravité | Mitigation |
|---|---|---|
| ALSroads expérimental / calibration boréale inadaptée aux terrains français | Élevée | Lot de validation dédié avec vérité terrain FR (via DESSOPT) avant mise en production |
| Entraîner le CNN sur du bruit de label BD Topo | Élevée | Étape 1 (correction) avant étape 2 ; PU-learning ; RTK en validation seule |
| Artefacts de bord SVF/openness sur les raccords de tuiles | Moyenne | Halo `radius_max` géré par le moteur de tuilage (lot 7) |
| Biais saisonnier (feuillus été) | Moyenne | Stratification train/val par bloc d'acquisition et saison |
| Surcoût données (LAS/LAZ dans un pipeline raster 5 m) | Moyenne | Étage LiDAR isolé dans le lot 19 ; tuilage/`renv.lock` mis à jour |
| Écarts de convention avec l'oracle RVT_py | Faible | Reproduire sémantique NoData à l'identique |
| Licence ALSroads incompatible | Faible | Vérifier avant toute dépendance/portage |

---

## 11. Critères d'acceptation

- [x] **`qualifier_desserte()` produit une couche conforme au contrat d'entrée actuel de `preprocess()`** (moteurs et non-régression Sylvaccess **inchangés**) — *implémenté v1.17.0 (étape 1)* : enveloppe déterministe sur `acquire_desserte_lidar()`, géométrie relocalisée par ALSroads, `largeur` renseignée depuis la largeur carrossable mesurée, qualification d'existence en option (`retirer_disparues`, désactivée par défaut faute de vérité terrain FR). Repli NDP 0 gracieux (desserte inchangée) testé en CI.
- [ ] Noyaux RVT (SVF, openness ±, LRM, pente) portés en Rust, **non-régression pixel à pixel** contre RVT_py sous tolérance définie, halos gérés par le moteur de tuilage (identité tuilé = mono-bloc, cf. lot 7).
- [ ] Sur le massif pilote : comparaison des surfaces par classe entre desserte BD Topo brute et desserte qualifiée (apport mesurable).
- [ ] Test d'agrégation contre les cibles ACCESSFOR (Morvan / Bauges) comme second oracle indépendant.
- [ ] Première livraison ciblée sur le **cas DFCI** (gain le plus évident, chantier déjà ouvert côté institutionnel).

---

## 12. Jalons proposés

1. **J1 — Exploration** : RVT_py tel quel (via `reticulate` ou CLI) sur un massif ; sélection des 3–5 canaux porteurs ; balayage de sensibilité des paramètres d'échelle.
2. **J2 — Étape 1** : correction déterministe de la BD Topo (ALSroads) sur le massif pilote → jeu de labels propre.
3. **J3 — Portage Rust** des canaux retenus, oracle RVT_py, intégration `preprocess()` + halos.
4. **J4 — Étape 2** : CNN binaire sur labels J2 → vectorisation topologique → régression d'attributs → classification par règles.
5. **J5 — Validation** : agrégation vs ACCESSFOR ; vérité terrain DESSOPT ; livraison DFCI.

> ⚠️ Le brief projet mentionne encore Python + PyO3 ; le dépôt est aujourd'hui ~72 % R / ~28 % Rust. Mettre à jour le brief pour éviter toute confusion sur la stack.

---

### Références clés
- Roussel et al. 2022, *IJAEOG* 114, 103020 — https://doi.org/10.1016/j.jag.2022.103020
- Roussel et al. 2023 — https://www.sciencedirect.com/science/article/pii/S1569843223000894
- ALSroads — https://github.com/r-lidar-lab/ALSroads · guide : https://ilythiamorley.github.io/ALSroads_Guide/
- lidR — https://r-lidar.github.io/lidRbook/
- RVT_py (Apache 2.0) — https://github.com/EarthObservation/RVT_py
- WhiteboxTools (manuel / périmètre MIT) — https://jblindsay.github.io/wbt_book/ · liste WTE payante : https://www.whiteboxgeo.com/wte-tools-list/
- DESSOPT — https://cnpf.fr/dessopt-detection-et-optimisation-du-reseau-de-dessertes-forestieres-le-lidar-hd
- ACCESSFOR — https://www.inrae.fr/actualites/nouvel-outil-accessibilite-forets
