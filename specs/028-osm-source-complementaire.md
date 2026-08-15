# specs/028 — OSM comme source **complémentaire** de desserte

> **Statut** : **IMPLÉMENTÉE ET VALIDÉE** ; **tous les CA sont soldés** au
> 2026-08-15. Le juge de paix CA-28.5
> donne **93 % du linéaire** en desserte réelle, pour 4 % de faux positifs. Version cible : `1.30.0`
> (feat). Complète la spec [026](026-desserte-detectee-mnt.md) : celle-ci cherche
> la desserte dans le **micro-relief**, celle-là dans une source **déjà
> vectorisée**. Les deux alimentent la même couche candidate.
> **Origine** : demande utilisateur du 2026-07-30, et mesure faite le jour même.

## 1. Le problème que ça résout

La spec 026 part du constat qu'une partie du réseau réel n'est pas dans la
BD TOPO. Elle propose de le retrouver par détection morphométrique — coûteux, et
avec des faux positifs par construction (drains, limites parcellaires, traces
fossiles).

**OSM contient déjà une partie de cette desserte manquante, vectorisée et
attribuée.** Mesuré sur l'AOI oracle (Chastel-Nouvel) le 2026-07-30 :

| | BD TOPO | OSM |
|---|---:|---:|
| objets (AOI stricte) | 169 tronçons | 115 lignes |
| linéaire | 44,64 km | **73,35 km** |

### 1.1. Ce qu'OSM apporte

Linéaire OSM par type, et part **hors d'un corridor de 15 m** autour de la
BD TOPO :

| type OSM | total | hors corridor |
|---|---:|---:|
| `track` | 40,28 km | **13,52 km** |
| `path` | 17,53 km | 14,09 km |
| `unclassified` | 8,47 km | 1,06 km |
| `tertiary` | 6,59 km | 3,79 km |
| `service` + `residential` | 0,48 km | 0,05 km |

**55,7 % du linéaire OSM tombe déjà dans le corridor BD TOPO.** Le gisement
exploitable est concentré dans les **13,52 km de `track`** — la catégorie des
pistes carrossables. Les 14,09 km de `path` sont majoritairement de la randonnée,
sans valeur pour le débardage.

### 1.2. Ce que la BD TOPO apporte qu'OSM ignore

Linéaire BD TOPO hors corridor OSM, par classe :

| classe | hors corridor OSM |
|---|---:|
| `piste` | **5,40 km** |
| `route` | 0,00 km |
| `reseau_public` | 0,01 km |

**OSM couvre la quasi-totalité des routes et du réseau public** — 10 m d'écart
cumulé sur 88 tronçons. La complémentarité est donc **asymétrique et entièrement
concentrée sur les pistes** : OSM en apporte ~13,5 km d'inconnues, la BD TOPO en
apporte 5,4 km qu'OSM n'a pas.

### 1.3. Ce que `hors_desserte` change à ces tables (2026-08-15)

Les deux tables ci-dessus ont été mesurées le 2026-07-30 sur une BD TOPO de
**169 tronçons / 44,64 km**. Depuis le jour même (`6b9df26` / `451935d`),
`acquire_desserte()` conserve par défaut la classe **`hors_desserte`** (sentiers,
ronds-points, liaisons — `CL_SVAC = 0`) : sur la même AOI, elle ajoute
**45 tronçons / 11,13 km**, soit 214 tronçons / 55,77 km.

Ces tronçons **élargissent le corridor**, donc réduisent mécaniquement le
linéaire OSM compté « hors corridor » :

| | table du §1 (169 tr.) | défaut actuel (214 tr.) |
|---|---:|---:|
| OSM déjà dans le corridor | 55,7 % | **64,2 %** |
| `track` hors corridor | 13,52 km | **12,07 km** |
| `path` hors corridor | 14,09 km | **9,30 km** |
| `unclassified` / `tertiary` / `service` | 1,06 / 3,79 / 0,05 km | identiques |

