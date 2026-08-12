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

## 6. Ce qu'il faudrait instruire

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
