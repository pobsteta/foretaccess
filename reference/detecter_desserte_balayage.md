# Balayage de seuils pour la détection (spec 026, CA-26.5)

La spec 026 ne pose pas un seuil : elle **mesure où la détection
décroche**. Ce balayage rend, pour chaque seuil, le linéaire détecté et
la part recoupant un objet **BD TOPO connu** — des faux positifs
quantifiés sans annotation.

## Usage

``` r
detecter_desserte_balayage(
  mnt,
  reference = NULL,
  las_source = NULL,
  seuils = seq(0.4, 0.8, by = 0.1),
  objets_connus = NULL,
  tol_recoupement = 10,
  ...
)
```

## Arguments

- mnt:

  Modèle numérique de terrain (`SpatRaster`/chemin), **1 m ou plus fin**
  — le micro-relief d'une plateforme ancienne ne survit pas à 5 m.

- reference:

  Desserte connue à exclure (sortie
  d'[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)).

- las_source:

  Nuage LiDAR pour le canal de surface. `NULL` : détection sur la seule
  géomorphologie, « nettement moins sûre » selon dessertR.

- seuils:

  Seuils balayés. Défaut `seq(0.4, 0.8, by = 0.1)`, la plage prescrite
  par la spec 026 §7.1.

- objets_connus:

  `sf` d'objets BD TOPO (cours d'eau, fossés, limites) dont le
  recoupement vaut faux positif. `NULL` pour ne pas le mesurer.

- tol_recoupement:

  Demi-largeur (m) du corridor de recoupement. Défaut 10.

- ...:

  Passé à
  [`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md)
  (`buffer_ref`, `long_min`, `emprise`, `dtm_res`).

## Value

Un `data.frame` : `seuil`, `n`, `km`, `km_recoupe`, `pct_recoupe`.

## Details

Le recoupement automatique ne **remplace pas** l'annotation sur
orthophoto : il la réduit. Un linéaire qui ne recoupe aucun objet connu
n'est pas pour autant une desserte — ce peut être une terrasse, une
limite parcellaire non cartographiée, ou une trace fossile. Le CA-26.5
n'est pas satisfait sans la part annotée.

## See also

[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md),
`specs/026`.
