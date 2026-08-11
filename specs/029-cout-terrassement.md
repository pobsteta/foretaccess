# specs/029 — Coût de terrassement : déblai / remblai dans la surface de coût

> **Statut** : **implémentée, non activée par défaut** — `cout_terrassement()` (§4) et le
> branchement `surface_cout_construction(methode_pente = "terrassement")` sont écrits et testés ;
> le barème reste le défaut. Le banc sur massif réel a tourné (**§7**) : il montre que la bascule
> **agrandit l'ensemble des cellules constructibles** (+4,45 % sur DABO, entre 60 % et 100 % de
> pente) et **déplace la moitié du tracé**. Elle demande donc un arbitrage explicite sur le seuil de
> constructibilité, plus un barème de prix de gestionnaire — pas un simple changement de défaut.
> **Lot** : extension du Lot 14 (roadmap [`docs/ROADMAP-desserte.md`](../docs/ROADMAP-desserte.md)).
> **Dépend de** : Lot 1 (`preprocess()` : pente du terrain), spec 014 (structure additive du coût).
> **Sert** : Lot 15 (solveur A\*) et Lot 16 (réseau MTAP), via `pondere_cout = TRUE`.
> **Attribution** : le modèle de profil en travers — point de niveau, ripage, talus — est celui de
> **CubaRoad** (Dupire, SylvaLab / ONF Pôle RDI Chambéry, 2021, GPL-3), déjà réimplémenté côté
> mesure dans `dessertR::dsr_cubature()`. Aucune réutilisation de code : formulation propre.

---

## 1. Le problème

La surface de coût du Lot 14 traite la pente par un **barème en escalier** :

| pente du terrain | surcoût |
|---|---|
| 0–15 % | 0 €/m |
| 15–35 % | 25 €/m |
| 35–60 % | 90 €/m |
| ≥ 60 % | non constructible |

C'est un proxy raisonnable et grossier. Il est **discontinu** — 34,9 % et 35,1 % de pente
diffèrent de 65 €/m alors que le terrassement, lui, varie continûment — et il est **aveugle à la
largeur de plateforme** : une piste de 3 m et une route de 5 m y coûtent le même surcoût sur le
même versant, alors que le volume déblayé croît comme le **carré** de la largeur.

Or ce que coûte réellement un mètre de route sur un versant, c'est un volume de terre déplacée.
Ce volume a une forme fermée sur un profil en travers plan, et cette forme fermée est exactement
ce que le barème en escalier approxime en quatre marches.

## 2. Ce qui change, et ce qui ne change pas

**Ne change pas** : la structure additive du coût (base + surcharges + ouvrages ponctuels), le
masque `franchissable`, l'interface de `surface_cout_construction()`, le fait que la pente au-delà
d'un seuil rende la cellule non constructible.

**Change** : le terme de pente devient un **coût de terrassement en €/m**, calculé cellule par
cellule à partir de la pente du terrain, de la largeur de plateforme visée et d'un prix au m³.

## 3. Le modèle, et pourquoi il tient en forme fermée

Sur un profil en travers **plan** de pente transversale `p`, une plateforme de largeur `L` posée
au niveau du terrain sous l'axe, talus amont de pente `A` et talus aval de pente `B`, ripage nul :

```
section_déblai  = p·L²/8 + ½·(p·L/2)² / (A − p)
section_remblai = p·L²/8 + ½·(p·L/2)² / (B − p)
```

C'est la forme fermée que `dessertR` utilise comme **oracle analytique** de ses tests de cubature
(`tests/testthat/test-cubature.R`, `attendu_plan()`), vérifiée sur quatre jeux `(p, L, A, B)`.
Deux conséquences décisives ici :

1. **Aucun échantillonnage n'est nécessaire.** Le coût d'une cellule s'évalue par une expression
   algébrique sur `p`, sans construire de transect. C'est ce qui rend le modèle utilisable dans un
   raster de coût — un portage du moteur par profil, lui, ne le serait pas.
2. **La dépendance à la largeur est quadratique**, ce que le barème en escalier ne peut pas rendre.

### Ripage — il déplace la plateforme, il ne transfère pas un volume

