# ForêtAccess de bout en bout

ForêtAccess cartographie l’**accessibilité des forêts** selon le mode
d’exploitation. Cette vignette déroule le **pipeline complet** sur le
jeu de données jouet livré avec le paquet : prétraitement, moteurs
terrestres (skidder, porteur), camion DFCI, volet câble (potentiel +
sélection), agrégation zonale et persistance en base spatiale. L’exemple
est **reproductible** : tout le code ci-dessous s’exécute tel quel.

``` r

library(foretaccess)
```

## Le jeu de données jouet

Le paquet embarque un petit territoire synthétique sous
`inst/extdata/toy/` : un modèle numérique de terrain (`mnt.tif`), une
desserte classée (route / piste / DFCI, `desserte.gpkg`) et un masque de
forêt (`foret.gpkg`).

``` r

toy <- system.file("extdata", "toy", package = "foretaccess")
list.files(toy)
#> [1] "cable_profils.csv" "desserte.gpkg"     "foret.gpkg"       
#> [4] "mnt.tif"
```

## Configuration

Tous les paramètres métier vivent dans un objet de configuration validé,
dont les **défauts sont ceux de Sylvaccess v3.6**. On peut surcharger
n’importe quelle clé.

``` r

config <- foretaccess_config()
config$skidder$pente_skidder_max_pct
#> [1] 30
config$dfci$distance_defense_max_m
#> [1] 440
```

## Prétraitement

