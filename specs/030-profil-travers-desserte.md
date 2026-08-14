# specs/030 — Profil en travers d'un tronçon de desserte, au clic

> **Statut** : **implémentée** — `profil_travers()` et `classer_desserte()`, livrées en v2.3.0.
> **Origine** : [`specs/BRIEF-profil-travers-desserte.md`](BRIEF-profil-travers-desserte.md)
> (demandeur : `nemetonshiny`, onglet Terrain > Accessibilité).
> **Dépend de** : spec 021 (`qualifier_desserte()`, vocabulaire `las_source` / `mnt` /
> `cache_dir`), spec 023 (moteur `dessertR`).
> **Ne dépend pas de** : `dessertR` pour le profil lui-même — voir §3.

---

## 1. Ce qui était demandé

Un clic sur la carte, un profil en travers du tronçon le plus proche : **nuage LiDAR en coupe**,
courbe ajustée de la chaussée, axe, et **cinq familles de bords cotées**. Le tracé reste côté app ;
le cœur ne rend que des données dérivées (pas de graphique, appelable dans un worker `future`,
aucun état global, quelques secondes par clic).

## 2. Ce qui manquait vraiment

Le brief posait la bonne question (§4) : `dessertR::dsr_profils()` échantillonne le **MNT**, donc
une surface **interpolée**, alors que la planche visée montre les **points** — un par écho, coloré
par classe et par intensité.

C'est le seul vrai développement du lot, et il n'était pas contournable : `dessertR` lit bien le
nuage (`dsr_layers_pc()`, `dsr_gabarit_libre()`), mais n'en rend que des **rasters**. Aucune
fonction, dans aucun des deux paquets, ne rendait des points.

Le reste — accrochage, station, chaînage, profil du terrain — est de la géométrie de quelques
dizaines de lignes ; l'écrire ici coûtait moins cher que de plier `dsr_profils()` (qui travaille
par tronçon entier, à pas régulier) à une station unique.

## 3. Pourquoi le profil ne passe pas par `dessertR`

`dessertR` reste le moteur de la **mesure** (`acquire_desserte_lidar()`, `qualifier_desserte()`) et
du **classement** (§4). Mais le profil au clic a trois contraintes que la mesure n'a pas :

1. **une station, pas un tronçon** — `dsr_measure()` mesure 200 stations pour en rendre une
   médiane ; ici on veut *cette* station, avec ses points ;
2. **le nuage, pas le MNT** ;
3. **le coût d'un clic** — on lit un rectangle de `epaisseur_m` × 2·`demi_largeur`, après avoir
   écarté les dalles par leur en-tête. Mesuré sur la dalle d'exemple `dessertR` (Lozère, 200 m ×
   200 m, 4,5 M points) : **0,42 s par clic** à froid, 0,08 s en cache, ~550 points par coupe.

