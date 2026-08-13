# BRIEF — unification et optimisation des requêtes OpenStreetMap

> **Statut** : ouvert, 2026-08-13.
> **Packages concernés** : `foretaccess` (source canonique), `dessertR`, `nemetonshiny`, `nemeton`.
> **Nature** : refactoring transverse + correction de robustesse. **Aucun changement d'API publique attendu.**
> **Préalable** : lire §0 en entier avant de toucher au code. Deux implémentations divergentes
> coexistent aujourd'hui et chacune a raison sur un point où l'autre a tort.

---

## 0. Pourquoi ce brief

Quatre packages consomment OpenStreetMap, via **deux implémentations indépendantes** du même
besoin, plus des usages tutoriels non maintenus.

| Package | Transport | Lecture | Découpage | Cache |
|---|---|---|---|---|
| `foretaccess` | `osmdata::opq` + `add_osm_feature` + `osmdata_sf` | `osmdata` | 1 requête / AOI, filtre local | GPKG + provenance |
| `dessertR` | `system2("curl")` + Overpass QL brut | `sf::st_read(layer = "lines")` | dalles 1 km | **aucun** |
| `nemetonshiny` | délègue à `foretaccess::acquire_desserte_osm()` | — | — | hérité |
| `nemeton` | `osmdata` dans les tutoriels `.Rmd` uniquement | `osmdata` | bbox | aucun |

**Ce que `dessertR` a compris et que `foretaccess` n'a pas.**

1. Une instance Overpass saturée **ne renvoie pas d'erreur, elle fait attendre**.
   `osmdata::osmdata_sf()` boucle alors en backoff 60 s sans rendre la main, et une rotation
   d'instances qui ne bascule que sur erreur n'est **jamais atteinte**. Mesure consignée dans la
   doc de `acquire_desserte_osm()` : 16 reprises consécutives, soit 16 minutes d'attente pure.
2. `setTimeLimit()` n'y change rien : il n'interrompt qu'aux points de contrôle R, pas un socket
   bloqué dans du C. Il faut une borne **au niveau du transport**.
3. Une instance bridée renvoie un **XML bien formé de quelques centaines d'octets, sans code HTTP
   d'erreur**, avec un élément `<remark>`. Sans ce test on conclut « aucune donnée ici ». C'est
   l'erreur qui a masqué l'absence de DFCI pendant une journée entière.

**Ce que `foretaccess` a compris et que `dessertR` n'a pas.**

1. **Overpass limite le nombre de requêtes, pas la surface.** Le coût suit la densité de voirie.
   Une requête `highway` sur une bbox de massif reste modeste — 5,9 s à froid pour 544 tronçons
   sur l'AOI Dabo. Le tuilage 1 km de `dsr_osm()` transforme une AOI de 10 × 10 km en
   **100 requêtes plus 100 s de `pause`**, ce qui est précisément le comportement qui déclenche
   le `429` que le reste du code s'efforce d'éviter.
2. Le tuilage induit une **redondance de téléchargement** : le `(._;>;)` récupère tous les nœuds
   de chaque way à chaque dalle traversée, puis `!duplicated(osm_id)` jette le surplus.
3. `dsr_osm()` **n'a aucun cache** : ni `st_write`, ni provenance, ni politique de réacquisition.
   Chaque appel retape le réseau. Sur un usage Shiny ou un pipeline relancé, c'est le premier
   poste de coût.

**Conclusion de cadrage.** L'objectif n'est pas de choisir un package gagnant, c'est de produire
**un transport unique** qui prend le bon des deux, et de ramener les quatre consommateurs dessus.

---

## 1. Décision d'architecture à trancher en premier (D1)

Le client Overpass canonique doit vivre **quelque part**. Trois options :

- **(a) Dans `foretaccess`**, exporté, et `dessertR` l'utilise via `Suggests` avec repli sur une
  copie interne. — *Recommandé.* `nemetonshiny` dépend déjà des deux ; `dessertR` reprend déjà
  explicitement la liste de serveurs de `foretaccess` (mention GPL-3 en commentaire de
  `R/acquisition.R`), donc le lien intellectuel existe déjà.
- **(b) Un micro-package `osmclient`** dédié. Plus propre, mais un dépôt de plus à publier,
  documenter et versionner pour ~200 lignes.
- **(c) Duplication assumée**, alignée à l'identique, avec un fichier de référence désigné et un
  test de non-régression partagé.

**Tranchez (a) sauf objection, et écrivez la décision dans un ADR** avant de coder. Si (a),
la dépendance `dessertR → foretaccess` reste en `Suggests` : `dsr_osm()` doit continuer à
fonctionner sans `foretaccess` installé.

