# ADR-005 — Passage à l'échelle : tuilage + parallélisme

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-08
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-005), §8 ; Lots 4 et 7

## Contexte

L'échelle visée va du **massif au national**. Les moteurs terrestres sont déjà rapides en v3.6
(Morvan 3290 km² → ~18 min skidder au 5 m), mais le **câble** est un point chaud
(~800 ha / 20 km ≈ 20 min). Le brief proposait `joblib`/`dask` (Python).

## Décision

- **Tuilage du territoire** : découper en tuiles avec chevauchement (buffer) suffisant pour des
  **raccords corrects** (pas d'artefact de bordure), puis recomposer.
- **Parallélisme** :
  - dans le **noyau câble Rust** : `rayon` (balayage 360°/pixel data-parallèle) ;
  - au niveau **R/orchestration** : parallélisme par tuile via `future`/`furrr` (ou `mirai`),
    en remplacement de `joblib`/`dask`.
- **Élagage spatial** : ne traiter que la forêt d'intérêt / le voisinage des dessertes.
- **Sorties COG** pour des rasters tuilés/pyramidaux exploitables.

## Conséquences

- Résultat tuilé **identique** au traitement mono-bloc (critère de sortie Lot 7).
- Choix de la lib de parallélisme R (`future` vs `mirai`) figé dans `specs/007`.
- Reproductibilité : seeds si aléatoire ; nombre de workers paramétrable.

## Alternatives écartées

- **`joblib`/`dask`** (Python, brief) : sans objet (stack R).
- **Pas de tuilage** (tout en mémoire) : écarté (échelle nationale impossible).
