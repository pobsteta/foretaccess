# BRIEF `nemetonshiny` — ce qui vous attend, dans l'ordre

> Consolidé le 2026-08-13, côté `foretaccess` (`v2.2.0`).
> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/nemetonshiny`.**
> Quatre briefs se sont accumulés au fil de la journée ; celui-ci ne les remplace
> pas, il les **ordonne** et signale la dépendance entre les deux premiers.

## L'ordre, et pourquoi

| # | Sujet | Brief | Priorité |
|---|---|---|---|
| **1** | Invalidation du cache desserte | `brief-nemetonshiny-couts-desserte-ui.md` **annexe A** | **Haute — bloquant** |
| **2** | `skidding_m` | `brief-nemetonshiny-skidding-desserte.md` | **Haute** |
| 3 | Les trois entrées de coût | `brief-nemetonshiny-couts-desserte-ui.md` §1-4 | Moyenne |
| 4 | Vérifications Overpass | `brief-nemetonshiny-overpass.md` | Basse |
| — | *(pour mémoire)* réponse au brief consolidé | `brief-nemetonshiny-desserte-consolide-reponse.md` | traité |

## 1 et 2 vont ensemble, dans cet ordre

**C'est le seul point de méthode de ce document, et il vous ferait perdre une
demi-journée si vous l'ignoriez.**

`skidding_m` est le correctif à plus fort impact de tout l'écosystème : « Générer
la desserte » tourne aujourd'hui **des heures sans rendre la main** sur une AOI
réelle (mesuré : > 22 min sans finir sur Dabo), et un argument le ramène à
**1 à 3 minutes**. C'est la seule fonctionnalité actuellement inutilisable.

Mais `.load_cached_desserte()` **ne compare aucun paramètre**. Elle prend le seul
chemin du projet, rejette les caches antérieurs à `pondere_cout = TRUE`, et sert
tout le reste tel quel — `skidding_m` y est *rapporté* depuis `meta`, jamais
confronté à la valeur demandée.

Conséquence, **déjà vraie aujourd'hui** : changer `skidding_m` puis rouvrir
l'onglet sert le réseau précédent, et le badge affiche l'ancienne valeur — rien
ne trahit l'écart.

**Si vous corrigez `skidding_m` avant le cache, vous ne verrez pas votre propre
correctif prendre effet**, et vous le chercherez au mauvais endroit. L'annexe A
donne le correctif de fond (comparaison des paramètres, cache sans le champ
traité comme divergent) et le passe-plat.

## Ce que le cœur fournit désormais

Toutes ces demandes sont livrées côté `foretaccess`, publié en **`v2.1.0`** et
**`v2.2.0`** :

* `reseau_desserte(skidding_m = )` — documenté, avec le domaine de validité
  mesuré (`@section Performance`) ;
* `surface_cout_construction(methode_pente =, largeur_m =, pente_max_pct =)` —
  les trois entrées du §2, avec le plafond de constructibilité **séparé** de la
  méthode de tarification ;
* `dessertR_disponible()` — pour garder vos actions avant de les lancer, plutôt
  que d'afficher un diagnostic vide qui se lit comme « aucune infraction » ;
* `osm_overpass()` — le pire cas Overpass est **borné** ; `acquire_desserte_osm()`
  garde sa signature, seul le transport change.

## Deux pièges signalés, à ne pas redécouvrir

**Zéro route est un succès.** À `skidding_m` réaliste, une forêt bien desservie
n'a rien à construire — mesuré sur Dabo : 39 routes à 100 m, **aucune** à 300 m.
Traitez ce cas comme un résultat (« le réseau existant suffit à *N* m »), pas
comme un échec ou un vide.

**`connexe = FALSE` n'est pas un défaut de vos tracés.** Il décrit la
fragmentation de la desserte **existante**. Ne l'affichez pas comme un badge
qualité de la génération — c'est `raccorde` qui répond à « mes routes
s'accrochent-elles ? ».

## Ce que le cœur ne fournira pas

Un **barème de prix au m³** pour le terrassement, et un **avis sur le seuil de
constructibilité**. Ce sont des décisions de gestionnaire ; le banc DABO
(`specs/029` §7) donne de quoi les instruire, pas de quoi les prendre.
