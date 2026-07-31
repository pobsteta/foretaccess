# Audit dessertR — la détection dépendait de l'emprise qu'on lui passait

> ## ✅ TRAITÉ — livré dans **dessertR 1.1.0** (`e7d3361`, 2026-07-31)
>
> Ce document est conservé comme **trace d'audit**. Les deux demandes du §5 sont
> livrées :
>
> | demande | livraison 1.1.0 |
> |---|---|
> | exposer `c` jusqu'à `dsr_layers_dtm()` | `dsr_c_vessel()` + `dsr_layers_dtm(c_vessel = )` |
> | faire produire `a`/`b` par `dsr_calibrer_specs()` | `dsr_calibrer_specs(bornes = TRUE)` |
>
> Le commit amont crédite « un audit ForêtAccess sur le commit `cb9376c` ».
> Le contournement listé au §6 a été **retiré** de ForêtAccess :
> `.vesselness_ancree()` est supprimé, `specs_desserte_calibrees()` ne porte plus
> que les valeurs de référence produites par l'amont.
>
> **Résidu connu** : `densite_sousetage` sort avec des bornes indéterminées
> (`a = NA`, `b = NA`) — les deux populations sont à zéro en médiane. Le canal est
> écarté de notre calibration de référence pour cette raison, faute de quoi il
> retomberait sur la dérivation par quantiles.

> **Origine** : session ForêtAccess du 2026-07-31, spec 026 (desserte détectée sur MNT).
> **Version auditée** : `dessertR` `1.0.0.9000`, commit **`cb9376c`**.
> **Écrit depuis ForêtAccess** : aucune modification n'a été faite dans le dépôt
> `dessertR` (règle stricte 6 — une session parallèle y commitait au même moment).

## 1. Le symptôme

`dsr_detecter()` rend des résultats **différents pour le même terrain** selon
l'étendue du raster qu'on lui soumet. Mesure sur le bloc `wsfi`, MNT LiDAR HD
0,50 m, 4 dalles COPC, référence BD TOPO identique dans les deux cas :

| fenêtre centrale de 0,25 km² | linéaire détecté |
|---|---:|
| analysée **seule** | **116 m** |
| analysée **à l'intérieur** de 4 km² | **0 m** |

Conséquences pratiques :

* le paramètre `seuil` n'est **pas une quantité absolue** — il désigne un rang
  dans la population de l'emprise fournie ;
* deux sites d'étendues différentes ne sont **pas comparables** au même seuil ;
* en production, le régime `corridor` restreint l'emprise et **change donc le
  barème** : la même piste est détectée ou non selon le découpage du chantier.

## 2. Défaut 1 — bornes d'appartenance dérivées par quantiles

`dsr_appartenance()` (`R/conductivity.R`) dérive ses bornes de la donnée quand
elles ne sont pas fournies :

```r
qs <- if (type == "cloche") c(0.25, 0.75) else c(0.5, 0.95)
if (is.null(a)) a <- stats::quantile(v, qs[1], na.rm = TRUE, names = FALSE)
if (is.null(b)) b <- stats::quantile(v, qs[2], na.rm = TRUE, names = FALSE)
```

Or `dsr_specs_geomorpho()` et `dsr_specs_surface()` (`R/conductivity.R:84` et
`:228`) ne portent **que** `type` et `poids` — jamais `a` ni `b`. Le chemin par
défaut est donc toujours relatif à l'emprise.

Démonstration minimale — la même valeur 0,40 dans deux populations :

| population | bornes dérivées | μ |
|---|---|---:|
| étroite | a=0,20 b=0,72 | 0,385 |
| large | a=0,025 b=0,05 | **1,000** |

## 3. Défaut 2 — le `c` de Frangi est dérivé du maximum de l'image

`dsr_frangi()` (`R/layers_dtm.R:628-629`) :

```r
smax <- suppressWarnings(max(s, na.rm = TRUE))
c <- if (is.finite(smax) && smax > 0) 0.5 * smax else 1
```

