# Politique de réutilisation des caches d'acquisition

Que faire quand un cache existe mais **n'a pas été produit avec les
paramètres de l'appel courant** ? Défaut `"reacquerir"` : le coût d'une
ré-acquisition est mesurable, celui d'un résultat faux ne l'est pas.

## Usage

``` r
cache_utilisable(
  chemin,
  couche,
  source = NULL,
  params = list(),
  politique = "reacquerir"
)
```

## Arguments

- chemin:

  Chemin du fichier de cache.

- couche:

  Nom de la couche (`"desserte"`, `"mnt"`, ...).

- source:

  Identifiant de la source (typename WFS, couche WMS...).

- params:

  Liste nommée des paramètres qui **changent le contenu**.

- politique:

  Une valeur de
  [`politique_cache_valeurs()`](https://pobsteta.github.io/foretaccess/reference/politique_cache_valeurs.md).

## Value

`TRUE` si le cache est utilisable en l'état, `FALSE` sinon.

## Details

- `"reacquerir"` — ignore le cache divergent et refait l'acquisition ;

- `"avertir"` — sert le cache en nommant ce qui diverge ;

- `"echouer"` — interrompt : pour les bancs et la CI, où un cache périmé
  fausse une mesure publiée ;

- `"ignorer"` — aucun contrôle, comportement antérieur à la v1.29.0.

Un cache **sans sidecar** de provenance (antérieur à cette version) est
traité comme divergent, avec un message distinct : on ne peut pas
savoir, donc on ne suppose pas que c'est bon.

## See also

`specs/027`.
