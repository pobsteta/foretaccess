# Distance de treuillage depuis la desserte (balayage radial)

Reproduit `skid_debusq_RF()` de Sylvaccess
(`sylvaccess_cython3.pyx:3116`). Le treuillage n'est **pas** un plus
court chemin : depuis chaque cellule de desserte, on balaie 360 azimuts
au pas de 1°, en **ligne droite**.

## Usage

``` r
treuiller(mnt, desserte, zone, config = foretaccess_config())
```

## Arguments

- mnt:

  `SpatRaster` du MNT.

- desserte:

  `SpatRaster` des cellules de desserte (non `NA` = desserte).

- zone:

  `SpatRaster` logique des cellules treuillables.

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Une liste de deux `SpatRaster` : `distance` (m, distance 3D ; `NA` si
non treuillable) et `allocation` (indice de la cellule de desserte).

## Details

Le long de chaque rayon, un pixel est treuillable si :

- la **distance 3D** `sqrt(Hdist^2 + dz^2)` ne dépasse pas
  [`distance_treuillage_max()`](https://pobsteta.github.io/foretaccess/reference/distance_treuillage_max.md)
  pour la pente signée du rayon (test appliqué seulement au-delà de
  `min(amont, aval)`) ;

- la **corde du câble**, tendue depuis la desserte à
  `hauteur_attache_treuil_m`, reste au-dessus du sol et sous
  `hauteur_degagement_max_m` **en tout point intermédiaire** ;

- le pixel est dans la zone treuillable.

Dès qu'une de ces conditions échoue, le rayon est **interrompu** : rien
n'est atteignable au-delà par cet azimut. Chaque pixel retient la plus
petite distance, tous azimuts et toutes cellules de desserte confondus.

Écart assumé avec la source : dans le `.pyx`, le test de dégagement
n'est évalué que si le pixel serait amélioré, ce qui rend l'interruption
du rayon dépendante de l'ordre de parcours des cellules de desserte. Ici
il est toujours évalué — c'est la sémantique visée, et elle est
déterministe.
