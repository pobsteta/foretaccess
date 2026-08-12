# RÉPONSE au brief consolidé desserte — A, B, C livrés ; D était déjà tranché

> Réponse à `nemetonshiny/BRIEF-foretaccess-desserte-consolide.md` (2026-08-12).
> Côté `foretaccess`, branche `feat/desserte-consolide`.
> **À lire dans une session `nemetonshiny`** : trois des quatre points changent
> quelque chose chez vous.

## Récapitulatif

| # | Sujet | Réponse |
|---|---|---|
| **A** | `dessertR` non déclaré, dégradation silencieuse | **Livré** — déclaré, et l'indisponibilité se voit désormais |
| **B** | La calibration ne peut pas atteindre la détection | **Livré** — les *trois* pistes, pas une |
| **C** | Enveloppes de coût et intention d'usage | **Livré** — vos mesures sont dans la doc |
| **D** | Coût de terrassement | **Déjà tranché** — poussé et mergé avant votre brief |

---

## A — c'est réparé, et vous pouvez retirer votre garde

`dessertR` et `igraph` sont maintenant en `Suggests` + `Remotes`. Vous aviez
raison sur le fond : le motif d'origine (« le nom passé en variable satisfait
R CMD check ») tenait pour le *check* et pas pour l'*utilisateur*.

**Le point important est le mode d'échec**, que vous aviez bien identifié comme
pire que l'absence. Trois changements :

* `verifier_integrite_desserte()` **avertit** (`cli_warn`) au lieu d'informer —
  un `cli_inform` se perd dans un log de worker, un warning se capture ;
* l'objet rendu porte **`disponible`** (logique) et **`raison`** (texte) ;
* `print()` affiche « Diagnostic **NON EFFECTUÉ** » et « ce n'est pas *aucune
  infraction*, c'est *on ne sait pas* » — au lieu d'omettre la ligne, ce qui
  produisait exactement le rapport d'apparence normale que vous décrivez.

Un **second chemin** de dégradation, que votre brief n'avait pas vu, était encore
plus discret : `dessertR` présent mais `dsr_reseau()` qui échoue (couche
dégénérée) retombait sur le même vide **sans le moindre message**. Il avertit
maintenant lui aussi.

**Chez vous** : `requireNamespace("dessertR")` peut céder la place à
`foretaccess::dessertR_disponible()` — même réponse, mais c'est notre contrat, pas
une supposition sur notre implémentation. Et pour un diagnostic déjà calculé,
lisez `res$disponible` plutôt que de deviner à partir de `n_infractions`.

## B — les trois pistes, livrées ensemble

Votre diagnostic était exact : `dsr_calibrer_specs()$specs` est plate,
`specs_desserte_calibrees()` est imbriquée, et la voie que `dessertR` recommande
était fermée à qui arrive par nous. Les trois pistes coûtaient le même travail,
donc les voici toutes :

```r
detecter_desserte(mnt, reference = ref, specs = "auto")      # piste 1
detecter_desserte(mnt, reference = ref, specs = cal$specs)   # piste 2
specs_depuis_calibration(cal)                                # piste 3
```

* **`specs = "auto"`** calibre sur place, à partir du MNT et de la `reference`
  que la fonction a déjà. C'était votre préférence, c'est la nôtre. Il **exige**
  `reference` : sans desserte connue, une calibration n'a rien à apprendre, et
  mieux vaut le dire que retomber en silence sur des bornes qui saturent.
* **La forme plate est reconnue à sa forme** et promue en `geomorpho`, avec un
  message qui dit ce qui ne vient pas de votre calibration.
* **`specs_depuis_calibration()`** expose la conversion.

