# Coefficients de la loi de bascule

Calcule `coeff` et `orig` à partir des quatre paramètres skidder, en
reproduisant les cas particuliers de Sylvaccess
(`Sylvaccess_1_skidder.py`).

## Usage

``` r
coefficients_bascule(config = foretaccess_config())
```

## Arguments

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Une liste : `coeff`, `orig`, `p_up`, `p_down`, `damont`, `daval`, `dmin`
(en deçà de laquelle aucun plafond n'est appliqué).
