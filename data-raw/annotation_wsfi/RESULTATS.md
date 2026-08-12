# Résultats de la campagne d'annotation CA-26.5 — bloc `wsfi`

> Annotation réalisée par Pascal Obstetar, dépouillée le 2026-08-12.
> Données : `annotation.gpkg` (12 tuiles annotées, 6 linéaires numérisés).
> **Ce résultat contredit la conclusion publiée la veille** — voir §4.

## 1. Le verdict

| grandeur | valeur |
|---|---|
| **Rappel** | **0 %** — 0 desserte réelle retrouvée sur 4 |
| **Précision** | **0 %** — 0 candidat sur 2 est une desserte |
| Taux de sondage | 13,0 % (8,91 ha analysables scrutés sur 68,7) |
| Gisement extrapolé | **31 dessertes non cartographiées** (IC95 : 8–79), ~1 529 m |

**Le détecteur est aveugle sur ce massif.** Ce n'est pas « rien à trouver ».

> **Suite du 2026-08-12 (§6)** : on sait maintenant **pourquoi**, et c'est
> réparable. Trois verrous en série — un veto `vesselness` compté deux fois,
> `long_min = 30` qui élimine le signal fragmenté, et des bornes figées faibles
> ici. Une fois levés : **rappel 75 %**, précision 36 %. Le §1 décrit l'état
> initial, pas une fatalité.

## 2. Ce que l'annotation a trouvé

Sur les 10 tuiles tirées au hasard, **4 pistes réelles absentes de la BD TOPO**,
toutes annotées `certitude = "sure"` :

| tuile | strate | type | longueur | hors corridor | candidat le plus proche |
|---:|---|---|---:|---:|---:|
| 2 | douce | piste | 41 m | 100 % | 734 m |
| 2 | douce | piste | 61 m | 100 % | 681 m |
| 7 | raide | piste | 46 m | 100 % | 170 m |
| 9 | raide | piste | 50 m | 100 % | 271 m |

Plus deux linéaires **qui ne sont pas de la desserte**, et qu'il faut écarter du
calcul : une `limite` parcellaire (tuile 8, 20 m) et une `terrasse` (tuile 102,
74 m).

**Le point qui tranche** : les quatre pistes sont **à 100 % hors du corridor de
15 m**. Le détecteur avait donc pleinement le droit de les voir — leur absence
n'est pas un artefact d'exclusion, c'est un échec de détection. Le candidat le
plus proche d'une piste réelle est à **170 m**.

## 3. Ce que le détecteur a trouvé

Ses 2 seuls candidats — obtenus en descendant le seuil à 0,40, rien au-dessus —
sont tous deux dans la tuile 101, où l'annotateur **n'a vu aucun linéaire réel**
(`n_trouve = 0`). Verdict porté sur les deux : `autre`.

Un détail éclairant : le linéaire annoté le plus proche de ces candidats est la
**terrasse** de la tuile 102, à 34 m — et cette terrasse est à 58 % dans le
corridor. C'est exactement le mode de faux positif que la spec 026 annonce dans
son en-tête : « le micro-relief garde aussi les drains, fossés, limites
parcellaires et **terrasses** ».

## 4. Correction — ce que j'avais conclu la veille était faux

Le 2026-08-11, après avoir mesuré que les trois formes de `specs` rendaient
toutes zéro, j'ai écrit dans `specs/026` §Mesure et dans le brief retour :

> « **Ce ne sont donc pas les bornes.** […] entre « bornes inadaptées » et « rien
> à trouver », c'est **rien à trouver** — ou rien que ce modèle sache voir. »

La première moitié tient : ce ne sont pas les bornes. **La seconde est
réfutée.** Il y a bel et bien quelque chose à trouver — au moins 4 pistes sûres
sur 8,91 ha, extrapolées à une trentaine sur l'emprise. C'est le détecteur qui ne
les voit pas.

J'avais d'ailleurs écrit que la mesure « ne prouve pas qu'il n'y a rien » et
qu'une détection à zéro « ne distingue pas absence de gisement de détecteur
aveugle ». La prudence était bonne ; la conclusion mise en avant ne l'était pas.
C'est cette campagne, et elle seule, qui pouvait trancher — ce qui est exactement
la raison d'être du CA-26.5.

## 5. Ce que cela ne dit pas

* **Un seul massif.** Lozère, forêt privée, 31 ha de parcelles. Un rappel nul ici
  ne condamne pas la méthode ailleurs — la spec 026 dit déjà des bornes figées
  qu'« elles ancrent, elles ne généralisent pas ».
* **Un seul annotateur, pas de double lecture.** Les 4 pistes sont données
  `sure`, mais rien ne mesure l'accord inter-annotateur.
* **4 événements**, d'où l'intervalle 8–79 sur l'extrapolation. L'ordre de
  grandeur est solide, le chiffre ne l'est pas.
* **Rien sur la praticabilité** de ces pistes : ni largeur, ni état, ni portance.
  C'est le travail de `qualifier_desserte()`, en aval.

## 6. Suite — pourquoi il était aveugle, et ce que ça donne une fois réparé

*(Instruit le 2026-08-12, après le dépouillement. Cette section change le verdict
du §1 : le rappel nul n'était pas une limite du signal, mais trois verrous en
série dans la chaîne de traitement.)*

### 6.1 Le signal était là depuis le début

