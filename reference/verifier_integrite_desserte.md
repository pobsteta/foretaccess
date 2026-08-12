# Vérifie les contraintes d'intégrité du réseau de desserte (spec 025)

Applique les deux contraintes de l'annexe ACCESSFOR (rapport février
2025, p. 51) : une **piste** doit être connectée à une route forestière
ou au réseau public, une **route forestière** au réseau public. Les
tronçons qui les violent sont **signalés, jamais retirés**.

## Usage

``` r
verifier_integrite_desserte(
  desserte,
  aoi = NULL,
  tol_noeud = 1,
  tol_test_topologie = 5,
  marge_bord_m = 10,
  largeur_dedupe = 0
)
```

## Arguments

- desserte:

  Réseau de desserte : `sf` de lignes portant `classe` (sortie
  d'[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)).

- aoi:

  Emprise (`sf`/`sfc`) servant à détecter les composantes touchant le
  bord. `NULL` : la cause `bord_aoi` n'est pas attribuée.

- tol_noeud:

  Distance (m) de collage des extrémités. Défaut 1.

- tol_test_topologie:

  Tolérance relâchée servant à tester la cause `topologie` : une
  infraction qui disparaît à cette tolérance en relève. Défaut 5.

- marge_bord_m:

  Distance (m) au bord de l'`aoi` en deçà de laquelle une composante est
  réputée le toucher. Défaut 10.

- largeur_dedupe:

  Écart (m) de déduplication des parallèles passé à `dsr_reseau()`.
  **Défaut 0 : désactivée.** La valeur 3 de dessertR vise des tracés
  forestiers corrigés indépendamment, où deux parallèles proches sont un
  artefact. Sur un réseau incluant le **réseau public** (chaussées
  séparées, giratoires, contre-allées) elle coupe des liaisons
  **réelles** : mesuré sur l'AOI oracle à 1600 m de buffer, elle
  retirait 260 tronçons sur 1003 et fragmentait le graphe en 69
  composantes dont 34 isolées, fabriquant 21 fausses infractions.

## Value

Un objet `foretaccess_integrite` : `troncons` (`sf` avec `composant`,
`connecte_public`, `viole_contrainte`, `cause`), `resume` (compteurs),
`courbe` (`NULL` ici, renseigné par
[`integrite_buffer_adaptatif()`](https://pobsteta.github.io/foretaccess/reference/integrite_buffer_adaptatif.md)),
`disponible` et `raison`.

**Lire `disponible` avant `resume`.** Sans `dessertR`/`igraph`, ou si
`dsr_reseau()` n'aboutit pas, le diagnostic n'est pas effectué :
`resume` est alors tout en `NA` et un avertissement est émis. Un
`n_infractions` à `NA` signifie **« on ne sait pas »**, jamais « aucune
infraction » — ne l'affichez pas comme un verdict.
[`dessertR_disponible()`](https://pobsteta.github.io/foretaccess/reference/dessertR_disponible.md)
permet de poser la question *avant* de lancer le calcul.

## Details

**Trois causes, de nature différente**, qu'il faut séparer avant toute
remédiation :

- `bord_aoi` — la composante touche le bord de l'emprise : le
  raccordement est probablement hors AOI, c'est un artefact de découpe
  et non un défaut ;

- `topologie` — l'infraction disparaît quand on relâche la tolérance de
  collage des nœuds : extrémités non nodées, écarts décimétriques ;

- `reel` — ni l'un ni l'autre. C'est une information, pas une erreur.

**Aucune donnée n'est modifiée.** Le recollage de nœuds (niveau 2) n'est
appliqué que si `tol_noeud` est explicitement augmenté ; la suppression
de composantes (niveau 3) **n'existe pas** dans ce code. C'est ce
qu'ACCESSFOR a fait à la main, et l'automatiser retirerait de la
desserte réelle dès que le diagnostic se trompe. Sylvaccess lui-même se
contente d'avertir.

## See also

[`dessertR_disponible()`](https://pobsteta.github.io/foretaccess/reference/dessertR_disponible.md),
[`integrite_buffer_adaptatif()`](https://pobsteta.github.io/foretaccess/reference/integrite_buffer_adaptatif.md),
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md),
`specs/025`.