C'est le défaut classique de Frangi (1998), et il est intrinsèquement relatif :
une emprise plus vaste contient un maximum de norme de Hessien plus élevé, ce
qui comprime `1 - exp(-s²/2c²)` pour **tous** les pixels.

Mesuré, `c` dérivé sur 4 km² contre 1 km² (même terrain, MNT 0,5 m → grille 1 m) :

| échelle | `c` sur 1 km² | `c` sur 4 km² | rapport |
|---:|---:|---:|---:|
| 1 m | 0,35417 | 0,74971 | **×2,12** |
| 2 m | 0,75931 | 1,64387 | **×2,16** |
| 4 m | 1,24541 | 2,40019 | **×1,93** |

**Ce défaut-ci est le plus gênant** : il agit **en amont** de la fonction
d'appartenance, donc **aucune borne `a`/`b` ne peut le rattraper**. Il touche
aussi `dsr_detecter(vesselness = , seuil_vessel = 0.3)`, où une vesselness
rescalée est comparée à un seuil absolu.

À noter : `c` varie de **3,52×** entre échelles d'un même site. Un scalaire
unique passé à `dsr_vesselness(c = )` aplatirait cette structure et fausserait
la sélection du maximum multi-échelle — il faut **une valeur par échelle**.

## 4. Preuve que les deux corrections suffisent

Bornes physiques + `c` figé par échelle, même fenêtre de 0,25 km², distributions
comparées entre « vue depuis 4 km² » et « analysée seule » :

| | avant | après |
|---|---|---|
| `sigma_geo` ≥ 0,4 | 4,75 % vs **11,75 %** | 10,47 % vs 9,90 % |
| `sigma_surf` ≥ 0,4 | 21,919 % vs 21,919 % | 21,919 % vs 21,919 % |
| **indice `p` ≥ 0,4** | 0,000 % vs **0,212 %** | **0,092 % vs 0,092 %** |

L'indice devient identique à la troisième décimale, même maximum (0,7945). Le
résidu sur `sigma_geo` (5,7 % relatif) est cohérent avec les effets de bord des
fenêtres focales sur la découpe.

## 5. Modifications proposées

### 5.1. Exposer `c` jusqu'à `dsr_layers_dtm()`

`dsr_vesselness()` expose déjà `c`, mais `dsr_layers_dtm()` ne le relaie pas :
l'appelant qui construit la pile n'a aucun moyen de le fixer. Proposition —
accepter un vecteur **aligné sur `echelles_vessel`** :

```r
dsr_layers_dtm(mnt, grille = NULL, res = DSR_RES_MULTIECHELLE,
               echelles_vessel = c(1, 2, 4),
               c_vessel = NULL,   # NULL = comportement actuel (par image)
               ...)
```

et, dans `dsr_vesselness()`, accepter `c` de longueur `length(echelles_m)` en
plus du scalaire, appliqué échelle par échelle dans la boucle existante.

### 5.2. Faire produire `a`/`b` par `dsr_calibrer_specs()`

`dsr_calibrer_specs()` (`R/conductivity.R:399`) mesure **déjà** les populations
présence/absence par canal pour calculer l'AUC et le sens. Les quantiles
nécessaires aux bornes sont donc à portée **dans la même boucle**, sans coût
supplémentaire. Proposition : ajouter `a` et `b` aux specs rendues, avec la
convention

* `croissante` → `a` = q50(absence), `b` = q75(présence) ;
* `decroissante` → `a` = q25(présence), `b` = q50(absence).

Ça rendrait `dsr_calibrer_specs()` suffisant à lui seul pour produire des specs
**absolues**, ce qui est sa vocation affichée (« mesurer les règles de
conductivité au lieu de les supposer »).

### 5.3. Accessoirement — `rugosite` est déclaré à l'envers dans les specs par défaut

`dsr_calibrer_specs()` lancé sur la dalle `LHD_FXX_0737_6385` (Chastel-Nouvel,
1 km², 32 tronçons, 7 561 m de desserte BD TOPO `piste` + `route`) rend :

