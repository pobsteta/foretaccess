# ADR-003 — Configuration : défauts = Sylvaccess v3.6

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-08
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-003), §6

## Contexte

Sylvaccess dissémine ses paramètres (~80 variables globales) lus depuis l'UI. ForêtAccess
doit rendre **tous les paramètres métier configurables**, avec des **valeurs par défaut
identiques à Sylvaccess v3.6** (RdV Experts 2026) — qui **diffèrent de l'article 2015**
(deltas signalés brief §6). La stack étant R, `pydantic` (proposé dans le brief) n'a pas
d'équivalent direct.

## Décision

- Un **objet de configuration R validé** (liste structurée / S3), chargé depuis **YAML**, avec
  **validation au chargement** (types, bornes, cohérence) via un helper dédié (p. ex.
  `checkmate`/`vctrs`), messages d'erreur ciblés.
- **Défauts = Sylvaccess v3.6** (brief §6) : skidder (50 m amont / 100 m aval ; bascules 75 % /
  20 % ; pente skidder 30 % ; abattage 100 % ; hors-desserte 50 m), porteur (travers 15 % ;
  long 30 %/25 % ; grue 8 m ; 300 m ; hors-desserte 200 m), câble (par type de matériel :
  hauteur mât, longueur/diamètre/masse linéaire/tension rupture du porteur, nb max supports,
  hauteur ∈ [4 m, 30 m], coeff. sécurité).
- Les défauts sont **documentés et testés** (un test vérifie chaque défaut v3.6).

## Conséquences

- Aucun paramètre en dur dans les moteurs ; reproductibilité et auditabilité.
- Les tableaux câble (matériels) sont encodés comme données de config versionnées.
- Changement de défaut = changement tracé (NEWS/CHANGELOG), potentiellement ADR.

## Alternatives écartées

- **Défauts de l'article 2015** : écarté (le brief impose v3.6).
- **Paramètres en arguments de fonctions seulement** : écarté (config centralisée + validée
  préférable pour l'auditabilité).
