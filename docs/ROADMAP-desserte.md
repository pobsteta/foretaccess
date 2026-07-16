# ForêtAccess — Roadmap « Conception de desserte » (Lots 14-18)

> **Statut** : proposé — en attente de validation.
> Extension de la [`ROADMAP.md`](ROADMAP.md) existante (Lots 0-13, accessibilité/débardage) à un
> **nouvel épic** : la **conception de nouvelles dessertes** (tracé de routes/pistes + réseau).
> Numérotation à partir de **14** pour ne renuméroter aucun lot existant.
> Même principe agile : une spec `specs/0XX-*.md` par lot, une branche git par lot, DoD
> respectée, non-régression verte contre les oracles avant de considérer un lot « fait ».

---

## 1. Pourquoi cet épic

Les Lots 0-13 répondent à *« où peut-on exploiter avec le matériel M ? »* (réimplémentation de
Sylvaccess). Cet épic répond à une question complémentaire : *« par où construire une nouvelle
desserte, et quel réseau pour desservir N parcelles ? »* — le périmètre du plugin QGIS
**ForestRoadNetwork** (Klemet) et des modèles **SylvaRoad** (Dupire/ONF) et **Forest Road
Designer** (PANOimagen).

**Constat de l'étude comparative** (voir §4) : aucun outil libre ne couvre tout. SylvaRoad et
FRD tracent **un** tronçon (excellents) mais ne font pas de réseau ; ForestRoadNetwork fait le
réseau + flux + types mais avec un solveur pauvre (Dijkstra 8-connexe). La **meilleure solution**
est une composition : solveur de tracé (SylvaRoad + FRD, porté Rust) + couche réseau MTAP
(apport propre, façon Steiner) + flux/types (repris de ForestRoadNetwork), le tout dans
l'ossature `foretaccess`.

---

## 2. Vue d'ensemble

| Lot | Nom | Spec | Rôle | Dépend de | Langage | Release |
|---|---|---|---|---|---|---|
| **14** | Coût de construction | `specs/014` | Surface de coût €/m + franchissabilité | 1, 10 | R | `v0.13.0` |
| **15** | Solveur de tracé A\* | `specs/015` | Tracé point-à-point, graphe étendu | 14, 0, 7 | **R + Rust** | `v0.14.0` |
| **16** | Réseau MTAP | `specs/016` | Réseau N parcelles (glouton + Steiner) | 15, 14, 7 | R (+ Rust `rayon`) | `v0.15.0` |
| **17** | Flux & typage | `specs/017` | Flux de bois + type de route | 16, 8 | R | `v0.16.0` |
| **18** | Optimisation | `specs/018` | Multi-start / recuit / rip-up | 16, 15 | R + Rust `rayon` | `v0.17.0` |

**ADR nouveau** : [`ADR-008`](adr/ADR-008-graphe-etendu.md) — graphe étendu à voisinage disque.

**Chemin critique** : 14 → 15 → 16 → 17. Le **Lot 18** (optimisation) est **optionnel /
post-MVP**, activé si la qualité du glouton (Lot 16) est jugée insuffisante.

---

## 3. Détail des lots

### Lot 14 — Coût de construction
**Livrables** : `surface_cout_construction()` (coût €/m additif : base, pente, sol, ponts,
buses, surcoûts) + raster de franchissabilité. Extension acquisition à l'hydrographie (10b).
`specs/014`. **Sortie** : `foretaccess_cout_construction`. R pur.

### Lot 15 — Solveur de tracé A\* (noyau Rust)
**Livrables** : voisinage disque paramétrable, A\* avec heuristique pré-calculée (Dijkstra
inverse), pénalités quadratiques direction/pente, épingles (`Radius`), rayon de courbure (FRD),
contrôle de profil, waypoints. Exposé `extendr`. `specs/015`, ADR-008. **Déclenche le portage
Rust** (ADR-001). **Non-régression** vs SylvaRoad (`meisenthal2`).

### Lot 16 — Réseau MTAP
**Livrables** : construction du réseau desservant N parcelles avec **réutilisation** du réseau
(coût ~0), 3 heuristiques d'ordre (ForestRoadNetwork), mode **Steiner** (MST + élagage,
Chung-Sessions) parallèle `rayon`. `specs/016`. **Valeur ajoutée** : aucun outil libre ne le
fait proprement. Non-régression qualitative vs ForestRoadNetwork.

### Lot 17 — Flux & typage
**Livrables** : vectorisation topologique (`sfnetworks`), points sources (min. 1/parcelle),
accumulation de flux, typage par seuils, routes temporaires. `specs/017`. R pur. Non-régression
vs ForestRoadNetwork (Wood Flux / Road Type).

### Lot 18 — Optimisation (post-MVP)
**Livrables** : multi-start parallèle, recuit simulé sur l'ordre, rip-up & reroute. `specs/018`.
R + Rust `rayon`. Gain ≥ 0 garanti vs glouton (Lot 16).

---

## 4. Sources & oracles

| Source | Apport | Rôle |
|---|---|---|
| **ForestRoadNetwork** (Klemet, GPL v3) | MTAP glouton + heuristiques d'ordre + flux + types + `Test_data/` | Oracle Lots 16/17 |
| **SylvaRoad** (Dupire/ONF, GPL v3) | A\* voisinage disque + heuristique pré-calculée + épingles + `check_profile` + `meisenthal2` | Oracle Lot 15 |
| **Forest Road Designer** (PANOimagen, GPL v3) | A\* + rayon de courbure explicite + dédup angulaire + polysimplify | Oracle/inspiration Lot 15 |
| **Chung & Sessions 2007** (Can. J. For. Res.) | 48 liens/16 directions, MST/Steiner | Fondement Lots 15/16 (ADR-008) |
| **Akay 2004 / ACO** | Recuit simulé, colonies de fourmis (~25 % de gain) | Fondement Lot 18 |
| **foretaccess** (Lots 0-13) | Acquisition, prétraitement, tuilage, PostGIS, socle Rust, non-régression | Ossature d'accueil |

Tous ces outils sont **GPL v3** — compatibles avec la licence de ForêtAccess. Attribution
systématique en §Attribution de chaque spec ; réécriture propre (R/Rust), aucune copie de source.

---

## 5. Ce que chaque outil NE fournit pas (justification de l'apport propre)

- SylvaRoad / FRD : **pas de réseau** (tracé point-à-point seulement) → Lot 16 est un apport.
- ForestRoadNetwork : **solveur pauvre** (8-connexe, pas de pente en long/rayon/épingles) → le
  tracé du Lot 15 le surclasse.
- Aucun : **acquisition automatique** des données (MNT/desserte/forêt/hydro), **base spatiale**,
  **passage à l'échelle** (tuilage), **socle Rust** → déjà dans `foretaccess` (Lots 0-13).

En une phrase : **tracé = SylvaRoad + FRD (porté Rust) ; réseau MTAP = apport propre façon
Steiner ; flux/types = ForestRoadNetwork (R) ; ossature = foretaccess.**

---

## 6. Séquencement

Specs rédigées et validées **une par une, avant le lot**. Ordre : 014 → 015 → 016 → 017, puis
018 si nécessaire. ADR-008 à valider avant le Lot 15 (il conditionne toute la famille).
