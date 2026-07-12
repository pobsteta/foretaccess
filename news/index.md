# Changelog

## foretaccess 0.8.0 (2026-07-12)

### Lot 6 — Camion DFCI (beta) : zone défendable

Sortie **beta** de défense de la forêt contre les incendies (EF-8).
Cartographie la **zone défendable** — la forêt qu’un camion peut
atteindre et défendre depuis les dessertes DFCI. Conception propre (le
module DFCI n’est pas dans les sources Sylvaccess de référence),
cohérente avec l’architecture des moteurs terrestres.

- **`camion_dfci(pre, config, write_dir, bord)`** : signature identique
  à
  [`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)
  /
  [`porteur()`](https://pobsteta.github.io/foretaccess/reference/porteur.md),
  directement branchable sur
  [`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md).
  La zone défendable est un **tampon au terrain** — un plus court chemin
  pondéré par la pente
  ([`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md) +
  [`surface_cout_skidder()`](https://pobsteta.github.io/foretaccess/reference/surface_cout_skidder.md))
  depuis les dessertes DFCI, plafonné à la portée de défense et coupé
  au-delà de la pente d’intervention. Aucun nouveau noyau : réutilise le
  service partagé du Lot 2.
- **Sorties** : raster catégoriel `accessibilite` (`defendable` /
  `non_defendable` / `hors_foret`), `distance_defense` (m),
  `allocation`, `recap` surfaces/volumes, écriture COG optionnelle.
- **Configuration `config$dfci`** : portée de défense (100 m), pente
  d’intervention max (40 %), classes de desserte-source (`"dfci"`).
  Hypothèses de travail explicites, non Sylvaccess (surchargeables,
  validées au chargement).
- **Tuilage** : sortie certifiée, identique au mono-bloc sur les
  cellules certifiées. Le réseau DFCI étant clairsemé, une tuile sans
  source reste indéterminée (le halo grandit) ; l’absence de source au
  niveau top-level lève une erreur ciblée.
- **Limites (beta)** documentées (`specs/006-dfci.md`, roxygen) : ni
  combustible, ni vent, ni physique de lance ; carrossabilité des
  dessertes non qualifiée (QUALIROAD). Sortie de **première
  hiérarchisation**, pas de dimensionnement.

## foretaccess 0.7.0 (2026-07-12)

### Lot 5 — Sélection multicritère des lignes câble

Sortie **décisionnelle** du volet câble (EF-7). Parmi les lignes
faisables du balayage 360°/pixel (Lot 4), on sélectionne un
sous-ensemble non redondant maximisant la couverture selon des critères
pondérés. Porté de `select_best_lines` / `create_best_table` (Sylvaccess
v3.6, GPL v3).

- **Table des lignes candidates** :
  [`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
  émet désormais `$lignes`, une candidate par couple (départ, azimut)
  faisable, avec surface forêt couverte, longueur, sens (amont/aval),
  nombre de supports, et — si un raster de volume est fourni — volume
  total et **IPC** (= volume / longueur).
- **[`selectionner_lignes()`](https://pobsteta.github.io/foretaccess/reference/selectionner_lignes.md)**
  : filtrage par limites min/max, score pondéré normalisé (maximiser →
  `valeur / p98` ; minimiser → `1 − valeur / max`), classement
  déterministe, **sélection gloutonne** (une ligne retenue apporte au
  moins 60 % de surface nouvelle). Sortie **`sf`** des lignes
  (LINESTRING, CRS strict) et **raster de couverture**.
- **Configuration** de la sélection dans `config$cable$selection`
  (poids, limites, sens préféré, contribution minimale). Les critères
  volume/IPC sont neutralisés automatiquement en l’absence de donnée de
  volume.

Six critères MVP (surface, supports, sens, longueur, volume, IPC) ;
VAM×10 et coût €/m³ de v3.6 repoussés. La reproductibilité vis-à-vis de
v3.6 sur le jeu test reste à confronter à un oracle réel ; le
déterminisme est verrouillé.

## foretaccess 0.6.0 (2026-07-12)

### Lot 4 — Noyau câble (Rust, CableHelp)

Premier moteur **non terrestre**, et point où le portage
`extendr`/`rextendr` prend son sens. La mécanique de câble-mât
(caténaire élastique) est portée depuis le code source Sylvaccess v3.6
(`sylvaccess_cython3.pyx`, GPL v3) dans le crate Rust `cablehelp`,
exposée via `extendr` ; l’orchestration SIG reste en R.

- **Caténaire élastique + Newton-Raphson** (`cable_f_x`, `cable_f_z`,
  `cable_calcul_xs`, `cable_calcul_zs`, `cable_newton_thtv`,
  `cable_find_thtv_tmax`). Le terme `Lo/EAo` (allongement sous tension)
  distingue le modèle d’une caténaire idéale. Résolution par Jacobien
  analytique, repli sur grille.
- **Faisabilité d’une travée** (`cable_check_droite`,
  `cable_check_hlinemin`) : la charge balaie la travée, on résout les
  tensions à chaque position et on vérifie la garde au sol dans
  `[hauteur_cable_min_m, hauteur_cable_max_m]` et la tension sous la
  limite admissible.
- **Optimisation de travée** (`cable_find_lomin`, `cable_test_span`) :
  longueur à vide minimale à tension = Tmax, pente bornée, contrainte
  d’angle au support intermédiaire. Amorçage par grille grossière
  (substitut aux tables `Tabmesh`).
- **Orchestration**
  ([`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md))
  : balayage 360°/pixel depuis la desserte, extraction du profil MNT,
  test d’une ligne **0 support** jusqu’à la longueur maximale,
  couverture des cellules forestières. Sortie `foretaccess_cable`.
- **Configuration câble** complétée avec les matériels v3.6
  (`config$cable`).

Extensions prévues (voir `specs/004-cable.md`) : placement de supports
intermédiaires (`OptPyl_Up`, avec oracle réel), pêchage latéral, portage
Rust de l’orchestration.

## foretaccess 0.5.1 (2026-07-12)

### Conformité du porteur — zone de conduite

Relecture de `Sylvaccess_3_forwarder.py` (construction de `Zone_OK` /
`Pente_ok_forwarder`). Deux corrections à `.zone_conduite()` :

- **Bug de borne de pente.** La zone bornait la pente par
  `min(travers, montée, descente)` = 15 %, alors que Sylvaccess la borne
  par le **maximum** = 30 %, le balayage affinant ensuite par le sens et
  le dévers. Le `min` excluait à tort les cellules roulables en montée
  dans le sens de la pente.
- **Saut hors forêt** (`distance_hors_desserte_max_m`, 200 m). Le
  porteur peut couper par un terrain récoltable non forestier, depuis le
  contour de la forêt, pour rejoindre un massif isolé — l’analogue de
  [`zone_roulable_connectee()`](https://pobsteta.github.io/foretaccess/reference/zone_roulable_connectee.md)
  du skidder. Le halo suffisant du tuilage intègre désormais ce saut.

La **double passe** réseau/contour reste une dette assumée : sans sortie
Sylvaccess de référence, son modèle de distance en composantes séparées
ne peut être validé sur les fixtures synthétiques. Voir
`specs/003-porteur.md`.

## foretaccess 0.5.0 (2026-07-11)

### Lot 3 — Moteur Porteur (forwarder)

Deuxième moteur terrestre,
[`porteur()`](https://pobsteta.github.io/foretaccess/reference/porteur.md).
Rédigé sur le code source Sylvaccess v3.6 (`Sylvaccess_3_forwarder.py`,
`sylvaccess_cython3.pyx`), qui renverse l’hypothèse « porteur = skidder
aux seuils différents ».

- La conduite est un **balayage radial** depuis le réseau de desserte
  (`fwd_azimuts_forest_roadnet`), non un plus court chemin. Nouvelle
  fonction exportée
  [`conduire()`](https://pobsteta.github.io/foretaccess/reference/conduire.md),
  qui partage la géométrie de rayons du treuillage mais s’en distingue
  par trois filtres, tous sur la pente du terrain **en degrés** :
  - **pente en long signée par l’altitude** : une cellule plus haute que
    la route relève de la descente (le porteur y ramène le bois chargé
    en descendant), plus basse de la montée ;
  - **dévers dépendant de l’azimut** : `pente_travers / cos(90 - Δ)`,
    nul dans le sens de la pente, maximal en travers — le basculement
    latéral de la machine ;
  - **accumulateur de distance en pente forte**, plafonné à
    `distance_pente_forte_max_m`.
- Pas de treuil, mais un **grappin** de `portee_grue_m` (8 m) : une
  extension géométrique bornée du terrain récoltable, reproduisant
  `fwd_add_hoist`.
- La distance retenue est **3D**.

Le porteur se tuile mieux que le skidder : sa portée étant bornée
(conduite 300 m, grappin 8 m), le halo suffisant est petit et connu.
`traiter_par_tuiles(moteur = porteur)` donne un résultat identique au
mono-bloc.

### Généralisation du tuilage

[`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md)
accepte un argument `couches` : il n’est plus lié aux couches du skidder
et sert n’importe quel moteur.

### Dette assumée

Le saut hors forêt du porteur (`f_dmax_outfor`, l’équivalent de
[`zone_roulable_connectee()`](https://pobsteta.github.io/foretaccess/reference/zone_roulable_connectee.md)
du skidder) et la double passe réseau/contour ne sont pas encore
implémentés. Voir `specs/003-porteur.md`.

## foretaccess 0.4.0 (2026-07-10)

### Lot 7 — Passage à l’échelle (tuilage, certificat, parallélisme)

Le brief exige un résultat tuilé **identique** au traitement mono-bloc.
Un halo fixe ne le donne pas : le traînage est un plus court chemin sans
portée bornée, et la connexité d’un massif à la desserte peut passer par
un détour arbitrairement long. Un halo trop court produit des artefacts
de bordure — distances trop grandes, cellules faussement inaccessibles —
que rien ne signale.

- [`certifier_propagation()`](https://pobsteta.github.io/foretaccess/reference/certifier_propagation.md)
  **prouve** l’exactitude cellule par cellule. Deux propagations sur la
  fenêtre : `d_R` depuis les sources, `d_∂` depuis le bord ouvert pris à
  coût nul. Si `d_R(v) ≤ d_∂(v)`, aucun chemin extérieur ne peut faire
  mieux. L’allocation est exacte si l’inégalité est stricte ; `∞ ≤ ∞`
  certifie l’inaccessibilité ; la connexité n’est que le cas `coût ≡ 0`.
- [`decouper_emprise()`](https://pobsteta.github.io/foretaccess/reference/decouper_emprise.md)
  découpe en fenêtres d’écriture **disjointes** avec halo. Le halo ne
  sert qu’au calcul : la recomposition est une mosaïque, sans règle de
  fusion.
- [`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md)
  double le halo tant que des cellules restent non certifiées. Au
  plafond, elles sortent en `indetermine` avec un avertissement — jamais
  rangées dans `non_accessible`, jamais tronquées en silence. Une
  cellule non certifiée ne publie rien : ni classe, ni distance, ni
  allocation.
- Parallélisme par tuile via **`mirai`** (nouvelle dépendance).
  `workers = 1` s’exécute sans démon. Le résultat ne dépend pas du
  nombre de workers.
- Sorties en COG recomposé.

#### Le halo, et ce qu’il coûte

Le certificat n’est satisfait que si le halo dépasse la plus longue
distance qui peut entrer dans la tuile, et le surcoût surfacique croît
comme `(1 + 2·halo/tuile)²`. Mesuré : 2,5× le mono-bloc avec
`tuile = 4 × halo`, mais **27×** quand le halo dépasse la tuile.

`distance_trainage_piste` atteint 4 km sur données réelles et aurait
imposé des tuiles de 16 km. Elle vit pourtant sur le réseau de desserte
— unidimensionnel et creux : une seule propagation globale la donne
exactement.
[`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md)
la précalcule, et elle cesse d’être un moteur de halo.

### Nouvelles fonctions

[`decouper_emprise()`](https://pobsteta.github.io/foretaccess/reference/decouper_emprise.md),
[`fenetre_tuile()`](https://pobsteta.github.io/foretaccess/reference/fenetre_tuile.md),
[`certifier_propagation()`](https://pobsteta.github.io/foretaccess/reference/certifier_propagation.md),
[`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md).
[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)
accepte `bord` et certifie alors ses sorties.

## foretaccess 0.3.1 (2026-07-10)

### Conformité à Sylvaccess v3.6

Première exécution sur données réelles (AOI de 7,2 km², RGE ALTI + BD
TOPO). Elle a révélé deux écarts au code source que le jeu jouet ne
pouvait pas exposer.

- `distance_hors_desserte_max_m` **ne plafonne pas la distance de
  débardage**. C’est la distance maximale que le skidder peut parcourir
  **hors forêt**, sur du terrain roulable, pour rejoindre un massif
  qu’aucune desserte ne touche. Nouvelle fonction exportée
  [`zone_roulable_connectee()`](https://pobsteta.github.io/foretaccess/reference/zone_roulable_connectee.md),
  qui reproduit la construction en trois temps de `Pente_ok_skidder`
  (connexité depuis la desserte, saut borné hors forêt, recollement), et
  [`terrain_roulable()`](https://pobsteta.github.io/foretaccess/reference/terrain_roulable.md),
  son critère de pente sans le critère forêt.
- La `distance_trainage_piste` est désormais pondérée par la pente,
  comme le traînage en forêt
  (`Dfwd_flat_forest_tracks(f, Lien_Piste, Pond_pente, …)`), et non
  propagée à coût uniforme.

Sur l’AOI de test, la surface parcourable augmente de 1,9 ha.

### Performance

- Le tas binaire du Dijkstra était recopié à chaque opération
  (sémantique de copie de R sur un vecteur porté par une liste) :
  **357×** sur une sonde de 200 000 insertions.
- Le balayage radial de treuillage portait des vecteurs pleine longueur
  sous un masque de rayons vivants : compacter les survivants le rend
  **2,2×** plus rapide, à sortie identique bit à bit.

[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)
traite désormais 7,2 km² en 22 s CPU (3,05 s/km²) sur un cœur.

## foretaccess 0.3.0 (2026-07-10)

### Lot 2 — Moteur Skidder (+ service least-cost partagé)

Les règles sont **dérivées du code source Sylvaccess v3.6** (GPL v3,
`forge.inrae.fr/sylvain.dupire/sylvaccess`), et non de l’article — qui
n’en donne pas les équations. Trois d’entre elles contredisaient nos
hypothèses initiales.

- **[`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md)**
  et
  **[`chemin_optimal()`](https://pobsteta.github.io/foretaccess/reference/chemin_optimal.md)**
  : service de plus court chemin sur grille, partagé avec le porteur
  (Lot 3) et le camion DFCI (Lot 6). Dijkstra 8-connexe, coût porté par
  la **cellule d’arrivée** (et non la moyenne des deux cellules, comme
  [`terra::costDist()`](https://rspatial.github.io/terra/reference/costDist.html)),
  diagonale × `sqrt(2)`, plafond de coût, et raster d’**allocation**
  identifiant la source atteinte. Aucune dépendance nouvelle. Le tas
  binaire vit dans des vecteurs mutés en place : le passer en liste
  ferait recopier le vecteur à chaque opération (sémantique de copie de
  R), rendant le Dijkstra quadratique — mesuré à 357× plus lent sur 200
  000 insertions.
- **[`surface_cout_skidder()`](https://pobsteta.github.io/foretaccess/reference/surface_cout_skidder.md)**,
  **[`ponderation_pente()`](https://pobsteta.github.io/foretaccess/reference/ponderation_pente.md)**
  : la fonction de coût est `sqrt(1 + (p/100)^2)`, le facteur
  d’allongement 3D de la traversée d’une cellule. Elle ne dépend que de
  la pente **absolue** : la propagation est **isotrope**.
- **[`treuiller()`](https://pobsteta.github.io/foretaccess/reference/treuiller.md)**
  : le treuillage n’est **pas** un plus court chemin, mais un balayage
  radial 360° au pas de 1°, en ligne droite, avec une distance **3D** et
  une contrainte de dégagement du câble (la corde reste entre le sol et
  `hauteur_degagement_max_m`, attachée à `hauteur_attache_treuil_m`).
  Les rayons vivants sont compactés à chaque pas : la plupart meurent en
  quelques cellules, et le travail s’effondre (2,2× sur terrain réel).
- **[`distance_treuillage_max()`](https://pobsteta.github.io/foretaccess/reference/distance_treuillage_max.md)**,
  **[`coefficients_bascule()`](https://pobsteta.github.io/foretaccess/reference/coefficients_bascule.md)**
  : la loi de bascule est affine en **dénivelé**, pas en pente. À plat,
  la distance admissible vaut **80,23 m** — ni 50 (plafond amont), ni
  100 (plafond aval).
- **[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)**
  : orchestrateur. Classes d’accessibilité, distances de treuillage, de
  traînage (forêt et piste) et de débardage, allocation, trajets
  optionnels, écriture GeoTIFF/COG.
- **[`recapituler()`](https://pobsteta.github.io/foretaccess/reference/recapituler.md)**
  : surfaces et volumes par classe, avec une ligne `indetermine`
  explicite — les bordures ne sont jamais rangées silencieusement dans
  une classe métier.
- **[`zone_roulage()`](https://pobsteta.github.io/foretaccess/reference/zone_roulage.md)**,
  **[`zone_treuillable()`](https://pobsteta.github.io/foretaccess/reference/zone_treuillable.md)**
  : les obstacles **partiels** bloquent le roulage mais pas le
  treuillage ; les obstacles **complets** reçoivent un surcoût additif
  prohibitif mais **fini** (1000), et ne sont pas `NA`.

### Changements

- [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
  conserve désormais le **MNT** dans son résultat (`$mnt`) : les moteurs
  en ont besoin, le treuillage raisonnant sur les altitudes. Ajout
  additif.
- Nouveaux paramètres `config$skidder`, aux défauts v3.6 lus dans le
  `.pyx` : `hauteur_attache_treuil_m`, `hauteur_degagement_max_m`,
  `surcout_obstacle_complet`, `option_modelisation`,
  `classes_distance_m`.

### Limites connues

- Seule l’**option de modélisation 1** (privilégier le treuillage) est
  implémentée ; l’option 2 lève une erreur explicite.
- Le plafond `distance_hors_desserte_max_m` n’est pas appliqué, et la
  hiérarchie route / piste est réduite à deux niveaux. Voir
  `specs/002-skidder.md`.

## foretaccess 0.2.0 (2026-07-09)

### Lot 1 — I/O & prétraitement

- **[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)**
  : socle commun aux quatre moteurs. Produit un objet
  `foretaccess_preprocessing` dont tous les rasters partagent exactement
  la grille du MNT (pente, exposition, masque forêt, desserte
  catégorielle, masques d’obstacles, masque d’exclusion de pente, volume
  aligné).
- **[`valider_entrees()`](https://pobsteta.github.io/foretaccess/reference/valider_entrees.md)**
  : validation **stricte** des entrées — CRS commun, alignement de
  grille, champ `classe` de la desserte, géométries non vides et
  valides, emprises se recouvrant. Aucune reprojection ni
  rééchantillonnage silencieux ; chaque manquement lève une erreur
  ciblée.
- **[`calculer_terrain()`](https://pobsteta.github.io/foretaccess/reference/calculer_terrain.md)**
  : pente en pourcentage et exposition en degrés depuis le nord (plat =
  `NA`), via `terra`. Méthode configurable
  (`config$general$methode_pente` : `"Horn"` par défaut, ou `"Evans"`).
- Écriture GeoTIFF/**COG** optionnelle (`preprocess(write_dir = )`) et
  relecture par
  **[`lire_rasters()`](https://pobsteta.github.io/foretaccess/reference/lire_rasters.md)**.
- Chaque entrée est acceptée comme **chemin de fichier** ou comme objet
  déjà chargé (`SpatRaster` / `sf`), conformément à l’ADR-004.
- Non-régression sur oracle **analytique** : le MNT jouet (plan incliné
  à 20 %) valide pente, exposition et masques via
  [`compare_to_oracle()`](https://pobsteta.github.io/foretaccess/reference/compare_to_oracle.md).

### Divers

- Ajout des badges README (R-CMD-check, version, pkgdown, couverture
  Codecov, lifecycle, licence) et du site pkgdown + job de couverture en
  CI.

## foretaccess 0.1.0 (2026-07-09)

### Lot 0 — Fondations

- Squelette de **package R** + **crate Rust `cablehelp`** liée par
  `extendr`
  ([`cablehelp_version()`](https://pobsteta.github.io/foretaccess/reference/cablehelp_version.md)
  comme preuve de chaîne R ↔︎ Rust).
- **Configuration** métier validée (`checkmate`), défauts **Sylvaccess
  v3.6**, chargement/écriture YAML.
- Interface **`StorageBackend`** : implémentations **PostGIS** et
  **GeoPackage**, sans backend par défaut (ADR-002).
- **Jeu de données jouet** (`inst/extdata/toy/`) + **harnais de
  non-régression**
  ([`compare_to_oracle()`](https://pobsteta.github.io/foretaccess/reference/compare_to_oracle.md)).
- **CI** (lint/tests/`R CMD check`/`cargo test`/`clippy`) et
  **infrastructure de versionnage** (`release.yml`, garde-fou
  `version-consistency`).

## foretaccess 0.0.1 (2026-07-08)

- Jalon **documentaire** d’amorçage : PRD, backlog, roadmap (§10),
  ADR-001…007. Aucun code (voir `docs/`).