Au-delà d'un dévers, le remblai ne tient pas. On reprend la règle de `dsr_cubature()` —
interpolation linéaire entre `ripage_min = 0.35` et `ripage_max = 0.60` — appliquée à
**l'assiette**, comme `assise_deblai` / `assise_remblai` :

```
r = clamp((p − ripage_min) / (ripage_max − ripage_min), 0, 1)
a = L/2 · (1 + r)     demi-largeur creusée
b = L/2 · (1 − r)     demi-largeur remblayée, nulle à ripage plein

S_déblai  = p·a²/2 + ½·(p·a)² / (A − p)
S_remblai = p·b²/2 + ½·(p·b)² / (B − p)      (nulle si b = 0)
```

À `r = 0`, `a = b = L/2` et l'on retrouve la forme fermée du dessus.

**Cette formulation n'est pas une élégance.** La version naïve — calculer les deux sections
symétriques puis transférer une fraction du remblai vers le déblai — transfère une quantité qui
**diverge** quand `p → B`, alors que cette configuration est précisément celle où il n'y a plus de
remblai du tout. Le défaut est apparu en écrivant le test de continuité : un saut de 22,8 €/m
entre deux pentes distantes de 0,5 point, là où le modèle doit être lisse.

Le déblai se réemploie sur place à hauteur du remblai ; l'excédent part en évacuation, et c'est
**ce transport qui coûte**.

### Ce que le modèle fait aux bornes

Le coût **diverge** quand `p → A` : le talus amont ne recoupe presque plus le terrain. Ce n'est
pas un défaut à corriger — le solveur évitera ces cellules de lui-même, et les déclarer
infranchissables serait poser un seuil de plus. Au-delà de `A`, la cellule est `NA`. Le talus aval
`B`, lui, ne condamne que tant qu'il reste du remblai à poser : à ripage plein la plateforme est
entièrement creusée, et c'est `A` qui devient la seule borne.

### Prix

```
coût_terrassement(€/m) = v_déblai · prix_déblai_m3
                       + v_remblai · prix_remblai_m3
                       + v_évacué · prix_evacuation_m3
```

où les `v` sont les sections en m² (donc des m³ par mètre linéaire de route). Les prix vont en
config, `desserte$cout$terrassement`.

### Calage des prix par inversion d'un plafond (2026-08-11)

**Aucune source publique ne donne de €/m³ de terrassement forestier.** Les barèmes de subvention
donnent des coûts *tout compris* au kilomètre — 65 000 €/km en création empierrée, 45 000 en mise
au gabarit, 20 000 en terrain naturel ; 30 000 €/km dans le massif vosgien, 50 000 sur plateau
calcaire, 60 à 70 000 sur plateau lorrain. Les prix de terrassement du BTP existent (30–70 €/m³ en
déblai-remblai, 40–110 une fois la mise en décharge incluse) mais décrivent un chantier de
bâtiment où le matériau part en décharge, alors qu'en desserte il est **réemployé sur place**.

On inverse donc le plafond. À la pente médiane de DABO (28,2 %) et 4 m de plateforme, le modèle
déplace **1,49 m³ par mètre linéaire** ; le barème y demande 25 €/m de surcoût — valeur ancrée sur
les 45 000 €/km de la « mise au gabarit », comme `fraction_reouverture`. Le facteur qui égalise les
deux vaut **2,79** :

| | avant | après calage |
|---|---:|---:|
| déblai | 6 €/m³ | **17 €/m³** |
| remblai | 4 €/m³ | **11 €/m³** |
| évacuation | 12 €/m³ | **33 €/m³** |

**Contrôle indépendant** : 17 €/m³ de déblai tombe au milieu de la fourchette BTP « déblai seul,
10–32 €/m³ », qui n'a pas servi au calcul.

### Le calage redistribue, il ne remet pas à l'échelle

C'est le fait le plus utile de l'opération, et il n'était pas prévu. Les deux courbes se croisent
**quatre fois** (14,9 %, 28,1 %, 34,9 %, 42,2 %) :

| pente | terrassement | barème |
|---:|---:|---:|
| 10 % | 6,4 €/m | 0 |
| 20 % | 15,1 €/m | 25 |
| 30 % | 27,8 €/m | 25 |
| 34,9 % | 36,6 €/m | 25 |
| 35,1 % | 37,0 €/m | **90** |
| 45 % | 131,9 €/m | 90 |
| 59 % | 550,3 €/m | 90 |

