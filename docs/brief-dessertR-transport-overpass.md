# BRIEF `dessertR` — reprendre le transport Overpass canonique

> Réponse au `BRIEF-osm-overpass-unification.md`, §5.2.
> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/dessertR`**
> (un repo = une session). Côté `foretaccess`, tout le §5.1 est livré.
> Décision D1 actée : **ADR-010**, le client canonique vit dans `foretaccess`.

## Ce qui est livré côté `foretaccess`

`osm_overpass()`, exporté, qui prend le bon de vos deux implémentations :

* **de vous** — la borne au niveau du transport (`curl`, pas `osmdata`), et le
  test du `<remark>` qui distingue un refus d'un vide ;
* **de nous** — une requête par AOI plutôt qu'un tuilage, et le cache.

Trois issues, jamais confondues, et c'est le contrat :

| issue | signal | comportement |
|---|---|---|
| données | XML contenant `<way` | rend le `sf` |
| vide légitime | XML valide, pas de `<way`, **pas** de `<remark>` | rend un `sf` vide |
| refus | `<remark>`, HTTP 429/504, timeout, corps < 100 o | **erreur** |

Durée bornée : `timeout × length(serveurs) × (1 + max_reprises)`, écrit dans la
doc comme le §8.3 l'exige.

## Ce que nous avons changé par rapport à votre implémentation

**`curl` le paquet, pas `system2("curl")`.** Votre borne transport est la bonne
idée ; l'exécutable ne l'est pas. Il exige un binaire (fragile sous Windows et en
conteneur minimal), impose du `shQuote` sur une requête pleine de guillemets, et
ne donne accès **ni au code HTTP ni aux en-têtes** — dont on a besoin pour lire
`Retry-After` et pour distinguer un 429 d'un 504. À déclarer en `Imports` : la
dépendance au binaire n'est aujourd'hui déclarée nulle part chez vous, ce qui est
un bug latent en conteneur.

**Le tuilage systématique disparaît.** Une AOI de 10 × 10 km devenait 100
requêtes plus 100 s de `pause` — soit précisément ce qui déclenche le 429 que le
reste du code s'efforce d'éviter. Une seule requête en nominal ; bissection en
quadrants **seulement** sur un refus de volume ou de timeout, jamais sur un 429
(qui appelle une rotation, pas un découpage). Profondeur maximale 3.

## Ce que nous vous demandons

1. **`.dsr_fetch_osm()` → `foretaccess::osm_overpass()`**, en `Suggests` avec
   repli sur votre copie interne : `dsr_osm()` doit continuer de fonctionner sans
   `foretaccess` installé.
2. **`.dsr_requete_overpass()` est conservée telle quelle** — la construction QL
   est bonne, nous l'avons reprise dans l'esprit.
3. **Gardez le test `<remark>`.** Il migre dans le transport, il ne disparaît
   pas. C'est votre apport le plus précieux du lot.
4. **`.dsr_tuiles()`** n'est plus appelée en nominal. Vérifiez si elle sert
   ailleurs (`dsr_catalog()` n'est pas concerné) avant de la supprimer ; sinon
   marquez-la interne de bissection.
5. **`cote` et `pause` sont dépréciés en douceur, pas supprimés** — `cote`
   devient un plafond de bissection, défaut `NULL`. À dire dans `NEWS.md` : les
   appelants qui comptaient sur l'alignement LiDAR HD doivent savoir qu'il ne
   s'applique plus à la requête OSM.
6. **Cache + provenance horodatée** sur le modèle d'`acquire_desserte_osm()` :
   `date_requete` (UTC ISO 8601), `instance` servie, `requete` exacte,
   `nb_entites`. Aujourd'hui deux exécutions à un mois d'écart diffèrent **sans
   aucune trace** — sur des données qui alimentent une conception de réseau,
   c'en est un problème de fond.

## Un point qui vous concerne particulièrement

`rlas`, dépendance dure de `dessertR`, est **archivé sur le CRAN**. C'est pour
cette raison que `foretaccess` ne peut pas vous déclarer en `Suggests` (la
déclaration a fait échouer quatre jobs de CI en 90 secondes), et c'est aussi
l'argument qui a fait pencher D1 vers `foretaccess` plutôt que vers vous : y
placer le transport l'aurait rendu inatteignable pour qui ne peut pas installer
`dessertR`. Si `rlas` revient au CRAN, ou si vous pouvez vous en passer, dites-le
— nous vous redéclarerons aussitôt.

## Ce que ce brief ne demande pas

L'extraction **Geofabrik `.pbf`** (§6 du brief d'origine). Overpass reste
réservé aux petites AOI interactives. Si la cible devient le massif entier en
batch, ni Overpass ni la bissection ne sont le bon outil — mais c'est une spec
dédiée, pas ce lot.
