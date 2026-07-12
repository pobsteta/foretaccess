# Selection multicritere des lignes cable (Lot 5)

Reproduit `select_best_lines` / `create_best_table` de Sylvaccess v3.6 :
parmi les lignes candidates du balayage cable
([`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)),
en selectionne un sous-ensemble non redondant maximisant la couverture
selon des criteres ponderes. Enchaine : filtrage par limites, score
pondere normalise, classement, selection **gloutonne** (une ligne n'est
retenue que si elle apporte assez de surface **nouvelle**).

## Usage

``` r
selectionner_lignes(cable, config = cable$config)
```

## Arguments

- cable:

  Objet `foretaccess_cable` (voir
  [`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)),
  dont la table `$lignes` porte les candidates.

- config:

  Objet `foretaccess_config` ; les poids/limites vivent dans
  `config$cable$selection`. Par defaut, celui du `cable`.

## Value

Un objet `foretaccess_selection` : `lignes` (objet `sf` LINESTRING des
lignes retenues, avec attributs), `couverture` (`SpatRaster` de la zone
couverte), `config`.

## Details

Six criteres (EF-7) : surface (max), supports (min), sens (amont/aval),
longueur (min/max), volume (max), IPC (max). Chacun a un **poids** (0 =
ignore) et une **limite**, dans `config$cable$selection`. Sans donnee de
volume, les criteres volume/IPC sont neutralises.
