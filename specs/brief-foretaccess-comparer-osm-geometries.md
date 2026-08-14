# BRIEF `foretaccess` — `comparer_desserte_osm()` doit rendre la géométrie hors corridor

> **Statut** : ouvert, 2026-08-14.
> **Package concerné** : `foretaccess` (source canonique). Demandeur :
> `nemetonshiny`, onglet Desserte — cf.
> `specs/brief-nemetonshiny-desserte-visualisation.md` §4.
> **Nature** : ajout **additif** à une valeur de retour. Aucun changement des
> trois tables existantes, aucun coût de calcul supplémentaire.
> **Contexte de lecture** : `foretaccess@2.3.0.9000`, `main` propre,
> `R/desserte-osm.R`, lecture seule.

---

## 1. Le constat

`comparer_desserte_osm(bdtopo, osm, corridor_m = 15)` renvoie trois tables de
**linéaire** — `osm` (par type), `bdtopo` (par classe) et `resume` — plus
`corridor_m`. Aucune géométrie.

Or la fonction **calcule déjà** la géométrie hors corridor. Elle est dans
l'helper interne `hors()` :

```r
hors <- function(x, corr) {
  ...
  vapply(seq_len(nrow(x)), function(i) {
    g <- sf::st_difference(sf::st_geometry(x)[i], corr)   # <- la geometrie est ici
    if (length(g)) sum(as.numeric(sf::st_length(g))) else 0   # <- on n'en garde que la longueur
  }, numeric(1))
}
```

`g` est exactement le tronçon amputé de sa portion dans le corridor : le
gisement, à la géométrie près. La ligne suivante en prend la longueur et
**jette l'objet**. Le calcul coûteux — 104 s pour 3 122 × 544 tronçons, mesure
`nemetonshiny` du 2026-08-12 — est donc déjà payé, et son résultat le plus
utile est détruit à la sortie de la boucle.

## 2. Pourquoi ça compte maintenant

L'onglet Desserte de `nemetonshiny` propose une action « Complément
OpenStreetMap ». Faute de géométrie, l'app écrit dans son GeoPackage la couche
OSM **brute** — tous les tronçons, doublons de la BD TOPO compris. Un calque
construit dessus ne peut honnêtement s'appeler que « pistes OSM », alors que ce
que l'utilisateur a demandé, et attend, ce sont **les pistes absentes de la
BD TOPO**. C'est aujourd'hui la seule sortie de l'onglet qu'on ne peut pas
cartographier correctement, et ce n'est pas un manque de l'app.

L'alternative — recalculer la différence côté app — est à écarter : elle
dupliquerait la logique du corridor, avec un `corridor_m` libre de diverger de
celui du cœur, et refacturerait 104 s pour retrouver un objet que le cœur avait
en main.

**Et le gisement vaut le détour.** Le juge de paix CA-28.5 de la spec 028 a été
tranché le 2026-07-31 par annotation utilisateur sur ortho IGN actuelle et
historique, 24 tronçons `track` hors corridor, 13,41 km :

| verdict | n | km | % du linéaire |
|---|---:|---:|---:|
| `piste` | 20 | 12,46 | **92,9 %** |
| `non_piste` | 2 | 0,59 | 4,4 % |
| `doute` | 2 | 0,36 | 2,7 % |

**93 % du linéaire hors corridor est de la desserte forestière réelle absente
de la BD TOPO**, pour 4 % de faux positifs avérés. La réserve du §1.1 de la
spec — « un linéaire hors corridor n'est pas une desserte manquante prouvée » —
reste juste sur le principe, mais le taux mesuré la borne à moins d'un
vingtième. Ce n'est pas un bruit qu'on cacherait à l'utilisateur : c'est un
résultat qu'on lui refuse faute de le renvoyer.

Accessoirement, **CA-28.3 est toujours ouvert** dans la spec 028 —
« `comparer_desserte_osm()` reproduit la table du §1 ». Rendre les géométries
donne aussi de quoi le clore proprement : on peut vérifier la table *et*
inspecter ce qu'elle compte.

