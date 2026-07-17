# ADR-006 — Validation : non-régression contre Sylvaccess v3.6 (+ récupération du `.pyx`)

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-08
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-006), §7, §9.4 ; décision utilisateur 2026-07-08

## Contexte

La valeur de ForêtAccess repose sur sa **fidélité** à Sylvaccess v3.6. L'article 2015 ne donne
que des **erreurs de validation** publiées, pas toutes les équations. Le code source
(module Cython `scripts/sylvaccess_cython3.pyx`, GPL v3) contient les équations
mécaniques CableHelp, la fonction de coût least-cost, les « unités de vidange optimales » et le
pas de recherche des supports/raccourcissement.

> **Référence exacte de la source** (traçabilité) : dépôt
> <https://forge.inrae.fr/sylvain.dupire/sylvaccess>, branche `main`, **commit
> `372abaf` (2025-06-12)**. Le dépôt ne porte **aucun tag git** : la mention « v3.6 » est
> interne au code, seul ce commit identifie sans ambiguïté la version portée. Les moteurs
> viennent des scripts `Sylvaccess_1_skidder.py`, `Sylvaccess_2_cable.py`,
> `Sylvaccess_3_forwarder.py`, `Sylvaccess_5_dfci.py` et `Sylvaccess_0_functions.py` ;
> l'oracle de non-régression est le jeu officiel `test/ColduPre/` du même dépôt.

## Décision

- **Harnais de non-régression** dès le **Lot 0** : sur un **jeu jouet** (MNT synthétique +
  desserte + forêt) et **N profils câble**, figer les sorties de **Sylvaccess v3.6** comme
  **oracles** et comparer nos résultats avec **tolérances**.
- **Cibles publiées** : trajectoire de charge **≤ 0,1 %**, tension **≤ 1,5 %**. Tolérances des
  sorties terrestres (distances, zones, tableaux) définies par moteur dans sa spec.
- **Récupération du `.pyx`** (§9.4, GPL v3 compatible) pour **deux usages** :
  1. **oracle** — générer les sorties de référence ;
  2. **portage** — traduire fidèlement les équations (CableHelp `asinh`/frottement/`mainline`,
     `OptPyl_Up/Down`, `calcul_distance_de_cout`).
- Un moteur reproduisant v3.6 n'est **« fait »** que **non-régression verte**.

## Conséquences

- Dépendance opérationnelle : disposer de Sylvaccess v3.6 exécutable pour figer les oracles
  (risque mitigé en figeant tôt sur le jeu jouet).
- Le code porté depuis le `.pyx` **hérite de GPL v3** (cohérent, cf. ADR licence README).
- Traçabilité : chaque oracle est versionné et daté ; toute dérive est un échec CI.

## Alternatives écartées

- **Réimplémentation depuis l'article seul** (sans `.pyx`) : écarté (équations incomplètes,
  risque de contresens non détectable).
- **Validation manuelle ponctuelle** : écarté (non reproductible, non CI).
