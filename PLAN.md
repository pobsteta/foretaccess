# PLAN.md — walking skeleton ForêtAccess

> **Source unique de vérité** de l'avancement (règle 5 de `CLAUDE.md`).
> Mise à jour à chaque étape terminée. Ne jamais clore un lot sans la release
> correspondante.

## État courant

- **Branche** : `release/0.6.0`
- **Version `DESCRIPTION`** : `0.6.0` (release du moteur câble ; `release.yml` pose `v0.6.0`
  au merge sur `main`, puis retour en cycle dev `0.6.0.9000`)
- **Lot terminé** : **Lot 4 — noyau câble (Rust)**, 0 support. **4a** (caténaire + Newton),
  **4b** (faisabilité), **4c** (`find_lomin`, `test_span`) et **4d** (`potentiel_cable()`)
  livrés et mergés (#19–#22). 10 bindings extendr + `potentiel_cable()`, 16 tests cargo +
  ~45 tests R, suite 590 PASS. Restent en extension (spec §11) : placement multi-supports
  (`OptPyl_Up`, oracle réel), pêchage latéral, portage Rust de l'orchestration.
- **Prochain lot** : **Lot 5 — sélection multicritère des lignes câble** (`specs/005`).

## Avancement par lot

| Lot | Nom | Spec | État | Release |
|---|---|---|---|---|
| 0 | Fondations | `specs/000-fondations.md` | ✅ terminé | `v0.1.0` |
| 1 | I/O & prétraitement | `specs/001-pretraitement.md` | ✅ terminé | `v0.2.0` |
| 2 | Moteur Skidder | `specs/002-skidder.md` | ✅ terminé | `v0.3.0`, `v0.3.1` |
| 3 | Moteur Porteur | `specs/003-porteur.md` | ✅ terminé | `v0.5.0`, `v0.5.1` |
| 4 | Noyau Câble (Rust) | `specs/004-cable.md` | ✅ terminé (0 support) | `v0.6.0` |
| 5 | Sélection lignes câble | à écrire | ⬜ | — |
| 6 | Camion DFCI (beta) | à écrire | ⬜ (post-MVP) | — |
| 7 | Passage à l'échelle | `specs/007-passage-echelle.md` | ✅ terminé | `v0.4.0` |
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
  - Restent en extension (documentées, spec §11) : placement multi-supports (oracle réel),
    pêchage latéral `distance_laterale_max_m`, portage Rust de l'orchestration (point chaud).
