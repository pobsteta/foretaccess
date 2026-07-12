# Potentiel d'accessibilite par cable-mat (Lot 4d)

Reproduit le balayage 360 deg / pixel de Sylvaccess v3.6 (moteur cable)
: depuis chaque cellule de desserte (depart de ligne), un rayon est
lance dans chacune des 360 directions ; le profil d'altitude sous le
rayon est extrait du MNT, echantillonne au demi-metre, et la faisabilite
d'une ligne de cable (travee simple, **sans support intermediaire**) est
evaluee par le noyau Rust
[`cable_test_span()`](https://pobsteta.github.io/foretaccess/reference/cable_test_span.md)
jusqu'a `longueur_max_m`. Les cellules forestieres traversees par une
ligne faisable sont marquees accessibles au cable.

## Usage

``` r
potentiel_cable(
  pre,
  config = foretaccess_config(),
  write_dir = NULL,
  bord = NULL
)
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (voir
  [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)).

- config:

  Objet `foretaccess_config`. Les parametres cable (garde au sol,
  materiel, geometrie) vivent dans `config$cable`.

- write_dir:

  Repertoire d'ecriture des rasters (COG), ou `NULL`.

- bord:

  Reserve au tuilage (Lot 7) ; ignore ici (pas de propagation longue
  portee a certifier au-dela du halo).

## Value

Un objet de classe `foretaccess_cable` : `accessibilite` (raster de
classes : accessible_cable / non_accessible / hors_foret),
`longueur_ligne` (m, meilleure ligne couvrant la cellule),
`azimut_ligne` (deg), `nb_supports` (0 dans ce lot), `lignes`
(data.frame des lignes candidates : `depart`, `azimut`, `longueur_m`,
`surface_ha`, `sens`, `supports`, `volume_m3`, `ipc` – une par (depart,
azimut) faisable, pour la selection du Lot 5), `recap`, `grid`,
`config`, `fichiers`.

## Details

Le placement de supports intermediaires (`OptPyl_Up`) et le pechage
lateral (`distance_laterale_max_m`) sont des extensions futures (voir
`specs/004`) : ce lot livre le potentiel **0 support**, colonne
vertebrale testable.
