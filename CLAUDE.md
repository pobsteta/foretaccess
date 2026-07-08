# CLAUDE.md — ForêtAccess Development Reference

## Identité du projet

ForêtAccess cartographie automatiquement l'**accessibilité des forêts** selon le
mode d'exploitation (skidder, porteur, câble-mât, camion DFCI). C'est une
réimplémentation moderne, découplée et testable du modèle **Sylvaccess**
(INRAE — S. Dupire), sous forme de **package R** avec un **noyau câble en Rust**
(via `extendr`/`rextendr`), et des sorties en **base spatiale** (PostGIS /
GeoPackage). Travail personnel de Pascal Obstetar, cohérent avec l'écosystème
Nemeton (utilitaires et base spatiale potentiellement partagés).

Statut : **amorçage**. Développement *spec-driven* / agile par lots
(`specs/0XX-*.md` + ADR + tests de non-régression), piloté via Claude Code. La
feuille de route vit dans le brief (`docs/foretaccess-brief.md`, §10 Lotissement).

## Stack technique

- **R (>= 4.1.0)** : orchestration, I/O SIG (`terra`, `sf`), prétraitement, plus
  court chemin (`leastcostpath`/`gdistance`), moteurs terrestres, pipeline
  (`targets`).
- **Rust** : noyau câble (mécanique CableHelp), exposé via **`extendr`/`rextendr`**,
  parallélisme **`rayon`**.
- **Stockage** : PostGIS (défaut, `DBI`/`RPostgres`) ou GeoPackage (`sf`) derrière
  une interface commune ; rasters en GeoTIFF/COG (`terra`).
- **Tests** : `testthat` (edition 3) côté R ; tests Rust (`cargo test`) côté crate.

## Commandes de référence

```bash
# Compiler le crate Rust + regénérer les bindings extendr
Rscript -e 'rextendr::document()'

# Regénérer la documentation R
Rscript -e 'devtools::document()'

# Lancer tous les tests R
Rscript -e 'devtools::test()'

# Tests du crate Rust
cargo test --manifest-path src/rust/Cargo.toml

# Vérifier le package
Rscript -e 'devtools::check()'

# Couverture de code
Rscript -e 'cat(covr::percent_coverage(covr::package_coverage(quiet=TRUE)))'
```

## Conventions de code

### Fonctions R
- Nouvelles fonctions : snake_case français sans accent (translittération
  é→e, è→e, à→a, ô→o, ç→c ; codes courts en majuscules).
