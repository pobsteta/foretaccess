# Campagne d'annotation CA-26.5 — bloc `wsfi` (ForetAccess)

> Produit le 2026-08-12. Tirage **reproductible** (`set.seed(26)`).
> Fichier à annoter : `annotation.gpkg` (Lambert-93, EPSG:2154).
> Script générateur : `data-raw/annotation_wsfi/` (cf. `PLAN.md`).

## Pourquoi cette campagne

Le CA-26.5 exige une **part annotée** : le recoupement automatique avec les objets
BD TOPO connus réduit le travail d'annotation, il ne le remplace pas. Elle n'a
jamais été produite, et sans elle la spec 026 reste bloquée.

Une mesure du 2026-08-12 a rendu la question urgente. Sur ce bloc, la détection
rend **0 tronçon** au seuil par défaut, et cela **quelles que soient les bornes** :

| forme de `specs` | tronçons |
|---|---:|
| bornes figées | 0 |
| `specs = NULL` (quantiles) | 0 |
| `specs = "auto"` (calibré sur place) | 0 |

En descendant le seuil à **0,40**, on obtient **2 tronçons, 72 m** sur 68,7 ha.

Deux lectures restent possibles, et **aucune mesure ne peut les départager** :

1. **il n'y a rien à trouver** — la desserte de ce massif est déjà cartographiée ;
2. **le détecteur est aveugle** à ce type de gisement.

C'est vous qui tranchez, en regardant le terrain.

## Ce qu'il y a à faire

### A. Qualifier les 2 candidats détectés — couche `candidats`

Pour chacun, remplir :

| champ | valeurs |
|---|---|
| `verdict` | `piste` · `cloisonnement` · `fosse` · `limite` · `terrasse` · `rien_visible` · `autre` |
| `commentaire` | libre |

`rien_visible` est un verdict à part entière : c'est un faux positif franc, et
c'est une information.

### B. Chercher ce qui MANQUE — couches `tuiles_a_scruter` et `a_numeriser`

**12 tuiles de 1 ha**, de deux natures qu'il ne faut surtout pas mélanger :

* **10 tuiles `origine = "aleatoire"`** (`id_tuile` 1 à 10), tirées au hasard dans
  80 tuiles candidates, stratifiées par pente médiane : 3 douces (15–20°),
  3 moyennes (22–25°), 4 raides (26–30°). **Ce sont les seules qui comptent pour
  le rappel et l'extrapolation** — leur tirage est aléatoire, donc sans biais ;
* **2 tuiles `origine = "porte_candidat"`** (`id_tuile` 101 et 102), ajoutées
  parce qu'elles contiennent les 2 candidats détectés. Le tirage aléatoire ne les
  avait pas retenues — ce qui n'a rien d'anormal : 10 tuiles sur 80, la
  probabilité que deux objets tombent tous deux à côté est de 73 %. Elles
  permettent de voir la sortie du détecteur **dans son contexte**.

  **Elles sont exclues de tout calcul de rappel.** Une tuile choisie *parce que*
  le détecteur y a réagi n'est pas représentative : l'y inclure gonflerait
  mécaniquement le rappel. Annotez-les comme les autres, elles seront traitées à
  part.

Seules les tuiles analysables à ≥ 60 % ont été retenues — inutile de chercher du
non-détecté dans le corridor de 15 m où le détecteur ne regarde pas (`part_libre`
donne la fraction hors corridor).

Dans chaque tuile, sur ortho (et sur ombrage LiDAR, qui montre le micro-relief) :

1. **numériser** dans `a_numeriser` tout linéaire qui vous paraît être une
   desserte réelle **absente de `reference_bdtopo`** — piste ancienne,
   cloisonnement, plateforme effacée ;
2. renseigner `id_tuile`, `type` (même vocabulaire qu'en A) et `certitude`
   (`sure` · `probable` · `douteuse`) ;
3. dans `tuiles_a_scruter`, mettre `fait = "oui"` et `n_trouve` = le nombre de
   linéaires numérisés — **y compris 0**.

Les 12 tuiles s'annotent de la même façon ; c'est au dépouillement que les deux
`origine` sont séparées.

**Le zéro est le résultat le plus important.** Une tuile scrutée où vous ne voyez
rien est une donnée ; une tuile non scrutée n'en est pas une. Sans `fait = "oui"`,
impossible de distinguer « rien trouvé » de « pas regardé », et c'est précisément
la distinction qui bloque la spec.

## Ce que la campagne produira

* **Précision** — part des candidats détectés qui sont de vraies dessertes.
  Avec 2 objets, ce sera indicatif, pas statistique. Assumé.
* **Rappel** — part des dessertes réelles non cartographiées que le détecteur
  retrouve. C'est le chiffre qui manque, et il se lit directement : si vous
  numérisez *n* linéaires réels et que le détecteur n'en a trouvé aucun, le
  rappel est nul et le détecteur est aveugle. Si vous n'en trouvez aucun sur
  10 ha stratifiés, l'hypothèse « rien à trouver » devient la bonne.

Extrapolation : 10 ha scrutés sur 68,7 analysables, soit **14,6 %** de l'emprise.
Un linéaire trouvé sur l'échantillon vaut environ 7 sur l'emprise, avec l'intervalle
de confiance qui va avec un si petit échantillon — d'où la stratification, qui
limite le risque de tomber par hasard sur un secteur atypique.

## Ce que la campagne ne dira pas

Elle porte sur **un massif** — Lozère, forêt privée, 31 ha de parcelles. Un rappel
nul ici ne condamne pas la méthode ailleurs, et un rappel bon ici ne la valide pas
ailleurs. La spec 026 le dit déjà des bornes figées : « elles ancrent, elles ne
généralisent pas ».

Elle ne dit rien non plus de la **praticabilité** de ce qui serait trouvé : un
linéaire détecté n'a ni largeur, ni état, ni portance. C'est le travail de
`qualifier_desserte()`, en aval.
