# specs/026 — Desserte **détectée** sur le MNT comme amorce de conception

> **Statut** : **IMPLÉMENTÉE PARTIELLEMENT, NON VALIDÉE** (2026-07-31).
> **CA-26.5 : protocole réécrit** le 2026-07-31 (§6.0) — l'ancien balayait
> `seuil` en tenant l'emprise pour neutre et mesurait un artefact. Aucune mesure
> antérieure à cette date n'est recevable (§6.0.5).
> `detecter_desserte()` et `detecter_desserte_balayage()` sont livrés
> (`R/desserte-detectee.R`, §5.1-5.2) ainsi que le tarif de réouverture (§5.3,
> `config$desserte$cout$fraction_reouverture`). **L'injection dans
> `reseau_desserte()` (§5.4) n'est délibérément PAS faite** : elle attend le
> CA-26.5, faute de quoi on ajouterait du réseau fantôme à un modèle qu'on vient
> de rendre conforme à ACCESSFOR. Second banc désigné le 2026-07-31 (§6.1).
> Décisions §7 prises par l'utilisateur
> le 2026-07-29. Indépendante des specs
> [024](024-desserte-clsvac-regle-publiee.md) (classification) et
> [025](025-integrite-reseau-desserte.md) (intégrité), mais consomme leurs
> sorties. Version cible : `1.30.0` (feat).
> **Origine** : question utilisateur du 2026-07-29 — *« est-ce que ça prend en
> compte les débuts de piste que le package découvre sur le MNT en plus de la
> BD TOPO ? »*

## 1. Le problème que ça résout

`reseau_desserte(pre, cout, parcelles, desserte_existante, ...)` conçoit un
réseau en raccrochant les parcelles à un réseau **existant**. Aujourd'hui
`desserte_existante` vient d'`acquire_desserte()`, donc de la **BD TOPO seule**.

Or une partie du réseau réel n'y est pas : pistes de débardage anciennes,
cloisonnements, tracés effacés du couvert mais **toujours lisibles dans le
micro-relief**. Le modèle propose alors de créer ce qui existe déjà, et
surestime d'autant le coût de mobilisation.

C'est un enjeu économique, pas cosmétique : une plateforme déjà terrassée se
rouvre pour une fraction du coût d'un tracé neuf. Notre barème actuel
(`desserte$cout$cout_base_m = 20` €/m, surcoût de pente 0/25/90/Inf) ne sait
distinguer que « construire » et « ne pas construire ».

## 2. Le constat de la spec 021 est périmé

`qualifier_desserte()` porte encore ceci (`R/desserte_qualif.R:26`) :

> the engine *corrects* an existing map, it does **not** detect roads absent from
> BD TOPO — those stay absent.

La spec 021 §5 renvoyait la détection à un jalon de recherche (un CNN sur canaux
RVT). **Ce n'est plus vrai** : dessertR expose `dsr_detecter()` et
`dsr_indice_detection()`, qui font exactement ça, et dont la doc énonce le besoin
mot pour mot :

> Fusionne les signaux disponibles en une carte de probabilité `p_desserte` dans
> [0, 1], **hors du corridor du réseau de référence** (BD TOPO).

## 3. Les briques sont déjà là

| brique | où | état |
|---|---|---|
| conception de réseau | `reseau_desserte()`, `desserte_trace()`, `optimiser_reseau()` | livrée (lots 14-18) |
| canaux morphométriques | `vat_combined()` (CVAT), `rvt_svf_opns()` (Rust), `micro_relief()` | livrés, CVAT validé 99,998 % vs plugin RVT |
| conductivité géomorpho | `dsr_conductivite()` via `.dsr_canaux_dalles()` | déjà appelé par l'adaptateur dessertR |
| canal de surface | `dsr_sigma_surf()` | déjà calculé, déjà utilisé pour l'état |
| **détection hors référence** | `dsr_detecter()` / `dsr_indice_detection()` + `dsr_vectoriser()` | **disponible, non branché** |

Rien à réimplémenter (règle stricte 1). Le chaînon manquant est un adaptateur.

`dsr_detecter()` prend `sigma_geo`, `reference` (notre desserte, exclue via
`buffer_ref = 15` m), `sigma_surf`, `vesselness`, et filtre déjà sur `long_min`
(30 m) et `ratio_min` (3, élongation) — donc élimine les taches compactes.

## 4. Les deux pièges, à traiter avant tout branchement

