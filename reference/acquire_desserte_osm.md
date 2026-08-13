# Acquiert la desserte candidate depuis OpenStreetMap (spec 028)

Source **complémentaire** de la BD TOPO, jamais substitutive. Les
tronçons rendus sont des **candidats** : ils doivent passer
[`qualifier_desserte()`](https://pobsteta.github.io/foretaccess/reference/qualifier_desserte.md)
avant d'entrer dans une conception de réseau.

## Usage

``` r
acquire_desserte_osm(
  aoi,
  crs = 2154,
  cache_dir = tempdir(),
  overwrite = FALSE,
  types = .TYPES_HIGHWAY_DESSERTE,
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

- types:

  Valeurs de `highway` retenues. Défaut : `track`, `unclassified`,
  `service`.

- politique_cache:

  Que faire d'un cache produit avec **d'autres paramètres** ?
  `"reacquerir"` (défaut) refait l'acquisition, `"avertir"` sert le
  cache en nommant ce qui diverge, `"echouer"` interrompt, `"ignorer"`
  désactive le contrôle. Un cache **sans provenance** (antérieur à la
  v1.29.0) compte comme divergent. Cf.
  [`cache_utilisable()`](https://pobsteta.github.io/foretaccess/reference/cache_utilisable.md)
  et `specs/027`.

## Value

Un `sf` de lignes avec `source = "osm"`, `highway`, et les attributs
`tracktype`, `surface`, `access` quand ils sont présents dans le flux.

## Details

`path` et `tertiary` sont exclus par défaut. Sur l'AOI oracle, `path`
représente 14,09 km hors corridor BD TOPO mais relève surtout de la
randonnée, et une `tertiary` absente de la BD TOPO est plus probablement
un décalage de saisie qu'une découverte.

**Overpass injoignable lève une erreur**, jamais une couche vide : un
appelant confondrait sinon « le serveur refuse » et « il n'y a rien ici
». C'est la confusion qui a masqué l'absence de DFCI pendant une journée
entière.

## Performance

Une requete Overpass par emprise, sans pavage : le cout suit la densite
de voirie, pas la surface. **5,9 s a froid** sur une AOI de 31 ha
(mesure nemetonshiny, 2026-08-12).

**Le pire cas est desormais BORNE** (ADR-010). Auparavant, une instance
bridee faisait boucler `osmdata` en backoff de 60 s sans plafond – 16
reprises consecutives mesurees, soit 16 minutes de pure attente, et plus
de 10 minutes pour une requete ordinaire un jour de bride. Le transport
passe maintenant par
[`osm_overpass()`](https://pobsteta.github.io/foretaccess/reference/osm_overpass.md),
dont la duree ne peut pas depasser
`timeout * length(serveurs) * (1 + max_reprises)`, soit **18 minutes au
pire absolu** avec les defauts (90 s x 4 instances x 3 essais) et
quelques secondes en nominal. Sur `429`, un `Retry-After` n'est honore
que s'il est court (\< 10 s) ; au-dela on change d'instance plutot que
d'attendre.

Cela reste long pour une interface : un bouton qui appelle cette
fonction doit etre **asynchrone et annulable**. Ce qui change, c'est
qu'il termine.

## See also

[`comparer_desserte_osm()`](https://pobsteta.github.io/foretaccess/reference/comparer_desserte_osm.md),
[`acquire_desserte()`](https://pobsteta.github.io/foretaccess/reference/acquire_desserte.md)
(la référence), `specs/028`.