---

## 2. Le transport cible — spécification

Fonction unique, sans effet de bord global, à écrire une fois.

```r
osm_overpass(bbox_wgs, cle, valeur = NULL, timeout = 90,
             serveurs = OSM_SERVEURS_OVERPASS, max_reprises = 2)
```

### 2.1 `curl` le package, pas `system2("curl")`

`dessertR` a raison sur la borne au niveau transport, mais `system2("curl", ...)` a trois
défauts : il exige le **binaire** `curl` (fragile sous Windows et en conteneur minimal), il
impose du `shQuote` sur une requête qui contient des guillemets, et il ne donne **pas accès au
code HTTP ni aux en-têtes**.

Utilisez le package R **`curl`** : `curl::new_handle(timeout = ..., connecttimeout = ...)` +
`curl::curl_fetch_memory()`. Le `timeout` de libcurl borne l'appel dans le C de libcurl, donc
il coupe un socket bloqué — c'est exactement la propriété recherchée, sans dépendance binaire.
Vous récupérez en prime `status_code` et `headers`, indispensables pour §2.3.

Ajoutez `curl` en `Imports` des packages concernés.

### 2.2 Trois issues distinctes, jamais confondues

Le point le plus important du brief. La fonction doit rendre un statut discriminant :

| Issue | Signal | Comportement |
|---|---|---|
| **Succès avec données** | XML contenant `<way` | rendre le `sf` |
| **Succès vide** | XML valide, pas de `<way`, **pas** de `<remark>` | rendre un `sf` vide — c'est un résultat |
| **Refus** | `<remark>` présent, ou HTTP 429/504, ou timeout, ou corps < 100 o | **erreur**, jamais une couche vide |

**Ne jamais transformer un refus en résultat vide.** C'est une règle de conservation, déjà
présente en commentaire dans les deux implémentations ; elle doit survivre au refactoring.

### 2.3 Rotation d'instances — sans taper le réseau pour basculer

Piège documenté dans `.fetch_osm()` de `foretaccess` : `osmdata::set_overpass_url()` appelle
`overpass_status()`, donc **le changement d'instance lui-même fait un appel réseau**. Quand
l'instance est saturée, c'est la bascule qui échoue et la rotation meurt avant d'avoir essayé
le moindre miroir.

En n'utilisant plus `osmdata` pour le transport, le problème disparaît par construction :
l'URL devient un simple argument de boucle. Conservez la liste existante, dans l'ordre :

```
https://overpass-api.de/api/interpreter
https://overpass.kumi.systems/api/interpreter
https://overpass.osm.ch/api/interpreter
https://overpass.private.coffee/api/interpreter
```

Sur `429`, honorez l'en-tête `Retry-After` **s'il est présent et inférieur à ~10 s** ; au-delà,
passez à l'instance suivante plutôt que d'attendre. Plafonnez à `max_reprises` par instance.
Le comportement à proscrire est celui d'`osmdata` : attendre 60 s en boucle sans plafond.

Quand une bascule a lieu, informez (`cli::cli_inform`) — `foretaccess` le fait déjà, gardez-le.

### 2.4 Lecture

`sf::st_read(f, layer = "lines")` via le driver OSM de GDAL, comme `dessertR`. Écrivez le corps
de la réponse dans un `tempfile(fileext = ".osm")`. Vérifiez que les colonnes `osm_id`,
`highway` et `other_tags` sont bien remontées ; si `tracktype`/`surface`/`access`/`barrier`
n'apparaissent que dans `other_tags` (comportement du driver selon `OSM_CONFIG_FILE`), prévoyez
un dépliage explicite — `acquire_desserte_osm()` les documente comme colonnes de sortie et ne
doit pas les perdre.

---

## 3. Stratégie de requête — une par AOI, tuilage en repli seulement

**Supprimez le tuilage systématique.** Le découpage 1 km n'est pas gratuit et il travaille
contre les quotas (§0).

Nouvelle logique, à appliquer dans `dsr_osm()` comme dans `acquire_desserte_osm()` :

1. **Une requête sur la bbox complète de l'emprise.**
2. Si elle est refusée pour cause de **volume ou de timeout** (et seulement dans ce cas —
   pas sur un `429`, qui appelle une rotation, pas un découpage), **bissecter en quadrants** et
   réessayer récursivement. Profondeur maximale 3 (soit 64 sous-emprises au pire), au-delà :
   erreur explicite.
3. Dédoublonnage sur `osm_id` à la fusion, comme aujourd'hui.

