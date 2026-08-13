# ADR-010 — Le client Overpass canonique vit dans `foretaccess`

* **Statut** : accepté, 2026-08-13.
* **Contexte** : `BRIEF-osm-overpass-unification.md` §1 (décision D1).
* **Concerne** : `foretaccess`, `dessertR`, `nemetonshiny`, `nemeton`.

## Contexte

Quatre paquets consomment OpenStreetMap par **deux implémentations indépendantes**
du même besoin, et chacune est juste là où l'autre se trompe.

`dessertR` a raison sur le **transport** : une instance Overpass saturée ne rend
pas une erreur, elle fait attendre. `osmdata` boucle alors en backoff de 60 s
sans rendre la main — 16 reprises consécutives mesurées, soit 16 minutes
d'attente pure —, `setTimeLimit()` n'y peut rien (il n'interrompt qu'aux points
de contrôle R, pas un socket bloqué dans du C), et une instance bridée renvoie un
XML **bien formé** de quelques centaines d'octets, sans code HTTP d'erreur, avec
un `<remark>`. Sans ce test on conclut « aucune donnée ici » : c'est l'erreur qui
a masqué l'absence de DFCI pendant une journée.

`foretaccess` a raison sur la **stratégie** : Overpass limite le nombre de
requêtes, pas la surface. Le tuilage 1 km de `dsr_osm()` transforme une AOI de
10 × 10 km en 100 requêtes, ce qui déclenche précisément le `429` que le reste du
code s'efforce d'éviter — et il n'a aucun cache.

## Décision

**Le transport canonique vit dans `foretaccess`, exporté** (option (a) du brief).

`dessertR` le consommera via `Suggests`, avec repli sur sa copie interne :
`dsr_osm()` doit continuer de fonctionner sans `foretaccess` installé.

## Pourquoi pas les autres options

**(b) Un micro-paquet `osmclient`.** Plus propre en théorie : un transport n'est
ni de la desserte ni de l'accessibilité. Mais c'est un dépôt de plus à publier,
documenter, versionner et faire installer, pour ~200 lignes — et l'écosystème
souffre déjà de ce que `rlas` ait été archivé du CRAN, ce qui rend `dessertR`
non déclarable (cf. `dessertR_disponible()`). Ajouter un maillon hors CRAN à une
chaîne déjà fragile aggraverait le problème qu'on cherche à réduire.

**(c) Duplication alignée.** C'est l'état actuel, et il a produit la divergence
qu'on corrige. Une duplication « alignée » ne le reste pas : les deux copies ont
divergé précisément parce que chacune a appris quelque chose que l'autre
ignorait.

## Pourquoi `foretaccess` plutôt que `dessertR`

Le lien intellectuel existe déjà dans l'autre sens : `dessertR` reprend
explicitement la liste de serveurs de `foretaccess`, mention GPL-3 à l'appui en
commentaire de son `R/acquisition.R`. Et `nemetonshiny` dépend déjà des deux,
donc l'héberger ici ne lui ajoute rien.

À l'inverse, `dessertR` porte une dépendance dure à `rlas`, **archivé sur le
CRAN** : y placer le transport rendrait le client Overpass inatteignable pour qui
ne peut pas installer `dessertR`. C'est l'argument décisif, et il n'était pas
prévisible au moment du brief.

## Conséquences

* `foretaccess` gagne `curl` en `Imports` — le **paquet**, pas le binaire.
  `system2("curl")` exige un exécutable (fragile sous Windows et en conteneur
  minimal), impose du `shQuote` sur une requête pleine de guillemets, et ne donne
  accès ni au code HTTP ni aux en-têtes, dont on a besoin pour distinguer un
  refus d'un vide.
* `osmdata` reste en `Suggests` tant qu'un appel subsiste ; il sort quand il n'en
  reste aucun.
* Le transport est **exporté** : c'est une API publique, donc son contrat — les
  trois issues du §2.2, le plafond de durée — est documenté et testé.
* `dessertR` et `nemetonshiny` reçoivent un brief sortant : ce dépôt ne modifie
  pas ses frères (règle 6 du `CLAUDE.md`).

## Ce que cette décision ne tranche pas

L'extraction **Geofabrik `.pbf`** pour le traitement par massif entier (§6 du
brief). Overpass reste réservé aux **petites AOI interactives**. Si la cible
devient le massif complet en batch, ni Overpass ni la bissection ne sont le bon
outil : un extrait `.pbf` se télécharge une fois, ne consomme aucun quota et
porte une date. À instruire dans une spec dédiée, pas ici.
