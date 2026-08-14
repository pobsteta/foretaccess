# BRIEF — profil en travers d'un tronçon de desserte au clic

> **Statut** : ouvert, 2026-08-14.
> **Packages concernés** : `foretaccess` (source canonique), `dessertR` (moteur), `nemetonshiny` (demandeur).
> **Nature** : nouvelle fonction exportée + correction d'une dépendance non déclarée.
> **Préalable** : lire §4 avant d'implémenter — `dessertR` fournit déjà une partie des briques,
> le seul vrai développement est l'extraction du nuage LiDAR (et non du seul MNT).
> **Contexte de rédaction** : `nemetonshiny@0.122.10.9001` ; `foretaccess 2.2.0`, `nemeton 0.169.0`.

---

## 1. Ce que l'app veut offrir

Dans l'onglet **Terrain > Accessibilité**, couche « Desserte BD TOPO / corrigée » :
un **clic sur la carte** affiche le **profil en travers** du tronçon le plus proche —
nuage LiDAR en coupe, bords détectés, largeurs.

La planche visée porte, sur un même graphique :

- les **points LiDAR** de la coupe, colorés (écart-type de Z, points sol, intensité) ;
- une **courbe ajustée** de la chaussée (`ax² + bx + c`) ;
- l'axe **« pathfinder centerline »** ;
- **cinq familles de bords** avec leur largeur cotée :
  `drivable` (~10 m), `road` (~21 m), `right of way` (~29,5 m), `shoulders`, `rescue`.

## 2. Ce que l'app NE fera PAS

Règle 1 de `nemetonshiny` : aucune logique métier côté app. L'app ne calculera donc
ni la coupe, ni les bords, ni les largeurs, ni l'accrochage du clic au tronçon.
Elle se contente de : appeler, mettre en cache, **dessiner**.

Le **tracé** reste côté app (`R/fct_plot_desserte_profil.R`), sur le modèle exact de
`R/fct_plot_pixel_dieback.R` : un helper de présentation pur, qui consomme une sortie
DÉJÀ dérivée et n'y recalcule rien. Le cœur ne doit donc **pas** renvoyer de graphique.

## 3. API demandée

Une fonction exportée par **`foretaccess`** (l'app ne doit jamais appeler `dessertR`
directement — cf. §7) :

```r
profil_travers(
  desserte,            # sf LINESTRING : le réseau (corrigé de préférence)
  xy,                  # numeric(2) ou sf POINT : le point cliqué
  las_source,          # dossier/catalogue LAS-LAZ, même vocabulaire que qualifier_desserte()
  mnt,                 # SpatRaster, idem
  crs = 2154,
  tolerance_m = 25,    # rayon d'accrochage au tronçon le plus proche
  demi_largeur = 20,   # demi-emprise de la coupe, en m
  epaisseur_m = 2,     # épaisseur de la tranche de nuage prélevée le long de l'axe
  cache_dir = tempdir()
)
```

Les noms d'arguments reprennent volontairement ceux de `qualifier_desserte()`
(`las_source`, `mnt`, `crs`, `cache_dir`) pour que l'app puisse réutiliser sa
résolution de chemins existante sans traduction.

### Contrat de retour (c'est le point critique)

Une liste, ou `NULL` si aucun tronçon dans `tolerance_m` :

| Élément | Type | Contenu |
|---|---|---|
| `troncon` | `sf` 1 ligne | le tronçon accroché, avec ses attributs (`classe`, `source`, `etat_dessertr`, `largeur_carrossable_m`) |
| `station` | `list` | `chainage_m`, `xy` du point projeté sur l'axe |
| `points` | `data.frame` | **un point LiDAR par ligne** : `x_travers` (m, 0 = axe, signé), `z` (m, 0 = sol), `intensite`, `sol` (logique), `classification` |
| `sol` | `data.frame` | profil du terrain : `x_travers`, `z` |
| `ajustement` | `list` | `a`, `b`, `c` de la parabole de chaussée + `rmse`, ou `NULL` si non ajustable |
| `bords` | `data.frame` | **une ligne par bord** : `type` ∈ {`drivable`, `road`, `right_of_way`, `shoulder`, `rescue`}, `x_gauche`, `x_droite`, `largeur_m` |
| `meta` | `list` | `moteur` (`"dessertr"`/…), `n_points`, `demi_largeur`, `epaisseur_m`, `crs` |

Contraintes de forme qui comptent pour l'app :

- `x_travers` **signé et centré sur l'axe** (négatif à gauche) : c'est l'axe X du graphique.
- `bords$type` en **vocabulaire stable et anglais** (clés techniques) ; l'app traduit.
  Ne pas renvoyer de libellé déjà traduit.
