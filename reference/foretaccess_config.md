# Configuration métier de ForêtAccess (défauts Sylvaccess v3.6)

Construit un objet de configuration validé regroupant les paramètres des
moteurs. Les valeurs par défaut sont celles de **Sylvaccess v3.6** (RdV
Experts 2026), qui diffèrent de l'article 2015 (cf.
`docs/foretaccess-brief.md` §6 et `docs/adr/ADR-003-configuration.md`).

## Usage

``` r
foretaccess_config(
  skidder = list(),
  porteur = list(),
  cable = list(),
  dfci = list(),
  general = list()
)
```

## Arguments

- skidder:

  Liste des paramètres skidder (voir *Détails*).

- porteur:

  Liste des paramètres porteur (voir *Détails*).

- cable:

  Liste des paramètres câble. Le **schéma** est posé dès le Lot 0 ; les
  tableaux matériels sont complétés au Lot 4 (dépendance ADR-006).

- dfci:

  Liste des paramètres du camion DFCI (beta, Lot 6 ; voir *Détails*).

- general:

  Liste des paramètres généraux (résolution, CRS, méthode de calcul de
  la pente).

## Value

Un objet de classe `foretaccess_config` (liste structurée), validé.

## Details

Défauts **skidder** (v3.6) : débardage amont max 50 m, aval max 100 m
(article : 150 m), pente de bascule amont 75 %, pente de bascule aval 20
%, distance hors desserte 50 m, pente skidder max 30 % (article : 25 %),
pente abattage max 100 %.

Défauts **porteur** (v3.6) : pente en travers max 15 %, pente montée max
30 %, pente descente max 25 %, portée de grue 8 m, distance en pente
forte 300 m, distance hors desserte 200 m, pente abattage max 100 %.

Défauts **DFCI** (beta) : portée de défense 100 m, pente d'intervention
max 40 %, dessertes-source `"dfci"`. Ce sont des hypothèses de travail,
non des valeurs Sylvaccess : le module DFCI est une sortie **beta**
(voir `specs/006-dfci.md`).

## Examples

``` r
cfg <- foretaccess_config()
cfg$skidder$debardage_aval_max_m
#> [1] 100
```
