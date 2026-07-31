# specs/027 — Marqueur de **provenance** dans les caches d'acquisition

> **Statut** : **IMPLÉMENTÉE** (`R/cache-provenance.R`, 2026-07-30 ; couverture
> complétée le 2026-07-31). Version cible : `1.29.0`
> (feat). Transversale : concerne toutes les fonctions `acquire_*`.
> **Origine** : **cinq incidents en deux jours** (2026-07-29/30), tous de la même
> cause. Aucun ne s'est signalé ; trois ont fait circuler des résultats faux.

## 1. Le problème que ça résout

Un cache d'acquisition est un fichier nommé d'après **ce qu'il contient**
(`desserte.gpkg`, `mnt.tif`, `foret.gpkg`), jamais d'après **ce qui l'a produit**.
Il ne porte ni la couche source, ni la version du paquet, ni les paramètres de la
règle qui l'a construit. Conséquence : toute correction du code est **annulée en
silence** pour quiconque possède déjà un cache.

Le journal des deux derniers jours :

| incident | cache | ce qui a circulé |
|---|---|---|
| classification desserte | `desserte.gpkg` | mapping `heuristique` servi après le passage en `clsvac` |
| masque forêt | `foret.gpkg` | 13 polygones de landes, exclus par ACCESSFOR |
| **MNT** | `mnt.tif` (14 juillet) | RGE ALTI par WMS, *blocky*, pentes fausses jusqu'à **382 %** |
| acquisition WFS | `desserte.gpkg` | réseau amputé de 110 tronçons intérieurs |
| DFCI / Overpass | *(pas de cache)* | « OSM injoignable » rendu comme « rien ici » |

Les trois premiers sont exactement le même défaut. Le troisième a fait tourner le
banc `aoi` **deux semaines sur un terrain fictif**, et n'a été trouvé que parce
qu'on a demandé *sur quel MNT* Sylvaccess avait tourné.

Aucun n'aurait survécu à un marqueur de provenance.

## 2. Ce que fait le contournement actuel

Rien de systématique. Trois rustines, chacune spécifique :

* `acquire_foret()` applique son filtre **aussi à la relecture** du cache ;
* `acquire_desserte()` ne le fait pas — le cache prime sur l'argument
  `classification`, silencieusement ;
* pour le MNT, il a fallu purger à la main après avoir compris le problème.

L'asymétrie est en soi un piège : rien ne dit à l'appelant lesquelles de ses
entrées sont rejouées et lesquelles sont figées.

## 3. Proposition

### 3.1. Un sidecar de provenance, pas un nom de fichier

À côté de chaque fichier de cache, un `<couche>.provenance.json` :

```json
{
  "couche": "desserte",
  "source": "BDTOPO_V3:troncon_de_route",
  "service": "https://data.geopf.fr/wfs/ows",
  "version_paquet": "1.28.0.9000",
  "date": "2026-07-30T18:42:11Z",
  "parametres": { "classification": "accessfor", "crs": 2154,
                  "garder_hors_desserte": true, "tuile_m": 2000 },
  "empreinte": "sha256:..."
}
```

Le **sidecar** plutôt qu'un nom de fichier encodé : le nom reste lisible et
stable pour les outils SIG, et la provenance peut s'enrichir sans casser les
chemins existants.

### 3.2. Contrôle à la relecture

`.cache_valide(chemin, attendu)` compare la provenance enregistrée aux paramètres
de l'appel courant. Trois issues :

* **concordance** → cache servi, comme aujourd'hui ;
* **divergence** → selon `politique_cache` (§3.3) ;
* **absence de sidecar** (cache antérieur à cette spec) → traité comme une
  divergence, avec un message distinct : on ne peut pas savoir, donc on ne
  suppose pas que c'est bon.

### 3.3. `politique_cache`, un seul réglage transversal

| valeur | comportement sur divergence |
|---|---|
| `"reacquerir"` (**défaut**) | ignore le cache et refait l'acquisition |
| `"avertir"` | sert le cache **avec un `cli_warn`** nommant ce qui diverge |
| `"echouer"` | `cli_abort` — pour les bancs et la CI, où un cache périmé fausse une mesure publiée |
| `"ignorer"` | comportement actuel, sans contrôle |

