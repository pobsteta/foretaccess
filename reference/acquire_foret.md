# Acquiert la forêt depuis BD Forêt v2 (IGN WFS)

Acquiert la forêt depuis BD Forêt v2 (IGN WFS)

## Usage

``` r
acquire_foret(
  aoi,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  country = "FR",
  exclure_landes = TRUE
)
```

## Arguments

- aoi:

  Objet `sf`/`sfc` d'emprise, dans le CRS cible.

- crs:

  Code EPSG de sortie. Défaut 2154.

- cache_dir:

  Répertoire de cache.

- overwrite:

  Re-télécharger même si le cache existe. Défaut `FALSE`.

- country:

  Code pays ISO. Défaut `"FR"`.

- exclure_landes:

  Exclure les landes (`code_tfv` dans `LA4`/`LA6`) du masque forêt,
  comme ACCESSFOR ? Défaut `TRUE`. Sans colonne `code_tfv` dans le flux,
  aucun filtrage n'est possible et la couche est renvoyée telle quelle.

## Value

Un objet `sf` de polygones de forêt.

## Details

Conforme au masque forêt d'ACCESSFOR (rapport février 2025, annexe p.
50) : les **landes** (`code_tfv` `LA4` ligneuses, `LA6` herbacées) sont
**exclues** du masque – elles portent `FORET = 0` chez ACCESSFOR, donc
n'entrent pas dans le calcul d'accessibilité. Passer
`exclure_landes = FALSE` pour l'ancien comportement (tous les polygones
BD Forêt retenus).