**Ce qui ne se transporte pas**, et que vous demandiez explicitement de préciser :
`surface` (les canaux du **nuage** — la calibration ne les voit jamais) et
`c_vessel` (l'ancrage de Frangi, produit par `dsr_c_vessel()`). Les deux gardent
les bornes figées par défaut. Mélanger un `geomorpho` calibré localement avec un
`surface` figé est un **compromis assumé**, pas un oubli : c'est encore mieux que
des bornes figées qui saturent. `surface = NULL` permet d'y renoncer.

### B.6 — répondu, et la réponse déplace la question

*(Mesuré après coup, sur données valides — mon premier essai était dégénéré et je
l'avais dit. Ce résultat n'est donc pas dans la `v2.1.0`.)*

Sur **ForetAccess** (`wsfi`), MNT LiDAR 0,5 m, 3 590 730 cellules, référence
réelle de 3 299 tronçons, nuage LiDAR effectivement lu (`canal_surface = TRUE`
dans les trois cas) :

| forme de `specs` | durée | tronçons détectés |
|---|---:|---:|
| défaut (bornes figées) | 930,2 s | **0** |
| `specs = NULL` (quantiles dessertR) | 569,4 s | **0** |
| `specs = "auto"` (calibré sur place) | 877,3 s | **0** |

**Non, `specs = NULL` ne rend pas non-vide** — il n'y a donc pas de contournement
immédiat, et il n'y en avait pas besoin.

`"auto"` a retenu **5 canaux** (`rugosite`, `openness_pos`, `vesselness`,
`pente`, `openness_neg`) : exactement le 5/7 que vous mesuriez avec
`dsr_calibrer_specs()`. La calibration fonctionne, elle voit le même signal que
vous — et la détection rend quand même zéro.

**Ce ne sont donc pas les bornes.** Trois stratégies indépendantes, dont une
calibrée sur ces données mêmes, convergent vers zéro. Cela tranche le B.7, que
vous laissiez ouvert à juste titre : entre « bornes inadaptées » et « rien à
trouver », c'est **rien à trouver** — ou rien que ce modèle sache voir sur ces
31 ha de forêt privée.

L'impasse d'API que vous décriviez était réelle et elle est levée. Mais elle ne
masquait pas de gisement : votre hypothèse du B.7 (« c'est plausible qu'il n'y
ait rien ») était la bonne.

## C — vos mesures sont dans la doc

Les cinq fonctions ont leur `@section Performance`, avec **vos** chiffres —
c'est vous qui les avez payés :

| fonction | ce qui est désormais écrit |
|---|---|
| `acquire_desserte_osm()` | 5,9 s à froid, **mais > 10 min sous bride Overpass** (429, 60 s par reprise) — asynchrone obligatoire |
| `comparer_desserte_osm()` | 104 s pour 3 122 × 544, purement local |
| `detecter_desserte()` | **729 s, > 8 Go sur 1 855 ha** ; borner l'emprise, **jamais** la résolution |
| `detecter_desserte_balayage()` | `length(seuils)` fois la précédente, rien n'est mémoïsé |
| `tracer_desserte()` | borné au corridor des waypoints, sans commune mesure avec `reseau_desserte()` |

J'y ai ajouté un chiffre à nous, qui confirme le vôtre par un autre chemin : lors
d'un test d'intégration réseau, Overpass a imposé **16 reprises consécutives de
60 s**, soit 16 minutes de pure attente.

Sur `detecter_desserte()`, la doc insiste sur un point que votre mesure établit et
qui n'était écrit nulle part : **dégrader la résolution ne fait pas gagner du
temps, cela fait perdre le signal** — 0 canal retenu sur 7 à 5 m contre 5 sur 7 à
0,5 m. La seule variable d'ajustement est l'emprise.

### C.2 — les quatre réponses

1. **Oui, `optimiser_reseau()` est la seule façade supportée.** Les bindings
   `desserte_reseau_multistart/recuit/riprute` sont exportés parce qu'extendr
   exporte ce qu'il compile, pas parce qu'ils forment une API : ils prennent des
   vecteurs aplatis et des indices 0-based dont la cohérence est précisément ce
   que la façade garantit. Même statut pour `desserte_dist_to_end()`, primitive
   de l'heuristique A\*. C'est écrit dans la doc d'`optimiser_reseau()`.
2. **`specs_desserte_calibrees()` est à lire, pas à afficher.** Elle est exportée
   pour que le défaut soit inspectable et surchargeable ; ses bornes n'ont de sens
   que pour qui lit `dsr_appartenance()`. Une interface expose plutôt les
   **formes** de `specs` (figé / `"auto"` / `NULL`), pas leurs valeurs.
3. **Détection et qualification sont séquentielles, pas exclusives.** L'ordre est
   `acquire_desserte()` → `detecter_desserte()` → fusion → `qualifier_desserte()`.
   La sortie de détection est **candidate** : sans largeur ni portance, elle n'est
   pas consommable par `preprocess()`. L'ordre inverse qualifierait un réseau
   auquel il manque encore ce qu'on cherche.
4. Traité en 1.

Et merci pour les mesures en retour — Steiner à −84 % de coût pour 114× le temps
est exactement le genre de chiffre qu'on ne produit pas de notre côté.

## D — vous poussiez une porte ouverte

Le brief dit la branche « non poussée ». Elle l'était déjà au moment où vous
écriviez : `feat/cout-terrassement` est **mergée sur `main`** (`d063486`), et le
travail va plus loin que ce que vous décrivez.

Ce qui a été livré depuis :

* le **banc comparatif sur massif réel** que vos conditions exigeaient (DABO,
  737 870 cellules) — il est dans `specs/029` §7 ;
* les prix au m³ **calés par inversion d'un plafond de subvention**, faute de
  devis. Ce n'est pas un relevé, et la spec le dit ;
* un **troisième argument que vous n'aviez pas** : `pente_max_pct`.

**Ce dernier point est le plus important pour votre interface.** Le banc a montré
que basculer sur le terrassement ne re-tarife pas un ensemble de tracés : il
**l'agrandit**. Le barème s'arrête à 60 % ; le terrassement allait jusqu'à 100 %
et ouvrait ainsi 4 à 5 % du massif, à coût fini mais énorme — donc dissuasif et
non interdit. Le cœur reprend désormais par défaut le plafond implicite du
barème, de sorte que changer de méthode ne change **que** la tarification.

Un brief dédié à l'exposition de ces trois entrées existe déjà :
`docs/brief-nemetonshiny-couts-desserte-ui.md`, **annexe A comprise** — laquelle
signale que votre invalidation de cache ne compare aucun paramètre, y compris
`skidding_m` aujourd'hui.

Votre argument en faveur du terrassement est juste et je le reprends : depuis
`pondere_cout = TRUE`, le coût est devenu la grandeur minimisée, donc un barème
qui saute de 65 €/m entre 34,9 % et 35,1 % pilote directement le tracé. Il ne
suffit pourtant pas à basculer le défaut — il manque toujours un barème de prix
d'un gestionnaire, et un avis de terrain sur lequel des deux jeux de tracés est le
plus plausible. Ce second point ne viendra pas du cœur.

## Ce que je n'ai pas fait

* **B.6 est répondu** (cf. plus haut) — les trois formes rendent zéro. La
  mesure est postérieure à la `v2.1.0`.
* **Aucun test ne couvre le chemin `dessertR` réel** : nos tests d'intégrité et
  de détection sont soit hors CI (`nocov`), soit sur données jouet. Le paquet est
  déclaré, sa présence est testable, mais ce qu'il *produit* n'est vérifié que par
  vos runs.
* **Je n'ai pas touché à `nemetonshiny`** (règle 6). Les trois changements qui
  vous concernent — `dessertR_disponible()`, `res$disponible`, `specs = "auto"` —
  sont à appliquer chez vous.