## 3. Ce qui est demandé

Deux éléments `sf` de plus dans la liste retournée, **sans toucher aux trois
tables existantes** ni à la classe `foretaccess_osm_compare` :

```r
comparer_desserte_osm(bdtopo, osm, corridor_m = 15)
# $osm                  data.frame  (inchangé)
# $bdtopo               data.frame  (inchangé)
# $resume               numeric     (inchangé)
# $corridor_m           numeric     (inchangé)
# $osm_hors_corridor    sf  <- NOUVEAU : tronçons OSM amputés de leur part dans
#                             le corridor BD TOPO, attributs d'origine + hors_m
# $bdtopo_hors_corridor sf  <- NOUVEAU : symétrique, BD TOPO hors corridor OSM
```

Garanties attendues, parce que l'aval va cartographier ces couches :

- **Géométrie clippée**, pas le tronçon entier : un tronçon à moitié dans le
  corridor ne doit pas s'afficher en entier, sinon on montre comme « absent de
  la BD TOPO » un linéaire qui y est.
- **Attributs d'origine conservés** (`highway`, `source`, `tracktype`,
  `surface`, `access` côté OSM ; `classe` côté BD TOPO) + une colonne `hors_m`.
  L'app colore et étiquette par `highway`, et `tracktype` est explicitement un
  **indice** utilisable et pas un filtre (CA-28.2 : renseigné sur 12 `track`
  sur 24).
- **Type de géométrie homogène** — voir §4, c'est le seul piège réel.
- **CRS conservé** ; couches vides rendues comme `sf` à 0 ligne, jamais `NULL`.
- Fonction toujours **purement locale** : aucun accès réseau.

## 4. Le code, et le piège vérifié

`hors()` devient un helper qui rend la longueur **et** les morceaux. Prototypé
et exécuté sur la fixture du test existant :

```r
hors <- function(x, corr) {
  n <- nrow(x)
  if (n == 0 || is.null(corr)) {
    return(list(long = rep(0, n), parts = list()))
  }
  parts <- lapply(seq_len(n), function(i) sf::st_difference(sf::st_geometry(x)[i], corr))
  long <- vapply(parts, function(g) if (length(g)) sum(as.numeric(sf::st_length(g))) else 0,
                 numeric(1))
  list(long = long, parts = parts)
}

# Assemble les morceaux non vides en un `sf`, attributs d'origine + hors_m.
.sf_hors <- function(x, h) {
  keep <- which(h$long > 0)
  if (!length(keep)) return(x[0, , drop = FALSE])
  g <- do.call(c, h$parts[keep])
  # st_difference rend un LINESTRING quand rien n'est coupe, un MULTILINESTRING
  # quand le corridor coupe le troncon en deux : sans ce cast la couche porte
  # DEUX types et l'ecriture GeoPackage en aval devient hasardeuse.
  g <- sf::st_cast(g, "MULTILINESTRING")
  out <- sf::st_drop_geometry(x)[keep, , drop = FALSE]
  out$hors_m <- h$long[keep]
  sf::st_sf(out, geometry = g, crs = sf::st_crs(x))
}
```

Les deux appels existants deviennent :

```r
h_o <- hors(o, corr_b); o$hors_m <- h_o$long
h_b <- hors(b, corr_o); b$hors_m <- h_b$long
```

et la liste retournée gagne `osm_hors_corridor = .sf_hors(o, h_o)` et
`bdtopo_hors_corridor = .sf_hors(b, h_b)`. Penser à retirer les colonnes de
travail `long_m` / `hors_m` en double si `o` les porte déjà.

**Vérifié** sur la fixture du test en place (`test-desserte-osm.R`, une piste
BD TOPO à `y = 0`, un tronçon OSM décalé de 5 m et un autre à 500 m) :

