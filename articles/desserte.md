# Conception d'un réseau de desserte

Les moteurs terrestres et câble cartographient l’accessibilité d’un
réseau de desserte **existant**. L’épic *conception de desserte* (Lots
14 à 18) va plus loin : il **conçoit** le réseau à créer pour desservir
des parcelles, en minimisant le coût de construction. Cette vignette
déroule la chaîne complète sur un terrain synthétique — de la surface de
coût au réseau optimisé.

``` r

library(foretaccess)
```

## Un terrain d’exemple

Pour rester reproductible et rapide, on fabrique un petit **plan
incliné** (pente de 8 % vers l’est) plutôt que de charger un massif
réel. Le prétraitement réel
([`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md))
produit exactement la même structure à partir d’un MNT.

``` r

nr <- 5L; nc <- 11L; csize <- 10; slope_pct <- 8
mnt <- terra::rast(nrows = nr, ncols = nc, xmin = 0, xmax = nc * csize,
                   ymin = 0, ymax = nr * csize, crs = "EPSG:2154")
col <- terra::colFromX(mnt, terra::xyFromCell(mnt, seq_len(terra::ncell(mnt)))[, 1]) - 1L
terra::values(mnt) <- col * slope_pct / 100 * csize
names(mnt) <- "mnt"

slope <- terra::setValues(terra::rast(mnt), slope_pct); names(slope) <- "slope_pct"
obst  <- terra::setValues(terra::rast(mnt), 0); names(obst) <- "obstacles_complets_mask"

pre <- structure(list(mnt = mnt, slope_pct = slope, obstacles_complets_mask = obst),
                 class = "foretaccess_preprocessing")
```

## Lot 14 — Surface de coût de construction

[`surface_cout_construction()`](https://pobsteta.github.io/foretaccess/reference/surface_cout_construction.md)
traduit le terrain en un **coût de construction en €/m** par cellule
(coût de base + surcoût de pente selon un barème + sol + ouvrages d’art)
et une couche de **franchissabilité** (les cellules trop raides, les
obstacles, les interdictions deviennent infranchissables). Le barème vit
dans `config$desserte$cout`.

``` r

cout <- surface_cout_construction(pre)
cout
#> 
#> ── Surface de cout de construction de desserte ─────────────────────────────────
#> Grille : 5 x 11 cellules
#> Franchissables : 55 cellules
#> Cout (EUR/m) : min 20 | median 20 | max 20
```

## Lot 15 — Tracé au moindre coût (solveur A\* en Rust)

[`tracer_desserte()`](https://pobsteta.github.io/foretaccess/reference/tracer_desserte.md)
relie des points de passage par la route la moins chère, en respectant
la géométrie routière : pente longitudinale bornée, virages adoucis,
rayon de braquage minimal, épingles contrôlées. Le solveur A\* est écrit
en **Rust** (noyau `desserte_trace`) ; R prépare les grilles et
reconstruit la polyligne `sf`.

``` r

depart  <- terra::cellFromRowCol(mnt, 3, 1)
arrivee <- terra::cellFromRowCol(mnt, 3, 11)
tr <- tracer_desserte(pre, cout, c(depart, arrivee))
tr
#> 
#> ── Trace de desserte ───────────────────────────────────────────────────────────
#> Faisable : TRUE
#> Cout total : 100
#> Points de passage : 2 | sommets du trace : 4
```

## Lot 16 — Réseau multi-cibles (glouton / Steiner)

[`reseau_desserte()`](https://pobsteta.github.io/foretaccess/reference/reseau_desserte.md)
raccorde un ensemble de **parcelles** à une desserte existante.
Insertion **gloutonne** (chaque parcelle rejoint le réseau le moins
cher, réutilisant les tronçons déjà posés — le réseau est arborescent)
ou variante **Steiner** (matérialisation d’un arbre couvrant). Une
parcelle déjà à portée de débardage (`skidding_m`) est desservie sans
construire de route.

``` r

parcelle <- function(row, col, id, volume) {
  centre <- terra::xyFromCell(mnt, terra::cellFromRowCol(mnt, row, col))
  r <- csize / 2
  poly <- sf::st_polygon(list(rbind(
    centre + c(-r, -r), centre + c(r, -r), centre + c(r, r),
    centre + c(-r, r), centre + c(-r, -r))))
  sf::st_sf(id = id, volume = volume, geometry = sf::st_sfc(poly, crs = 2154))
}
parcelles <- rbind(parcelle(2, 11, 1, 100), parcelle(4, 11, 2, 500))

# Desserte existante : la colonne de gauche.
cx <- terra::xyFromCell(mnt, terra::cellFromRowCol(mnt, 1, 1))[1]
ext <- terra::ext(mnt)
route <- sf::st_sf(id = 1, geometry = sf::st_sfc(
  sf::st_linestring(rbind(c(cx, ext$ymin), c(cx, ext$ymax))), crs = 2154))

net <- reseau_desserte(pre, cout, parcelles, route, "plus_proche",
                       volume_champ = "volume")
net
#> 
#> ── Reseau de desserte ──────────────────────────────────────────────────────────
#> Mode : "glouton"
#> Heuristique : "plus_proche"
#> Routes creees : 2
#> Parcelles desservies : 2/2
#> Routes creees raccordees : oui
#> Reseau global connexe : oui (souvent 'non' : existant fragmente -- voir
#> ?reseau_desserte)
#> Cout total : 144.7
```

## Lot 17 — Graphe, flux de bois, typage des routes

Le réseau se **vectorise en graphe**
([`vectoriser_reseau()`](https://pobsteta.github.io/foretaccess/reference/vectoriser_reseau.md),
indices de cellule = nœuds), sur lequel on **accumule les flux de bois**
depuis les parcelles vers la sortie
([`calculer_flux()`](https://pobsteta.github.io/foretaccess/reference/calculer_flux.md)),
puis on **type** chaque tronçon (route permanente vs piste temporaire)
selon le flux qui le traverse
([`typer_desserte()`](https://pobsteta.github.io/foretaccess/reference/typer_desserte.md)).

``` r

g   <- vectoriser_reseau(net)
fl  <- calculer_flux(g, parcelles, volume_champ = "volume")
typ <- typer_desserte(fl, seuils_flux = c(temporaire = 0, permanente = 300))
sf::st_drop_geometry(typ$troncons)[, c("de", "vers", "flux", "type")]
#>   de vers flux       type
#> 1  1    2  600 permanente
#> 2  2    3  100 temporaire
#> 3  2    4  500 permanente
```

## Lot 18 — Optimisation du réseau

Le glouton est une bonne base, pas un optimum.
[`optimiser_reseau()`](https://pobsteta.github.io/foretaccess/reference/optimiser_reseau.md)
explore l’espace des **ordres d’insertion** et garde le réseau le moins
cher. L’essai 0 est toujours l’ordre glouton, donc le résultat n’est
**jamais pire** que le Lot 16. Trois stratégies : `"multistart"` (K
ordres perturbés en parallèle, `rayon`), `"recuit"` (recuit simulé, Akay
2004) et `"riprute"` (rip-up & reroute).

``` r

opt <- optimiser_reseau(pre, cout, parcelles, route, strategie = "multistart",
                        n_start = 8, graine = 1, volume_champ = "volume")
c(glouton = net$cout, optimise = opt$cout)
#>  glouton optimise 
#> 144.7214 144.7214
```

## Pondérer le tracé par le coût €/m

Par défaut, le solveur minimise la **distance géométrique**
(comportement d’origine SylvaRoad) ; la surface de coût du Lot 14 ne
sert qu’à écarter les obstacles. L’option `pondere_cout = TRUE` fait
consommer la surface €/m par le solveur : chaque segment est pondéré par
le coût moyen de ses cellules, si bien que le tracé **contourne les
cellules chères** et emprunte les corridors bon marché. L’admissibilité
de l’heuristique A\* est préservée (remise à l’échelle par le coût
minimal de la zone franchissable), donc le tracé reste optimal.

``` r

net_geo <- reseau_desserte(pre, cout, parcelles, route, "plus_proche",
                           pondere_cout = FALSE, volume_champ = "volume")
net_eur <- reseau_desserte(pre, cout, parcelles, route, "plus_proche",
                           pondere_cout = TRUE, volume_champ = "volume")
c(geometrique = net_geo$cout, pondere_cout = net_eur$cout)
#>  geometrique pondere_cout 
#>     144.7214    2683.8962
```

## Attribution

Le solveur de tracé (Lot 15) porte **SylvaRoad** (S. Dupire / SylvaLab /
ONF) et **Forest Road Designer** (PANOimagen / Gob. La Rioja) ; le
réseau, les flux et le typage (Lots 16-18) reprennent
**ForestRoadNetwork** (Klemet). Tous GPL v3, comme ForêtAccess ; merci
de citer ces travaux (références dans le `README`).
