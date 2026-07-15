# specs/006 — Camion DFCI : zone de défendabilité (balayage radial)

> **Statut** : **réécrit au Lot 12a.4** (2026-07-15). La version initiale (Lot 6)
> reposait sur une **hypothèse fausse** — « Sylvaccess n'a pas de module DFCI ». Il
> en a un (`Sylvaccess_5_dfci.py`, `debusq_dfci`), désormais transcrit à la lettre
> et **confronté à l'oracle** ColduPre.
> **Exigence** : EF-8 ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 1 (`preprocess()` : MNT, pente %, forêt, desserte + flag
> `CL_DFCI`), noyau Rust (`dfci_scan`), Lot 7 (`traiter_par_tuiles()`).

---

## 1. Contexte

Le camion DFCI (défense de la forêt contre les incendies) stationne sur le réseau
de défense et **défend** le terrain avoisinant en déroulant une **lance** (tuyau).
Le Lot cartographie la **zone de défendabilité** : jusqu'où, depuis le réseau DFCI,
une lance peut atteindre la forêt en épousant le relief.

Contrairement à la version beta initiale (plus court chemin pondéré par la pente),
c'est le **vrai moteur de Sylvaccess** qui est transcrit : un **lancer de rayons
radial**. Le chemin Dijkstra pondéré (`calc_dist_dfci`) existe dans les sources de
Sylvaccess mais y est **désactivé**.

---

## 2. Modèle — `debusq_dfci` transcrit

Depuis chaque **pixel-source** du réseau DFCI, un rayon est tiré dans les **360
azimuts** (pas de 1°). Le long d'un rayon, la lance progresse cellule par cellule
et sa longueur **suit le terrain** :

```
Lcum += sqrt(dh² + ddist²)
```

où `ddist` est le pas planimétrique entre deux cellules consécutives et `dh` leur
dénivelé. Le rayon **s'arrête** dès que :

1. il sort de la grille ;
2. il entre dans une cellule **non franchissable** (`zone_ok = 0` : pente
   > `dfci_slope_max`, obstacle, ou trou de MNT) ;
3. `Lcum` dépasse `dfci_lmax` (longueur de lance disponible).