Le barème est **gratuit sous 15 %** là où tout terrassement coûte quelque chose, **surtaxe la
pente moyenne** par sa marche à 35 %, et **sous-tarifie massivement le raide** — 90 €/m à 59 %
quand le terrassement en demande 550. Un calage qui n'aurait fait que multiplier une échelle
n'aurait rien changé aux tracés ; celui-ci change l'ordre relatif des cellules, donc les tracés.

### Ce que ce calage ne règle pas

1. Il cale le terrassement sur le **barème**, c'est-à-dire sur le proxy que cette spec veut
   remplacer. Le raisonnement n'est pas circulaire — le barème est lui-même ancré sur des plafonds
   d'État — mais il transporte l'erreur du barème **à la pente médiane**.
2. **Un point de calage ne contraint que la somme pondérée des trois prix.** Leur rapport reste
   arbitraire : il faudrait un second massif, raide, où l'évacuation domine, pour les séparer.
3. Un plafond de subvention **majore** un coût observé.

Un devis de gestionnaire reste supérieur à tout ceci.

## 4. Interface

```r
cout_terrassement(pente_pct, largeur_m, config = foretaccess_config())
```

- `pente_pct` : `SpatRaster` de pente du terrain (%), ou vecteur numérique.
- `largeur_m` : largeur de plateforme visée (m), scalaire.
- retourne un `SpatRaster` (ou vecteur) de €/m, `NA` là où la pente rend la construction
  impossible : `p ≥ A` toujours, et `p ≥ B` tant qu'il reste du remblai à poser (voir « Ce que le
  modèle fait aux bornes »).

Le découplage est volontaire : la fonction ne connaît ni `preprocess()` ni le reste de la chaîne,
ce qui la rend testable contre la forme fermée sans monter un raster de terrain.

## 5. La limite qu'il faut énoncer

**La pente transversale n'est pas la pente du terrain.** Elle en dépend par l'azimut de la route,
que le solveur connaît et que le raster de coût, lui, ignore : un coût pré-calculé par cellule ne
peut pas savoir dans quelle direction la route la traversera.

L'approximation retenue est `p_transversale = p_terrain`, c'est-à-dire **la route suit la
courbe de niveau**. Ce n'est pas neutre, et c'est défendable dans les deux sens :

- c'est le cas réel dominant en desserte forestière de versant, où la pente en long est bornée à
  12 % (`config$desserte$trace$pente_long_max`) alors que le versant en fait couramment 30 à 60 % :
  une route ne peut donc pas monter dans la ligne de plus grande pente, elle biaise ;
- c'est **majorant** : toute route qui s'écarte de la courbe de niveau a une pente transversale
  plus faible, donc un terrassement moindre. Surestimer le coût d'un versant raide est le sens
  conservateur.

Le lever demanderait de porter le coût **sur les arêtes** du graphe du solveur plutôt que sur les
cellules — la structure est déjà là (ADR-008, graphe étendu), mais c'est un autre lot.

## 6. Reste à faire

| Étape | Charge | État |
|---|---|---|
| `cout_terrassement()` + oracle analytique en test | 2 j | **fait** |
| Prix en config + validation `checkmate` | 0,5 j | **fait** |
| Branchement dans `surface_cout_construction()` (`methode_pente = "bareme" \| "terrassement"`) | 1 j | **fait** |
| Banc de comparaison barème / terrassement sur un massif réel | 2 j | **fait** (§7) |
| Prix au m³ calés par inversion de plafond | 0,5 j | **fait** (§Prix) |
| Barème de prix au m³ d'un gestionnaire | — | **reste — bloquant pour la bascule** |
| Refaire le banc du §7 aux prix calés | 0,5 j | **reste** |
| Coût porté sur les arêtes (lève §5) | 1,5 sem | non arbitré |

**Le défaut reste `"bareme"`, délibérément** : changer le terme de pente change tous les tracés
produits, et la comparaison des deux méthodes sur un massif réel doit précéder la bascule. La
méthode est écrite, testée et appelable — elle n'est pas activée.

