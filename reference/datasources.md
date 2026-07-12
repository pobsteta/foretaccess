# Sources de données géographiques par pays (config-driven)

Couche d'abstraction pour les sources de données (ADR-002, patron
**nemeton**) : les endpoints de service et les identifiants de couche ne
sont **jamais codés en dur**. Ils sont déclarés dans un fichier JSON par
pays (`inst/datasources/FR.json`). Ajouter un pays ne demande qu'un
fichier JSON, pas de modification de code.

## Details

Le résolveur alimente le Lot d'acquisition
([`acquire_inputs()`](https://pobsteta.github.io/foretaccess/reference/acquire_inputs.md))
: celui-ci demande une couche par sa **clé logique** (`dem`, `roads`,
`bdforet_v2`, `cadastre`) et obtient l'URL de service + l'identifiant de
couche résolus.