Le défaut à `"reacquerir"` est un choix : le coût d'une ré-acquisition est
mesurable, celui d'un résultat faux ne l'est pas. Le MNT du 14 juillet a coûté
deux semaines de banc et deux conclusions retirées.

### 3.4. Ce que la provenance doit contenir, et pas plus

**Ce qui change le contenu** : couche source, service, paramètres de la règle
(classification, filtres, résolution, tuilage), CRS. **Pas** ce qui n'a pas
d'effet : chemin du cache, machine, utilisateur. Une provenance trop bavarde
invaliderait des caches sains et pousserait à mettre `politique_cache =
"ignorer"` — ce qui ramènerait au problème de départ.

## 4. Ce que ça n'est PAS

* Pas un système de versionnement de données ni un cache distribué.
* Pas une garantie de fraîcheur **de la source** : si l'IGN republie sa BD TOPO,
  la provenance est inchangée et le cache reste servi. Détecter ça demanderait
  d'interroger le millésime à chaque appel — hors périmètre, à traiter séparément.
* Pas un remplacement du filtre à la relecture d'`acquire_foret()` : les deux
  sont complémentaires, l'un corrige, l'autre alerte.

## 5. Critères d'acceptation

- [x] **CA-27.1 — TENU** (complété le 2026-07-31). Toute fonction `acquire_*`
      écrit un sidecar et contrôle à la relecture. **La première livraison ne le
      tenait pas** : `acquire_mnt_rgealti()` et `acquire_cadastre()` servaient
      leur cache sans aucun contrôle — dont, ironiquement, celle écrite *en
      réponse* à l'incident du MNT blocky. Un cache à 5 m aurait été servi à qui
      demande 1 m, rejouant le même scénario à la résolution près. Le trou tenait
      à un test qui vérifiait **quelques** fonctions au lieu de les **énumérer** ;
      il énumère désormais (`test-cache-provenance.R`).
- [x] **CA-27.2 — TENU** — divergence → comportement de `politique_cache` ; le
      défaut `"reacquerir"` ré-acquiert.
- [x] **CA-27.3 — TENU** — cache sans sidecar traité comme divergent, message
      distinct (`"sidecar_absent"`).
- [x] **CA-27.4 — TENU** — les cinq incidents du §1 sont rejoués et détectés.
- [x] **CA-27.5 — TENU** — `"ignorer"` reproduit le comportement antérieur.

## 6. Portée

`acquire_mnt()`, `acquire_mnt_rgealti()`, `acquire_desserte()`,
`acquire_foret()`, `acquire_obstacles()`, `acquire_obstacles_bdtopo()`,
`acquire_dfci()`, `acquire_cadastre()`, `.acquire_retournements()`, et
`acquire_inputs()` qui doit propager `politique_cache`.

## 7. Décisions prises (2026-07-30)

1. **Défaut `"reacquerir"`** — retenu. Un avertissement dans un script de banc se
   noie dans la sortie, et c'est précisément ce qui s'est produit avec le MNT.
2. **Bancs de `data-raw/` en `"echouer"`** — retenu : ce sont eux qui publient
   des chiffres, un cache périmé y est plus grave qu'ailleurs.
3. **Empreinte `sha256` : NON retenue.** Coûteuse sur un MNT de 250 Mo, et elle
   détecterait une corruption ou une édition manuelle — pas le défaut visé, qui
   est un cache *intact* produit avec d'autres paramètres. Aucun des cinq
   incidents du §1 n'aurait été pris par une empreinte.
4. **Migration : pas de purge.** Un cache sans sidecar est traité comme divergent
   (CA-27.3), donc ré-acquis au défaut — la migration se fait d'elle-même, sans
   détruire quoi que ce soit. Choix conforté par la perte irréversible d'une
   entrée de banc le 2026-07-31 : le code ne supprime pas de données d'entrée.

## 8. Sources

- `PLAN.md`, journal des 2026-07-29 et 2026-07-30 (les cinq incidents).
- `R/acquire-ign.R` (`.chemin_cache()`, `acquire_mnt()`, `acquire_desserte()`,
  `acquire_foret()`), `R/acquire-osm.R`, `R/acquire-obstacles-ign.R`.
