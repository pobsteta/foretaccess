# ADR-004 — Découplage : cœur pur, sans UI, sans variable globale

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-08
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-004), §1, §8

## Contexte

Le défaut majeur de Sylvaccess est le **couplage logique métier ↔ UI PyQt** : la logique est
lue depuis l'interface, avec ~80 variables globales. Cela empêche CLI/batch, réutilisation et
tests automatisés.

## Décision

- **Cœur métier pur** : fonctions prenant `config + données` et retournant des résultats, sans
  effet de bord caché, **sans dépendance UI**, **sans variable globale mutable**.
- **Couches séparées** :
  - *cœur* (calcul : prétraitement, moteurs, sélection, mécanique câble) ;
  - *I/O* (lecture IGN, `StorageBackend` — ADR-002) ;
  - *orchestration* (pipeline, tuilage, CLI `Rscript`).
- L'I/O et l'orchestration **dépendent du cœur**, jamais l'inverse. Une éventuelle UI (Shiny,
  QGIS — hors v1) ne serait qu'un consommateur du cœur.

## Conséquences

- Le cœur est testable en isolation (fonctions déterministes) → non-régression facilitée.
- La CLI et tout futur front sont de simples adaptateurs.
- Discipline requise : pas d'accès disque/base dans les fonctions de calcul.

## Alternatives écartées

- **Réutiliser l'architecture Sylvaccess** (métier dans l'UI) : écarté (cause racine du problème).
