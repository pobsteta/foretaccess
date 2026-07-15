# Moteur camion DFCI — zone de défendabilité (balayage radial)

Cartographie la **zone défendable** contre l'incendie depuis le réseau
DFCI (défense de la forêt contre les incendies). Transcription du moteur
`debusq_dfci` de Sylvaccess v3.6 : depuis chaque pixel du réseau DFCI,
une **lance** est déroulée en ligne droite dans les 360 azimuts (pas de
1°). La lance **épouse le relief** (longueur 3D cumulée cellule à
cellule), elle est plafonnée à `config$dfci$distance_defense_max_m`
(`dfci_lmax`) et **arrêtée** par une pente supérieure à
`config$dfci$pente_defense_max_pct` (`dfci_slope_max`), par un obstacle,
ou par le bord.

## Usage

``` r
camion_dfci(pre, config = foretaccess_config(), write_dir = NULL, bord = NULL)
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` issu de
  [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

- write_dir:

  Répertoire d'écriture des rasters en GeoTIFF/COG, ou `NULL`.

- bord:

  Côtés ouverts de la fenêtre quand `pre` est une **tuile**. `NULL`
  (défaut) : `pre` couvre tout le territoire.

## Value

Un objet de classe `foretaccess_dfci` :

- `accessibilite`:

  `SpatRaster` catégoriel à 6 classes : `inaccessible`,
  `non_defendable_pente`, `defendable_c1`/`c2`/`c3` (bandes de lance),
  `hors_foret`.

- `longueur_lance`:

  longueur de lance (m) atteignant la cellule ; `NA` hors portée / hors
  forêt.

- `denivele`:

  dénivelé cellule − desserte-source (m) ; `NA` idem.

- `lien_reseau`:

  cellule de desserte DFCI de rattachement (index 1-based).

- `pente_ok`:

  `SpatRaster` logique : pente ≤ seuil pompier.

- `certifie`:

  `SpatRaster` logique (tuilage), ou `NULL`.

- `recap`:

  `data.frame` des surfaces et volumes par classe.

- `grid`, `config`, `fichiers`:

  comme au Lot 1.

## Details

Ce n'est **pas** un plus court chemin pondéré (le chemin
`calc_dist_dfci` de Sylvaccess est désactivé) mais un **lancer de rayons
radial** : la charge est défendue en ligne droite depuis la desserte,
tant que le terrain se laisse franchir. La longueur de lance minimale
atteignant chaque cellule de forêt donne sa **classe de défendabilité**
(bandes `config$dfci$classes_distance_m`).

Les sources sont les cellules portant le flag **`CL_DFCI`** (attribut
orthogonal aux classes route/piste/réseau public : une desserte peut
être route classique *et* réseau de défense). Elles sont portées par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
dans `pre$dfci_source_mask`.

## Écart assumé avec Sylvaccess

Le **bug de masquage** du dénivelé (`sylvaccess_cython3.pyx:4807`, qui
écrit aux coordonnées de la dernière source au lieu de la cellule
courante) est **corrigé** : `denivele` est bien remis à `NA` sur toute
cellule non défendable. L'accord à l'oracle sur `Denivele_sur_piste`
s'en trouve très légèrement dégradé, au profit de la justesse.

## See also

[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md),
[`porteur()`](https://pobsteta.github.io/foretaccess/reference/porteur.md),
[`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
                  file.path(toy, "foret.gpkg"))
df <- camion_dfci(pre)
df$recap
#>                 classe cellules surface_ha
#> 1         inaccessible        0       0.00
#> 2 non_defendable_pente        0       0.00
#> 3        defendable_c1     1564       3.91
#> 4        defendable_c2       36       0.09
#> 5        defendable_c3        0       0.00
#> 6           hors_foret      900       2.25
#> 7          indetermine        0       0.00
```
