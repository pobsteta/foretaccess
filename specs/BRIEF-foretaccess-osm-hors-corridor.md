# BRIEF `foretaccess` — `comparer_desserte_osm()` doit rendre les géométries hors corridor

> **Statut** : **SOLDÉ** au 2026-08-16. Copie du brief tel que reçu de
> `nemetonshiny` (l'original vit dans ce dépôt-là, jamais modifié d'ici) ; seuls
> ce bandeau et la checklist du §9 sont annotés. L'essentiel a été livré en
> **`2.4.0`** (2026-08-14) via `specs/brief-foretaccess-comparer-osm-geometries.md`,
> le reliquat `long_m` en **`2.6.0`** (2026-08-16). Réponse au §6 : **pas
> d'argument `geometries`** — le calcul est déjà fait, le volume est borné par
> celui des entrées, et un défaut `FALSE` laisserait l'aval dans la situation
> actuelle sans que personne pense à l'activer. Si une mesure sur une très grande
> AOI montre un problème de mémoire, l'argument sera ajouté **après**, en `TRUE`
> par défaut.
>
> **Statut d'origine** : ouvert, 2026-08-14.
> **Paquet concerné** : `foretaccess` (uniquement).
> **Demandeur** : `nemetonshiny@0.124.0` — le calque « Pistes OSM » de l'onglet
> Desserte est livré, mais **dégradé**, faute de cette sortie.
> **Contexte de lecture** : `foretaccess 2.3.0` installée, lecture seule.
> **Origine** : §4 de `specs/brief-nemetonshiny-desserte-visualisation.md`,
> option (b), qui recommandait déjà cette place.

---

## 1. Le constat

`comparer_desserte_osm(bdtopo, osm, corridor_m = 15)` renvoie trois tables de
linéaire — `osm` (par `highway`), `bdtopo` (par `classe`), `resume` — et
`corridor_m`. **Aucune géométrie.**

Le « hors corridor », c'est-à-dire le gisement à instruire, n'existe donc qu'en
**kilomètres agrégés par type**. Impossible de le montrer sur une carte, de
l'exporter vers un SIG, ou d'aller voir de quel tronçon il s'agit.

Ce n'est pas un calcul qui manque. C'est un calcul **jeté**.

## 2. La géométrie est déjà matérialisée, puis abandonnée

Dans le corps de la fonction, le helper `hors()` :

```r
hors <- function(x, corr) {
  if (nrow(x) == 0 || is.null(corr)) return(rep(0, nrow(x)))
  vapply(seq_len(nrow(x)), function(i) {
    g <- sf::st_difference(sf::st_geometry(x)[i], corr)   # <- LA geometrie
    if (length(g)) sum(as.numeric(sf::st_length(g))) else 0
  }, numeric(1))
}
```

`g` **est** le linéaire hors corridor du tronçon `i`. Il est construit, mesuré,
puis perdu à l'itération suivante. Ce que l'appelant récupère est la somme de sa
longueur.

C'est ce qui rend la demande peu coûteuse : il n'y a pas un second passage à
faire, il y a un objet à ne pas laisser tomber.

## 3. Ce que ça coûte — mesuré, pas supposé

Banc synthétique reproduisant les ordres de grandeur du terrain de recette
(544 tronçons OSM contre 3 122 BD TOPO, corridor 15 m, EPSG:2154) :

| | durée |
|---|---:|
| (a) état actuel — longueur seule | 23,1 s puis 25,7 s |
| (b) variante — géométrie conservée, longueurs calculées en une fois | 15,4 s puis 26,7 s |

Deux exécutions du **même** code donnent −33 % puis +4 % : l'écart est du bruit
de mesure, pas un effet. La conclusion à en tirer est donc « **conserver la
géométrie ne coûte rien de mesurable** », et surtout pas « c'est plus rapide ».

Volume produit : **392 Ko** pour 500 tronçons hors corridor sur 544. Négligeable
à l'échelle d'un massif ; à surveiller seulement si un usage national apparaît
(cf. §6).

## 4. Ce qui est demandé

Deux éléments de plus dans la liste renvoyée, **sans toucher aux trois
existants** :

- `osm_hors_corridor` — les portions de linéaire OSM hors du corridor BD TOPO ;
- `bdtopo_hors_corridor` — symétriquement, les portions BD TOPO hors du
  corridor OSM.

Chacun un `sf`, dans le CRS d'entrée, portant :

- les attributs d'origine du tronçon (`highway` côté OSM, `classe` côté
  BD TOPO — ce sont eux qui servent à colorer et à filtrer côté app) ;
- `long_m` — longueur totale du tronçon d'origine ;
- `hors_m` — longueur de la portion hors corridor, cohérente avec
  `resume[["osm_hors_km"]]` à la somme près.

**Les tronçons intégralement couverts sont absents de la couche.** Un tronçon
dont la différence est vide n'a rien à instruire ; le garder avec une géométrie
vide ferait compter des lignes qui ne représentent rien.

## 5. Trois pièges rencontrés en préparant ce brief

**a. Types de géométrie mixtes.** `st_difference()` d'un `LINESTRING` par un
polygone rend un `LINESTRING` **ou** un `MULTILINESTRING` selon que la coupure
fragmente ou non. Sur le banc, les deux types coexistaient dans la même sortie.