[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
aligne les entrées sur une grille commune, calcule pente et exposition,
et rasterise desserte et forêt. Le résultat alimente tous les moteurs.

``` r

pre <- preprocess(
  mnt      = file.path(toy, "mnt.tif"),
  desserte = file.path(toy, "desserte.gpkg"),
  foret    = file.path(toy, "foret.gpkg")
)
pre
#> Pretraitement ForetAccess
#> • grille : 50 x 50 cellules, resolution 5 x 5 m
#> • emprise : [0, 250] x [0, 250]
#> • couches facultatives : aucune
#> • seuil d'exclusion (pente abattage) : 100 %
```

## Moteurs terrestres

Le **skidder** (débusqueur) combine traînage (plus court chemin) et
treuillage (balayage radial). Le **porteur** (forwarder) conduit puis
grappille. Chaque moteur renvoie un raster catégoriel d’accessibilité et
un récapitulatif de surfaces.

``` r

sk <- skidder(pre)
sk$recap[, c("classe", "surface_ha")]
#>           classe surface_ha
#> 1    parcourable       4.08
#> 2     accessible       0.00
#> 3 non_accessible       0.00
#> 4     hors_foret       1.68
#> 5    indetermine       0.49

po <- porteur(pre)
po$recap[, c("classe", "surface_ha")]
#>           classe surface_ha
#> 1    parcourable       4.08
#> 2     accessible       0.00
#> 3 non_accessible       0.00
#> 4     hors_foret       1.68
#> 5    indetermine       0.49
```

## Camion DFCI (beta)

[`camion_dfci()`](https://pobsteta.github.io/foretaccess/reference/camion_dfci.md)
cartographie la **zone défendable** contre l’incendie depuis les
dessertes DFCI : un tampon au terrain plafonné à la portée de défense.
Sortie **beta** (voir
[`?camion_dfci`](https://pobsteta.github.io/foretaccess/reference/camion_dfci.md)
pour les limites).

``` r

df <- camion_dfci(pre)
df$recap[, c("classe", "surface_ha")]
#>                 classe surface_ha
#> 1         inaccessible       0.00
#> 2 non_defendable_pente       0.00
#> 3        defendable_c1       3.91
#> 4        defendable_c2       0.09
#> 5        defendable_c3       0.00
#> 6           hors_foret       2.25
#> 7          indetermine       0.00
```

## Volet câble

Le balayage 360°/pixel produit l’ensemble des **lignes de câble
faisables** (noyau mécanique en Rust).
[`selectionner_lignes()`](https://pobsteta.github.io/foretaccess/reference/selectionner_lignes.md)
en retient un sous-ensemble non redondant maximisant la couverture.

Une ligne ne part pas de n’importe où : il lui faut une **place de
dépôt** (plateforme + accès grumier). C’est une entrée à part entière,
`potentiel_cable(departs = )` ; sans elle le balayage part de *toute* la
desserte et la couverture devient très optimiste. À défaut d’un relevé,
[`places_depot()`](https://pobsteta.github.io/foretaccess/reference/places_depot.md)
en dérive des candidates, à passer en `departs` :

``` r

places <- places_depot(
  desserte = file.path(toy, "desserte.gpkg"),
  mnt      = file.path(toy, "mnt.tif"),
  foret    = file.path(toy, "foret.gpkg"),
  espacement_min_m = 100
)
#> ! Aucune largeur mesuree (largeur_carrossable_m / largeur /
#>   largeur_de_chaussee) : le critere d'acces camion ne rejette rien.
#> ℹ Les colonnes dfci et classe sont rapportees dans acces mais ne tranchent pas
#>   -- sur l'oracle ColduPre elles ecartent une vraie place de depot sur deux.
#> ℹ Aucune couche `retournements` : le critere de demi-tour n'est pas applique.
#> ✔ 2 places de depot candidates sur 1/3 troncons.
#> ! Pre-filtre grossier, pas un releve. Sur l'oracle ColduPre : les 2 vraies
#>   places de depot sont retrouvees, mais parmi 54 troncons sur 125 (precision ~4
#>   %).
#> ℹ A confirmer par photo-interpretation ou visite. Voir la section Validation de
#>   `places_depot()`.
places[, c("troncon", "acces", "pente_pct")]
#> Simple feature collection with 2 features and 3 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: 125 ymin: 62.5 xmax: 125 ymax: 187.5
#> Projected CRS: RGF93 v1 / Lambert-93
#>     troncon        acces pente_pct          geometry
#> 2         2 classe:piste         0  POINT (125 62.5)
#> 2.1       2 classe:piste         0 POINT (125 187.5)
```

Le MNT jouet est un plan incliné vers l’est à 20 % : seule la route **de
niveau** (nord-sud, 0 % en long) porte des plateformes. C’est bien la
pente **de la route** qui décide, pas celle du versant — mesurer le
versant éliminerait la montagne, c’est-à-dire le terrain où l’on câble.
Le détail de la confrontation à l’oracle ColduPre est dans
[`?places_depot`](https://pobsteta.github.io/foretaccess/reference/places_depot.md),
section *Validation* : rappel 2/2, précision ~4 % — un **pré-filtre**,
pas un relevé.

``` r

cab <- potentiel_cable(pre)
#> ! Aucune couche de places de depot (`departs`) : le balayage part des 195
#>   cellules de desserte.
#> ℹ La couverture cable sera optimiste -- une piste n'accueille pas un cable-mat.
#>   Voir la section Places de depot de `potentiel_cable()`.
nrow(cab$lignes)          # lignes candidates
#> [1] 3128

sel <- selectionner_lignes(cab)
nrow(sel$lignes)          # lignes retenues
#> [1] 36
```

## Agrégation zonale

[`agreger_zones()`](https://pobsteta.github.io/foretaccess/reference/agreger_zones.md)
agrège n’importe quel raster d’accessibilité en surfaces (et volumes, si
fournis) **par zone** — massif, parcelle, commune — et par classe.

``` r

# Deux zones : moitie ouest / moitie est de l'emprise.
e <- terra::ext(pre$mnt)
xm <- (e[1] + e[2]) / 2
crs <- terra::crs(pre$mnt)
za <- sf::st_as_sf(terra::as.polygons(terra::ext(e[1], xm, e[3], e[4]), crs = crs))
zb <- sf::st_as_sf(terra::as.polygons(terra::ext(xm, e[2], e[3], e[4]), crs = crs))
zones <- rbind(za, zb)
zones$nom <- c("ouest", "est")

agg <- agreger_zones(sk$accessibilite, zones[, "nom"], id = "nom")
sf::st_drop_geometry(agg)
#> Agregation zonale ForetAccess
#> • zones : 2
#> • colonnes de surface : surface_parcourable_ha, surface_accessible_ha,
#>   surface_non_accessible_ha, surface_hors_foret_ha, surface_indetermine_ha,
#>   surface_totale_ha
#> • surface totale : 6.25 ha
#>     nom surface_parcourable_ha surface_accessible_ha surface_non_accessible_ha
#> 1 ouest                   2.03                     0                         0
#> 2   est                   2.05                     0                         0
#>   surface_hors_foret_ha surface_indetermine_ha surface_totale_ha
#> 1                  0.85                  0.245             3.125
#> 2                  0.83                  0.245             3.125
```

## Persistance en base spatiale

Les sorties vectorielles s’écrivent derrière une interface commune, avec
deux backends interchangeables : **GeoPackage** et **PostGIS**.
L’écriture est idempotente ; côté PostGIS, un index spatial GiST est
créé automatiquement.

``` r

gpkg <- tempfile(fileext = ".gpkg")
sb <- storage_gpkg(gpkg)
sb_write_layer(sb, "lignes_cable", sel$lignes)
sb_write_layer(sb, "agregation_massif", agg)
sb_list_layers(sb)
#> [1] "lignes_cable"      "agregation_massif"
```

Pour PostGIS, on remplace le backend sans changer le reste :

``` r

conn <- DBI::dbConnect(RPostgres::Postgres(), dbname = "foretaccess")
sb <- storage_postgis(conn, schema = "run_2026")  # un schema par run/massif
sb_write_layer(sb, "agregation_massif", agg)       # + index GiST
```

## Passage à l’échelle

Sur un massif réel,
[`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md)
découpe le territoire en tuiles traitées en parallèle, avec un halo
certifié garantissant un résultat **identique** au traitement mono-bloc.
Les rasters de sortie s’écrivent en GeoTIFF/COG.

## Attribution

Les moteurs terrestres et le câble dérivent de **Sylvaccess** (INRAE, S.
Dupire) ; l’optimisation de la hauteur des supports câble reprend la
méthode **SEILAPLAN** (Bont & Heinimann ; P. Moll et al.). Tous deux GPL
v3, comme ForêtAccess. Merci de les citer (liste complète et références
dans le `README` et `CITATION.cff`).