Le lecteur de nuage est `rlas`, dépendance **optionnelle** accédée dynamiquement — même régime que
`dessertR` (cf. `dessertR_disponible()` et l'en-tête de `R/desserte_lidar.R` : `rlas` est archivé
sur le CRAN, le déclarer casserait l'installation pour tout le monde). Sans lui : `NULL` et un
avertissement, jamais une erreur.

## 4. Les cinq familles de bords — décision de conception

Le brief les laissait ouvertes (« `shoulders` et `rescue` sont à confirmer »). Elles sont définies
**ici**, sur *ce* profil, et emboîtées **par construction** :

```
drivable  ⊆  road  ⊆  rescue  ⊆  right_of_way
```

| clé | ce qu'elle mesure | comment |
|---|---|---|
| `drivable` | la chaussée | plage où le sol reste à `tol_chaussee` (5 cm) de la parabole de bombement ajustée au centre, **écrêtée par `road`** |
| `road` | la plateforme | plage où le sol reste à `tol_plateforme` (15 cm) du plan de chaussée ajusté au centre — méthode « planéité » de `dessertR`, transposée à une station |
| `shoulder` | les accotements | ce qui reste de la plateforme de chaque côté — **deux lignes**, `cote` = `gauche` / `droite` |
| `rescue` | la largeur utilisable en secours | croissance depuis `road` tant que la pente en travers reste sous `pente_max` (20 %), écrêtée par `right_of_way` |
| `right_of_way` | l'emprise dégagée | plage sans écho dans la bande de **troncs** (0,5 à 5 m au-dessus du sol), **unie à `road`** |

L'ordre n'est donc pas espéré, il tient par le code : `drivable` est écrêté, `rescue` part de
`road`, `right_of_way` est une union. Une emprise contient la route qu'elle porte.

**Les troncs, pas le couvert — et c'est une mesure, pas une préférence.** La première version
lisait l'emprise comme *« plage sans écho à plus de 2 m du sol »*, ce qui est la définition
intuitive. Sur la dalle d'exemple `dessertR` (futaie fermée, piste de 3,6 m), les houppiers se
referment **au-dessus** de la piste : ce critère rend une trouée **nulle**, donc une emprise
strictement égale à la plateforme — une famille qui ne dit plus rien, à toutes les stations. Les
troncs, eux, s'écartent : **23 m** de couloir libre à la même station. La bande de mesure est donc
0,5–5 m.

## 5. Le référentiel vertical

`z = 0` est le sol **à l'axe** (altitude MNT à la station), pas le sol sous chaque point. Normaliser
point par point — ce que fait `lasR::normalize()` — aplatirait le bombement, or c'est exactement ce
que `ajustement` ajuste. La hauteur au-dessus du sol local reste disponible par point
(`hauteur_sol`) : c'est elle qui alimente `right_of_way`.

## 6. Contrat de retour

Celui du brief §3, sans écart : `troncon` (`sf`, 1 ligne), `station`, `points` (`x_travers` **signé**
centré sur l'axe, `z`, `intensite`, `sol`, `classification`, plus `hauteur_sol` et `abscisse`),
`sol`, `ajustement` (`a`, `b`, `c`, `rmse`, `n`, `source`), `bords`, `meta`.

`NULL` franc dans les quatre cas dégradés — pas de tronçon dans `tolerance_m`, pas de `rlas`, pas de
dalle sous la station, coupe vide — chacun avec son message `cli`.

## 7. Validation

**Sur données réelles** (dalle d'exemple `dessertR`, MNT 50 cm, BD TOPO livrée avec) :

| grandeur | `profil_travers()` | `dsr_measure()` |
|---|---|---|
| plateforme (`road`) au chaînage 65 m | 3,58 m | 3,58 m (`LARGEUR_ROULABLE_MED`, méthode chaussée) |
| chaussée (`drivable`) | 3,29 m | 3,11 m à la station la plus proche |

Dix stations réparties le long du tronçon : **10/10** rendues, l'emboîtement des quatre familles
respecté partout, 4,2 s pour les dix (caches distincts).

**En CI** (ni `rlas` ni `dessertR`) : une route de synthèse — chaussée bombée de 4 m, accotements à
12 %, banquette à 8 % franchissable, talus à 60 %, **couvert fermé au-dessus de la route** et troncs
à 7 m — dont les quatre bords sont connus. Le nuage est injecté à la place de la lecture LAS. Le cas
« couvert au-dessus de la route » est un **test de non-régression de conception** (§4) : il échoue
si l'on revient à lire l'emprise sur le couvert.

## 8. Dette de dépendance soldée (brief §7)

`nemetonshiny` appelait `dessertR::dsr_classer()` **directement**, alors que `dessertR` n'est
déclaré nulle part dans son `DESCRIPTION`, l'appel étant enveloppé dans un
`tryCatch(error = function(e) NULL)` : sur un poste sans `dessertR`, le classement disparaissait
**sans le dire**.

`classer_desserte()` l'enveloppe (option 1 du brief, celle qui respecte le sens des dépendances :
l'app dépend de `foretaccess`, jamais de son moteur), fait le recast `LINESTRING` une fois pour
toutes, et rend l'indisponibilité **visible** : avertissement, colonnes présentes à `NA`, attribut
`disponible = FALSE`. Un `NA` de classe signifie *non classé*, jamais *rien trouvé*.

## 9. Ce que le lot ne fait pas

* **Aucun graphique** — la planche (plotly) reste côté app, sur le modèle de
  `fct_plot_pixel_dieback.R`.
* **Aucune traduction** — `bords$type` est en clés techniques anglaises ; l'app traduit.
* **Aucune calibration des tolérances** sur vérité terrain. `tol_chaussee`, `tol_plateforme`,
  `pente_max` et `h_obstacle` sont des valeurs d'ordre de grandeur, exposées en arguments, calées
  sur une seule dalle. Les tenir pour calibrées serait la même erreur que celle de la spec 026.
