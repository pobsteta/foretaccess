# Valide un objet de configuration ForêtAccess

Vérifie types, bornes et cohérence via checkmate. Lève une erreur ciblée
au premier manquement.

## Usage

``` r
validate_config(cfg)
```

## Arguments

- cfg:

  Objet `foretaccess_config`.

## Value

`cfg` de façon invisible si valide ; sinon une erreur.
