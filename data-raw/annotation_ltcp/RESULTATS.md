# Résultats de la campagne d'annotation CA-26.5 — bloc `ltcp`

> Annotation réalisée par Pascal Obstetar, dépouillée le 2026-08-13.
> Données : `annotation.gpkg` (10 tuiles annotées, 11 linéaires numérisés).
> Second bloc, **disjoint du jeu de calibration** — ce que le CA-26.5 exige et
> que `wsfi` ne satisfaisait pas.

## 1. Le verdict

| grandeur | `ltcp` | `wsfi` (config comparable) |
|---|---:|---:|
| **Rappel** | **22 %** (2/9) | 50 % (2/4) |
| **Précision** | **23 %** (3/13) | 36 % (4/11) |
| dessertes réelles trouvées | 9 (583 m) | 4 (198 m) |
| taux de sondage | 10,1 % (9,5 ha sur 94) | 13,0 % |
| gisement extrapolé | **~89 pistes, ~5 770 m** | ~31 pistes, ~1 529 m |

**Les bornes ne se transportent pas** — et c'est réparable. Avec les bornes
issues d'une calibration sur la référence BD TOPO, le rappel tombe à 22 % contre
50 % sur `wsfi`, alors que le gisement y est **deux fois plus dense**. Recalibré
sur les pistes annotées, il remonte à **78 %** (§5) : le signal existe, ce sont
les bornes qui ne voyagent pas.

Ce qui ne se répare pas, en revanche, c'est la **précision** : 23 à 28 % selon
la calibration, contre 36 % en montagne, et deux limites parcellaires détectées
sur deux dans tous les cas.

## 2. Les canaux discriminent mal, mais discriminent quand même

Le fait brut, tiré de la **calibration sur les 9 pistes annotées** :

| canal | AUC `ltcp` | AUC `wsfi` |
|---|---:|---:|
| svf | 0,607 | 0,509 |
| rugosite | 0,605 | **0,780** |
| openness_pos | 0,600 | 0,529 |
| pente | 0,595 | 0,598 |
| vesselness | 0,594 | 0,510 |
| slrm | 0,572 | 0,557 |

**Aucun canal ne dépasse 0,61**, et les six retenus sont serrés entre 0,57 et
0,61 — à peine mieux que le hasard, et surtout **indiscernables entre eux**. Sur
`wsfi`, `rugosite` seule atteignait 0,780 et portait le poids 3.

Une calibration qui donne le même poids à cinq canaux quasi équivalents ressemble
à un modèle qui ne sait pas discriminer, et j'en ai conclu trop vite qu'il n'y
aurait « pas grand-chose à exploiter ». **Le §5 me contredit** : la conjonction
de six canaux faibles suffit à retrouver 78 % des pistes. Un AUC de 0,60 sur six
canaux indépendants n'est pas la même chose qu'un AUC de 0,60 sur un seul.

Ce que ces chiffres disent vraiment : sur 28 m de dénivelé au kilomètre, **aucun
canal ne porte à lui seul le signal**, là où `rugosite` le portait en montagne.
D'où un modèle plus fragile — il tient par accumulation, donc il coûte cher en
faux positifs.

## 3. Le mode de faux positif est confirmé, et il est total

**Les 2 limites parcellaires annotées sont détectées toutes les deux.**

L'en-tête de la spec 026 l'annonçait — « le micro-relief garde aussi les drains,
fossés, limites parcellaires et terrasses » — mais c'est la première mesure sur
vérité terrain, et elle ne laisse aucune marge : 2 sur 2. Sur `wsfi`, la
terrasse annotée était également la plus proche des seuls candidats produits.

Le détecteur ne distingue pas une desserte d'un linéaire creux quelconque. En
plaine, où les limites et fossés de drainage sont nombreux et les pistes peu
marquées, ce défaut domine.

## 4. Les 87 candidats étaient bien du bruit

La question laissée ouverte à la livraison de la campagne — « le détecteur
trouve enfin ce qu'il manquait » ou « il part en faux positifs » — est tranchée :
à **23 % de précision**, une soixantaine des 87 tronçons ne sont pas des
dessertes.

L'écart de volume avec `wsfi` (87 contre 2) ne mesurait donc pas une meilleure
détection, mais une plus grande **densité de linéaires creux** dans un terrain
plat — exactement ce que le détecteur confond.

## 5. Test circulaire — la borne supérieure

Calibré sur les 9 pistes annotées, puis évalué sur ces mêmes 9 pistes. Ce n'est
**pas une performance**, c'est un plafond : si même dans ces conditions
favorables le rappel reste bas, la calibration est hors de cause.

