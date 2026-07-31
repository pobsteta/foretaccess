# specs/026 — Desserte **détectée** sur le MNT comme amorce de conception

> **Statut** : **IMPLÉMENTÉE PARTIELLEMENT, NON VALIDÉE** (2026-07-31).
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
- [ ] **CA-26.5 (juge de paix)** — Sur l'AOI oracle, en régime `complet` et pour
      chaque seuil du balayage 0,4-0,8 : publier le linéaire détecté, la part qui
      survit à la qualification, la part **recoupant un objet BD TOPO connu**
      (cours d'eau, fossé, limite — faux positifs quantifiés sans annotation), et
      le taux de faux positifs résiduel sur orthophoto annotée. Sans ce dernier
      chiffre la fonction n'est pas livrable : on ajouterait du réseau fantôme à
      un modèle qu'on vient de rendre conforme à ACCESSFOR.

      **NON EXERÇABLE SUR L'AOI ORACLE** (mesure du 2026-07-31). Le balayage rend
      **3 linéaires à 0,4 (134 m) et ZÉRO au-delà**.

      **L'explication d'abord retenue — « le corridor ne laisse plus de surface à
      explorer » — est FAUSSE**, et le contrôle du 2026-07-31 la réfute : hors du
      corridor de 15 m, il reste **6,03 km² sur 7,21, soit 83,7 %** de l'emprise.
      La saturation n'est pas la cause. (La densité invoquée, « 44 tronçons sur
      1 km² », mélangeait par ailleurs le linéaire — 44,64 km — et un décompte
      d'objets : la valeur réelle est 197 objets sur 7,21 km².)

      **La cause probable est la résolution du MNT.** Aucun MNT plus fin que
      **5 m** n'existe pour Chastel-Nouvel — l'entrée oracle `mnt.tif` est à 5 m,
      et les caches RGE ALTI de la campagne l'étaient aussi. Or
      `detecter_desserte()` **avertit lui-même au-delà de 1,5 m** que « le
      micro-relief d'une plateforme ancienne ne survit pas à cette résolution ».
      Le balayage a donc tourné à 3,3 fois le seuil de son propre garde-fou.

      C'est le motif exact du faux négatif ALSroads (0/22 à 5 m, 22/22 à 1 m) :
      **conclure à l'échec d'un détecteur qu'on n'a jamais alimenté correctement.**
      Chastel-Nouvel n'est pas un banc valable pour cette spec — non parce qu'il
      est trop desservi, mais parce qu'il n'a pas de MNT à la résolution requise.

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
