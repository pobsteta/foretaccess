# ADR-001 — Langages : R (cœur) + Rust (noyau câble)

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-08
- **Décideurs** : Pascal Obstetar
- **Sources** : brief §5 (ADR-001), §9.3 ; décision utilisateur 2026-07-08

## Contexte

Sylvaccess est en Python 3 + Cython. Le brief initial envisageait une orchestration Python
(PyO3 + maturin). Le projet a été réorienté vers l'écosystème **R** (cohérence avec Nemeton :
package R, PostGIS, outillage SIG). Le noyau câble (CableHelp) est le **point chaud** de
performance (~60 M lignes, ~1 ms/ligne en v3.6) et doit rester en code natif.

## Décision

- **R** pour le cœur métier, l'orchestration, les moteurs terrestres (skidder, porteur, DFCI)
  et le service **least-cost** : `terra`, `sf` (I/O SIG), `leastcostpath`/`gdistance` (coût-
  distance), et les libs de calcul du tidyverse/base selon besoin.
- **Rust** pour le **noyau câble** (mécanique CableHelp + balayage 360°/pixel), exposé à R via
  **`extendr`/`rextendr`**, parallélisme **`rayon`**.
- **Least-cost en R d'abord** (§9.3) : `leastcostpath`/`gdistance`. Un **portage Rust** n'est
  entrepris que si la tolérance de non-régression ou la performance l'exigent (déclencheur
  documenté au Lot 2).

## Conséquences

- Frontière R↔Rust minimale et typée : le crate reçoit des profils/tableaux, retourne des
  résultats numériques ; aucune logique SIG dans le crate.
- Outillage : `rextendr::document()` (build + bindings), `Cargo.lock` versionné.
- La transposition remplace l'outillage Python du brief (voir ADR-007).
- Risque : reproduire la fonction de coût v3.6 (`calcul_distance_de_cout`) en R sous tolérance ;
  mitigation = portage Rust en réserve.

## Alternatives écartées

- **Tout Python (brief initial)** : abandonné au profit de la cohérence écosystème R/Nemeton.
- **Tout R (y compris câble)** : trop lent pour le point chaud câble.
- **Least-cost Rust dès le départ** : reporté (charge Rust précoce non justifiée avant mesure).
