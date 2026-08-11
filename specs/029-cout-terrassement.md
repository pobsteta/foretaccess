# specs/029 — Coût de terrassement : déblai / remblai dans la surface de coût

> **Statut** : **implémentée, non activée par défaut** — `cout_terrassement()` (§4) et le
> branchement `surface_cout_construction(methode_pente = "terrassement")` sont écrits et testés ;
> le barème reste le défaut. Le banc sur massif réel a tourné deux fois (**§7**), avant et après le
> calage des prix : il montre que la bascule **agrandit l'ensemble des cellules constructibles**
> (+5,02 % sur DABO, entre 60 % et 100 % de pente) et **déplace plus de la moitié du tracé**. Elle demande donc un arbitrage explicite sur le seuil de
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
| Refaire le banc du §7 aux prix calés, et le rendre rejouable | 0,5 j | **fait** (§7) |
| Coût porté sur les arêtes (lève §5) | 1,5 sem | non arbitré |

**Le défaut reste `"bareme"`, délibérément** : changer le terme de pente change tous les tracés
produits, et la comparaison des deux méthodes sur un massif réel doit précéder la bascule. La
méthode est écrite, testée et appelable — elle n'est pas activée.

Un point que le branchement a révélé : le barème rend `Inf` là où la construction est impossible,
le terrassement rend `NA`. Les deux doivent aboutir au même endroit — une cellule
infranchissable — alors qu'un `NA` se propagerait en silence dans la somme et laisserait passer le
solveur. La conversion est faite au branchement, et testée.

---

## 7. Banc barème / terrassement sur massif réel

Rejouable : [`data-raw/banc_029_terrassement.R`](../data-raw/banc_029_terrassement.R).
Le premier passage (2026-08-11, prix 6 / 4 / 12) avait été conduit à la main et n'a laissé que ses
résultats ; **il n'était pas reproductible**, et il a fallu le refaire après le calage des prix.
D'où le script. C'est la leçon du premier tour, autant que ses chiffres.

Passage de référence : **DABO / xpdk**, emprise `emprise_1000m`, 1 348 212 cellules à 5 m, pente
médiane 30,3 %, p90 54,5 %, 3 122 tronçons existants, 4 parcelles / 774 ha, `skidding_m = 100`,
`largeur_m = 4`, `pondere_cout = TRUE`, moteur glouton, prix calés (17 / 11 / 33).

> **Les deux passages ne portent pas sur la même emprise** — le premier annonçait 737 870 cellules
> et une pente médiane de 28,2 %, contre 1 348 212 et 30,3 % ici. Son extraction n'ayant pas été
> scriptée, elle n'est pas reconstituable. **Aucune comparaison chiffrée entre les deux passages
> n'est licite** ; seules les comparaisons barème / terrassement *à l'intérieur* d'un passage le
> sont. Les deux concordent qualitativement sur les trois résultats.

### 7.1 Le résultat qui décide : le *feasible set* s'agrandit

| | barème | terrassement |
|---|---:|---:|
| cellules franchissables | 1 275 143 | **1 342 775** |
| **ouvertes** par le terrassement | — | **67 632 (5,02 % du MNT)** |
| fermées | — | **0** |

Cellules ouvertes : **60 à 100 % de pente**, exactement la classe que le barème déclare non
constructible. Le terrassement y rend un coût fini, de **620 à 57 478 755 €/m**.

Ce résultat **ne dépend pas des prix** — la borne vient de la géométrie des talus — et il est le
seul des trois dans ce cas. Basculer la méthode n'est donc pas re-tarifer : c'est **agrandir
l'ensemble des tracés possibles**. 57 M€/m est dissuasif, pas interdit : dans un corridor sans
alternative, le solveur le prendra. Le barème répond « on ne construit pas au-dessus de 60 % », le
terrassement « on construit, et voici le prix ». Les deux sont défendables — ce n'est pas au modèle
de coût de trancher en silence.

**La bascule demande donc un arbitrage séparé du seuil de constructibilité**, pas un changement de
défaut.

### 7.2 Les coûts : le calage a fait son travail, la queue reste divergente

Sur le domaine commun aux deux méthodes :

| | médiane | moyenne |
|---|---:|---:|
| barème | 45,0 €/m | 64,6 €/m |
| terrassement | 46,4 €/m | **99,0 €/m** |

Rapport des médianes : **× 1,03**. Le « × 0,63 » du premier passage a disparu — c'était l'effet
attendu du calage, et il vaut vérification plus que découverte : les prix ont été choisis pour
égaliser ces médianes.

**Les moyennes, elles, divergent d'un facteur 1,5.** C'est le résultat non trivial du §2 : le
calage aligne le centre et laisse la queue s'écarter, parce qu'il redistribue au lieu de remettre à
l'échelle. Le terrassement est plus lourd sur les fortes pentes, où le barème plafonne à 90 €/m.

### 7.3 Les tracés : les agrégats se ressemblent, la géométrie non

| | barème | terrassement |
|---|---:|---:|
| routes créées | 37 | 40 |
| longueur totale | 6 931 m | 7 550 m |
| coût total | 359 269 | 691 860 |
| durée | 243 s | 226 s |

**Recouvrement : 44,1 %** du tracé barème repris à moins d'une cellule par le tracé terrassement,
**40,8 %** dans l'autre sens. Moins de la moitié du réseau est commune, pour une longueur totale à
9 % près et trois routes d'écart. Comparer deux méthodes sur leurs totaux conclurait à
l'équivalence ; c'est faux.

Le coût total du terrassement est 1,9 fois celui du barème alors que leurs médianes s'égalent :
son tracé passe donc par des cellules plus chères, c'est-à-dire plus raides. Il achète de la
longueur en terrain difficile là où le barème l'évite — cohérent avec le §7.1.

### 7.4 Ce que le banc ne dit pas

Il ne dit pas **laquelle est la plus plausible pour un gestionnaire**. Il faudrait confronter les
deux jeux de tracés à un avis de terrain sur un massif connu ; c'est le seul juge, et il n'a pas
été sollicité. Le banc établit que le choix a des conséquences fortes, pas qu'il a une bonne
réponse.