| | par défaut (`specs = "auto"`) | **circulaire** (calibré sur les 9 pistes) |
|---|---:|---:|
| tronçons produits | 87 (2 214 m) | **203 (4 638 m)** |
| **rappel** | 22 % (2/9) | **78 % (7/9)** |
| **précision** | 23 % (3/13) | **28 % (11/39)** |
| limites parcellaires détectées | 2/2 | **2/2** |

**Le rappel monte à 78 %** — donc le signal EST exploitable, contrairement à ce
que les AUC toutes sous 0,61 laissaient craindre. J'avais pronostiqué qu'il n'y
aurait « pas grand-chose à exploiter » ; c'était faux, et le test le montre.

**Mais la précision ne suit pas** : 28 % seulement, pour **2,3 fois plus de
tronçons produits** (203 contre 87). Le détecteur retrouve les pistes en
inondant l'emprise — 39 candidats dans les tuiles au lieu de 13, dont 28 faux
positifs. Et **les 2 limites parcellaires restent détectées**, calibration ou pas.

### Leave-one-out — le chiffre honnête

Calibré sur 8 pistes, évalué sur la 9ᵉ, neuf fois. Aucune fuite entre
apprentissage et évaluation.

| | circulaire | **leave-one-out** |
|---|---:|---:|
| rappel | 7/9 = 78 % | **7/9 = 78 %** |
| tronçons produits | 203 | 224 en moyenne par pli |

**Identique.** J'avais annoncé avant le run que le risque de mémorisation était
« plus élevé, pas moindre » qu'sur `wsfi`, les AUC y étant toutes plates.
**Réfuté** : la calibration généralise ici comme là-bas. Six canaux faibles mais
indépendants apprennent quelque chose de transportable d'une piste à l'autre.

Les deux pistes manquées (52 m et 111 m) ne sont pas les plus courtes — la
longueur n'explique donc pas l'échec.

**Ce que cela confirme en revanche** : les ~224 tronçons par pli montrent que
l'inondation est **systématique**, pas un artefact du montage circulaire. Le
problème de précision est structurel.

**Ce qu'il faut en retenir** : sur ce bloc, on peut avoir 78 % de rappel *ou*
une précision utilisable, pas les deux. Le compromis est nettement moins
favorable qu'en montagne, où `wsfi` donnait 75 % de rappel pour 36 % de
précision avec 2,9 fois moins de tronçons.

## 6. Une erreur de dépouillement, corrigée

Mon premier passage signalait deux incohérences entre les `n_trouve` déclarés et
les objets numérisés (tuiles 3 et 7). **C'était mon attribution, pas
l'annotation** : un objet de 99 m, à 100 % dans la tuile 7, effleurait le bord de
la tuile 3, et j'assignais la première tuile intersectée au lieu de celle qui en
contient la plus grande part. Après correction par la part de longueur, les 10
tuiles concordent exactement.

Le générateur assigne désormais par la part de longueur.

## 7. Ce que ces deux campagnes établissent ensemble

* **Le correctif du veto était nécessaire et il est validé sur deux massifs.**
  Sur `ltcp` le veto était *absolu* — maximum de vesselness 0,1729 pour une rampe
  démarrant à 0,30, soit zéro cellule éligible sur 4 millions, et une rampe
  249,8 fois au-dessus de la borne calibrée du canal.
* **Le modèle se transporte mal, mais le signal existe.** À configuration
  comparable, 50 % de rappel sur `wsfi` contre 22 % ici. Recalibré sur place, il
  remonte à 78 % — donc ce n'est pas le signal qui manque, c'est que **les
  bornes ne se transportent pas**, exactement ce que la spec 026 dit
  (« elles ancrent, elles ne généralisent pas »). La différence avec `wsfi` est
  le **prix** : il faut 2,3 fois plus de détections pour y arriver.
* **La précision plafonne autour de 23–36 %.** Sur les deux blocs, deux tiers des
  détections ne sont pas des dessertes. Une validation humaine reste
  indispensable — ce que la spec disait déjà, et qui est maintenant chiffré.

## 8. Ce que cela ne dit pas

* **Deux massifs ne font pas une validation nationale.** Un rappel faible en
  plaine lozérienne ne condamne pas la méthode sur tous les terrains plats.
* **Un seul annotateur, pas de double lecture**, sur les deux blocs.
* **9 et 4 événements** : les ordres de grandeur tiennent, les pourcentages ont
  des intervalles larges.
* **Rien sur la praticabilité** de ce qui est trouvé — ni largeur, ni état, ni
  portance. C'est `qualifier_desserte()`, en aval.