`dsr_osm()` garde son argument `cote` **pour compatibilité**, mais il devient un plafond de
bissection plutôt qu'un pas de grille, et sa valeur par défaut passe de `DSR_TAILLE_DALLE`
(1000) à `NULL` = pas de découpage a priori. Documentez le changement dans `NEWS.md` : les
appelants qui comptaient sur l'alignement Lidar HD doivent savoir qu'il ne s'applique plus à
la requête OSM (il reste pertinent pour `dsr_catalog()`, qui n'est pas concerné).

L'argument `pause` perd sa raison d'être dans le cas nominal ; gardez-le pour le mode bissection.

---

## 4. Cache et reproductibilité

### 4.1 Aligner `dessertR` sur `foretaccess`

`dsr_osm()` doit gagner cache GeoPackage + provenance, sur le modèle exact de
`acquire_desserte_osm()` : `.chemin_cache()`, `cache_utilisable()`, `.provenance_ecrire()`,
argument `politique_cache`. Si D1 = (a), réutilisez les helpers de `foretaccess` ; sinon,
transposez-les.

### 4.2 Horodater — le manque commun aux deux packages

Aujourd'hui, deux exécutions à un mois d'écart donnent des résultats différents **sans aucune
trace**. Sur des données qui alimentent une conception de réseau, c'est un problème de fond.

Ajoutez systématiquement à la provenance :

- `date_requete` (UTC, ISO 8601) ;
- `instance` (URL Overpass effectivement servie) ;
- `requete` (la chaîne Overpass QL exacte) ;
- `nb_entites` et `lineaire_km` en sortie.

C'est peu de travail et ça rend les diagnostics de type `comparer_desserte_osm()` **datables**,
donc citables.

---

## 5. Travaux par package

### 5.1 `foretaccess` — source canonique

- `R/acquire-osm.R` : remplacer `.fetch_osm()` par le nouveau transport. `osmdata` sort des
  `Suggests` **si plus aucun appel ne subsiste** — vérifiez `acquire_obstacles()`, `acquire_dfci()`
  et les tests.
- `R/desserte-osm.R` : `acquire_desserte_osm()` garde sa signature, son filtrage local
  (`track`, `unclassified`, `service`) et son cache. Seul le transport change.
- Mettre à jour la section `@section Performance:` de `acquire_desserte_osm()` : la mesure
  « 5,9 s à froid, 31 ha » reste valable, mais l'avertissement « plus de 10 minutes un jour de
  bride, 16 reprises » doit être **remplacé** par le nouveau pire cas borné. Ne laissez pas une
  doc qui décrit un comportement corrigé.
- `acquire_obstacles()` fait aujourd'hui **une requête par couple (clé, valeur)**, soit 5 appels
  pour les 4 types par défaut. Regroupez-les en une seule requête Overpass à filtres multiples
  (union `(way[...];way[...];)`) puis dispatch local par tag. Gain direct : 5 → 1.
- Idem `acquire_dfci()` : 3 requêtes pour `ref:FR:DFCI`, `ref:dfci`, `dfci_ref` → 1 requête
  avec union de filtres. Gain : 3 → 1.

### 5.2 `dessertR`

- `R/acquisition.R` : `.dsr_requete_overpass()` est **conservée telle quelle** (la construction
  QL est bonne). `.dsr_fetch_osm()` est remplacée par le transport commun. Gardez le test
  `<remark>` — il migre dans le transport, il ne disparaît pas.
- `.dsr_tuiles()` n'est plus appelée par `dsr_osm()` en nominal. Vérifiez si elle sert ailleurs
  avant de la supprimer ; sinon marquez-la `@noRd` interne de bissection.
- `dsr_osm()` : nouvelle stratégie §3 + cache §4.
- Retirer la dépendance implicite au **binaire** `curl` (`system2`). Elle n'est déclarée nulle
  part dans `DESCRIPTION` aujourd'hui, ce qui est un bug latent en conteneur.

### 5.3 `nemetonshiny`

- `R/service_desserte.R` continue d'appeler `foretaccess::acquire_desserte_osm()` — rien à
  changer fonctionnellement, mais **vérifiez que l'appel est asynchrone et annulable**. La doc
  de la fonction l'exige explicitement (« un bouton qui appelle cette fonction doit donc être
  asynchrone et annulable ») ; le pire cas est maintenant borné mais reste de l'ordre de la
  dizaine de secondes.
- `osmdata` peut probablement sortir du `DESCRIPTION` : aucun appel direct n'a été trouvé dans
  `R/`. Confirmez avant de retirer.
- Les fonds de carte (`leaflet::addProviderTiles("OpenStreetMap")`, `maptiles::get_tiles()`)
  ne sont **pas** concernés par ce brief. N'y touchez pas.