- 1 tronçon OSM hors corridor, `hors_m = 100`, soit **0,1 km — exactement la
  valeur que le test attend déjà** pour `osm_hors_km` ;
- attributs `source` et `highway` conservés ;
- classe `sf`, CRS 2154 conservé ;
- couches vides → `sf` à 0 ligne, pas d'erreur.

Et sur un tronçon qui **traverse** le corridor : `st_difference` rend bien un
`MULTILINESTRING` là où l'autre reste `LINESTRING`, l'`sfc` assemblé porte les
deux types, et `st_cast(g, "MULTILINESTRING")` les homogénéise. Écriture puis
relecture GeoPackage : OK, 2 entités. **C'est le seul piège** — sans le cast,
la couche part en GeoPackage avec des types mélangés.

### Faut-il un argument pour désactiver ?

Non, à mon avis. Le volume rendu est borné par celui des entrées, le calcul est
déjà fait, et un `geometries = FALSE` par défaut laisserait l'aval dans la
situation actuelle sans que personne ne pense à l'activer. Si une mesure sur
une très grande AOI montrait un problème de mémoire, un argument pourra être
ajouté **après**, en `TRUE` par défaut.

## 5. Tests attendus

Le fichier `tests/testthat/test-desserte-osm.R` porte déjà la fixture qu'il
faut ; deux tests à ajouter, un à étendre :

1. **Les tables ne bougent pas** — les quatre valeurs de `resume` déjà
   assertées gardent la même valeur. C'est le test de non-régression qui compte.
2. `osm_hors_corridor` est un `sf` d'**1 ligne**, de longueur 100 m, portant
   `highway == "track"` et `hors_m == 100` ; `bdtopo_hors_corridor` est vide
   (la piste BD TOPO est couverte par l'OSM voisin).
3. **Tronçon traversant** — un tronçon OSM perpendiculaire coupé en deux par le
   corridor : la géométrie rendue est plus courte que l'originale, et
   `st_geometry_type()` est homogène sur toute la couche.
4. **Couches vides** — `osm_hors_corridor` et `bdtopo_hors_corridor` sont des
   `sf` à 0 ligne avec le bon CRS, pas `NULL`.

## 6. Ce que ça débloque en aval

Côté `nemetonshiny` (brief `brief-nemetonshiny-desserte-visualisation.md`) :
un calque « Pistes OSM hors BD TOPO » honnêtement nommé, coloré par `highway`,
avec `hors_m` et `tracktype` au popup — et l'export de cette couche dans le
GeoPackage téléchargeable. L'app écrira alors la sortie de la **comparaison**,
et non plus la couche OSM brute.

Le libellé et l'infobulle devront reprendre la réserve du cœur, qui reste
juste : *un linéaire hors corridor est un gisement à instruire*, à confronter
aux objets BD TOPO connus puis à une annotation (CA-28.5). Le `print()` de
`foretaccess_osm_compare` le dit déjà, mot pour mot — c'est ce texte-là qu'il
faut porter à l'écran, pas une reformulation.

Rappel utile pour ce libellé : `path` et `tertiary` sont **exclus par défaut**
de `acquire_desserte_osm()`. La couche rendue ne contient donc pas les 14 km de
randonnée de l'AOI oracle — ce qu'on affiche est déjà pré-trié sur `track`,
`unclassified`, `service`.

## 7. Protocole de livraison

`feat` additif → bump **mineur**, `2.4.0`. Implémenter, documenter (`@return`
et `@details` à compléter, la réserve du §1.1 de la spec 028 à garder telle
quelle), tester, NEWS, **release**.

Me redonner la version publiée : `nemetonshiny` tire `foretaccess` par
`Remotes: pobsteta/foretaccess@*release`, qui ne voit que les tags — tant que
ce n'est pas taggué, l'app ne peut pas consommer la nouveauté.

Et cocher **CA-28.3** dans `specs/028-osm-source-complementaire.md` si la table
du §1 est reproduite au passage.