**On ne détecte pas « des pistes », on détecte des linéaires creux.** Le
micro-relief garde aussi les drains, fossés, limites parcellaires, terrasses et
traces fossiles. dessertR le dit lui-même : le canal de surface est pondéré
double (`poids = c(geo = 1, surf = 2, vessel = 1)`) précisément parce que les
pistes se lisent d'abord dans la **discontinuité du sous-étage**, leur empreinte
au sol étant « faible ou noyée dans les traces fossiles ». Injecter la sortie
brute dans `desserte_existante` ferait rouler un skidder dans un fossé.

**Une piste détectée n'est pas une piste utilisable.** Elle n'a ni largeur, ni
état, ni portance mesurés. Elle doit passer par la même chaîne que la desserte
déclarée — `dsr_measure()`, `dsr_trafficability()` — avant d'être admise. C'est
la chaîne Phase B (v1.26.1), appliquée cette fois à des tracés qu'on vient
d'inventer, donc avec un risque d'échec de mesure bien plus élevé.

## 5. Proposition

### 5.1. `detecter_desserte()` — une couche **candidate**, séparée

Enveloppe `dsr_detecter()`. Rend un `sf` de `LINESTRING` avec `p_desserte` par
tronçon et l'attribut `source = "detectee"`. **Jamais fusionnée d'office** dans
la desserte déclarée : c'est une couche distincte, à qualifier.

### 5.2. Qualification obligatoire

La couche candidate passe par `qualifier_desserte()` avant tout usage. Un tronçon
détecté n'est admis que s'il obtient une `largeur_carrossable_m` mesurée et un
`apte_grumier` non-`FALSE`. Les autres restent dans la couche candidate, pour
inspection, mais n'entrent pas dans la conception.

### 5.3. Un coût de **réouverture**, distinct du coût de création

C'est là que se joue le gain. Nouveau paramètre `desserte$cout$cout_reouverture_m`,
appliqué aux cellules couvertes par un tronçon détecté **et qualifié**. Le surcoût
de pente continue de s'appliquer (une plateforme ancienne sur pente forte reste
chère à remettre en état) mais la base baisse.

Valeur par défaut : **0,65 × `cout_base_m`**, sourcée sur deux barèmes régionaux
(cf. §7.3). Exprimée en fraction pour que le barème de base reste le seul point
de calage.

### 5.4. Injection **opt-in** dans la conception

`reseau_desserte(..., desserte_detectee = NULL)`. Par défaut `NULL` : comportement
strictement inchangé. Fourni, les tronçons qualifiés deviennent du réseau
raccrochable au tarif réouverture.

## 6. Critères d'acceptation

- [ ] **CA-26.1** — `detecter_desserte()` rend un `sf` de linéaires **hors** du
      corridor de la desserte déclarée, avec `p_desserte`. Sans `dessertR`,
      dégradation propre (couche vide + message), jamais d'échec.
- [ ] **CA-26.2** — La couche candidate n'entre **jamais** dans
      `desserte_existante` sans qualification.
- [ ] **CA-26.3** — `reseau_desserte(desserte_detectee = NULL)` reproduit
      bit-pour-bit la sortie actuelle.
- [ ] **CA-26.4** — Le coût de réouverture est appliqué aux seules cellules de
      tronçons détectés **et** qualifiés.
- [ ] **CA-26.5 (juge de paix)** — **protocole réécrit le 2026-07-31**, voir
      §6.0. L'ancienne rédaction balayait `seuil` de 0,4 à 0,8 en tenant
      l'emprise pour neutre : elle mesurait un artefact. Détail en §6.3.

### 6.0. CA-26.5 — protocole (réécriture du 2026-07-31)

**Ce que le CA doit établir** : que la détection trouve de la desserte *réelle*
et *absente de la BD TOPO*, en quantité et en pureté suffisantes pour qu'on
puisse en ajouter au réseau sans le fausser. Rien de moins ne justifie
d'appliquer le tarif de réouverture à des cellules détectées.

#### 6.0.1. Préconditions — à vérifier **avant** toute mesure, et à publier

Chacune a coûté une journée de mesures fausses au moins une fois.

| # | précondition | contrôle |
|---|---|---|
| P1 | MNT ≤ **1,5 m** | `max(terra::res(mnt))` — garde-fou de `detecter_desserte()` |
| P2 | canal de surface **consommé**, pas seulement disponible | `attr(det, "canal_surface")` — jamais `list.files()` |
| P3 | `dessertR` ≥ **1.1.0** | sinon `c_vessel` est ignoré et la mesure redevient relative |
| P4 | specs **absolues** — toute borne `a`/`b` renseignée | un canal sans bornes retombe sur les quantiles |
| P5 | vectoriseur **nommé**, jamais subi | `methode` explicite ; un repli silencieux change la chaîne mesurée |
| P6 | banc **disjoint** du jeu de calibration | recouvrement mesuré et publié |

