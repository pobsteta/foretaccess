# Détecte la desserte absente de la référence, sur le MNT (spec 026)

Cherche dans le **micro-relief** les linéaires que la BD TOPO ne porte
pas : pistes anciennes, cloisonnements, tracés effacés du couvert. Rend
une couche **candidate**, jamais une desserte utilisable.

## Usage

``` r
detecter_desserte(
  mnt,
  reference = NULL,
  las_source = NULL,
  seuil = 0.6,
  buffer_ref = 15,
  long_min = 30,
  emprise = NULL,
  dtm_res = 1,
  specs = specs_desserte_calibrees()
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

- seuil:

  Seuil de binarisation de `p_desserte`. Défaut 0,6 (dessertR). La spec
  026 prescrit un **balayage 0,4 → 0,8** pour la validation, pas un
  seuil unique — voir
  [`detecter_desserte_balayage()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte_balayage.md).

- buffer_ref:

  Demi-largeur (m) du corridor de référence exclu. Défaut 15.

- long_min:

  Longueur minimale (m) d'un linéaire retenu. Défaut 30.

- emprise:

  Emprise polygonale restreignant le balayage (régime `corridor`) ;
  `NULL` balaye toute la grille (régime `complet`). La spec 026 prescrit
  `complet` pour la **validation** — un corridor biaise le dénominateur
  du taux de faux positifs vers les zones déjà intéressantes — et
  `corridor` en production.

- dtm_res:

  Résolution (m) de la grille de référence. Défaut 1.

- specs:

  Bornes d'appartenance, voir
  [`specs_desserte_calibrees()`](https://pobsteta.github.io/foretaccess/reference/specs_desserte_calibrees.md)
  (défaut). **`NULL` restaure les specs de dessertR**, dont les bornes
  sont dérivées par quantiles de l'emprise — le `seuil` cesse alors
  d'être comparable d'un site à l'autre.

## Value

Un `sf` de `LINESTRING` avec `source = "detectee"` et `p_desserte`. Sans
`dessertR`, une couche vide et un message — jamais d'échec. L'attribut
**`canal_surface`** (logique) dit si le canal de surface a réellement
été calculé : il est présent sur **toute** sortie, vide comprise, pour
qu'un résultat nul se lise sans ambiguïté.

## Details

**La sortie n'est pas de la desserte.** On détecte des linéaires creux,
et le micro-relief garde aussi les drains, fossés, limites parcellaires
et terrasses. Un tronçon détecté n'a ni largeur, ni état, ni portance
mesurés : il doit passer
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md)
avant d'entrer dans une conception de réseau. Aucun chemin ne doit
permettre à un candidat d'entrer dans `desserte_existante` sans
qualification.

**Deux gisements disjoints.** Cette détection trouve ce qui est *effacé
du couvert mais lisible au sol* ;
[`acquire_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_osm.md)
trouve ce que *quelqu'un a cartographié*. Les deux alimentent la même
couche candidate, avec `source` distinct.

**Éloigne d'ACCESSFOR délibérément** : ACCESSFOR consomme la BD TOPO
seule. Ne jamais activer dans une comparaison ACCESSFOR.

## See also

[`detecter_desserte_balayage()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte_balayage.md),
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md),
[`acquire_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_osm.md),
`specs/026`.
