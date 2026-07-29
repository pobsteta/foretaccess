# specs/026 — Desserte **détectée** sur le MNT comme amorce de conception

> **Statut** : **PROPOSÉE** — décisions §7 à prendre. Indépendante des specs
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

Valeur par défaut : à caler. Je ne propose pas de chiffre — le poser au doigt
mouillé ferait basculer des arbitrages économiques sur une constante inventée.

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
- [ ] **CA-26.5 (juge de paix)** — Sur l'AOI oracle : publier le linéaire
      détecté, la part qui survit à la qualification, et le **taux de faux
      positifs sur orthophoto** (échantillon annoté à la main). Sans ce chiffre,
      la fonction n'est pas livrable — on ajouterait du réseau fantôme à un
      modèle qu'on vient de rendre conforme à ACCESSFOR.

## 7. Décisions à prendre

1. **Le seuil de détection** (`seuil = 0.6` par défaut chez dessertR) : le garder
   ou le caler sur l'AOI ? Un seuil bas gonfle les faux positifs, un seuil haut
   rate les pistes anciennes — c'est-à-dire justement celles qui ont de la valeur.
2. **Le régime** : `"complet"` (balayer toute la grille) ou `"corridor"`
   (restreindre à une emprise autour des parcelles à desservir) ? Le second est
   bien moins coûteux et suffit sans doute au cas d'usage.
3. **`cout_reouverture_m`** : quelle valeur, et sur quelle base ? Barème ONF,
   dire d'expert, ou paramètre laissé sans défaut pour forcer un choix explicite ?
4. **L'échantillon d'annotation** pour le CA-26.5 : qui annote, sur quelle
   surface, avec quelle orthophoto ?

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
- `R/desserte_reseau.R` (`reseau_desserte()`), `R/config.R` (`desserte$cout`).