Le §1.2 (BD TOPO hors corridor OSM) est **inchangé** : `piste` 5,40 km, `route`
0,00 km, `reseau_public` 0,01 km — `hors_desserte` n'y ajoute qu'une **ligne**
(4,20 km) sans toucher aux trois autres.

**Ce resserrement va dans le bon sens** : un `track` OSM qui suit un sentier déjà
présent en BD TOPO n'est pas une découverte, et c'est précisément ce que
`hors_desserte` absorbe. La table du §1 reste la référence historique de la
mesure ; c'est la colonne de droite qui décrit ce qu'un appelant obtient
aujourd'hui **sans argument particulier**.

## 2. Pourquoi c'est préférable à la détection, et pourquoi ça ne la remplace pas

**Préférable** : déjà vectorisé (pas de squelettisation), déjà attribué
(`tracktype`, `surface`, `access`, `barrier`), et **sans faux positifs
géomorphologiques** — un `track` OSM n'est jamais un fossé. Le volume à annoter
pour le CA-26.5 s'en trouve considérablement réduit.

**Ne remplace pas** : OSM ne contient que ce que quelqu'un a cartographié. Les
pistes **anciennes, effacées du couvert** mais lisibles dans le micro-relief —
précisément l'intérêt économique de la spec 026, puisque leur plateforme existe
déjà — n'y sont pas. Les deux sources visent des gisements disjoints.

## 3. Ce qui rend la source utilisable

`highway=track` porte `tracktype` (`grade1` à `grade5`), qui décrit la
consistance de la surface — de la voie stabilisée à la trace non consolidée. Cet
attribut est le candidat naturel pour un pré-tri avant qualification LiDAR, et
potentiellement pour un mapping direct vers CL_SVAC.

**Il n'est pas systématiquement renseigné.** La proportion sur l'AOI n'a pas été
mesurée — à faire avant de s'appuyer dessus (CA-28.2).

## 4. Proposition

### 4.1. `acquire_desserte_osm()`

Récupère les `highway` sur l'emprise via `.fetch_osm()` (rotation d'instances
déjà en place), filtre sur une liste de types configurable — défaut
`c("track", "unclassified", "service")`, **`path` exclu** — et rend un `sf`
avec `source = "osm"`, `highway`, `tracktype`, `surface`, `access`.

### 4.2. Un recoupement, pas une fusion

`comparer_desserte_osm(bdtopo, osm, corridor_m = 15)` rend le linéaire de part et
d'autre, par type et par classe : la table du §1, reproductible sur toute AOI.
C'est le livrable de diagnostic, **antérieur** à toute intégration.