- Documentation roxygen : en anglais (cohérence avec l'écosystème).
- Commentaires inline : en français.
- Chaque nouvelle fonction exportée a un test dans `tests/testthat/`.

### Rust (noyau câble)
- Frontière R↔Rust minimale et typée ; la logique métier vit dans le crate,
  R orchestre et convertit les données SIG.
- Toute fonction exposée via `#[extendr]` a un test `cargo test` et un test
  d'intégration R qui l'appelle.

### Tests
- Framework R : testthat edition 3, nommage `test-{module}.R`.
- `withr::with_tempdir()` pour les fichiers temporaires.
- Ne jamais versionner de rasters/SIG volumineux (cf. `.gitignore`) ; garder
  les fixtures légères sous `inst/extdata/` explicitement dé-ignorées.

# Consignes de commit

Format **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`,
`refactor:`, `test:`, `BREAKING CHANGE:`). Le type détermine le bump semver
(feat → minor, fix → patch, BREAKING CHANGE → major).

Chaque commit doit se terminer par la ligne de co-auteur Claude quand le
changement a été produit en session Claude Code.

# Consignes de release

> Ces règles s'appliquent dès que le squelette de package R existe
> (`DESCRIPTION`, `NEWS.md`, `CITATION.cff`). Tant qu'on est en pur amorçage
> (docs seulement), un simple commit `docs:`/`chore:` suffit, sans bump.

**Le tag et la release GitHub sont AUTOMATISÉS** par
`.github/workflows/release.yml` : au push sur `main`, il lit `Version:` dans
`DESCRIPTION` et, si c'est une version **stable `X.Y.Z`** dont le tag `vX.Y.Z`
n'existe pas encore, crée le tag annoté + la release GitHub (`--generate-notes`).
**Ne pas faire `git tag` / `git push origin vX.Y.Z` / `gh release create` à la
main.**

À chaque push qui modifie le code fonctionnel (hors doc pure, hors CI), Claude
doit :

1. Déterminer le type de changement selon Conventional Commits → bump semver
   correspondant (minor / patch / major).

2. Mettre à jour la version, de façon **cohérente** dans les trois fichiers
   (un job CI `version-consistency` échoue sinon) :
   - `DESCRIPTION` (champ `Version`) → la version stable `X.Y.Z` de la release ;
   - `NEWS.md` (entrée datée `# foretaccess X.Y.Z (YYYY-MM-DD)`) ;
   - `CITATION.cff` (`version:` + `date-released:`).

3. Si `CHANGELOG.md` existe, ajouter la section `[X.Y.Z] - YYYY-MM-DD`
   (Added / Changed / Fixed / Removed).

4. Mettre à jour `PLAN.md` (journal daté ; table d'avancement si l'état change).
   Source unique de vérité du walking skeleton. Ne jamais clore un chantier sans
   release correspondante.

5. Ouvrir une PR vers `main` et la merger → `release.yml` pose le tag + la
   release. Rien d'autre à faire : le badge version du README est dynamique
   (`img.shields.io/github/v/release`) et se met à jour seul.

6. **Repasser en cycle dev** : juste après la release, bumper `DESCRIPTION` en
   version de dev `X.Y.Z.9000` (cf. *Cycle de développement* ci-dessous).

## Cycle de développement (versions `.9000`)

Entre deux releases, `DESCRIPTION` porte une version de **dév** `X.Y.Z.9000`
(4 composantes). Convention :

- **État publié sur `main`** : `DESCRIPTION` = `X.Y.Z` stable, tag `vX.Y.Z` posé
  par le CI.
- **Démarrage du cycle dev** : bumper `DESCRIPTION` → `X.Y.Z.9000`. `NEWS.md` et
  `CITATION.cff` **restent** sur `X.Y.Z` (la dernière release).
- **Pendant le dev** : `DESCRIPTION` reste `X.Y.Z.9000`.
- **Release suivante** : poser une version stable `X.Y.(Z+1)` (ou `X.(Y+1).0`,
  etc.) dans `DESCRIPTION` **et** `NEWS.md` **et** `CITATION.cff`, merger.

`release.yml` **ignore** les versions `.9000+` (gate « stable only ») et le
garde-fou `version-consistency` **saute** en cycle dev. Un push de cycle dev ne
déclenche donc ni release ni échec CI.

## Règles de cohérence

- Pour une version **stable**, `DESCRIPTION` = tête de `NEWS.md` =
  `CITATION.cff` (vérifié en CI par `version-consistency`). Tag et release sont
  ensuite posés automatiquement, donc identiques par construction.
- Vérifier que la doc (pkgdown) est à jour — elle rend le README (badge
  dynamique) et lit la version de `DESCRIPTION`.
- **Toujours demander confirmation avant un bump majeur.**

## Règles strictes

1. La logique métier (accessibilité, moteurs terrestres, mécanique câble) vit
   dans le package `foretaccess` (R + crate Rust), jamais dans un dépôt frère.
2. Les rasters et données SIG volumineuses ne sont JAMAIS commités ni stockés
   dans PostgreSQL ; PostGIS/GeoPackage pour le vectoriel, GeoTIFF/COG pour le
   raster.
3. La frontière R↔Rust reste minimale et typée ; pas de logique SIG dans le
   crate au-delà du calcul câble pur.
4. Travail dérivé de Sylvaccess (GPL v3) → ForêtAccess est distribué sous
   **GPL v3** ; citer Sylvaccess (cf. README, section attribution).
5. Pour une tâche longue, maintenir `PLAN.md` à la racine (état courant,
   décisions, prochaine étape) et le mettre à jour à chaque étape terminée.
6. **Ne JAMAIS modifier le répertoire de travail d'un repo frère** (`nemeton`,
   `nemetonshiny`, etc.) depuis une session ForêtAccess. Lecture seule permise ;
   toute opération git mutante y est interdite (risque d'écraser un WIP d'une
   session parallèle).