J'ai vérifié : **l'écriture GeoPackage ne casse pas** — GDAL promeut
silencieusement l'ensemble en `MULTILINESTRING`, et la relecture ne rend que ce
type. Ce n'est donc pas un bug, mais une promotion muette : `st_cast(x,
"MULTILINESTRING")` explicite avant de renvoyer évite que l'appelant découvre un
type qu'il n'a pas demandé.

**b. Le `print()` ne dira rien de neuf tout seul.** `print.foretaccess_osm_compare()`
lit des éléments nommés (`resume`, `osm`, `bdtopo`) : ajouter deux éléments ne le
casse pas, mais il continuera de taire leur existence. Une ligne du genre
« géométries hors corridor disponibles : N tronçons OSM, M BD TOPO » rendrait la
sortie découvrable — sans quoi la fonctionnalité n'existe que pour qui a lu le
`@return`.

**c. Le contrat existant est consommé tel quel.** `nemetonshiny` lit
`cmp$resume` (converti en liste) et `cmp$corridor_m`. Ces deux-là ne doivent pas
bouger, ni de nom, ni de forme.

## 6. Une question ouverte, à trancher côté cœur

Faut-il un argument `geometries = TRUE` pour pouvoir s'en passer ?

À l'échelle d'un massif, non : 392 Ko ne justifient pas une option. Mais si un
usage départemental ou national est prévu, l'objet retourné grossit
proportionnellement au linéaire, et une option de retrait devient utile. C'est
un arbitrage qui appartient au cœur, qui connaît ses autres appelants —
`nemetonshiny` n'a pas d'avis et s'adaptera.

## 7. Documentation

Le `@details` actuel porte déjà l'essentiel, et le `print()` le répète :

> « Un linéaire hors corridor n'est PAS une desserte manquante prouvée :
> décalage de saisie, tracé erroné, chemin non carrossable. Gisement à
> instruire (CA-28.5). »

Cet avertissement doit **suivre les géométries**, et pas seulement les
kilomètres. Une carte affirme beaucoup plus qu'un tableau : un tronçon dessiné
sur un fond satellite se lit comme un constat, là où « 2,4 km hors corridor » se
lit comme un indicateur. Le `@return` des deux nouveaux éléments devrait le
redire mot pour mot.

## 8. Côté app, une fois livré

Rien à demander en retour, mais pour information — c'est ce qui justifie la
demande :

- `run_desserte_osm()` écrira `osm_hors_corridor` dans `desserte_osm.gpkg` à
  côté de `osm_track` ;
- le calque « Pistes OSM » deviendra **« Pistes OSM hors BD TOPO »**, ce qui est
  le calque réellement attendu : aujourd'hui il affiche l'acquisition brute,
  doublons de la BD TOPO compris, et son libellé comme son popup le disent
  explicitement pour ne pas mentir ;
- `hors_m` par tronçon alimentera l'infobulle.

## 9. Checklist

- [x] `hors()` conserve la géométrie de `st_difference()` au lieu de n'en
      renvoyer que la longueur. — `2.4.0`, `R/desserte-osm.R`, `hors()` rend
      `list(long, parts)`.
- [x] `comparer_desserte_osm()` renvoie `osm_hors_corridor` et
      `bdtopo_hors_corridor` (`sf`, CRS d'entrée, attributs d'origine +
      `long_m` + `hors_m`), tronçons entièrement couverts exclus. — `2.4.0`,
      **sauf `long_m`, ajoutée en `2.6.0`** : elle avait été écartée comme
      colonne de travail, à tort — c'est le dénominateur de `hors_m`.
- [x] Les trois éléments existants (`osm`, `bdtopo`, `resume`) et `corridor_m`
      sont inchangés — un test de non-régression le fige. — test
      « comparer_desserte_osm mesure de part et d'autre du corridor ».
- [x] `st_cast("MULTILINESTRING")` explicite avant retour. — `.sf_hors()`, et
      test « un troncon qui traverse le corridor est CLIPPE, type homogene ».
- [x] `print.foretaccess_osm_compare()` mentionne les deux couches. — ligne
      « Geometries clippees (troncons) », test dédié.
- [x] `@return` et `@details` reprennent l'avertissement « gisement à
      instruire, pas une desserte manquante prouvée » sur les géométries. —
      complété en `2.6.0` : le `@return` des deux couches le redit, le
      `@details` ajoute pourquoi (une carte affirme plus qu'un tableau).
- [x] Tests : somme des `hors_m` cohérente avec `resume[["osm_hors_km"]]` ;
      couche vide quand tout est couvert ; entrée vide sans erreur. — les
      trois, plus `long_m` sur le tronçon traversant (200 m d'origine,
      170 m dehors).
- [x] **Release taguée.** `nemetonshiny` tire `pobsteta/foretaccess@*release` :
      un correctif resté sur `main` ne lui parviendra pas. — `v2.4.0` puis
      **`v2.6.0`**, posées par `.github/workflows/release.yml` au merge.

### Point non retenu

Le §4 demandait aussi les attributs d'origine **et rien d'autre** ; la couche
porte en plus `source` et `tracktype` côté OSM, parce que CA-28.2 en fait un
**indice** utilisable (renseigné sur 12 `track` sur 24) et que l'app en a besoin
au popup. C'est un ajout, pas un retrait : aucun attribut demandé ne manque.
