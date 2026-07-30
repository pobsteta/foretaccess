# Élargissement adaptatif de l'emprise pour distinguer l'effet de bord (spec 025)

Une piste connectée à une route située **hors de l'AOI** paraît
orpheline : c'est un artefact de découpe, pas un défaut de donnée.
Plutôt que de deviner un buffer, on le fait **converger**.

## Usage

``` r
integrite_buffer_adaptatif(
  aoi,
  acquerir = NULL,
  buffer_initial = 100,
  buffer_max = 3000,
  facteur = 2,
  gain_min = 0.05,
  ...
)
```

## Arguments

- aoi:

  Emprise stricte (`sf`/`sfc`).

- acquerir:

  Fonction `function(emprise)` rendant la desserte sur cette emprise.
  Défaut :
  [`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
  avec les réglages courants.

- buffer_initial, buffer_max:

  Bornes du balayage (m). Défauts 100 et 3000 – au-delà on
  téléchargerait un département pour rattacher une piste.

- facteur:

  Multiplicateur d'une itération à l'autre. Défaut 2.

- gain_min:

  Arrêt quand la décroissance relative de `L(b)` passe sous ce seuil.
  Défaut 0,05 (5 %).

- ...:

  Passé à
  [`verifier_integrite_desserte()`](https://pobsteta.github.io/foretaccess/reference/verifier_integrite_desserte.md).

## Value

Un objet `foretaccess_integrite` du dernier buffer, dont `courbe` est un
`data.frame` (`buffer_m`, `n_infractions`, `longueur_infraction_m`).

## Details

Le point qui fait la validité de la méthode : la longueur en infraction
est mesurée **sur l'AOI stricte** à chaque itération. Mesurée sur
l'emprise élargie, elle augmenterait mécaniquement (plus de réseau, donc
plus d'infractions) et la suite ne convergerait jamais.

La **décroissance de `L(b)` sépare les causes** : ce qui disparaît en
élargissant était un effet de bord ; ce qui résiste à un buffer large
est topologique ou réel. La courbe est le diagnostic, pas un
sous-produit.

## See also

[`verifier_integrite_desserte()`](https://pobsteta.github.io/foretaccess/reference/verifier_integrite_desserte.md),
`specs/025`.
