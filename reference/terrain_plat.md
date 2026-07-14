# Terrain plat au sens du porteur

Reproduit `Pente_ok_forw` de Sylvaccess (`slopes_skid()`, second retour)
: la pente de la cellule est sous le **minimum** des trois seuils du
porteur — c'est le terrain où l'engin roule *quelle que soit* la
direction, et donc celui sur lequel se propage le plus court chemin. Le
balayage radial
([`conduire()`](https://pobsteta.github.io/foretaccess/reference/conduire.md)),
lui, va plus loin en arbitrant selon le sens et le dévers ; il est borné
par le **maximum** des trois.

## Usage

``` r
terrain_plat(pre, config = foretaccess_config())
```

## Arguments

- pre:

  Objet `foretaccess_preprocessing` (Lot 1).

- config:

  Objet
  [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md).

## Value

Un `SpatRaster` logique (1 = terrain plat pour le porteur).

## Details

Le réseau public rejoint les obstacles
(`Obstacles_forwarder[Res_pub==1]=1`).
