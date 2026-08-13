# Campagne d'annotation CA-26.5 — bloc `ltcp`

> Produit le 2026-08-13. Tirage **reproductible** (`set.seed(26)`).
> Fichier à annoter : `annotation.gpkg` (Lambert-93, EPSG:2154).
> Générateur : `data-raw/annotation_wsfi/preparer_annotation.R`, paramétré par
> `FA_BLOC` — le protocole ne vaut que s'il se transporte.

## Pourquoi un second bloc

La campagne `wsfi` a établi que le détecteur était **aveugle** (rappel 0 %), a
identifié pourquoi (trois verrous en série), et a mesuré ce que donne la
correction : **rappel 75 %, précision 36 %**. Sur **un seul massif**.

`ltcp` est le second bloc, et il est **disjoint du jeu de calibration** — ce que
le CA-26.5 exige et que `wsfi` ne satisfaisait pas (la dalle de calibration en
est le quart sud-ouest).

## Ce qui diffère de `wsfi`, et qu'il faut savoir avant d'annoter

### 1. Ce n'est pas le même terrain

| | `ltcp` | `wsfi` |
|---|---|---|
| altitude | 126–154 m | 879–1 217 m |
| dénivelé au km | **28 m** | 337 m |
| pente médiane | **2,7°** | 21,9° |

`ltcp` est une **plaine**, `wsfi` une montagne. Un rappel bon ici ne validerait
pas la méthode en montagne, et réciproquement.

### 2. Le tirage est simple, pas stratifié

Sur `wsfi`, les tuiles étaient stratifiées par pente (douce / moyenne / raide).
Ici l'étendue p10–p90 ne fait que **1,9°** : trois strates y décriraient le même
terrain et donneraient une fausse assurance. Le script mesure l'étendue et
bascule tout seul en tirage simple au-dessous de 5°, en le disant.

### 3. Il y a beaucoup plus de candidats

| | `wsfi` | `ltcp` |
|---|---:|---:|
| candidats sur l'emprise | 2 (72 m) | **87 (2 214 m)** |
| dans les tuiles scrutées | 0 | **13** |

87 contre 2, sur des emprises comparables (100 ha contre 90). **Cet écart n'est
pas interprétable sans vous** : soit le détecteur trouve enfin ce qu'il manquait,
soit il part en faux positifs sur des micro-reliefs de plaine (fossés de
drainage, limites parcellaires), soit les deux.

Point positif pour la mesure : les 13 candidats **dans** les tuiles rendent la
précision mesurable localement, ce que `wsfi` ne permettait pas (ses 2 candidats
tombaient hors échantillon). Votre annotation donnera donc précision **et**
rappel sur le même terrain.

## Ce qu'il y a à faire

Identique à `wsfi`. Deux volets, et le second porte le résultat.

### A. Qualifier les 87 candidats — couche `candidats`

| champ | valeurs |
|---|---|
| `verdict` | `piste` · `cloisonnement` · `fosse` · `limite` · `terrasse` · `rien_visible` · `autre` |
| `commentaire` | libre |

`rien_visible` est un verdict à part entière : un faux positif franc est une
information.

**87 objets, c'est beaucoup.** Si le temps manque, qualifiez **en priorité les
13 qui tombent dans une tuile** (`dans_tuile = TRUE`) : ce sont les seuls dont
la précision se rapproche de la vérité terrain que vous établirez au volet B.

### B. Chercher ce qui MANQUE — `tuiles_a_scruter` et `a_numeriser`

10 tuiles de 1 ha, tirées parmi 94 analysables à ≥ 60 % hors corridor.

1. **numériser** dans `a_numeriser` (couche **polyligne**) tout linéaire qui vous
   paraît être une desserte réelle absente de `reference_bdtopo` ;
2. renseigner `id_tuile`, `type` (même vocabulaire qu'en A) et `certitude`
   (`sure` · `probable` · `douteuse`) ;
3. dans `tuiles_a_scruter`, mettre `fait = "oui"` et `n_trouve` — **y compris 0**.

**Le zéro est le résultat le plus important.** Une tuile scrutée où vous ne voyez
rien est une donnée ; une tuile non scrutée n'en est pas une. Sans `fait`, on ne
distingue pas « rien trouvé » de « pas regardé » — la distinction même qui
bloquait la spec.

## Ce que la campagne produira

* **Précision** sur 13 candidats en zone de vérité établie — comparable aux 11 de
  `wsfi`, donc les deux blocs se confrontent ;
* **Rappel** — la question de fond, et cette fois sur un terrain différent ;
* **Une réponse à la généralisation** : les bornes figées, calibrées en
  **montagne**, saturent ici (`svf` 99 %, `openness_pos` 98 %). C'est pourquoi la
  détection a tourné en `specs = "auto"`. Si le rappel tient sur une plaine avec
  une calibration locale, la méthode se transporte ; sinon, elle est montagnarde.

## Ce que la campagne ne dira pas

La **praticabilité** : un linéaire détecté n'a ni largeur, ni état, ni portance.
C'est le travail de `qualifier_desserte()`, en aval. Et deux blocs ne font pas
une validation nationale.
