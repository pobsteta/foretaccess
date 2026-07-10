# PLAN.md — walking skeleton ForêtAccess

> **Source unique de vérité** de l'avancement (règle 5 de `CLAUDE.md`).
> Mise à jour à chaque étape terminée. Ne jamais clore un lot sans la release
> correspondante.

## État courant

- **Branche** : `lot-2-skidder`
- **Version `DESCRIPTION`** : `0.3.0` (version stable préparée ; `release.yml` pose le
  tag au merge sur `main`)
- **Lot en cours** : **Lot 2 — Moteur Skidder** — 2a et 2b implémentés, tests verts,
  reste la PR et la revue.

## Avancement par lot

| Lot | Nom | Spec | État | Release |
|---|---|---|---|---|
| 0 | Fondations | `specs/000-fondations.md` | ✅ terminé | `v0.1.0` |
| 1 | I/O & prétraitement | `specs/001-pretraitement.md` | ✅ terminé | `v0.2.0` |
| 2 | Moteur Skidder | `specs/002-skidder.md` | 🟡 code fait, PR à ouvrir | `v0.3.0` (à poser) |
| 3 | Moteur Porteur | à écrire | ⬜ | — |
| 4 | Noyau Câble (Rust) | à écrire | ⬜ | — |
| 5 | Sélection lignes câble | à écrire | ⬜ | — |
| 6 | Camion DFCI (beta) | à écrire | ⬜ (post-MVP) | — |
| 7 | Passage à l'échelle | à écrire | ⬜ | — |
| 8 | Base spatiale & agrégation | à écrire | ⬜ | — |
| 9 | Doc & publication | à écrire | ⬜ | — |
| 10 | Acquisition depuis AOI | `specs/010-acquisition-aoi.md` | ⬜ spec validée | — |

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

Ouvrir la PR `lot-2-skidder` → `main` (le merge pose le tag `v0.3.0`), puis repasser
en cycle de dev `0.3.0.9000`. Ensuite : `specs/003-porteur.md`, qui réutilise le
service least-cost livré ici.

### Dette assumée du Lot 2

- Seule l'**option de modélisation 1** (privilégier le treuillage) est implémentée ;
  l'option 2 lève une erreur explicite.
- Le plafond `distance_hors_desserte_max_m` n'est pas appliqué (la propagation est
  déjà confinée à la forêt) et la hiérarchie route / piste est réduite à deux niveaux.
- Le Dijkstra est en R pur : ~10 s sur le jouet 50×50. Sur l'AOI réelle (295 k
  cellules) il faudra mesurer, et probablement porter le noyau en Rust (ADR-001).
  La frontière est déjà au bon endroit : `propager_cout()` ne connaît aucune règle métier.

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
