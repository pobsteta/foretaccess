# specs/008 — Lot 8 : Base spatiale & agrégation zonale

> **Statut** : **validé** (décisions §9 du 2026-07-12).
> **Lot** : 8 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 8 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md)). **Exigences** : EF-9, EF-12
> ([`docs/PRD.md`](../docs/PRD.md)). **ADR** : ADR-002 (stockage).
> **Dépend de** : Lot 0 (interface `StorageBackend` : `storage_gpkg()`,
> `storage_postgis()`, `sb_write_layer()`), Lot 1 (`recapituler()`, `preprocess()` :
> grille, `parcellaire`), moteurs Lots 2/3/6 et sélection Lot 5 (sorties à agréger).
> **Consomme** : toutes les sorties catégorielles `accessibilite` + rasters de volume.

---

## 1. Contexte

Les Lots 0 à 7 produisent des sorties **par cellule** (rasters d'accessibilité) et
**par ligne** (sélection câble). Le Lot 8 les rend **exploitables en base** : il
garantit une écriture **idempotente** et **indexée** spatialement (le socle
`StorageBackend` du Lot 0 est complété), et il **agrège** les surfaces et volumes
par entité de gestion — massif, parcelle, commune (EF-12).

Le socle vectoriel existe déjà (Lot 0) : deux backends interchangeables
(**GeoPackage** et **PostGIS**), écriture/lecture/liste (`sb_*`). Ce lot ajoute les
**deux briques manquantes** du critère de sortie : l'**index spatial** côté PostGIS
et l'**agrégation zonale**.

---

## 2. Périmètre

### Dans le périmètre

- **Index spatial** GiST à l'écriture PostGIS (US-8.1 CA1).
- **Agrégation zonale** `agreger_zones()` : surfaces (ha) et volumes (m³) par zone
  et par classe, pour n'importe quel raster catégoriel d'accessibilité (US-8.2).
- La **persistance** de l'agrégation via le socle `StorageBackend` existant
  (l'agrégation est un `sf`, donc directement `sb_write_layer()`-able).

### Hors périmètre

- Un ORM / schéma DDL figé par table : l'écriture reste pilotée par `sf::st_write`
  (le schéma des colonnes suit les données). Le « schéma par run/massif » est le
  **schéma PostgreSQL** paramétrable du backend (Lot 0), pas un DDL de tables.
- Le parcellaire cadastral en propre : `zones` est un `sf` fourni par l'appelant
  (le `parcellaire` optionnel de `preprocess()` en est un cas d'usage).

---

## 3. API

```r
# Agrégation zonale (nouveau).
agreger_zones(classes, zones, volume = NULL, id = NULL)

# Écriture indexée (socle Lot 0 complété).
sb_write_layer(backend, layer, data, ..., spatial_index = TRUE)  # backend PostGIS
```

`agreger_zones()` renvoie un `sf` (classe `foretaccess_agregation`) : `zones`
augmenté de colonnes **larges** `surface_<classe>_ha` (+ `volume_<classe>_m3` si
`volume`) et `surface_totale_ha`. Directement persistable/requêtable.

---

## 4. Agrégation zonale (US-8.2)

C'est le pendant zonal de [`recapituler()`] (qui agrège sur l'emprise entière) :

1. **Verrou CRS** : `zones` doit avoir un CRS (règle stricte du projet — aucune
   couche sans CRS) ; il est reprojeté vers celui de `classes` au besoin.
2. **Rasterisation** de `zones` sur la grille de `classes`, par leur rang `1..n`.
3. **Croisement** zone × classe : comptage des cellules (via `table`), somme des
   volumes (via `tapply`) — **vectorisé**, pas de boucle par cellule.
4. Surface = `cellules × prod(res)/10000` ha ; les cellules de classe `NA`
   (indéterminées) forment une colonne `indetermine` explicite, comme `recapituler()`.

**Propriété de partition** : si les zones partitionnent l'emprise (couverture
complète, sans recouvrement), la somme des surfaces zonales par classe égale le
`recapituler()` global — c'est le test de non-régression central (§7).

### 4.1 Parcellaire optionnel

`zones` est quelconque : massif, parcelle (le `parcellaire` de `preprocess()`),
commune. Le choix de la maille est à l'appelant. Une zone disjointe du raster a des
surfaces nulles (aucune cellule) — jamais d'erreur.

---

## 5. Index spatial (US-8.1)

`sb_write_layer()` sur backend PostGIS crée, après l'écriture idempotente
(`delete_layer = TRUE`), un **index GiST** sur la colonne de géométrie (nom lu dans
la vue `geometry_columns`). Le nom d'index est stable et la création est idempotente
(`CREATE INDEX IF NOT EXISTS`). Désactivable par `spatial_index = FALSE`.

Côté **GeoPackage**, l'index spatial (R-tree) est créé automatiquement par
GDAL/`sf` à l'écriture : l'équivalence US-8.1 CA2 est acquise sans code
supplémentaire.

---

## 6. Idempotence

- **Vectoriel** : `sb_write_layer()` remplace la couche (`delete_layer = TRUE`) —
  ré-écrire ne duplique rien (déjà garanti au Lot 0, testé) ; l'index n'est pas
  dupliqué non plus (`IF NOT EXISTS`).
- **Agrégation** : fonction pure, déterministe (aucun état).

---

## 7. Tests

`tests/testthat/test-agregation.R` (sans base, sur le jouet) :

- **Conservation** de la surface totale ; **partition** = égalité au `recapituler()`
  global par classe.
- **Volume** agrégé par zone quand fourni (égal au volume global).
- **Identifiant** de zone par défaut (`zone_id`).
- Agrégation sur une **autre sortie** (DFCI) — colonnes adaptées aux classes.
- **Verrous** : raster non catégoriel → erreur ; `zones` sans CRS → erreur.
- Zone **disjointe** → surfaces nulles.
- `print`.

`tests/testthat/test-storage-postgis.R` (base jetable, `skip_if_no_test_db()`) :

- L'écriture crée un **index GiST** ; ré-écrire ne le duplique pas.

---

## 8. Critères d'acceptation (backlog)

- **US-8.1 CA1** : schéma par run/massif (Lot 0), **index spatiaux** (ce lot),
  écriture **idempotente** (Lot 0 + index idempotent). ✅
- **US-8.1 CA2** : export GeoPackage équivalent (R-tree auto). ✅
- **US-8.2 CA1** : requêtes d'agrégation validées ; parcellaire optionnel pris en
  compte quand fourni. ✅

---

## 9. Décisions figées (2026-07-12)

1. **Agrégation en R/terra** (croisement raster vectorisé), backend-agnostique :
   testable sans base, persistable dans les deux backends. Pas de SQL spécifique
   PostGIS pour l'agrégation — le résultat `sf` se requête ensuite indifféremment.
2. **Sortie large** (`surface_<classe>_ha`) : une ligne par zone, directement
   jointe à la géométrie et requêtable ; pas de forme longue séparée.
3. **Index GiST** systématique à l'écriture PostGIS (`spatial_index = TRUE`),
   idempotent ; R-tree auto côté GPKG.
4. **`zones` fourni par l'appelant** : pas de dépendance cadastrale en propre.
   Verrou CRS strict (cohérent avec le reste du pipeline).
5. Le « **DDL / schéma par run** » de l'ADR-002 est le **schéma PostgreSQL**
   paramétrable du backend (Lot 0), pas un DDL de tables figé.

---

## 10. Attribution

ForêtAccess dérive de Sylvaccess (INRAE, S. Dupire — GPL v3). L'agrégation zonale et
le socle de stockage sont une conception propre, distribuée sous GPL v3.