Recalibrer `dsr_calibrer_specs()` sur les 4 pistes annotées donne, pour le canal
dominant `rugosite`, une **AUC de 0,780** — contre 0,793 pour la desserte
BD TOPO. Vos pistes ont donc **la même signature** que des routes carrossables
sur le canal qui porte l'essentiel du poids. L'hypothèse « la calibration
apprend sur le mauvais objet » était raisonnable et s'avère largement fausse.

Un canal fait exception, et c'est lui qui a tout expliqué : `vesselness` tombe
de 0,596 à **0,510** — le hasard.

### 6.2 Le verrou principal : un veto, pas une pondération

`dsr_detecter()` fusionne ses termes en **moyenne géométrique pondérée**
(`exp(Σ w·log(μ) / Σ w)`), donc dominée par le **plus petit**. Un poids n'y dose
pas une contribution : **il arme un veto**.

`vesselness` y pèse 1 — le double du canal de surface — et entre par une rampe
démarrant à 0,3, alors que c'est un détecteur de crêtes **creux par nature** :
sur ce bloc, **1,62 %** des cellules atteignent 0,3 (médiane 0,0023).

Mesuré sur les cellules des 4 pistes :

| termes de la fusion | médiane de `p_desserte` | cellules ≥ 0,40 |
|---|---:|---:|
| `sigma_geo` seul | 0,210 | 11,8 % |
| + `sigma_surf` (poids 0,5) | 0,181 | 11,8 % |
| **+ veto `vesselness`** (poids 1) | **0,001** | **0,0 %** |

Et il était **compté deux fois** : `specs_desserte_calibrees()$geomorpho` porte
déjà un canal `vesselness` de poids 2, calibré entre 0,00064 et **0,0708** — une
borne haute **4,2 fois plus basse** que le début de la rampe du veto. Les deux
lectures se contredisent, et le veto l'emporte.

### 6.3 Le second verrou : `long_min`

Comme seules ~12 % des cellules d'une piste franchissent le seuil, le squelette
se fragmente en morceaux de 5 à 7 m — alors que vos pistes font 41 à 61 m. Un
filtre à `long_min = 30` les élimine **tous**, y compris les vrais. Il ne
filtrait pas le bruit, il filtrait le **signal fragmenté**.

### 6.4 Ce que donnent les trois leviers

| configuration | rappel | précision |
|---|:---:|:---:|
| origine — veto + `long_min 30` + bornes figées | **0 / 4** | 0 / 2 |
| veto retiré + `long_min 10` + bornes figées | 2 / 4 | — |
| + bornes annotées, **validation croisée** | **3 / 4 = 75 %** | **36 %** |

Aucun levier ne suffit seul : à `long_min = 20`, même sans veto, on retombe à
0/4 ; et recalibrer sans lever le veto donne 0/4 également.

**Le leave-one-out donne le même résultat que le test circulaire** (3/4 dans les
deux cas) : la calibration **généralise**, elle ne mémorise pas les 4 pistes.
C'était le risque avec 4 objets et 5 canaux, et il est écarté.

### 6.5 Le revers : la précision

**36 %.** Dans les 10 tuiles où la vérité est établie, 11 tronçons détectés dont
4 réels — donc **7 faux positifs**. On est passé de « rien, jamais » à « les
trois quarts des pistes, noyées dans deux tiers de bruit ».

C'est un compromis, pas une victoire. Pour un usage en conception de desserte,
une validation humaine reste indispensable — ce que la spec 026 dit déjà de la
couche détectée (« elle doit passer `qualifier_desserte()` avant tout usage »).
Cette campagne le **chiffre** pour la première fois.

### 6.6 Livré dans le cœur

* `detecter_desserte()` ne repasse plus `vesselness` en veto quand il est déjà un
  canal de `specs$geomorpho`, et le dit à l'appelant ;
* nouveaux arguments **`poids`** et **`seuil_vessel`**, sans lesquels le veto
  était impossible à neutraliser quand la calibration écarte `vesselness` de
  `geomorpho` ;
* la documentation énonce que la fusion est géométrique, **donc qu'un poids y
  arme un veto**.

`long_min` et le choix des bornes restent des **réglages de l'appelant** : les
chiffres ci-dessus donnent de quoi les arbitrer, ils ne les imposent pas.

## 7. Ce qu'il faudrait encore instruire


Le rappel nul se lit à seuil 0,40 déjà très bas. Les pistes trouvées font 41 à
61 m, donc au-dessus de `long_min = 30`. Trois pistes à creuser, par coût
croissant :

1. **Le canal de surface.** La spec dit qu'il « porte le signal » (AUC 0,870 sur
   `taux_penetration`). Il était actif (`canal_surface = TRUE`). Vérifier ce
   qu'il vaut *sur ces 4 pistes précisément* : l'annotation fournit désormais la
   vérité terrain qui manquait pour le mesurer.
2. **La calibration.** `dsr_calibrer_specs()` retient 5 canaux, mais elle apprend
   sur la desserte **BD TOPO** — des routes carrossables. Rien ne dit que la
   signature d'une piste effacée de 45 m soit la même. Recalibrer *sur les
   linéaires annotés* est maintenant possible.
3. **`buffer_ref = 15 m`.** Deux des quatre pistes sont à moins de 100 m d'une
   référence. Le corridor ne les couvre pas, mais l'exclusion pourrait tronquer
   leur voisinage et affaiblir la réponse. À tester à 5 et 10 m.
