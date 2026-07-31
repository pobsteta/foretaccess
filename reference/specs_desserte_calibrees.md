# Calibration de référence de la détection (spec 026)

Specs **absolues** et `c_vessel` figés sur un jeu de référence, pour que
le `seuil` de
[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md)
désigne la même chose d'un site à l'autre.

## Usage

``` r
specs_desserte_calibrees()
```

## Value

Une liste : `geomorpho` (pour `dessertR::dsr_conductivite()`), `surface`
(pour `dessertR::dsr_sigma_surf()`) et `c_vessel` (pour
`dessertR::dsr_layers_dtm()`, une valeur par échelle).

## Details

**Pourquoi figer.** `dessertR::dsr_calibrer_specs()` calibre sur les
données qu'on lui donne : appelé par AOI, il rendrait des specs justes
localement mais **incomparables entre sites**, ce qui est précisément ce
que le CA-26.5 interdit. On calibre donc **une fois**, sur un jeu de
référence, et on fige.

**Valeurs produites par** `data-raw/calibrer_bornes_dsr.R` contre
**dessertR 1.1.0**, sur la dalle `LHD_FXX_0737_6385` (Chastel-Nouvel, 1
km², 32 tronçons, 7 561 m de desserte BD TOPO `piste` + `route`). Onze
canaux retenus, AUC de 0,826 (`taux_penetration`) à 0,572 (`svf`).

**Ordre de calibration, qui n'est pas indifférent** : `c_vessel` est
mesuré **avant** la pile, et la pile construite avec — sinon les bornes
seraient calibrées sur une vesselness elle-même relative à l'emprise, et
le défaut réapparaîtrait un cran plus bas.

**`densite_sousetage` est écarté**, bien que `dsr_calibrer_specs()` le
retienne (AUC 0,565). Motif : ses bornes sortent **indéterminées**
(`a = NA, b = NA`), les deux populations étant à zéro en médiane. Le
garder le ferait retomber sur la dérivation par quantiles, donc
**réintroduirait la dépendance à l'emprise** sur ce canal — l'inverse du
but. Ce n'est pas un jugement sur sa valeur : dessertR 1.1.0 note qu'il
mesure un **état** et non la présence d'une route, « une route
recolonisée reste une route ».

**Portée — un seul massif.** Lozère, 830–1 260 m, forêt de montagne.
dessertR 1.1.0 calibre sur **deux** massifs ; nous n'en avons qu'un, et
il recouvre le bloc `wsfi` à 54 %. Ces valeurs sont **provisoires** :
elles ancrent, elles ne généralisent pas. `specs = NULL` dans
[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md)
restaure les défauts dessertR.

## See also

[`detecter_desserte()`](https://pobsteta.github.io/foretaccess/reference/detecter_desserte.md),
`dessertR::dsr_calibrer_specs()`, `dessertR::dsr_c_vessel()`,
`specs/026`.
