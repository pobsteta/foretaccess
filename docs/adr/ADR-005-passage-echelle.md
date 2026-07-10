# ADR-005 — Passage à l'échelle : tuilage + parallélisme

- **Statut** : **accepté** (2026-07-10, `specs/007` §10)
- **Date** : 2026-07-08, révisé le 2026-07-10
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-005), §8 ; Lots 4 et 7

## Contexte

L'échelle visée va du **massif au national**. Les moteurs terrestres sont déjà rapides en v3.6
(Morvan 3290 km² → ~18 min skidder au 5 m), mais le **câble** est un point chaud
(~800 ha / 20 km ≈ 20 min). Le brief proposait `joblib`/`dask` (Python).

## Décision

- **Tuilage du territoire** : découper en tuiles avec halo, puis recomposer. Le halo n'est
  **pas** un chevauchement à fusionner : les fenêtres écrites sont disjointes, le halo ne sert
  qu'au calcul. Sa largeur suffisante n'est **pas devinable** pour un plus court chemin sans
  plafond ; elle est **certifiée** par cellule (`specs/007` §4.3) et le halo grandit tant que
  le certificat échoue.
- **Parallélisme** :
  - dans le **noyau câble Rust** : `rayon` (balayage 360°/pixel data-parallèle) ;
  - au niveau **R/orchestration** : parallélisme par tuile via **`mirai`** (décision
    `specs/007` §10.2), en remplacement de `joblib`/`dask`. `future`/`furrr` est écarté : ses
    workers `workRSOCK` survivent aux crashs, et il coûte deux dépendances au lieu d'une.
- **Élagage spatial** : ne traiter que la forêt d'intérêt / le voisinage des dessertes.
- **Sorties COG** pour des rasters tuilés/pyramidaux exploitables.

## Conséquences

- Résultat tuilé **identique** au traitement mono-bloc (critère de sortie Lot 7), **prouvé**
  cellule par cellule et non supposé. Les cellules qu'aucun halo admissible ne certifie
  sortent en `indetermine` — jamais rangées silencieusement dans `non_accessible`.
- Le certificat coûte une propagation de plus par tuile, soit ~1,6× le mono-bloc avant
  parallélisme. Coût assumé, mesuré (CA-7.10).
- Choix de la lib de parallélisme R figé : **`mirai`**.
- Reproductibilité : aucun aléatoire n'intervient, donc aucune graine. Le résultat ne dépend
  pas du nombre de workers, qui est paramétrable (`config$general$workers`).
- **Le portage Rust vient après le tuilage, pas avant** : à 3,05 s/km² (mesure du 2026-07-10),
  le tuilage suffit jusqu'au département. Rust se justifie à partir de la région, et sa cible
  est le **Dijkstra**, non le balayage radial.

## Alternatives écartées

- **`joblib`/`dask`** (Python, brief) : sans objet (stack R).
- **Pas de tuilage** (tout en mémoire) : écarté. Le temps n'est pas le premier obstacle, la
  mémoire l'est : à 5 m, un département fait 80 M de cellules, soit 640 Mo par vecteur `double`,
  et le moteur en matérialise une dizaine.
- **Halo fixe, sans certificat** : écarté. Il produit des artefacts de bordure
  *plausibles* — distances trop grandes, cellules faussement inaccessibles — que rien ne
  signale. Sur l'AOI réelle, le traînage sur piste atteint 4 030 m : un halo « raisonnable »
  de 500 m aurait faussé la majorité des cellules.
