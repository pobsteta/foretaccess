# Bornes de pente admissibles d'une ligne de câble

Reproduit `get_cable_configs()` de Sylvaccess v3.6. Ces bornes ne sont
**pas** des paramètres : elles se **déduisent** du type de chariot, du
type de câble et du sens de débardage autorisé. C'est une contrainte de
la machine, pas un réglage.

## Usage

``` r
bornes_pente_cable(ca)
```

## Arguments

- ca:

  La liste `config$cable`.

## Value

Une liste de quatre bornes en radians : `amont_min`, `amont_max`,
`aval_min`, `aval_max`.

## Details

Pour un **chariot classique** sur mât-câble (`type_chariot = 0`,
`type_cable < 3`), débardage dans les deux sens : la ligne « machine en
haut » est bornée à \\\[-1{,}4\\;\\+0{,}1\]\\ rad — elle **doit
descendre**, avec 0,1 rad de tolérance — et la ligne « machine en bas »
à \\\[-0{,}1\\;\\+1{,}4\]\\. Débardage à l'amont seul
(`sens_debardage = 1`), la borne haute devient
\\-\arctan(p\_{grav}/100)\\ : le chariot descend **par gravité**, il lui
faut donc une pente minimale.

Pour un **winch-liner** (`type_chariot = 1`), les bornes viennent de
`pente_winchliner_amont_pct` / `_aval_pct` : le chariot est tracté, il
ne dépend plus de la gravité.