- Prévoir une invalidation de cache : les sorties changent (colonnes de provenance, et
  potentiellement la couverture si la bissection remplace le tuilage).

### 5.4 `nemeton`

Périmètre minimal, priorité basse.

- `inst/tutorials/03-terrain/03-terrain.Rmd` (densité de sentiers, indicateur S3) et
  `04-ecological.Rmd` (landuse en repli d'OCS-GE) utilisent `opq |> add_osm_feature |> osmdata_sf`
  directement. Ils tournent en `requireNamespace()` conditionnel avec `tryCatch` — c'est
  acceptable pour un tutoriel.
- **Action** : ajouter une note dans chaque chunk indiquant que le chemin de production est
  `foretaccess::acquire_desserte_osm()` / le client commun, et que l'appel direct `osmdata` est
  pédagogique. Ne réécrivez pas les tutoriels dans ce lot.

---

## 6. Piste hors périmètre, à instruire séparément

Si la cible devient **le massif entier en traitement batch**, ni Overpass ni le tuilage ne sont
le bon outil. Un extrait Geofabrik `.pbf` (via `osmextract::oe_get()` ou directement GDAL) se
télécharge une fois, se filtre localement, **ne consomme aucun quota** et porte une **date**,
donc il est reproductible.

Overpass doit rester réservé aux **petites AOI interactives** — exactement le cas `nemetonshiny`.

**N'implémentez pas cette piste dans ce lot.** Ouvrez une spec dédiée
(`specs/0XX-osm-extraits-pbf.md`) et laissez la décision à Pascal.

---

## 7. Tests

- **Aucun test ne doit taper le réseau.** `foretaccess` a déjà `tests/testthat/helper-acquire.R`
  qui mocke `.fetch_osm` : reprenez le motif pour le nouveau transport et étendez-le à `dessertR`.
- Cas à couvrir explicitement, un test par ligne du tableau §2.2 :
  - réponse avec `<way>` → `sf` non vide ;
  - réponse valide sans `<way>` et sans `<remark>` → `sf` vide, **pas d'erreur** ;
  - réponse avec `<remark>` → **erreur**, et le message contient le texte du remark ;
  - HTTP 429 sur l'instance 1, succès sur l'instance 2 → succès + message de bascule ;
  - toutes instances en échec → erreur relayant la dernière cause.
- Test de bissection : simuler un timeout sur la bbox complète, un succès sur les quadrants,
  vérifier la fusion et le dédoublonnage `osm_id`.
- Test de cache : deux appels successifs, le second ne doit **pas** appeler le transport (mock
  compteur).

---

## 8. Critères d'acceptation

1. Un seul chemin de code fait un appel réseau vers Overpass dans l'écosystème (hors tutoriels
   `nemeton`, explicitement dérogés).
2. `acquire_obstacles()` : 5 requêtes → 1. `acquire_dfci()` : 3 → 1. `dsr_osm()` sur une AOI de
   10 × 10 km : ~100 requêtes → 1 en nominal.
3. Aucun appel ne peut dépasser `timeout × longueur(serveurs) × (1 + max_reprises)` secondes.
   Écrivez ce plafond dans la doc roxygen.
4. Un refus Overpass ne produit jamais une couche vide. Test dédié présent et passant.
5. `dsr_osm()` a un cache et une provenance horodatée, comme `acquire_desserte_osm()`.
6. `devtools::check()` propre sur `foretaccess`, `dessertR` et `nemetonshiny`.
7. Les mesures de performance dans les `@section Performance:` sont **re-mesurées**, pas
   recopiées, et datées.

---

## 9. Garde-fous

- **Ne cassez aucune signature publique.** `dsr_osm()`, `acquire_desserte_osm()`,
  `acquire_obstacles()`, `acquire_dfci()` gardent leurs arguments. Les arguments devenus inertes
  (`cote`, `pause`) sont dépréciés en douceur, pas supprimés.
- **Ne touchez pas aux fonds de carte** (`leaflet`, `maptiles`).
- **N'augmentez le nombre de requêtes nulle part.** Si une optimisation locale se paie en appels
  supplémentaires, elle n'en est pas une.
- **`rosm` n'a rien à faire ici** : c'est un fournisseur de tuiles raster, pas un client de
  données vectorielles. Si le nom apparaît dans une proposition, c'est une erreur d'aiguillage.
- Ne remplacez pas les commentaires de rationale existants par des commentaires descriptifs.
  Ceux qui expliquent *pourquoi* (le backoff d'`osmdata`, le piège de `set_overpass_url`, le
  `<remark>`) sont le produit d'incidents réels et doivent **migrer** avec le code, pas mourir
  avec lui.
