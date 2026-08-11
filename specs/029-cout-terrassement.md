# specs/029 — Coût de terrassement : déblai / remblai dans la surface de coût

> **Statut** : **spécifiée, implémentation amorcée** — `cout_terrassement()` (§4) écrite et testée ;
> le branchement dans `surface_cout_construction()` reste à faire (§6).
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
config, `desserte$cout$terrassement`, et sont **à caler avec un gestionnaire** : aucune valeur par
défaut n'est défendable sans devis régional.

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
| Branchement dans `surface_cout_construction()` (`methode = "bareme" \| "terrassement"`) | 1 j | reste |
| Banc de comparaison barème / terrassement sur un massif réel | 2 j | reste |
| Coût porté sur les arêtes (lève §5) | 1,5 sem | non arbitré |

Le branchement est laissé en second temps **délibérément** : changer le terme de pente change tous
les tracés produits, et la comparaison des deux méthodes sur un massif réel doit précéder la
bascule du défaut. La fonction est écrite, testée et appelable ; `surface_cout_construction()` ne
l'utilise pas encore.