Une cellule de forêt atteinte reçoit la **longueur de lance minimale** sur tous les
rayons de toutes les sources (comparaison `>` stricte : à égalité, la première
source balayée — ordre row-major — l'emporte). Sa **classe de défendabilité** est
la bande de `classes_distance_m` où tombe cette longueur.

### 2.1 Sources : le flag `CL_DFCI`

Les sources sont les cellules portant le flag **`CL_DFCI`** (Sylvaccess :
`respub = allroads[CL_DFCI == 1]`). Ce flag est **orthogonal** aux classes de
desserte (`CL_SVAC`) : une même route peut être route classique *et* réseau de
défense, et un tronçon de réseau public — barrière pour les engins de débardage —
redevient source valide pour le camion-citerne s'il porte le flag. `preprocess()`
le rasterise (ALL_TOUCHED) dans `pre$dfci_source_mask`, indépendamment du raster de
classes.

### 2.2 Arrondis et fidélité

- Longueur cumulée en centimètres, `int(Lcum·100 + 0.5)` (**half-up**), puis
  cm → m `int(Dist/100 + 0.5)`. Ce n'est **pas** l'arrondi demi-au-pair du câble.
- Dénivelé `int(difH ± 0.5)` (**half-away-from-zero**).
- Pente pompier : seuil **simple par cellule** `pente ≤ dfci_slope_max`
  (Sylvaccess jette la version max-local 3×3 via le *swap* de `slopes_skid`).

### 2.3 Écart assumé avec Sylvaccess

Le **bug de masquage** du dénivelé (`sylvaccess_cython3.pyx:4807`, qui écrit aux
coordonnées de la dernière source au lieu de la cellule courante) est **corrigé** :
`denivele` est remis à `NA` sur toute cellule non défendable. L'accord oracle sur
`Denivele_sur_piste` s'en trouve très légèrement dégradé, au profit de la justesse.

---

## 3. Configuration (`config$dfci`)

| Clé | Défaut | Sylvaccess | Sens |
|---|---|---|---|
| `distance_defense_max_m` | `440` | `dfci_lmax` | Longueur de lance max (m). |
| `pente_defense_max_pct` | `110` | `dfci_slope_max` | Pente pompier max (%). |
| `classes_distance_m` | `0;120;280;440` | `dfci_class` | Bornes des bandes de défendabilité. |

Défauts alignés sur `dic_AllParam.json` (ADR : ne diverger qu'avec justification).

---

## 4. Sorties

Objet `foretaccess_dfci` :

- `accessibilite` : raster catégoriel **6 classes** : `inaccessible`,
  `non_defendable_pente`, `defendable_c1` / `c2` / `c3` (bandes de lance
  `[0,120[`, `[120,280[`, `[280,440]`), `hors_foret`. La pente trop élevée écrase
  (une cellule raide est `non_defendable_pente`, jamais défendable).
- `longueur_lance` : longueur de lance (m) atteignant la cellule ; `NA` sinon.
  ↔ `Longueur_lance.tif`.
- `denivele` : dénivelé cellule − source (m). ↔ `Denivele_sur_piste.tif`.
- `lien_reseau` : cellule de desserte DFCI de rattachement. ↔ `Lien_foret_reseau.tif`.
- `pente_ok` : logique, pente ≤ seuil pompier. ↔ `Pente_OK_pompier.tif`.
- `certifie` : logique (tuilage), ou `NULL`.
- `recap`, `grid`, `config`, `fichiers`.

### 4.1 Tuilage

La portée est bornée par `dfci_lmax` : une cellule à plus de `dfci_lmax` de tout
bord **ouvert** de la fenêtre ne peut être atteinte par aucune source extérieure,
son résultat est donc identique au mono-bloc (`.certifier_dfci()`). Le réseau DFCI
étant clairsemé, une tuile sans source dans sa fenêtre reste **indéterminée** (le
halo grandit) ; au top-level, l'absence de source est une **erreur ciblée**.

---

## 5. Architecture

Boucle chaude (balayage radial 360°/pixel) portée en **Rust** (`src/rust/src/dfci/`,
`dfci_scan`), comme le câble : R rasterise sources / pente / obstacles, le crate
balaie, R assemble les 6 classes et les rasters SIG. Frontière minimale et typée
(ADR-001).

---

## 6. Confrontation à l'oracle (ColduPre, 532 016 cellules forestières)

| Sortie | Accord / écart |
|---|---|
| Zone défendable | **99,87 %** (0 % trop optimiste, 0,13 % trop conservateur) |
| Longueur de lance | écart **médian 0,0 m** (moyen 0,57 m) sur 247 897 cellules |
| Dénivelé | écart **médian 0,0 m** |

Le reliquat (0,13 %, 716 cellules) est de la discrétisation de rayon en bordure
(4-connexité vs `ALL_TOUCHED` de GDAL), négligeable.

Banc : `data-raw/oracle_coldupre.R` (génération) + `data-raw/oracle_compare.R`
(bloc DFCI). L'oracle Sylvaccess DFCI n'est pas dans le lanceur standard
(`g_do_dfci` défaut `false`) : le bloc de comparaison se saute si `DFCI_1/` est
absent.

---

## 7. Tests (`tests/testthat/test-dfci.R`)

Disque radial borné ; bandes de défendabilité croissantes ; portée monotone ;
coupure de pente ; sources via le flag `CL_DFCI` (orthogonalité aux classes) ;
récap conservant la surface ; erreur ciblée sans source ; écriture COG relisible ;
`print` ; tuilage (égalité mono-bloc sur cellules certifiées, halo court →
indéterminé).

---

## 8. Limites

Le modèle ne représente ni le **combustible**, ni le **vent**, ni la **physique de
la lance** au-delà de sa longueur maximale, ni la **carrossabilité réelle** des
dessertes (projet QUALIROAD). La coupure de pente pompier est un proxy
d'atteignabilité. Ces sorties valent pour une **hiérarchisation** du territoire.

---

## 9. Attribution

ForêtAccess dérive de Sylvaccess (INRAE, S. Dupire — GPL v3). Le module DFCI
(`debusq_dfci`, `create_buffer_skidder`) est transcrit sous GPL v3.
