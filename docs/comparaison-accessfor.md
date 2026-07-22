# Comparaison ForêtAccess vs ACCESSFOR (IGN)

> Rédigé le 2026-07-22. Réponse au brief nemeton
> `nemeton/specs/brief-foretaccess-accessfor.md`. Mécanique de comparaison :
> `comparer_accessfor()` (`R/accessfor.R`, testée hors ligne). Chiffres :
> `data-raw/accessfor_compare.R` sur l'AOI **Chastel-Nouvel** (dép. 48, ~610 ha de
> forêt comparés, grille 5 m, édition ACCESSFOR 2025-01-01).

## En une phrase

Sur l'accord **accessible / non-accessible** — le seul chiffre robuste —
ForêtAccess et ACCESSFOR **concordent à 81 % (skidder) et 86 % (porteur)** ; le
désaccord fin sur les bandes de distance est attendu (paramétrage d'engin et
desserte de référence différents), et le **choix du masque forêt ne change rien**
(< 1 pt entre les deux variantes ACCESSFOR).

## Chiffres (AOI Chastel-Nouvel)

| engin | masque ACCESSFOR | accord global (9 classes) | **accord agrégé** (access./non) | surface comparée |
|---|---|---|---|---|
| skidder | défaut | 30,6 % | **81,4 %** | 608,9 ha |
| skidder | MASQUE-FORETV3 | 30,9 % | **81,2 %** | 610,2 ha |
| porteur | défaut | 65,8 % | **86,0 %** | 608,9 ha |
| porteur | MASQUE-FORETV3 | 66,5 % | **86,2 %** | 610,2 ha |

Surface exclue de la comparaison (intersection des masques, §4a du brief) :
« forêt pour nous, hors ACCESSFOR » ≈ 32 ha ; « ACCESSFOR hors notre forêt » 3,4 ha
(défaut) à 15,8 ha (V3). L'écart de masque est donc **borné et faible** : il ne
domine pas le résultat, contrairement à la crainte du §4a.

## Lecture

**L'accord agrégé est élevé et c'est l'essentiel.** Là où le brief attendait un
possible artefact de masque écrasant, on trouve au contraire un accord
accessible/non-accessible solide (81-86 %) et **stable entre les deux masques** —
la parenté Sylvaccess se confirme au niveau qui compte.

**Le désaccord fin (accord global) est plus marqué pour le skidder (31 %) que
pour le porteur (66 %).** Ce n'est pas un flip accessible↔inaccessible (sinon
l'agrégé chuterait) mais un **décalage de bande** : à lire la matrice skidder,
notre modèle est **plus optimiste sur la portée** — nous classons ~86 ha en
« accessible » qu'ACCESSFOR déclare « inaccessible », contre ~28 ha en sens
inverse. Deux causes plausibles, non départageables ici :
- **desserte de référence différente** (nous : BD TOPO ; ACCESSFOR : sa propre
  couche) — un point de départ de débardage plus dense raccourcit les distances ;
- **paramétrage d'engin** (distances de treuillage/débardage du skidder).

**La classe `inexploitable` (pente) concorde peu en surface** (≈ 1 ha en commun),
mais c'est attendu : le seuil de pente d'ACCESSFOR n'est pas publié, le nôtre est
`pente_skidder_max_pct = 30`. Un écart ici est un **artefact de paramètre**, pas
un défaut — d'où l'importance d'avoir passé `pre` à `classes_debardage()` (sans
quoi la classe serait absente et le désaccord total).

## Ce que ça vaut comme validation

Un **constat de cohérence**, pas une non-régression : ACCESSFOR est lui-même un
modèle (édition figée, desserte et paramètres non maîtrisés), pas une vérité
terrain. Le signal utile est **l'absence de flip massif accessible↔inaccessible**
et la **stabilité au masque** ; le décalage de bandes du skidder est une **piste à
instruire** (desserte de référence surtout), pas une alerte. Pour un usage
« repli » (§6 du brief — accessibilité de référence IGN quand le calcul local est
hors budget), ces chiffres soutiennent le porteur mieux que le skidder.

## Reproduire

```r
# Mecanique testable hors ligne :
foretaccess::comparer_accessfor(cl, accessfor)   # cl = classes_debardage(sk, pre)
# Chiffres reels (reseau) :
#   Rscript data-raw/accessfor_compare.R
```
