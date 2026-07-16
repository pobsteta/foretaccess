# Comparaison des méthodes câble : ForêtAccess / Sylvaccess vs SEILAPLAN

> Rédigé le 2026-07-16. Sources : Bont et al. (2022), *SEILAPLAN, a QGIS Plugin for
> Cable Road Layout Design*, Croat. j. for. eng. 43(2)241-255
> ([`Bont_et_al_2022_Seilaplan_CROJFE_bont_241-255.pdf`](Bont_et_al_2022_Seilaplan_CROJFE_bont_241-255.pdf)) ;
> le plugin QGIS SEILAPLAN (<https://github.com/piMoll/SEILAPLAN>, GPL) ; le code
> Sylvaccess v3.6 (`sylvaccess_cython3.pyx`, module câble) ; le noyau Rust
> `cablehelp` de ForêtAccess.

## En une phrase

ForêtAccess (via Sylvaccess/CableHelp) et SEILAPLAN sont **deux outils de la même
famille « close-to-reality »** (mécanique caténaire non-linéaire résolue
numériquement) qui **résolvent des problèmes différents** : ForêtAccess *cartographie
l'accessibilité* d'un massif entier, SEILAPLAN *conçoit et optimise une ligne* précise.
Aucun n'est « non conforme » à l'autre ; ils sont **complémentaires**.

## 1. Généalogie commune

Le papier SEILAPLAN cite explicitement **CableHelp** (Dupire et al. 2014 ; adapté
Dupire et al. 2016) — le noyau câble de Sylvaccess, que ForêtAccess réimplémente en
Rust — et le range **au même rang** que SEILAPLAN parmi les outils *close-to-reality*
pertinents pour le SIG. Le vrai critère de conformité à l'état de l'art n'est donc pas
« SEILAPLAN vs nous » mais **caténaire non-linéaire vs linéarisation de Pestal** :

| Approche mécanique | Outils | Fidélité |
|---|---|---|
| **Caténaire non-linéaire, numérique** | **SEILAPLAN**, **CableHelp/Sylvaccess/ForêtAccess** | *close-to-reality* ✅ |
| Équations **linéarisées de Pestal (1961)** | LoggerPC, Skyline XL, NEWFOR Cableway, SimulCable | surestiment la flèche → **sur-dimensionnent** (supports plus hauts/nombreux) |

**ForêtAccess passe le test de l'état de l'art, comme SEILAPLAN.** Les deux rejettent
la linéarisation de Pestal et résolvent la caténaire élastique.

## 2. Mécanique du câble

| | SEILAPLAN | Sylvaccess / ForêtAccess |
|---|---|---|
| Formulation | **Zweifel (1959, 1960)** | **Irvine (1981)**, adapté Dupire (2016) — Newton-Raphson sur caténaire élastique (`f_x`, `f_z`, Jacobien analytique ; noyau Rust `cablehelp::newton`) |
| Friction au sabot | **Oui** (suit Dupire 2016) | **Non** — les fonctions `frottement*` existent dans le `.pyx` mais sont **du code mort** (jamais appelées ; `c_friction` n'est qu'imprimé au rapport). Sylvaccess v3.6 l'ignore, et ForêtAccess l'omet **fidèlement**. |
| Validation terrain | **Bont et al. (2022)** : mesures vs prédictions | Dupire et al. (2016) : mesures sur terrain raide |
| Charge dynamique | Non modélisée (facteur de sécurité l'« absorbe ») | idem |
| Philosophie | Contrainte admissible (*permissible stress*) | idem |

**Effet de la friction** (d'après le papier) : la négliger rend le résultat
**légèrement conservateur** (flèche et effort un peu plus grands → côté sécurité, plus
de/plus hauts supports que le strict nécessaire). Donc ForêtAccess/Sylvaccess est
**marginalement plus prudent** que SEILAPLAN — jamais « faux ». Les deux sont validés
contre des mesures.

## 3. Optimisation des supports intermédiaires

| | SEILAPLAN | Sylvaccess / ForêtAccess |
|---|---|---|
| Algorithme | **Bont & Heinimann (2012)** : graphe (à la Leitner) + mécanique de Zweifel | Heuristique de faisceau (`OptPyl` / `get_Tabis`, lignée Sessions 1992 → Chung & Sessions 2003) |
| Position des supports | Optimisée | Optimisée |
| **Hauteur des supports** | **Optimisée** (minimise nombre *et* hauteur), pas `δh ≈ 1 m`, pas position `δl ≈ 10 m` | **Non** par défaut v3.6 (variantes `_NoH`). C'est la branche `c_option_h = 1` (`OptPyl_Up`/`Up2`) — chez nous **expérimentale, buguée et lente** (voir ci-dessous). |
| Contraintes vérifiées | garde au sol min, effort de traction max, gradient min (gravité) | garde au sol, tension ≤ `Tmax`, `check_line` (fin en forêt, dévers) |

### Le point qui compte pour ForêtAccess

**Ce que SEILAPLAN fait nativement et proprement — optimiser la hauteur des
supports — est exactement ce qui manque (défaut) ou bugue (`c_option_h=1`) chez nous.**

- Le défaut v3.6 (`c_option_h=0`, hauteur fixe) est reproduit fidèlement, à
  ~98,4 % d'accord câble sur ColduPre.
- Le portage de la branche `c_option_h=1` (transcription de `OptPyl_Up`/`Up2` de
  Sylvaccess) a été **tenté puis shelvé le 2026-07-16** : il *réduit* la couverture
  (net −999 cellules) là où l'oracle l'*augmente* (+470), et il est ~20× plus lent.
  De plus, le code d'origine de Sylvaccess **plante lui-même** sur ce chemin (bug de
  tampon `Tab`, jamais exercé sur un vrai jeu). Voir `PLAN.md` (journal 16/07),
  `specs/004` (§ Statut c_option_h).

L'algorithme de SEILAPLAN (**Bont & Heinimann 2012**, publié et validé) est
**vraisemblablement plus sain** que `OptPyl_Up2`. D'où la décision : **transcrire
SEILAPLAN plutôt que déboguer `OptPyl_Up2`** — objet de `specs/013`.

> **Fait (2026-07-16, spec 013).** SEILAPLAN est **implémenté** (graphe + Dijkstra en Rust,
> réutilisant notre caténaire Newton/Irvine à tension imposée) et activable par
> `cable$methode_supports = "seilaplan"` (défaut `"sylvaccess"` = `_NoH`). Confronté **cellule à
> cellule** à l'oracle Sylvaccess `c_option_h=true` sur ColduPre : **accord 94,7 %** (vs 93,2 % pour
> le `_NoH`), couverture en hausse et **fidèle à l'oracle** (+454 en fenêtre ≈ le +470 de l'oracle),
> **perf ~2,8×** le `_NoH`. Le code shelvé `OptPyl_Up2` et son flag ont été retirés.

