# Moteur camion DFCI — zone défendable (beta)

Cartographie la **zone défendable** contre l'incendie depuis les
dessertes DFCI (défense de la forêt contre les incendies), en réponse à
EF-8. Sortie **beta** au sens du brief (§4.5) : le modèle est
volontairement simple et ses limites sont explicites (voir *Section
limites*).

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

  Côtés ouverts de la fenêtre quand `pre` est une **tuile** (voir
  [`certifier_propagation()`](https://pobsteta.github.io/foretaccess/reference/certifier_propagation.md)).
  `NULL` (défaut) : `pre` couvre tout le territoire.

## Value

Un objet de classe `foretaccess_dfci` :

- `accessibilite`:

  `SpatRaster` catégoriel : `defendable`, `non_defendable`,
  `hors_foret`. `NA` = indéterminé.

- `distance_defense`:

  distance de défense au terrain (m) depuis la desserte-source la plus
  proche ; 0 sur la desserte, `NA` hors portée.

- `allocation`:

  cellule de desserte de rattachement.

- `certifie`:

  `SpatRaster` logique, ou `NULL` si `bord` l'est.

- `recap`:

  `data.frame` des surfaces et volumes par classe.

- `grid`, `config`, `fichiers`:

  comme au Lot 1.

## Details

Le camion stationne sur une desserte carrossable et défend le terrain
avoisinant, dans une **portée latérale** limitée. On modélise cette
portée par un **plus court chemin pondéré par la pente**
([`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md),
[`surface_cout_skidder()`](https://pobsteta.github.io/foretaccess/reference/surface_cout_skidder.md))
depuis les cellules de desserte-source, plafonné à
`config$dfci$distance_defense_max_m` et interdit au-delà de la pente
d'intervention `config$dfci$pente_defense_max_pct`. C'est donc un
**tampon au terrain** : la distance de défense épouse le relief, et le
terrain trop raide est réputé indéfendable.

Les dessertes-source sont les classes listées dans
`config$dfci$classes_source` (défaut : `"dfci"` seul). Une cellule de
forêt atteinte est `defendable` ; une cellule de forêt non atteinte,
`non_defendable` ; le reste, `hors_foret`.

## Section limites (beta)

Le modèle **ne représente pas** : le combustible (type de peuplement,
charge), le vent, ni la physique de la lance (portée du jet, débit,
pression). La portée de défense est un **paramètre unique**, non dérivé
des caractéristiques du matériel. Les dessertes sont prises telles
quelles : leur carrossabilité réelle par un camion (projet QUALIROAD)
n'est pas qualifiée. La coupure de pente est un proxy grossier
d'atteignabilité. Ces sorties valent pour une **première
hiérarchisation**, pas pour du dimensionnement opérationnel.

## See also

[`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md),
[`porteur()`](https://pobsteta.github.io/foretaccess/reference/porteur.md),
[`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md)

## Examples

``` r
toy <- system.file("extdata/toy", package = "foretaccess")
pre <- preprocess(file.path(toy, "mnt.tif"), file.path(toy, "desserte.gpkg"),
                  file.path(toy, "foret.gpkg"))
df <- camion_dfci(pre)
df$recap
#>           classe cellules surface_ha
#> 1     defendable     1443     3.6075
#> 2 non_defendable      157     0.3925
#> 3     hors_foret      704     1.7600
#> 4    indetermine      196     0.4900
```