Un point que le branchement a révélé : le barème rend `Inf` là où la construction est impossible,
le terrassement rend `NA`. Les deux doivent aboutir au même endroit — une cellule
infranchissable — alors qu'un `NA` se propagerait en silence dans la somme et laisserait passer le
solveur. La conversion est faite au branchement, et testée.

---

## 7. Banc barème / terrassement sur massif réel (2026-08-11)

> ⚠️ **Mesuré AVANT le calage des prix** (§Prix), aux valeurs 6 / 4 / 12 €/m³.
> Ce qui tient : le §7.1 — le *feasible set* ne dépend que de la géométrie des talus, pas des
> prix. Ce qui ne tient plus : les coûts du §7.2, à multiplier par 2,79 côté terrassement, ce qui
> aligne sa médiane sur celle du barème **par construction** et fait disparaître le « × 0,63 ».
> Les tracés du §7.3 sont à **refaire** : le calage redistribue au lieu de remettre à l'échelle,
> donc il change l'ordre relatif des cellules.


Massif **DABO** : emprise de 737 870 cellules à 5 m, pente médiane 28,2 %, p90 53,7 %.
4 parcelles / 774 ha, desserte existante réelle, `skidding_m = 100`, `pondere_cout = TRUE`,
`largeur_m = 4`.

### 7.1 Le résultat qui doit décider : le *feasible set* change

| | barème | terrassement |
|---|---:|---:|
| cellules franchissables | 704 905 | **737 770** |
| **ouvertes** par le terrassement | — | **32 865 (4,45 % du MNT)** |
| fermées par le terrassement | — | 0 |

Les cellules ouvertes sont **entre 60 % et 100 % de pente** — précisément la classe que le barème
déclare non constructible (`surcout = Inf`). Le terrassement y rend un coût **fini**, de 236 à
**1 334 168 €/m**.

C'est le point le plus important du banc, et il n'est pas de nature comptable : **basculer la
méthode ne re-tarife pas un ensemble de tracés possibles, il l'agrandit.** Un coût de 1,3 M€/m est
dissuasif, pas interdit : dans un corridor sans alternative, le solveur le prendra. Le barème
répondait « on ne construit pas au-dessus de 60 % » ; le terrassement répond « on construit, et
voici le prix ». Les deux réponses sont défendables — ce n'est pas au modèle de coût de trancher
en silence.

**Conséquence pour la bascule** : elle ne peut pas être un simple changement de défaut. Il faut
décider séparément d'un **seuil de constructibilité**, et le poser explicitement — soit en gardant
la borne à 60 % du barème, soit en l'assumant plus haut avec l'accord d'un gestionnaire.

### 7.2 Les coûts, sur le domaine commun

Sur les cellules franchissables par les deux méthodes :

| | médiane | moyenne |
|---|---:|---:|
| barème | 45 €/m | 61,7 €/m |
| terrassement | 28,5 €/m | 46,5 €/m |

Le terrassement est **moins cher en médiane (× 0,63)** aux prix par défaut. Ce chiffre ne vaut
rien en soi — les prix au m³ sont des ordres de grandeur, cf. §Prix — mais il dit que les deux
échelles ne sont pas comparables telles quelles : un massif tarifé au terrassement paraîtra moins
coûteux à construire, sans qu'aucune information nouvelle ne le justifie.

### 7.3 Les tracés

| | barème | terrassement |
|---|---:|---:|
| routes créées | 38 | 41 |
| longueur totale | 7 535 m | 7 640 m |
| coût total | 408 043 | 381 103 |
| durée | 117 s | 149 s |

**Recouvrement des deux tracés : 50,1 %** (part du tracé barème reprise à moins d'une cellule par
le tracé terrassement). C'est la réponse à « quels tracés changent, et de combien » : **la moitié
du réseau change de position.** Les agrégats se ressemblent — longueur à 1,4 % près, nombre de
routes à 3 près — et masquent une refonte géométrique de moitié. Comparer deux méthodes sur leurs
totaux aurait conclu à tort qu'elles sont équivalentes.

### 7.4 Ce que le banc ne dit pas

Il ne dit pas **laquelle est la plus plausible pour un gestionnaire**. Il faudrait confronter les
deux jeux de tracés à un avis de terrain sur un massif connu ; c'est le seul juge, et il n'a pas
été sollicité. Le banc établit que le choix a des conséquences fortes, pas qu'il a une bonne
réponse.
