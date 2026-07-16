# Potentiel d'accessibilite par cable-mat (Lot 4d)

Reproduit le balayage 360 deg / pixel de Sylvaccess v3.6 (moteur cable)
: depuis chaque **place de depot** (depart de ligne), un rayon est lance
dans chaque direction ; le profil d'altitude sous le rayon est extrait
du MNT, et le noyau Rust place jusqu'a `nb_supports_max` **supports
intermediaires** (`OptPyl_Up_NoH`), coupant la ligne au point le plus
lointain atteint quand il ne peut pas la porter entiere. Les cellules
forestieres traversees par une ligne faisable sont marquees accessibles
au cable.

## Usage

``` r
potentiel_cable(
  pre,
  config = foretaccess_config(),
  departs = NULL,
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

- departs:

  Places de depot d'ou une ligne de cable peut partir : chemin de
  vecteur ou objet `sf` (lignes, polygones ou points). Si la couche
  porte un champ `cable`, seules les entites dont `cable` est non nul
  sont retenues (equivalent de l'attribut `CABLE` de Sylvaccess). `NULL`
  (defaut) : repli sur toute la desserte – voir la section *Places de
  depot*.

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

Le profil sert sous deux formes, comme dans la source : **au pixel**
pour poser les supports, **au demi-metre** pour la garde au sol.

## Validite de la ligne

Avant meme de savoir si le cable TIENT, il faut savoir jusqu'ou la ligne
a un SENS. `check_line` la coupe sur trois criteres geometriques : elle
**finit en foret** (on n'installe pas un cable pour desservir un pre),
elle ne traverse pas plus de `min(0,1 x longueur_max_m, longueur_min_m)`
metres de non-foret d'affilee, et elle ne **court pas en travers d'un
versant raide** (`angle_transversal_deg`, `pente_transversale_max_pct`,
`distance_transversale_max_m`, `proportion_transversale_max`). Sans ce
filtre, les lignes filent jusqu'a `longueur_max_m` a travers n'importe
quel terrain : sur le jeu ColduPre, cela declare accessible a tort **10
%** de la foret.

## Sens de debardage

Une ligne se resout dans l'un ou l'autre sens selon que la machine,
posee sur la desserte, **domine** ou non le profil (mat au depart +
`hauteur_mat_m` contre point haut de la ligne + `hauteur_ancrage_m`). «
Machine en haut » : le cable descend, les bornes de pente sont
`bornes_pente_cable()$amont_*`. « Machine en bas » : le cable monte, la
ligne se resout sur le profil **retourne** (l'ancrage ouvre, le mat
ferme) avec les bornes `aval_*` niees, et elle ne peut pas etre coupee
du cote machine – seulement raccourcie par le haut.

## Ecarts assumes avec Sylvaccess v3.6

L'optimisation de la **hauteur de fixation** sur chaque support
(`c_option_h`, `cable$optimiser_hauteur_fixation`) est **experimentale**
et desactivee par defaut (variante `_NoH`, le defaut de v3.6). Le
portage des variantes a hauteur balayee (`OptPyl_Up` / `OptPyl_Up2`)
existe mais **ne reproduit pas encore l'oracle** : sur ColduPre il
*reduit* la couverture (net -999 cellules) la ou Sylvaccess l'*augmente*
(net +470), signe d'un defaut restant dans la passe machine-en-bas ; et
il est **~20x plus lent** (46 min pour 2 departs). A n'activer que pour
experimenter. Cf. `PLAN.md` (dette assumee du cable) et
`specs/004-cable.md`.

Alternative : `cable$methode_supports = "seilaplan"` bascule le
placement des supports sur le **graphe + Dijkstra** de Bont & Heinimann
(2012), qui optimise position **et** hauteur en reutilisant notre
mecanique caténaire (spec 013). Le defaut reste `"sylvaccess"`
(`OptPyl_NoH`, fidelite ColduPre garantie).

Le **pechage lateral** (`distance_laterale_max_m`, `c_l_hor`) est pris
en compte : la couverture d'une ligne faisable n'est pas son seul axe
mais le rectangle de demi-largeur `c_l_hor` autour du segment, comme
`create_rast_couv` chez Sylvaccess.

## Places de depot

Une ligne de cable ne part pas de n'importe ou : installer un cable-mat
exige une aire de depot, une plateforme et un acces camion. Sylvaccess
en fait une **entree a part** (`c_file_departure`), dont il ne retient
que les troncons portant l'attribut `CABLE` – sur son jeu de test
officiel, **2 troncons sur 125**. Passer `departs` reproduit ce
comportement.

Sans `departs`, on retombe sur *toute* la desserte : la couverture est
alors tres **optimiste** (on desservirait de la foret depuis des pistes
incapables d'accueillir un cable) et le balayage, proportionnel au
nombre de departs, devient tres long. Ce repli n'existe que pour les cas
ou l'on ne dispose d'aucune couche de places de depot.