#### 6.0.2. Ce qu'on balaye — et ce qu'on ne balaye plus

Balayer `seuil` n'avait de sens que si `seuil` désignait une quantité absolue.
Depuis que les bornes sont figées, **c'est le cas** — le balayage redevient
licite, mais il n'est plus le cœur du protocole. Les trois variables à mesurer,
par ordre d'effet observé :

1. **`long_min`** — le filtre de longueur décide de tout. Mesuré : 23 linéaires
   à 5 m contre 1 à 30 m, sur la même fenêtre. À balayer sur **5, 10, 15, 20,
   30, 50 m**.
2. **`seuil`** — plage 0,4 → 0,8, désormais interprétable entre sites.
3. **`methode`** — `squelette` et `agent` explicitement, jamais `auto`.

#### 6.0.3. Ce qu'on publie, par point de mesure

| grandeur | définition |
|---|---|
| `n`, `km` | linéaire détecté hors corridor de référence |
| `km_qualifie` | part survivant à [`qualifier_desserte()`] |
| `km_recoupe`, `pct_recoupe` | part recoupant un objet BD TOPO connu (cours d'eau, fossé, limite) — faux positifs **sans annotation** |
| `pct_annote` | **taux de faux positifs sur orthophoto annotée** |
| `km2_explorable` | surface hors corridor — le dénominateur, sans quoi `km` ne veut rien dire |

**`pct_annote` reste bloquant** — mais la méthode est **établie et éprouvée**,
pas à inventer. Le CA-28.5 (spec 028) a été tranché le 2026-07-31 par annotation
utilisateur : 24 tronçons `track` OSM hors corridor, 13,41 km, sur ortho IGN
actuelle **et historique**. Outillage réutilisable tel quel :
`data-raw/oracle/aoi/annoter.qgz` (projet QGIS, millésimes WMS du §7.5) et
`a_annoter_osm.gpkg`. Le recoupement automatique *réduit* ce travail, il ne le
remplace pas : un linéaire qui ne recoupe aucun objet connu peut être une
terrasse, une limite non cartographiée ou une trace fossile.

#### 6.0.4. Seuil de recevabilité

**Référence disponible** : le gisement **OSM** annoté rend **92,9 %** de desserte
réelle pour **4,4 %** de faux positifs avérés (CA-28.5). C'est le point de
comparaison, et il est exigeant — un gisement détecté qui tolérerait 20 % de faux
positifs serait quatre fois plus sale que celui dont on dispose déjà, pour un
coût d'instruction bien supérieur.

Le CA-26.5 est **atteint** si, pour au moins un jeu de paramètres :

* `pct_annote` ≤ **10 %** de faux positifs sur l'échantillon annoté — deux fois
  la tolérance mesurée sur OSM, pas davantage ;
* `km_qualifie` ≥ **0,5 km/km² explorable** — en deçà, l'apport ne justifie pas
  le risque de fausser le réseau ;
* l'échantillon annoté compte au moins **20 linéaires** **de longueur médiane
  ≥ 100 m** — les deux conditions, pas l'une ou l'autre ;
* le tout sur un banc **disjoint** du jeu de calibration (P6).

> **Correction du 2026-07-31, au premier usage du critère.** La rédaction
> initiale exigeait « au moins 20 linéaires » sans condition de longueur. Le banc
> `wsfi` l'a **satisfait avec 21 linéaires totalisant 255 m — 12 m de moyenne**,
> c'est-à-dire du bruit. Un critère d'effectif qui ne regarde pas la longueur se
> laisse satisfaire par la fragmentation, exactement le travers reproché au
> protocole précédent. Le seuil de 100 m est prudent : le CA-28.5 mesure **559 m
> de moyenne** sur le gisement OSM (13,41 km pour 24 tronçons), soit cinq fois
> plus. En deçà de 100 m, on n'annote pas une desserte, on annote un fragment.

Il est **rejeté** — et la spec close en « détection non exploitable » — si aucun
jeu de paramètres n'y parvient sur deux bancs indépendants.

**Le blocage réel n'est pas l'annotation, c'est le volume à annoter.**

#### 6.0.6. Première mesure conforme au protocole — banc `wsfi`, 2026-07-31

`data-raw/banc_wsfi_longmin.R`, seuil 0,4, méthode `squelette` (nommée).
Préconditions **P1–P5 vertes** (MNT 0,50 m ; canal de surface **consommé**,
attribut et non `list.files()` ; dessertR 1.1.0 ; 10 canaux à bornes absolues ;
vectoriseur nommé). **P6 violée** — la dalle de calibration est le quart
sud-ouest de l'emprise —, d'où la colonne « hors calibration ».

| `long_min` | linéaires | total | hors dalle de calibration |
|---:|---:|---:|---:|
| 5 m | 21 | 255 m | **243 m** |
| 10 m | 9 | 170 m | 170 m |
| 15 m | 4 | 112 m | 112 m |
| 20 m | 1 | 58 m | 58 m |
| 30 m | 1 | 58 m | 58 m |

**Volume : NON ATTEINT.** 0,078 km/km² explorable au mieux, contre 0,5 exigé —
il manque un facteur **6,4**.

**La circularité n'explique rien** : 243 des 255 m tombent *hors* de la dalle de
calibration, qui ne produit presque rien. La violation de P6 ne gonfle donc pas
le résultat, elle le laisse intact.

**Longueur médiane 12 m** contre 559 m pour le gisement OSM (CA-28.5) : deux
ordres de grandeur. Ce sont des fragments, pas des dessertes — d'où la
correction du critère d'effectif ci-dessus.

**Conclusion partielle.** Le §6.0.4 exige **deux bancs indépendants** pour
rejeter ; nous en avons **un** valide, Chastel-Nouvel étant disqualifié par P1
(MNT 5 m). Pas de rejet formel, donc, mais la direction n'est pas ambiguë :
dans des conditions enfin valides, la détection MNT rend 255 m de fragments là
où **`acquire_desserte_osm()` rend 13,41 km à 93 % de justesse**. Le second banc
indépendant (bloc `ltcp`) est ce qui manque pour trancher — et l'annotation n'a
pas lieu d'être tant que le volume est à ce niveau.

#### 6.0.5. Ce qui invalide une mesure, explicitement

Une mesure est **nulle et non avenue** si l'une des préconditions P1-P6 n'est pas
publiée avec elle, ou si le vectoriseur a replié sans qu'on le nomme. C'est la
règle qui manquait : les mesures du 2026-07-31 (balayage de 82 min, balayage
`long_min`, comparaison Chastel-Nouvel/`wsfi`) violent P3, P4 et P5, et sont donc
écartées — pas discutées.

### 6.1. Le second banc — bloc `wsfi` (désigné le 2026-07-31)

Bloc **`wsfi`** du projet nemeton, déjà utilisé comme jeu de validation de
`dessertR` lui-même. Chemin (**lecture seule**, cf. §6.2) :

```
/home/pascal/.local/share/nemeton/projects/20260717_101641_wsfi/cache/layers/
```

Chiffres **mesurés** par `data-raw/banc_wsfi_026.R` le 2026-07-31, sur l'emprise
du banc = emprise de la mosaïque MNT (2 × 2 km) :

| | Chastel-Nouvel | **wsfi** |
|---|---:|---:|
| **résolution MNT** | **5 m** ❌ | **0,50 m** ✅ |
| emprise | 7,21 km² | 4,00 km² |
| forêt | — | 3,68 km² |
| surface hors corridor 15 m | 6,03 km² (83,7 %) | 3,10 km² (77,6 %) |
| réseau BD TOPO | 47,05 km / 197 obj. | 32,13 km / 129 obj. |
| densité / emprise | 6,53 km/km² | **8,03 km/km²** |
| densité / forêt | 7,89 km/km² | **8,74 km/km²** |
| dalles LiDAR classées | — | **4** (COPC, LAS 1.4) |
| altitude | — | 827 – 1263 m |

Classes ACCESSFOR (spec 024) dans l'emprise : 60 `piste`, 32 `route`,
7 `reseau_public`, 30 `hors_desserte`.

> **Trois chiffres de la première rédaction de cette fiche étaient faux**
> (corrigés ci-dessus le 2026-07-31). Ils avaient été lus sur `roads.gpkg`, la
> couche que **nemeton** met en cache dans le bloc — 51 objets, 16,4 km, natures
> 29 `Chemin` / 10 `Route empierrée` / 3 `Route à 1 chaussée` / 9 `Sentier`.
> Cette couche est découpée sur l'AOI du **projet nemeton**, plus petite que la
> mosaïque MNT sur laquelle le banc travaille. Décrire un banc avec les chiffres
> d'une **autre emprise** est la même faute que servir un cache produit avec
> d'autres paramètres (spec 027) : la fiche d'un banc se **mesure** sur l'emprise
> du banc, elle ne se recopie pas d'une couche voisine.

**Ce qui en fait le bon second banc, par ordre d'importance :**

1. **Un MNT à 50 cm** — trois fois plus fin que le seuil du garde-fou, dix fois
   plus fin que Chastel-Nouvel. C'est la raison décisive, et c'est **la seule qui
   ait survécu à la mesure** : c'est le premier site où l'exigence de résolution
   de la spec est effectivement satisfaite.
2. **Le canal de surface est disponible** — 4 dalles LiDAR classées. Sans lui,
   dessertR annonce une détection « nettement moins sûre », et c'est le canal
   qu'il pondère **double**.
3. ~~**Moins desservi**~~ — **RÉFUTÉ par la mesure.** `wsfi` est **plus** dense
   que Chastel-Nouvel, pas moins : 8,74 contre 7,89 km/km² de forêt, et 8,03
   contre 6,53 km/km² d'emprise. Le « 4,92 km/km², soit 38 % de moins » venait de
   la couche nemeton sur une emprise plus petite.

**Ce qui l'affaiblit, à ne pas passer sous silence** — et la mesure a **aggravé**
ce point au lieu de le rassurer : l'emprise est plus petite (4,00 contre
7,21 km²), le réseau y est plus dense, et la surface explorable tombe à
**3,10 km² contre 6,03, soit 0,51×** (et non 0,6× comme d'abord écrit). Un
résultat nul sur wsfi est donc **encore moins concluant** que prévu : il cumule
une emprise réduite et une desserte plus serrée. Si le CA-26.5 n'est pas tranché
ici, il faudra un **troisième** bloc plus vaste — le projet `ltcp` (25 dalles,
5×5 km) est le candidat déjà identifié.

**Biais à déclarer** : `wsfi` est le jeu sur lequel `dessertR` a été calibré
(mémoire `dessertr-validation-wsfi`). Valider notre détection dessus mesure
l'intégration, **pas** la généralisation. Le constat dessertR du 2026-07-28 y est
d'ailleurs défavorable : « repositionnement sur `sigma_geo` SEUL n'aide pas, le
pathfinder accroche des linéaires parallèles (fossés, traces fossiles) » —
exactement le piège du §4. À contraindre par `sigma_surf`, et à ne jamais
présenter comme une validation indépendante.

### 6.2. Règle d'usage du bloc

Le répertoire `wsfi` appartient à **nemeton**. Il est en **lecture seule** depuis
une session ForêtAccess (règle stricte 6) : aucune écriture, aucun `git`, aucune
purge de cache. Toute sortie du banc est écrite dans
`data-raw/oracle/wsfi/`, jamais dans le projet nemeton. Le chemin est lu depuis
la variable d'environnement `FA_WSFI` avec ce défaut, pour que le banc reste
rejouable ailleurs.

**`wsfi` ne satisfait PAS la précondition P6.** Le recouvrement avec l'AOI oracle
est de **2,143 km² sur 4,00**, soit **54 %**, et la dalle sur laquelle les specs
sont calibrées (`LHD_FXX_0737_6385`) est son **quart sud-ouest**. Un résultat
obtenu sur `wsfi` entier est donc partiellement circulaire. Deux issues : scorer
uniquement sur les 3 km² **hors** dalle de calibration, ou passer au bloc `ltcp`
(25 dalles, 5 × 5 km) comme banc disjoint.

### 6.3. Pourquoi le protocole précédent était invalide

L'ancien CA-26.5 balayait `seuil` de 0,4 à 0,8 en régime `complet` et comparait
les sites entre eux. Trois explications successives ont été données à ses zéros,
les deux premières fausses :

1. *« Le corridor de 15 m ne laisse plus de surface à explorer »* — **réfuté** :
   hors corridor, il reste 6,03 km² sur 7,21, soit **83,7 %**.
2. *« La cause est le MNT à 5 m, 3,3× le seuil du garde-fou »* — **non
   confirmé** : `wsfi`, MNT **0,50 m** avec canal de surface, rend **zéro aux
   cinq seuils** en 82 min. Dix fois plus fin, et moins de détections.
3. **La cause réelle : la détection dépendait de l'emprise soumise.** La même
   fenêtre de 0,25 km² rendait **116 m** analysée seule et **0 m** analysée dans
   4 km². `dsr_appartenance()` dérivait ses bornes des quantiles de la donnée
   reçue, et `dsr_frangi()` son `c` du maximum de l'image — ce second mécanisme
   agissant **en amont** des bornes, donc hors de leur portée. Le `seuil` n'était
   pas une quantité absolue mais un **rang dans l'emprise**.

Corrigé en amont le jour même (**dessertR 1.1.0** : `dsr_calibrer_specs(bornes =
TRUE)`, `dsr_c_vessel()`, `dsr_layers_dtm(c_vessel = )`). Trace :
`docs/brief-dessertR-ancrage-emprise.md`.

**Ce que ça enseigne au protocole**, et qui est la vraie raison de la
réécriture : un balayage ne vaut que si la grandeur balayée est **absolue**.
Balayer un rang en le prenant pour une mesure, c'est produire un tableau de
chiffres cohérents entre eux et sans référent. Les préconditions P1-P6 du §6.0.1
existent pour que cette faute soit détectable **avant** la mesure, pas après.

**Restriction en vigueur** : `dsr_detecter()` ne peut pas amorcer le vectoriseur
`agent` quand `buffer_ref > 0` — `dsr_amorces()` filtre ses amorces sur
`!is.na(p)` à l'extrémité des tronçons de référence, qui est précisément la zone
masquée. Le vectoriseur par défaut replie donc sur le squelette dans le cas
d'usage de cette spec. Tant que ce n'est pas corrigé en amont, **P5 impose de
nommer `methode = "squelette"`** plutôt que de subir le repli.

## 7. Décisions prises (2026-07-29)

1. **Seuil : balayage `0,4 → 0,8`, courbe publiée.** On ne pose pas un seuil, on
   mesure où la détection décroche. Le livrable est la courbe « linéaire détecté ×
   faux positifs » par seuil, pas un chiffre unique.
2. **Régime : `complet` pour la validation, `corridor` en production.** Le
   dénominateur du taux de faux positifs doit être non biaisé — un corridor le
   tire vers les zones déjà intéressantes. Deux modes à maintenir, chaque chiffre
   restant interprétable.
3. **`cout_reouverture_m` : SOURCÉ (2026-07-30), fraction de `cout_base_m`,
   défaut 0,65.** Deux barèmes régionaux indépendants, repris de **plafonds de
   dépense fixés par l'État** (dispositifs FEADER), distinguent création et
   *mise au gabarit* d'une route forestière empierrée :

   | | création | mise au gabarit | ratio |
   |---|---:|---:|---:|
   | Puy-de-Dôme | 65 000 €/km | 45 000 €/km | 0,69 |
   | Auvergne-Rhône-Alpes | 65 000 €/km | 40 000 €/km | 0,62 |

   Le défaut retenu est le milieu, **0,65**, exprimé en **fraction** de
   `cout_base_m` et non en valeur absolue : le barème de base reste ainsi le seul
   point de calage.

   **Validation incidente** : le barème donne « création de route forestière en
   terrain naturel : 20 000 €/km », soit exactement notre `cout_base_m = 20` €/m,
   posé antérieurement. Et « piste forestière : 8 000 €/km » recoupe les 5,5 à
   8 €/m relevés par ailleurs pour les pistes de débardage.

   **RÉSERVE, à ne pas perdre** : « mise au gabarit » désigne l'élargissement
   d'une route **existante et praticable** aux normes. La spec 026 vise une piste
   **effacée du couvert**, dont seule la plateforme subsiste dans le
   micro-relief : pas de couche de roulement à reprendre, mais de la végétation à
   rouvrir. Aucun des barèmes consultés ne comporte de ligne « réouverture
   d'ancienne piste ». **0,65 est un point d'ancrage défendable, pas une mesure
   du bon objet.**
4. **Faux positifs : recoupement automatique BD TOPO d'abord.** Combien de
   linéaires détectés tombent sur des objets connus (cours d'eau, fossés,
   limites) ? Ça chiffre une part des faux positifs sans annotation humaine.
   **L'annotation reste nécessaire pour le reste** — ce recoupement la réduit, il
   ne la remplace pas, et le CA-26.5 n'est pas satisfait sans elle.

5. **L'annotation se fait sur l'ortho HISTORIQUE, pas seulement l'actuelle**
   (2026-07-31). Une piste effacée du couvert ne se voit **plus** aujourd'hui —
   sinon la BD TOPO la porterait. Sur une photo prise quand le peuplement était
   plus jeune, elle peut apparaître **en service**. L'IGN diffuse ces millésimes
   par WMS (`https://data.geopf.fr/wms-r/wms`) :

   | couche | usage |
   |---|---|
   | `ORTHOIMAGERY.ORTHOPHOTOS.1950-1965` | **la preuve décisive** : la piste en service |
   | `ORTHOIMAGERY.ORTHOPHOTOS.1965-1980` | millésime intermédiaire |
   | `ORTHOIMAGERY.ORTHOPHOTOS.BDORTHO` | état actuel du terrain |
   | `ORTHOIMAGERY.ORTHOPHOTOS.IRC-EXPRESS.<année>` | infrarouge, la végétation ressort |

   Un linéaire détecté dans le micro-relief **et** visible sur une photo de 1960
   est une piste ancienne, sans discussion. Détecté sans rien sur aucun millésime,
   il reste douteux — terrasse, limite parcellaire, trace fossile.

   Corollaire de méthode : **ne pas regarder `tracktype` avant de trancher**.
   Renseigné une fois sur deux (§CA-28.2), le connaître oriente le jugement.
   Annoter sur l'image, comparer ensuite.

## 8. Ce que ça n'est PAS

- Pas une correction de la BD TOPO : la desserte déclarée reste autoritaire,
  la détection ne fait qu'**ajouter** des candidats.
- Pas le CNN de la spec 021 §5. C'est l'approche morphométrique de dessertR,
  déterministe et explicable. Le CNN reste un jalon distinct.
- Pas un changement des moteurs terrestres ni du câble (règle 1).
- Pas une garantie de conformité ACCESSFOR : ACCESSFOR **ne détecte rien**, il
  consomme la BD TOPO. Cette spec nous en **éloigne** délibérément, au nom du
  réalisme économique. À activer en connaissance de cause, et à ne jamais laisser
  par défaut dans une comparaison ACCESSFOR.

## 9. Sources

- `dessertR` : `?dsr_detecter`, `?dsr_indice_detection`, `?dsr_vectoriser`.
- `specs/021` §5 (le jalon de recherche que cette spec rend caduc),
  `specs/014` (barème de coût), `specs/016` (réseau MTAP).
- **Barèmes de desserte** (consultés le 2026-07-30) :
  [Puy-de-Dôme](https://www.puy-de-dome.fr/subventions/guide-des-aides-departementales/aide-a-la-desserte-forestiere.html),
  [Communes forestières AURA](https://www.communesforestieres-aura.org/article_535_102_le-reglement-de-l-aide-regionale-a-la-creation-de-desserte-forestiere-se-precise.html),
  [Zimmer — coût des routes forestières](https://www.zimmersa.com/blog-forestier/des-routes-forestieres-quoi-comment-et-a-quel-prix--n125),
  [CNPF, fiche desserte](https://ifc.cnpf.fr/sites/socle/files/cnpf-old/441060_fiche33_desserte_ok_1.pdf).
- `R/desserte_reseau.R` (`reseau_desserte()`), `R/config.R` (`desserte$cout`).

---

## Mesure du 2026-08-12 — ce ne sont pas les bornes

Sur **ForetAccess** (`wsfi`), MNT LiDAR 0,5 m, **3 590 730 cellules**, référence réelle de
3 299 tronçons, nuage LiDAR effectivement lu (`canal_surface = TRUE` dans les trois cas) :

| forme de `specs` | durée | tronçons détectés |
|---|---:|---:|
| défaut (bornes figées, §Calibration) | 930,2 s | **0** |
| `specs = NULL` (quantiles dessertR) | 569,4 s | **0** |
| `specs = "auto"` (calibré sur place) | 877,3 s | **0** |

`"auto"` retient **5 canaux sur 7** — `rugosite`, `openness_pos`, `vesselness`, `pente`,
`openness_neg` — soit exactement ce que `dsr_calibrer_specs()` mesure de son côté. **La
calibration voit donc bien un signal, et la détection rend quand même zéro.**

**Trois stratégies de bornes indépendantes convergent vers zéro**, dont une calibrée sur ces
données mêmes. L'hypothèse « bornes figées inadaptées au massif » est donc **écartée pour ce
jeu** : soit il n'y a rien à détecter sur ces 31 ha de forêt privée, soit le modèle ne sait pas
le voir.

> **TRANCHÉ le 2026-08-12 — c'est la seconde branche.** La campagne d'annotation
> (`data-raw/annotation_wsfi/RESULTATS.md`) a trouvé **4 pistes réelles sûres** absentes de la
> BD TOPO sur 8,91 ha analysables scrutés, toutes **à 100 % hors du corridor d'exclusion** — le
> détecteur avait donc le droit de les voir. Il n'en a trouvé aucune : **rappel 0 %**, candidat
> le plus proche à 170 m. Ses 2 seuls candidats sont dans une tuile où l'annotateur n'a rien vu :
> **précision 0 %**. Extrapolation : ~31 dessertes non cartographiées (IC95 8–79) sur l'emprise.
>
> **Le détecteur est aveugle, il n'y a pas « rien à trouver ».** La conclusion inverse, écrite ici
> la veille, est réfutée.
>
> **Suite, le même jour — pourquoi, et le rappel une fois réparé.** Trois verrous en série, aucun
> suffisant seul :
> 1. **un veto `vesselness` compté deux fois.** `dsr_detecter()` fusionne en moyenne géométrique
>    pondérée, donc dominée par son plus PETIT terme : un poids n'y dose pas une contribution,
>    **il arme un veto**. `vesselness` y pèse 1 et entre par une rampe démarrant à 0,3, alors que
>    1,62 % des cellules l'atteignent ici. Sur les cellules des 4 pistes, `p_desserte` passe de
>    0,210 (géomorphologie seule) à **0,001**. Et il figurait déjà dans `specs$geomorpho`, calibré
>    entre 0,00064 et 0,0708 — borne haute **4,2 fois plus basse** que la rampe du veto ;
> 2. **`long_min = 30`.** Seules ~12 % des cellules d'une piste passent le seuil : le squelette se
>    fragmente en morceaux de 5 à 7 m, et le filtre les élimine tous. Il ne filtrait pas le bruit,
>    il filtrait le **signal fragmenté** ;
> 3. **les bornes figées, faibles ici** — médiane 0,210 sur les pistes annotées, contre 0,403 avec
>    des bornes recalibrées localement.
>
> | configuration | rappel | précision |
> |---|:---:|:---:|
> | origine | **0 / 4** | 0 / 2 |
> | veto retiré + `long_min 10` | 2 / 4 | — |
> | + bornes annotées, **leave-one-out** | **3 / 4 = 75 %** | **36 %** |
>
> Le leave-one-out donne le même chiffre que le test circulaire : la calibration **généralise**.
> Le revers est la précision — 7 faux positifs sur 11 détections. Détail dans
> `data-raw/annotation_wsfi/RESULTATS.md` §6.
>
> **Conséquence pour cette spec** : `long_min = 30` est un défaut à réexaminer, et la
> `@section Performance` de la fusion mérite d'être lue avant tout réglage de poids.
>
> **Second bloc, `ltcp`, préparé le 2026-08-13.** Le veto y était **absolu** — maximum de
> vesselness 0,1729 pour une rampe démarrant à 0,30, soit **zéro cellule éligible sur 4 millions**
> (contre 1,62 % sur `wsfi`) ; la rampe y serait 161,8 fois au-dessus de la borne calibrée du
> canal, contre 4,2 fois sur `wsfi`. Le défaut n'était donc pas une particularité de `wsfi`.
>
> Une fois corrigé, la détection y rend **87 tronçons / 2 214 m** sur 100 ha, dont 13 dans les
> tuiles à scruter — contre 2 tronçons sur `wsfi`. **Cet écart n'est pas interprétable sans
> annotation** : plaine plus riche en linéaires anciens, ou faux positifs sur micro-relief de
> drainage. Campagne prête (`data-raw/annotation_ltcp/`).
>
> Deux enseignements de méthode, obtenus en TRANSPORTANT le protocole plutôt qu'en le rejouant :
> * la **stratification par pente** est vide de sens sur une plaine (étendue p10–p90 de 1,9° contre
>   20° sur `wsfi`) — le générateur mesure désormais l'étendue et bascule en tirage simple en le
>   disant ;
> * les **bornes figées, calibrées en montagne, saturent en plaine** (`svf` 99 %, `openness_pos`
>   98 %). `specs = "auto"` n'y est pas une option mais une nécessité.

**Conséquence pour le CA-26.5.** Le protocole du §6.0 balaie `long_min` en supposant qu'il existe
un jeu de paramètres rendant du linéaire. Sur `wsfi`, aucun réglage de **bornes** n'y suffit — le
balayage doit donc porter sur un bloc où l'on a établi indépendamment qu'il **y a** quelque chose
à trouver, sans quoi on mesure la sensibilité d'un détecteur à un signal absent. C'est un
argument de plus pour le bloc `ltcp`, disjoint du jeu de calibration (cf. `data-raw/banc_longmin.R`
et son `FA_BLOC`).

**Ce que la mesure ne dit pas** : elle ne prouve pas qu'il n'y a rien. Une détection à zéro sur
un massif ne distingue pas « absence de gisement » de « détecteur aveugle à ce type de gisement ».
Trancher demanderait une annotation sur orthophoto — la part que le CA-26.5 exige et qui n'a
toujours pas été produite.
