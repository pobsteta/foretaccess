# Earthwork cost of one metre of forest road

Cost, in euros per metre of road, of the cut and fill required to lay a
platform of width `largeur_m` across a hillside of transverse slope
`pente_pct`. Replaces the step-function slope surcharge of Lot 14 by a
continuous, width-aware quantity (spec 029).

## Usage

``` r
cout_terrassement(pente_pct, largeur_m, config = foretaccess_config())
```

## Arguments

- pente_pct:

  Terrain slope in percent: a `SpatRaster` or a numeric vector.

- largeur_m:

  Target platform width, in metres.

- config:

  A `foretaccess_config`; prices live in
  `config$desserte$cout$terrassement`.

## Value

Same shape as `pente_pct` (a `SpatRaster` or a numeric vector), in euros
per metre of road. `NA` where the slope makes construction impossible –
when the terrain is at least as steep as a cut or fill slope, the batter
never meets the ground again and no finite volume exists.

## Details

**Forme fermee.** Sur un profil en travers plan de pente `p`, plateforme
de largeur `L` posee au niveau du terrain sous l'axe, talus amont `A` et
aval `B`, ripage nul :

\$\$S\_{deblai} = p L^2/8 + \frac{1}{2}\frac{(pL/2)^2}{A - p}\$\$
\$\$S\_{remblai} = p L^2/8 + \frac{1}{2}\frac{(pL/2)^2}{B - p}\$\$

C'est l'oracle analytique des tests de cubature de `dessertR`. Les
sections sont en m2, donc en **m3 par metre lineaire** de route.

**Ripage.** Le partage deblai / remblai n'est pas fixe : au-dela d'un
devers, le remblai ne tient pas. Le ripage ne transfere pas un VOLUME,
il deplace la **plateforme** – une part croissante de sa largeur est
creusee plutot que remblayee, comme `assise_deblai` / `assise_remblai`
dans `dessertR::dsr_cubature()`. Les sections se recalculent alors sur
des demi-largeurs asymetriques `a = L/2 (1 + r)` et `b = L/2 (1 - r)` ;
a ripage nul on retrouve la forme fermee ci-dessus.

La distinction n'est pas theorique : transferer la section de remblai
vers le deblai transfererait une quantite qui **diverge** quand le
terrain approche la pente du talus aval, alors que cette configuration
est justement celle ou il n'y a plus de remblai du tout.

Le deblai se reemploie sur place a hauteur du remblai ; l'excedent part
en evacuation, et c'est ce **transport** qui coute, pas le deblai
lui-meme.

**La pente transversale n'est pas la pente du terrain** – elle en depend
par l'azimut de la route, qu'un cout pre-calcule par cellule ignore. On
pose `p_transversale = p_terrain`, c'est-a-dire une route qui suit la
courbe de niveau. C'est le cas dominant en desserte de versant, ou la
pente en long est bornee a 12 % quand le versant en fait 30 a 60 %, et
c'est **majorant** : toute route qui s'en ecarte terrasse moins. Voir
spec 029 section 5.

## See also

[`surface_cout_construction()`](https://pobsteta.github.io/foretaccess/reference/surface_cout_construction.md),
`vignette` spec 029.

## Examples

``` r
# Terrain plat : rien a terrasser.
cout_terrassement(0, largeur_m = 4)
#> [1] 0
# Versant a 30 % : le cout croit avec le carre de la largeur.
cout_terrassement(30, largeur_m = 3)
#> [1] 15.62143
cout_terrassement(30, largeur_m = 6)
#> [1] 62.48571
```
