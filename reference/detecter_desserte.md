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
  methode = "squelette",
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

- methode:

  Vectoriseur, passé tel quel à `dessertR::dsr_detecter()`. **Défaut
  `"squelette"`, nommé et non subi** : depuis dessertR 1.1.0, `"auto"`
  résout vers `"agent"`, mais l'agent ne peut pas s'amorcer quand
  `buffer_ref > 0` — `dsr_amorces()` filtre ses amorces sur `!is.na(p)`
  à l'extrémité des tronçons de référence, qui est précisément la zone
  que `dsr_indice_detection()` vient de masquer. `"auto"` replierait
  donc sur le squelette **en silence**, et la chaîne mesurée changerait
  sans préavis au jour où l'amont corrigera. Voir `specs/026` §6.0.1
  (précondition P5).

- specs:

  Bornes d'appartenance. **Quatre formes acceptées** :

  - [`specs_desserte_calibrees()`](https://pobsteta.github.io/foretaccess/reference/specs_desserte_calibrees.md)
    (défaut) — bornes figées, imbriquées
    (`geomorpho`/`surface`/`c_vessel`) ;

  - `"auto"` — **calibre sur place** avec
    `dessertR::dsr_calibrer_specs()`, à partir du MNT et de la
    `reference` fournis. C'est la réponse au conseil de dessertR quand
    les bornes figées saturent (« des bornes calibrées sur un AUTRE
    massif ne se transportent pas ») : l'appelant suit ce conseil sans
    avoir à connaître deux vocabulaires de specs. **Exige `reference`.**
    `surface` et `c_vessel` restent figés, une calibration ne les
    produisant pas ;

  - la sortie **plate** de `dsr_calibrer_specs()$specs` — reconnue à sa
    forme et promue en `geomorpho`, cf.
    [`specs_depuis_calibration()`](https://pobsteta.github.io/foretaccess/reference/specs_depuis_calibration.md)
    ;

  - `NULL` — **restaure les specs de dessertR**, dont les bornes sont
    dérivées par quantiles de l'emprise — le `seuil` cesse alors d'être
    comparable d'un site à l'autre.

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

## Performance

**La fonction la plus couteuse du paquet.** Mesure nemetonshiny du
2026-08-12 : **729 s et plus de 8 Go de pic** sur 1 855 ha, MNT LiDAR
0,5 m.

Deux postes, qui ne se compensent pas :

- la **pile de couches** (`dsr_layers_dtm()`) tient toute l'emprise en
  memoire a la resolution du MNT – d'ou le pic, proportionnel a la
  surface DIVISEE par le carre de la resolution ;

- le **canal de surface** relit le nuage LiDAR dalle par dalle : compter
  la taille du nuage en plus.

Ne jamais cabler cette fonction sur un bouton synchrone ; prevoir un
worker separe. Et **borner l'emprise, pas la resolution** : passer de
0,5 m a 5 m ne fait pas gagner du temps, cela fait perdre le signal – 0
canal retenu sur 7 a 5 m contre 5 sur 7 a 0,5 m (mesure nemetonshiny).
Sur un poste de 31 Go partage, une emprise de l'ordre de 2 000 ha est
deja le plafond raisonnable.

## Place dans le flux

`detecter_desserte()` et
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md)
sont **sequentielles, pas exclusives** : la premiere trouve l'ABSENT
(des linéaires candidats hors du réseau connu), la seconde requalifie
l'EXISTANT (largeur, état, portance mesurés au LiDAR). L'enchaînement
naturel est
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
-\> `detecter_desserte()` -\> fusion -\>
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md),
car la sortie de détection est **candidate** : sans largeur ni portance,
elle n'est pas consommable par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).
Les enchaîner dans l'autre sens qualifierait un réseau auquel il manque
encore ce qu'on cherche.

## See also

[`detecter_desserte_balayage()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte_balayage.md),
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md),
[`acquire_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte_osm.md),
`specs/026`.
