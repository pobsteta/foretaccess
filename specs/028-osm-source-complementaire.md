# specs/028 — OSM comme source **complémentaire** de desserte

> **Statut** : **PROPOSÉE** — décisions §7 à prendre. Version cible : `1.30.0`
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

- [ ] **CA-28.1** — `acquire_desserte_osm()` rend les `highway` filtrés avec
      leurs attributs ; sans réseau, dégradation propre. Overpass injoignable →
      **erreur relayée**, jamais une couche vide (règle posée le 2026-07-30).
- [ ] **CA-28.2** — Publier le **taux de renseignement de `tracktype`** sur les
      `track` de l'AOI. Sans ce chiffre, aucun pré-tri ne s'appuie dessus.
- [ ] **CA-28.3** — `comparer_desserte_osm()` reproduit la table du §1.
- [ ] **CA-28.4** — Aucun tronçon OSM n'entre dans `desserte_existante` sans
      qualification (invariant testé).
- [ ] **CA-28.5 (juge de paix)** — Sur un échantillon des 13,52 km de `track`
      hors corridor : quelle part est **réellement** de la desserte forestière
      absente de la BD TOPO ? Un linéaire hors corridor peut être un décalage de
      saisie, une trace erronée ou un chemin non carrossable. Recoupement
      automatique BD TOPO d'abord (comme au CA-26.5), annotation ensuite.

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