| canal | AUC | sens | poids |
|---|---:|---:|---:|
| `taux_penetration` | 0,825 | + | 3 |
| `densite_sol` | 0,796 | + | 3 |
| `rugosite` | 0,759 | **+** | 2 |
| `pente` | 0,758 | − | 2 |
| `vesselness` | 0,693 | + | 2 |
| `h_couvert` | 0,682 | − | 2 |
| `openness_pos` | 0,666 | − | 2 |
| `slrm` | 0,628 | − | 1 |
| `openness_neg` | 0,605 | + | 1 |
| `svf` | 0,571 | + | 1 |
| `densite_sousetage` | 0,558 | − | 1 |

**Le point d'action** : `dsr_specs_geomorpho()` déclare `rugosite` en
`decroissante`, alors que la mesure donne **`sens = +1`**. Sur ce terrain la
desserte est **plus** rugueuse que le fond (médiane 0,1032 contre 0,0393). Le
confondant « le masque de mesure mord sur le bord de plateforme » est écarté :
l'AUC est **plate** selon la demi-largeur du masque (0,757 / 0,758 / 0,762 à
1 / 2 / 3 m), là où un artefact de bord se serait effondré en resserrant. À 1 m
dans une fenêtre de 5 cellules, c'est le profil en travers — fossé, talus,
dévers — qui domine, pas l'état de la chaussée.

**Écart notable entre specs par défaut et specs mesurées** : les specs par défaut
retiennent 5 canaux, la calibration en retient **11**. `densite_sol` (AUC 0,796,
deuxième meilleur) ne figure dans aucune spec par défaut. C'est un argument pour
documenter `dsr_calibrer_specs()` comme le chemin **recommandé**, les specs par
défaut n'étant qu'un point de départ.

**Réserve explicite** : un seul terrain (Lozère, 830–1 260 m, forêt de montagne),
une seule dalle. Le constat sur `rugosite` est peut-être local — c'est
précisément ce que l'agrégation multi-massifs de `dsr_calibrer_specs()`
(`stable`) est faite pour trancher, et il faudrait le refaire sur au moins deux
massifs avant de toucher au défaut du paquet.

> **Correction d'une version antérieure de ce brief** : il affirmait que
> `densite_sousetage` était « aveugle (AUC 0,393) » et devait être écarté. C'est
> **faux**, et l'erreur était de lecture : 0,393 mesuré en P(présence > absence)
> est symétrique de 0,607 et signifie « discrimine dans le sens **décroissant** »,
> soit exactement le `decroissante` déclaré par le paquet. `dsr_calibrer_specs()`
> le retient (AUC 0,558, sens −1). Aucune action n'est requise sur ce canal.

## 6. Ce que ForêtAccess porte en attendant

Contournement **temporaire**, à retirer dès que 5.1 et 5.2 sont livrés :

| élément | fichier | à supprimer une fois l'amont corrigé |
|---|---|---|
| `specs_desserte_calibrees()` | `R/desserte-detectee.R` | remplacer par `dsr_calibrer_specs()` |
| `.vesselness_ancree()` | `R/desserte-detectee.R` | **oui** — duplique la boucle de `dsr_vesselness()` |
| `data-raw/calibrer_bornes_dsr.R` | banc | remplacer par un appel à `dsr_calibrer_specs()` |

`.vesselness_ancree()` est la dette la plus nette : elle **rejoue une boucle
interne de dessertR** pour imposer un `c` par échelle, et se désynchronisera au
premier changement amont. Elle n'existe que parce que `dsr_layers_dtm()` ne
relaie pas `c`.

## 7. Reproduire

* Banc de calibration : `data-raw/calibrer_bornes_dsr.R` (ForêtAccess).
* Entrées : `data-raw/oracle/aoi/phaseB/cache_0p5/layers/mnt/mnt.tif` et la dalle
  `LHD_FXX_0737_6385_PTS_LAMB93_IGN69.copc.laz`.
* Bloc de contrôle : `wsfi` (nemeton), 4 dalles, MNT 0,50 m.
  **Attention** : `wsfi` recouvre l'AOI oracle sur **2,143 km² des 4,00** — les
  deux jeux ne sont pas indépendants, et la dalle de calibration est le quart
  sud-ouest de `wsfi`.
