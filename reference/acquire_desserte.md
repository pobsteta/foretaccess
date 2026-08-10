# Acquiert la desserte depuis BD TOPO (IGN WFS)

Récupère `troncon_de_route`, reprojette, découpe sur l'AOI et dérive le
champ `classe` attendu par
[`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md).

## Usage

``` r
acquire_desserte(
  aoi,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  country = "FR",
  classification = c("accessfor", "clsvac", "heuristique"),
  garder_hors_desserte = TRUE,
  politique_cache = "reacquerir"
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

- classification:

  Comment classer la BD TOPO en desserte Sylvaccess. `"accessfor"`
  (défaut, spec 024) applique la table **publiée** du rapport ACCESSFOR
  (annexe p. 51), fondée sur `nature` **seul** : « Route à 1 ou 2
  chaussées » → `reseau_public`, « Route empierrée » et route forestière
  nommée → `route`, « Chemin » → `piste`, **tout le reste** (dont «
  Sentier ») → hors desserte, donc retiré. `"clsvac"` (spec 022) est le
  calage empirique antérieur, qui utilisait `importance` ;
  `"heuristique"` l'historique deux classes. Sur l'AOI oracle,
  `"accessfor"` et `"clsvac"` divergent sur 42 % des tronçons.

- garder_hors_desserte:

  Conserver les tronçons `hors_desserte` (CL_SVAC = 0) dans la sortie ?
  **Défaut `TRUE` depuis le 2026-07-30.** Les retirer **coupe le
  réseau** : mesuré sur l'AOI oracle, leur suppression faisait passer
  les infractions de connectivité de 15 à 21 à 1600 m de buffer.
  L'annexe ACCESSFOR le dit elle-même du rond-point — « non nécessaire
  mais **permet de garder un réseau intègre** ». Ils sont donc conservés
  pour la **topologie** et exclus de l'**exploitation**.

  Le consommateur qui en tire le bénéfice est
  [`verifier_integrite_desserte()`](https://pobsteta.github.io/foretaccess/reference/verifier_integrite_desserte.md)
  (spec 025), qui construit son graphe sur la couche `sf` **sans filtrer
  `classe`** : ces tronçons y soudent les composantes. Ils ne
  franchissent en revanche aucune rasterisation —
  [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
  les retire explicitement avant
  [`terra::rasterize()`](https://rspatial.github.io/terra/reference/rasterize.html),
  de la desserte comme des sources DFCI. Les sorties de
  [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
  sont donc **invariantes** sous ce paramètre ; il ne change que ce que
  voit le diagnostic d'intégrité (et ce que l'on relit dans le
  GeoPackage).

  `FALSE` reproduit la couche Sylvaccess stricte (classes 1/2/3
  seulement).

- politique_cache:

  Que faire d'un cache produit avec **d'autres paramètres** ?
  `"reacquerir"` (défaut) refait l'acquisition, `"avertir"` sert le
  cache en nommant ce qui diverge, `"echouer"` interrompt, `"ignorer"`
  désactive le contrôle. Un cache **sans provenance** (antérieur à la
  v1.29.0) compte comme divergent. Cf.
  [`cache_utilisable()`](https://pobsteta.github.io/foretaccess/reference/cache_utilisable.md)
  et `specs/027`.

## Value

Un objet `sf` de lignes avec un champ `classe`.
