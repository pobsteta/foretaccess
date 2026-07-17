# Performance — temps de calcul sur ColduPre (ForêtAccess vs Sylvaccess)

> Rédigé le 2026-07-17. Jeu de test officiel **ColduPre** (894 × 1034 cellules,
> `test/ColduPre/Input/` du dépôt Sylvaccess v3.6). Harnais de mesure :
> [`data-raw/oracle_coldupre.R`](../data-raw/oracle_coldupre.R). Chiffres Sylvaccess :
> mesure de référence antérieure (Cython v3.6). Chiffres ForêtAccess : **2 passes
> séquentielles** (`workers = 1`), machine au repos, le 2026-07-17.

## En une phrase

À **isopérimètre** (mêmes paramètres, en particulier **3 supports intermédiaires
câble**), les moteurs terrestres de ForêtAccess sont **à parité** avec le Cython, et
le **câble est ~5× plus rapide** grâce à son noyau Rust parallélisé (`rayon`).

## 1. Résultats

| Moteur | ForêtAccess (temps écoulé) | ForêtAccess (CPU) | Sylvaccess (réf. Cython) |
|---|---|---|---|
| Prétraitement | 1,2 s | 1,1 s | — |
| Skidder | ~15 s | ~14,5 s | 14 s |
| Porteur | ~17–19 s | ~17 s | 14 s |
| **Câble (`c_sup = 3`)** | **~40 s** | ~165 s (`rayon`) | 3 min 18 s (198 s) |
| Camion DFCI | ~26–31 s | ~21 s | — |

Détail des deux passes (temps écoulé) : skidder 15,1 / 15,3 s ; porteur 16,5 / 18,8 s ;
câble 38,7 / 44,9 s ; DFCI 26,0 / 31,2 s. Les moteurs terrestres sont séquentiels
(`workers = 1`), donc CPU ≈ écoulé — signe que la machine était **réellement au repos**
(pas de contention, contrairement à d'anciennes mesures faussées, cf. §4).

## 2. Le câble à isopérimètre : ~5× plus rapide

Le point important. L'ancienne comparaison publiée (câble ForêtAccess « 2 min 18 s »)
était **doublement trompeuse** :

1. **Mauvais périmètre.** Elle datait d'**avant le Lot 4d** (2026-07-14), quand le
   noyau câble était à **zéro support intermédiaire** (`c_sup = 0`), alors que
   Sylvaccess en posait 3. On comparait deux problèmes différents.
2. **Mesure pré-parallélisation.** Le scan 360°/pixel n'était pas encore dans sa forme
   Rust parallélisée actuelle.

Depuis, le placement des supports (`0…3`) est porté (`src/rust/src/cable/optpyl.rs`) et
le **défaut de configuration est `nb_supports_max = 3`** — donc ForêtAccess tourne bel et
bien à `c_sup = 3`, comme Sylvaccess. À ce périmètre commun :

- ForêtAccess : **~40 s de temps écoulé** pour **~165 s de temps CPU** — le noyau
  `cablehelp` répartit le balayage sur les cœurs via `rayon` (facteur ~4 ici).
- Sylvaccess : **198 s** (Cython monocœur).

Le gain vient donc du **portage Rust + parallélisme**, pas d'un changement d'algorithme :
la mécanique caténaire résolue est la même (cf.
[`comparaison-cable-seilaplan.md`](comparaison-cable-seilaplan.md)).

## 3. Ce que ça implique pour le passage à l'échelle

Les moteurs terrestres restent séquentiels et à parité avec le Cython. Le portage Rust
n'y est donc justifié qu'à **l'échelle régionale/nationale** ; à l'échelle du massif ou
du département, le **tuilage** (Lot 7, `traiter_par_tuiles()` + halo certifié) suffit et
donne un résultat identique bit à bit au traitement mono-bloc. Le câble, lui, bénéficie
déjà du parallélisme intra-nœud (`rayon`) quelle que soit l'échelle.

## 4. Pièges de mesure (à ne pas rejouer)

Cette machine de développement a historiquement faussé les chronométrages ; deux pièges
identifiés et corrigés :

- **Workers orphelins.** Une suite de tests interrompue laissait huit workers `workRSOCK`
  tourner : une première mesure donnait 39,8 s / 47,2 s pour le skidder/porteur au lieu de
  ~15 s. *Toujours vérifier la charge (`uptime`) avant de chronométrer.*
- **Throttling thermique / idle injecté.** À certaines périodes, le noyau injecte de
  l'idle : la charge affiche 6–10 sur 8 cœurs sans processus utilisateur, et le temps
  écoulé vaut le double du temps CPU. Les mesures de cette note ont été prises à charge
  ~1,0, avec CPU ≈ écoulé sur les moteurs séquentiels — condition de repos vérifiée.

## Voir aussi

- Fidélité cellule à cellule à l'oracle (skidder 99,95 %, porteur 99,72 %, câble
  98,36 %, DFCI 99,87 %) : `PLAN.md` et l'article pkgdown *Architecture & feuille de route*.
- Comparaison des méthodes câble : [`comparaison-cable-seilaplan.md`](comparaison-cable-seilaplan.md).
- Harnais de mesure et de confrontation : `data-raw/oracle_coldupre.R`,
  `data-raw/oracle_compare.R`.