Depuis `2.4.0`, elle rend aussi la **géométrie** hors corridor —
`$osm_hors_corridor` et `$bdtopo_hors_corridor`, deux `sf` de tronçons
**clippés** (attributs d'origine plus `hors_m`). Elle la calculait déjà pour
mesurer le linéaire ; l'ajout ne coûte rien de plus, et il permet d'**inspecter**
ce que la table compte, pas seulement de la lire (cf. CA-28.3).

### 4.3. Alimentation de la couche candidate de la spec 026

Les tronçons OSM hors corridor rejoignent la **même couche candidate** que les
linéaires détectés, avec `source = "osm"` au lieu de `"detectee"`. Ils suivent
**le même parcours** : qualification LiDAR obligatoire, puis injection opt-in
dans `reseau_desserte()` au tarif réouverture.

Aucun chemin ne doit permettre à un tronçon OSM d'entrer dans `desserte_existante`
sans qualification. La règle de la spec 026 vaut ici sans exception.

### 4.4. Ce qui n'est pas décidé ici

Le **mapping `tracktype` → CL_SVAC** est tentant (`grade1`/`grade2` →
`route`, `grade3`+ → `piste`) mais ce serait une seconde règle de classification
concurrente de celle de l'annexe ACCESSFOR. À trancher séparément, après mesure
du taux de renseignement.

## 5. Ce que ça n'est PAS

- Pas un remplacement de la BD TOPO : elle reste la **référence autoritaire**,
  OSM n'ajoute que des candidats.
- Pas la détection morphométrique (spec 026) : gisements disjoints.
- Pas une conformité ACCESSFOR : ACCESSFOR consomme la BD TOPO seule. Comme la
  spec 026, cette source **nous en éloigne** délibérément et ne doit jamais être
  active dans une comparaison ACCESSFOR.

## 6. Critères d'acceptation

- [x] **CA-28.1 — ATTEINT**, couvert par `tests/testthat/test-desserte-osm.R`
      depuis l'implémentation, coché le 2026-08-15. Les trois volets ont chacun
      leur test : *« ne retient que les types de desserte »* (`highway` filtrés,
      `source = "osm"`, `path` et `tertiary` exclus, `tracktype` conservé),
      *« Overpass injoignable LEVE, ne rend jamais une couche vide »* (erreur
      relayée — la règle posée le 2026-07-30), et *« une emprise sans ligne OSM
      rend une couche vide, pas une erreur »* (dégradation propre). Overpass
      n'étant pas joignable en CI, `.fetch_osm()` y est mocké.
- [x] **CA-28.2 — MESURÉ** (2026-07-31) : `tracktype` renseigné sur **12 des 24
      `track`** hors corridor de l'AOI, soit **50 %**. Un pré-tri sur cet attribut
      laisserait la moitié du gisement sans information : utilisable comme
      **indice**, pas comme **filtre**. Valeurs présentes : 8 `grade2`,
      3 `grade3`, 1 `grade4`.
- [x] **CA-28.3 — ATTEINT** (2026-08-15, `data-raw/ca_28_3_table_sec1.R`, AOI
      Chastel-Nouvel). Sur les **mêmes entrées** que la mesure d'origine — BD TOPO
      restreinte aux trois classes de desserte (169 tronçons, 44,64 km, valeurs de
      la table au tronçon et au centième près) et OSM en une requête `highway`
      toutes valeurs (115 lignes, 73,35 km) — `comparer_desserte_osm()` rend la
      table du §1.1 **cellule pour cellule** :

      | type | total (réf / obtenu) | hors corridor (réf / obtenu) | écart |
      |---|---:|---:|---:|
      | `track` | 40,28 / 40,28 | 13,52 / **13,522** | 0,00 |
      | `path` | 17,53 / 17,53 | 14,09 / **14,090** | 0,00 |
      | `unclassified` | 8,47 / 8,47 | 1,06 / **1,058** | 0,00 |
      | `tertiary` | 6,59 / 6,59 | 3,79 / **3,792** | 0,00 |
      | `service`+`residential` | 0,48 / 0,48 | 0,05 / **0,052** | 0,00 |

      Part déjà dans le corridor : **55,7 %** contre 55,7 %. Le §1.2 tombe juste
      aussi, et sans retrait de classe : `piste` **5,4006** km, `reseau_public`
      **0,0099** km, `route` **0,000** km.

      L'écart apparent avec le défaut d'aujourd'hui (64,2 %, `track` à 12,07 km)
      ne vient **pas** de la fonction mais de son entrée : voir §1.3.

      Deux corroborations au passage, sur la couche `$osm_hors_corridor` livrée en
      `2.4.0` : `tracktype` renseigné sur **13 `track` sur 26** — les 50 % du
      CA-28.2, réaffirmés deux semaines plus tard sur un tirage indépendant — et
      la longueur de chaque géométrie clippée **égale `hors_m` à 0 m près**, ce qui
      prouve que la colonne et la géométrie décrivent bien le même objet.

      Une nuance à garder : sur les entrées du §1, les `track` hors corridor sont
      aujourd'hui **28 tronçons pour 13,52 km**, là où l'annotation du CA-28.5 en
      couvrait **24 pour 13,41 km**. Les 4 tronçons de plus pèsent 0,11 km — des
      bouts, pas un gisement — mais le taux de 92,9 % porte sur les 24 annotés,
      pas sur les 28.
- [x] **CA-28.4 — ATTEINT** (2026-08-15). La règle n'était tenue que par la
      discipline de l'appelant : elle est désormais une **erreur**.
      `.reseau_preparer()` — le point de passage commun de [`reseau_desserte()`]
      et [`optimiser_reseau()`] — refuse une `desserte_existante` portant
      `source` `"osm"` ou `"detectee"` dont les lignes ne sont pas marquées
      `qualifiee`. `qualifier_desserte()` pose désormais cette marque **en
      colonne** en plus de l'attribut de couche : seule la colonne survit au
      sous-ensemble et à la fusion avec la BD TOPO.

      Une desserte BD TOPO pure n'a **pas** de colonne `source` : le contrôle est
      alors un no-op, sans effet sur les appels existants. 7 tests
      (`test-desserte-reseau.R`, `test-desserte-optim.R`) : OSM refusé, `detectee`
      refusé de la même façon, qualifié par colonne accepté, par attribut accepté,
      mélange BD TOPO + OSM brut mis en cause **pour le seul OSM**, BD TOPO pure
      intacte, et l'optimisation qui ne contourne pas l'invariant.

      **Limite assumée** : on vérifie que le tronçon est *passé par*
      `qualifier_desserte()`, pas que la mesure a abouti. Sans LiDAR (NDP 0) cette
      fonction rend la couche telle quelle en la marquant qualifiée — contrat
      antérieur à ce contrôle. La porte fermée ici est celle du **candidat brut**.
      L'autre porte, `preprocess(desserte = )`, n'est pas gardée : le CA nomme
      `desserte_existante`, et l'étendre demanderait de trancher le cas d'une
      desserte candidate consommée par les quatre moteurs.
- [x] **CA-28.5 (juge de paix) — ATTEINT** (annotation utilisateur du
      2026-07-31, 24 tronçons `track` hors corridor, 13,41 km, sur ortho IGN
      actuelle et historique) :

      | verdict | n | km | % du linéaire |
      |---|---:|---:|---:|
      | `piste` | 20 | 12,46 | **92,9 %** |
      | `non_piste` | 2 | 0,59 | 4,4 % |
      | `doute` | 2 | 0,36 | 2,7 % |

      **93 % du linéaire est de la desserte forestière réelle absente de la
      BD TOPO**, pour 4 % de faux positifs avérés. Le gisement OSM est donc
      exploitable : la réserve du §1.1 — « un linéaire hors corridor n'est pas
      une desserte manquante prouvée » — reste juste sur le principe, mais le
      taux mesuré la borne à moins d'un vingtième du linéaire.

      À confirmer sur une seconde AOI avant d'en faire une règle générale : 24
      tronçons sur un seul site, et le gisement `path` (14,09 km) n'a pas été
      annoté puisqu'il est exclu par défaut.

## 7. Décisions à prendre

1. **Liste de types par défaut** : `track` + `unclassified` + `service`, ou
   `track` seul ? Les 3,79 km de `tertiary` hors corridor interrogent — une
   départementale absente de la BD TOPO est plus probablement un décalage.
2. **`path` définitivement exclu ?** 14,09 km hors corridor, mais un `path` peut
   être une piste dégradée mal taguée. Coût d'instruction contre gisement.
3. **Millésime OSM** : figer une date d'extraction pour la reproductibilité d'un
   banc, ou toujours prendre le courant ? Un banc oracle a besoin de stabilité.
4. **`tracktype` → CL_SVAC** : après le CA-28.2, ou jamais ?

## 8. Sources

- Mesure du 2026-07-30 : `data-raw/diag_osm_vs_bdtopo.R`, AOI Chastel-Nouvel.
- `R/acquire-osm.R` (`.fetch_osm()`, rotation d'instances Overpass).
- `specs/026` (détection morphométrique), `specs/024` (classification CL_SVAC).
- `man_made=cutline` : **0 objet** sur l'AOI élargie à 2 km. Le tag n'est pas
  utilisé ici ; sa vérification régionale n'a pas abouti (Overpass saturé).
