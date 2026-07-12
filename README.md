# ForêtAccess

<!-- badges: start -->
[![R-CMD-check](https://github.com/pobsteta/foretaccess/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/pobsteta/foretaccess/actions/workflows/R-CMD-check.yaml)
[![Version](https://img.shields.io/github/v/release/pobsteta/foretaccess?sort=semver&logo=github&label=version&color=blue)](https://github.com/pobsteta/foretaccess/releases/latest)
[![pkgdown](https://github.com/pobsteta/foretaccess/actions/workflows/pkgdown.yaml/badge.svg)](https://pobsteta.github.io/foretaccess/)
[![codecov](https://codecov.io/gh/pobsteta/foretaccess/graph/badge.svg)](https://codecov.io/gh/pobsteta/foretaccess)
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg?logo=gnu)](https://www.gnu.org/licenses/gpl-3.0)
<!-- badges: end -->

Cartographie automatique de l'**accessibilité des forêts** selon le mode d'exploitation
(skidder, porteur, câble-mât, camion DFCI). Réimplémentation moderne, découplée et
testable du modèle **Sylvaccess** (INRAE — S. Dupire), sous forme de **package R** avec un
**noyau câble en Rust** (via `extendr`), et des sorties en **base spatiale**
(PostGIS / GeoPackage).

## Démarrage rapide

```r
library(foretaccess)

toy <- system.file("extdata", "toy", package = "foretaccess")
pre <- preprocess(
  mnt      = file.path(toy, "mnt.tif"),
  desserte = file.path(toy, "desserte.gpkg"),
  foret    = file.path(toy, "foret.gpkg")
)

sk  <- skidder(pre)          # débusqueur
po  <- porteur(pre)          # porteur
df  <- camion_dfci(pre)      # zone défendable DFCI (beta)
cab <- potentiel_cable(pre)  # lignes de câble faisables (noyau Rust)
sel <- selectionner_lignes(cab)

sk$recap                     # surfaces (ha) par classe d'accessibilité
```

Le pipeline complet — prétraitement, moteurs, câble, **agrégation zonale**
(`agreger_zones()`) et **persistance** en base spatiale — est détaillé dans la
vignette :

```r
vignette("foretaccess")
```

## Architecture

![Architecture ForêtAccess](docs/architecture.svg)

Détail des couches, périmètre et décisions : voir le **brief projet**
[`docs/foretaccess-brief.md`](docs/foretaccess-brief.md).

## Statut

Développement *spec-driven* / agile par lots (`specs/0XX-*.md` + ADR + tests de
non-régression). Les **Lots 0 à 8** sont livrés (prétraitement, moteurs skidder /
porteur / câble Rust, sélection câble, camion DFCI beta, passage à l'échelle par
tuilage, base spatiale & agrégation) ; la doc d'usage est en place (Lot 9). La
feuille de route vit dans [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Stack

- **R** : orchestration, I/O SIG (`terra`, `sf`), prétraitement, plus court chemin
  (`leastcostpath`/`gdistance`), moteurs terrestres, pipeline (`targets`).
- **Rust** : noyau câble (mécanique CableHelp), exposé via **`extendr`/`rextendr`**,
  parallélisme **`rayon`**.
- **Stockage** : PostGIS (défaut, `DBI`/`RPostgres`) ou GeoPackage (`sf`) derrière une
  interface commune ; rasters en GeoTIFF/COG (`terra`).

Cohérent avec l'écosystème Nemeton (R/Shiny/golem, PostGIS) : utilitaires et base
spatiale potentiellement partagés.

## Licence & attribution

Distribué sous **GPL v3** (travail dérivé de Sylvaccess, GPL v3). Merci de citer :

- Dupire S., Bourrier F., Monnet J.-M., Berger F. (2015). *Sylvaccess : un modèle pour
  cartographier automatiquement l'accessibilité des forêts.* Revue Forestière Française.
- Dupire S., Bourrier F., Berger F. (2015). *Predicting load path and tensile forces
  during cable yarding operations on steep terrain.* Journal of Forest Research,
  DOI [10.1007/s10310-015-0503-4](https://doi.org/10.1007/s10310-015-0503-4).
- Sylvaccess : DOI [10.15454/JUBESS](https://doi.org/10.15454/JUBESS).
