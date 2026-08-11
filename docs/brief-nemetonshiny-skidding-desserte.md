# BRIEF `nemetonshiny` — les 22 minutes de « Générer la desserte » viennent de `skidding_m = 0`

> Réponse au hand-off `BRIEF-foretaccess-progression-reseau-desserte.md`.
> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/nemetonshiny`**
> (un repo = une session). Repo concerné : `pobsteta/nemetonshiny`.
> Mesuré avec `foretaccess 2.0.1` sur le cache Dabo du projet `20260801_130303_xpdk`.
> **Le correctif est côté app, en un argument.** Rien à corriger dans le cœur.

## 1. Verdict

Le brief demandait un canal de progression dans le noyau Rust, au motif que le
glouton met 11,5 à 22 min sans rien afficher. La mesure montre que **le calcul
ne devrait pas durer si longtemps** : `run_desserte()` appelle
`foretaccess::reseau_desserte()` **sans `skidding_m`**, donc au défaut `0`, qui
est le **pire cas explicitement documenté** par la fonction.

`service_desserte.R:357` :

```r
foretaccess::reseau_desserte(pre, cout, parcelles = parcelles,
                             desserte_existante = desserte, mode = engine)
#                            ^ pas de skidding_m -> defaut 0
```

Le `@section Performance` de `reseau_desserte()` dit, mot pour mot :

> At `skidding_m = 0` *every* parcel cell off a road spawns its own A\* trace —
> hundreds per hectare-scale parcel. […] Measured on Chastel-Nouvel (30 parcels,
> ~302k cells) at `skidding_m = 0`: the greedy runs in **~17 min** […]
> **Set `skidding_m` to your real skidding/forwarding distance**; it is not
> optional tuning.

Les ~11,5 min de l'en-tête de `service_desserte.R` sont donc la mesure du pire
cas, pas celle du moteur en usage normal.

## 2. Mesure sur Dabo

Emprise du cache : 832 × 891 = **741 312 cellules** à 5 m. Parcelles : **4 UGF /
774 ha**, soit **309 726 cellules-source**.

| `skidding_m` | durée | routes tracées | coût |
|---:|---:|---:|---:|
| **0** (défaut — ce que fait l'app aujourd'hui) | **> 22 min, jamais fini** | — | — |
| 100 m | **174 s** | 39 | 18 021 |
| 300 m | **70 s** | 0 | 0 |
| 500 m | **115 s** | 0 | 0 |

Pour référence : `preprocess()` + `surface_cout_construction()` = 3,6 s, et la
table de voisinage seule (le moteur avec zéro source) = 38,4 s.

Deux enseignements :

- un `skidding_m` réaliste fait passer Dabo d'un calcul **interminable** à
  **1 à 3 minutes** ;
- à 300 m et au-delà, la réponse est **« rien à construire »** — le réseau
  existant dessert déjà les 774 ha. C'est un résultat utile, rendu en 70 s, que
  l'utilisateur n'a jamais pu voir parce que le calcul ne rendait pas la main.

Le non-monotone (300 m plus rapide que 500 m) est normal : le test « une route
est-elle à portée de débardage ? » balaie un disque de rayon `skidding_m`, donc
son coût croît en `r²`, pendant que le nombre de tracés décroît.

## 3. Pourquoi le compteur demandé n'aurait pas pu marcher

Le brief proposait `{"i": 17, "n": 42}`, affiché « Moteur glouton (17/42) », écrit
après **chaque parcelle traitée**. Or `reseau_desserte()` ne boucle pas sur les
parcelles : `.desserte_cellules_parcelles()` (`R/desserte_reseau.R:397-400`)
renvoie **toutes les cellules couvertes par les parcelles**, et c'est cette liste
qui part au noyau.

Sur Dabo, `n` ne vaut donc pas 4 (ni 42), mais **309 726**. Une écriture atomique
« fichier temporaire + `rename` » par itération, ce sont trois cent mille
créations/renommages de fichier : l'instrumentation coûterait plus cher que le
calcul qu'elle mesure.

Ce n'est pas un obstacle définitif — c'est une correction du contrat, voir §5.

## 4. Correctif demandé

**Passer `skidding_m` à `reseau_desserte()`**, avec la distance de
débardage/portage réelle du mode d'exploitation retenu.

1. `run_desserte()` (`service_desserte.R:357`) transmet un `skidding_m`.
2. La valeur devrait venir du même endroit que le reste du paramétrage
   d'exploitation, pas d'une constante en dur — c'est un paramètre métier
   (distance de débardage), pas un réglage de performance. À vous de voir s'il
   se prend dans la config d'accessibilité déjà exposée dans l'app.
3. **Le rendre visible à l'utilisateur.** Il change le résultat, pas seulement la
   durée : à 100 m Dabo demande 39 routes, à 300 m aucune. Un utilisateur qui ne
   voit pas ce paramètre ne peut pas interpréter « rien à construire ».
4. Corriger l'en-tête de `service_desserte.R`, qui documente « ~11,5 min (un tracé
   A\* par parcelle) » — c'est **un tracé par cellule de parcelle**, et la durée
   citée est celle du pire cas.

Point d'attention : à `skidding_m` élevé le moteur peut légitimement ne rendre
**aucune** route. L'app doit traiter ce cas comme un **succès** (« le réseau
existant suffit »), pas comme un échec ou un résultat vide — sinon on remplace
une attente aveugle par un message d'erreur trompeur. Le `connexe = FALSE`
retourné dans ce cas reflète la fragmentation de la desserte **existante**, pas
un défaut des routes créées (il n'y en a aucune).

## 5. Le canal de progression, si vous le voulez toujours

Il garde du sens — 70 à 174 s restent longs — mais avec un contrat corrigé :

- **`n` = nombre de sources** (~3 × 10⁵), pas de parcelles. Afficher un
  pourcentage, pas « 17/42 ».
- **Écritures throttlées** : une toutes les N itérations ou toutes les X ms,
  jamais une par itération.
- **La table de voisinage est une phase à part.** Elle pèse 38,4 s sur Dabo,
  avant la première itération. Sans événement dédié, la barre resterait à 0 %
  pendant 38 s — soit exactement l'attente aveugle qu'on veut supprimer.
- **`i` compte des sources examinées, pas des routes tracées.** La boucle saute
  les cellules hors grille, sur obstacle, ou déjà desservies (sur Dabo : 17 533
  sautées d'emblée, l'heuristique `plus_proche` les mettant en tête). L'app
  afficherait donc « 100 % » avec 39 routes — à expliciter côté libellé.

Contrainte d'implémentation relevée côté cœur, pour mémoire : l'instrumentation
ne pourra pas vivre dans `build_network_with_table()`, partagée avec le
multistart qui l'appelle en `par_iter()` — N trials écriraient dans le même
fichier. Elle devra se poser au point d'entrée `desserte_reseau`.

**Notre position** : ce chantier redevient de la **priorité basse** une fois le
§4 appliqué. Dites-nous si vous le voulez quand même, et nous l'ouvrirons avec ce
contrat-là.

## 6. Références

- Mesures : cache `~/.local/share/nemeton/projects/20260801_130303_xpdk`, emprise
  250 m, MNT 5 m, `foretaccess 2.0.1`, 2026-08-11.
- Cœur : `reseau_desserte()` `@section Performance` (le domaine de validité y est
  déjà écrit), `R/desserte_reseau.R:397` (`.desserte_cellules_parcelles`),
  `src/rust/src/desserte/solver.rs:646` (la boucle).
- App : `nemetonshiny/R/service_desserte.R:357` (l'appel), en-tête du fichier
  (les ~11,5 min à corriger).