- `NULL` franc plutôt qu'une liste vide en cas d'échec, pour que l'app distingue
  « pas de tronçon ici » de « tronçon trouvé mais coupe vide ».

## 4. Briques existantes — à réutiliser, pas à réécrire

`dessertR` expose déjà :

- `dsr_profils(trace, mnt, pas, demi_largeur, pas_travers, methode)` → `stations`,
  `offsets`, `z` (matrice), `normales`. C'est la coupe **sur le MNT**.
- `dsr_measure(trace, mnt, …, methode_largeur = c("chaussee","planeite","gradient"))`
  → largeur roulable, dévers, fossés, pente longitudinale, courbure, confiance.
- `dsr_emprise_certu(...)` → emprise réglementaire.

**Question ouverte, à trancher côté cœur** : `dsr_profils()` échantillonne le **MNT**,
alors que la planche visée montre les **points LiDAR individuels** (colorés par
intensité et par classe sol). Il faut donc soit une extraction de nuage à ajouter,
soit confirmer qu'une fonction équivalente existe déjà. C'est le seul vrai
développement du lot ; le reste est de l'assemblage.

De même, les cinq familles de bords ne semblent pas toutes disponibles : `dsr_measure()`
donne la largeur roulable, `dsr_emprise_certu()` l'emprise. `shoulders` et `rescue`
sont à confirmer.

## 5. Contraintes non fonctionnelles

- **Appelable dans un worker `future`** : l'app l'exécutera en `ExtendedTask`. Pas
  d'état global, pas de connexion ouverte, pas de graphique.
- **Coût borné** : un clic doit rendre en quelques secondes. Ne pas relire tout le
  nuage : ne prélever que la tranche `epaisseur_m` autour de la station.
- **Idempotence / cache** : réutiliser `cache_dir` comme `qualifier_desserte()`.
- Aucun `print()` / `message()` : `cli::cli_*` uniquement.

## 6. Tests attendus côté cœur

1. Accrochage : un point à moins de `tolerance_m` d'un tronçon renvoie ce tronçon ;
   au-delà, `NULL`.
2. Centrage : `min(points$x_travers) < 0 < max(points$x_travers)`, et l'axe est en 0.
3. Vocabulaire : `bords$type` ⊆ des cinq clés attendues, aucune valeur traduite.
4. Ordre : pour un même profil, `largeur(drivable) <= largeur(road) <= largeur(right_of_way)`.
5. Dégradé : sans LAS disponible, `NULL` (et non une erreur).

## 7. Dette de dépendance à traiter dans le même lot

`nemetonshiny/R/service_desserte.R:595` appelle **`dessertR::dsr_classer()`
directement**, alors que `dessertR` n'est déclaré **nulle part** dans le
`DESCRIPTION` de l'app (ni Imports, ni Suggests, ni Remotes). L'appel est enveloppé
dans un `tryCatch(error = function(e) NULL)` : sur un poste sans `dessertR`, la
classification des tronçons détectés **disparaît sans le dire**.

Deux corrections possibles, la première étant conforme au sens des dépendances
(l'app dépend de `foretaccess`, jamais de son moteur) :

1. **`foretaccess` expose un `classer_desserte()`** qui enveloppe `dsr_classer()`, et
   l'app bascule dessus — à privilégier, et à livrer avec `profil_travers()` ;
2. à défaut, l'app déclare `dessertR` en `Suggests` + `Remotes` et garde l'appel
   derrière un `requireNamespace()` explicite qui **prévient** l'utilisateur au lieu
   de dégrader en silence.

## 8. Protocole de livraison

1. `foretaccess` : implémenter, exporter, documenter, tester, entrée NEWS, **release**.
2. Me redonner la version publiée : l'app bumpera `Imports: foretaccess (>= X.Y.Z)`
   (plancher actuel : `>= 2.1.0`, installé : `2.2.0`).
3. Côté app, je livrerai alors :
   - `R/service_desserte.R` — adaptateur (résolution LAS/MNT, cache, `ExtendedTask`) ;
   - `R/fct_plot_desserte_profil.R` — planche plotly, présentation pure ;
   - `R/mod_accessibility.R` — `observeEvent(input$map_click)`, gardé par
     `input$layer == "desserte_comparee"`, toast immédiat, rendu en modale.

**Rappel** : tant que `profil_travers()` n'est pas dans une **release** de
`foretaccess`, l'app ne peut pas la consommer — `Remotes: @*release` ne tire que les
tags, jamais `main`.