## 4. Ils résolvent des problèmes différents

| | SEILAPLAN | ForêtAccess / Sylvaccess |
|---|---|---|
| Objet | **Une** ligne précise (départ/arrivée donnés) | **Un massif** entier |
| Sortie | Plan de construction : hauteurs/positions de supports, DBH des arbres-supports, efforts aux sabots, load-path | Carte d'accessibilité (raster) : où le câble est faisable |
| Mode | Interactif (QGIS), ajustement manuel | Automatique, balayage 360°/pixel, milliers de lignes |
| Échelle | Locale (une desserte) | Territoriale (massif → département) |

**Aucun ne remplace l'autre.** SEILAPLAN ne sait pas balayer un massif ; ForêtAccess
ne produit pas un plan de construction d'une ligne.

## 5. Laquelle est la « meilleure » ?

- **Pour concevoir UNE ligne** : **SEILAPLAN** est mécaniquement le plus abouti
  (Zweifel + friction, validé mesures 2022, optimisation de hauteur native) et fournit
  un rapport de construction. Le bon outil pour le staking d'une desserte décidée.
- **Pour CARTOGRAPHIER l'accessibilité** d'un territoire : **ForêtAccess/Sylvaccess**
  est le bon outil — c'est sa raison d'être — et sa mécanique est de la même classe
  *close-to-reality*.

**Flux idéal : ForêtAccess cartographie *où* le câble est faisable → SEILAPLAN conçoit
*comment* construire les lignes retenues.**

## 6. Conséquences pour ForêtAccess

1. **Notre méthode est conforme** à l'état de l'art incarné par SEILAPLAN (même
   caténaire non-linéaire, même lignée Dupire/IRSTEA).
2. **Écarts assumés** vs SEILAPLAN : (a) friction au sabot (eux oui / nous non → on est
   plus prudents, négligeable) ; (b) optimisation de la hauteur des supports (eux oui,
   validé / nous : défaut non, expérimental bugué).
3. **Levier prioritaire de fidélité** : l'optimisation de la hauteur. Plutôt que
   déboguer `OptPyl_Up2`, transcrire **Bont & Heinimann (2012)** de SEILAPLAN
   (open-source GPL, code lisible, algorithme publié et validé). → `specs/013`.
4. **SEILAPLAN comme oracle** : étant open-source, publié et validé contre des mesures,
   il peut servir de **banc de référence** pour le noyau câble — mieux documenté que le
   `.pyx` de Sylvaccess.

## Références

- Bont, L.G., Moll, P.E., Ramstein, L., Frutig, F., Heinimann, H.R., Schweier, J.
  (2022). *SEILAPLAN, a QGIS Plugin for Cable Road Layout Design.* Croat. j. for. eng.
  43(2), 241-255. <https://doi.org/10.5552/crojfe.2022.1824>
- Bont, L., Heinimann, H.R. (2012). *Optimum geometric layout of a single cable road.*
  Eur. J. For. Res. 131(5), 1439-1448. <https://doi.org/10.1007/s10342-012-0612-y>
- Bont, L.G., Ramstein, L., Frutig, F., Schweier, J. (2022). *Tensile forces and
  deflections on skylines of cable yarders: comparison of measurements with
  close-to-catenary predictions.* Int. J. For. Eng. (validation Zweifel).
- Dupire, S., Bourrier, F., Berger, F. (2014). *CableHelp.* / (2016) *Predicting load
  path and tensile forces during cable yarding operations on steep terrain.* Eur. J.
  For. Res. 21(1). <https://doi.org/10.1007/s10310-015-0503-4>
- Irvine, M.H. (1981). *Cable structures.* MIT Press.
- Zweifel, O. (1959, 1960). Näherungslösungen / Seilbahnberechnung bei beidseitig
  verankerten Tragseilen.
- Pestal, E. (1961). *Seilbahnen und Seilkräne für Holz- und Materialtransport.*
- SEILAPLAN (plugin) : <https://github.com/piMoll/SEILAPLAN> ·
  <https://seilaplan.wsl.ch>
