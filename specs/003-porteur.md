# specs/003 — Lot 3 : Moteur Porteur (forwarder)

> **Statut** : **validé** (décisions §10 du 2026-07-11, prises sur **lecture du code source**
> Sylvaccess v3.6 : `Sylvaccess_3_forwarder.py` et `sylvaccess_cython3.pyx`, cf. §12).
> **Lot** : 3 (roadmap [`docs/ROADMAP.md`](../docs/ROADMAP.md)). **Epic** : 3 (backlog
> [`docs/BACKLOG.md`](../docs/BACKLOG.md)). **Exigence** : EF-5 ([`docs/PRD.md`](../docs/PRD.md)).
> **Dépend de** : Lot 1 (`preprocess()`), Lot 2 (surface de coût, distance sur piste),
> Lot 7 (tuilage — le porteur en hérite sans travail spécifique).
> **Attribution** : les règles §4 dérivent du code source Sylvaccess (GPL v3) — §12.

---

## 1. Contexte

Le porteur (*forwarder*) est le deuxième moteur terrestre. Il consomme le même jeu de
rasters alignés que le skidder et produit la même forme de sortie — carte d'accessibilité et
distances de débardage. C'est le §4.3 du brief.

La tentation était de le traiter comme un skidder aux seuils différents. **Le code source
l'interdit.** Le porteur n'a ni treuil ni Dijkstra de traînage : sa mécanique est un
**balayage radial depuis le réseau de desserte**, proche de celui du treuillage du skidder,
mais gouverné par la praticabilité de l'engin et non par un câble. Trois contraintes de pente
distinctes — montée, descente, dévers — et une **portée de grappin** de 8 m closent le modèle.

---

## 2. Périmètre

### Dans le périmètre

- Le **balayage radial** de conduite depuis le réseau, avec ses trois contraintes de pente.
- L'accumulateur de **distance en pente forte**, plafonné à `distance_pente_forte_max_m`.
- L'extension au **grappin** (`portee_grue_m`, défaut 8 m).
- La **distance sur piste** (réutilisée du Lot 2) et la distance totale.
- La carte d'accessibilité catégorielle et le tableau récapitulatif.

### Hors périmètre

- Le **treuillage** : le porteur n'en a pas. C'est la différence structurante avec le skidder.
- L'option de modélisation `s_option` : elle n'existe pas pour le porteur (pas de treuillage à
  arbitrer contre la conduite).
- Le calcul du chemin du bois (`f_link_output`) : reporté, comme pour le skidder.
- La carte ONF (`f_onf_class`) : hors MVP.

---

## 3. Entrées / sorties

Entrées identiques au Lot 2 (objet `foretaccess_preprocessing`). Le porteur a ses **propres
obstacles** dans Sylvaccess (`Obstacles_forwarder`), traités comme ceux du skidder : surcoût
additif prohibitif sur la surface de coût, exclusion de la zone roulable.

Sortie : un objet `foretaccess_porteur`, de même structure que `foretaccess_skidder` —
`accessibilite`, `distance_conduite`, `distance_trainage_piste`, `distance_debardage`,
`allocation`, `certifie` (sous tuilage), `recap`. Pas de `distance_treuillage` : le champ n'a
pas de sens ici.

---

## 4. Algorithme

### 4.1 Conversion des pentes en angles

Sylvaccess **convertit toutes les pentes en degrés** avant comparaison
(`Sylvaccess_3_forwarder.py`) :

\deqn{\theta_{max} = \arctan(p_{\%} / 100)}

appliqué aux trois seuils (`pente_montee_max_pct`, `pente_descente_max_pct`,
`pente_travers_max_pct`) et à la pente du terrain (`Pente_deg`). Les comparaisons du §4.2 se
font donc **en degrés**, jamais en pourcentage. C'est un écart de fond avec le skidder, qui
compare en pourcentage.

### 4.2 Balayage radial de conduite (`fwd_azimuts_*`)

Depuis chaque cellule du réseau de desserte, un balayage **360° au pas de 1°**, en ligne
droite, sur des rayons pré-calculés jusqu'à `distance_pente_forte_max_m` (300 m). À chaque
cellule `j` d'un rayon d'azimut `az`, trois filtres, dans l'ordre — le premier qui casse
arrête le rayon (`break`) :

1. **Pente en long, signée par l'altitude.** Le porteur ramène le bois de la cellule `j` vers
   la route, **chargé**. Si `alt_j > alt_route`, le trajet en charge est une **descente** :
   casse si `pente_j > pente_descente_max`. Sinon c'est une **montée** : casse si
   `pente_j > pente_montee_max`. Le code lie ainsi le sens de la contrainte à la différence
   d'altitude, pas à la direction de balayage. **À reproduire tel quel, sans ré-interpréter.**
2. **Inclinaison latérale de l'engin (dévers).**
   \deqn{\Delta = (az - aspect_j) \bmod 180, \quad p_{lat,max} = \left| \frac{\theta_{lat}}{\cos((90 - \Delta)\pi/180)} \right|}
   Casse si `pente_j > p_lat_max`. La géométrie : rouler **dans le sens de la pente**
   (`az` aligné sur l'aspect, `Δ → 0`) donne `cos(90°) = 0`, donc `p_lat_max → ∞` — aucun
   dévers, l'engin est droit. Rouler **en travers** (`Δ → 90`) donne `cos(0°) = 1`, donc
   `p_lat_max = θ_lat` — le dévers est maximal. C'est le basculement latéral de la machine,
   fonction de l'angle entre la trajectoire et la ligne de plus grande pente.
3. **Distance cumulée en pente forte.** Un accumulateur `dpt` s'incrémente de la longueur du
   pas **là où** `pente_j > θ_lat` ; si `dpt + d_slope_route > distance_pente_forte_max_m`, le
   rayon casse. `d_slope_route` est la distance en pente forte déjà consommée pour atteindre
   la cellule de route (portée par le réseau).

La distance retenue en `j` est **3D** : `dist = √(Hdist² + (alt_j − alt_route)²)`. Comme pour
le treuillage, chaque cellule garde la **meilleure** desserte selon un coût composite
`dist + 0.1·d_piste + d_foret` (le `.pyx` mélange distance de conduite, distance sur piste
pondérée, et distance en forêt).

Sylvaccess fait **deux passes** : d'abord depuis le réseau (`fwd_azimuts_forest_roadnet`),
puis depuis le **contour** de la zone déjà atteinte (`fwd_azimuts_contour`), pour propager
au-delà d'un premier front. Les deux partagent le même corps ; la seconde relaie la distance
accumulée. À reproduire, ou à prouver équivalent à une passe unique bien amorcée (§10.4).

### 4.3 Extension au grappin (`fwd_add_hoist`)

Le porteur saisit le bois à `portee_grue_m` (8 m) de l'engin. Depuis le **contour** de la zone
conduite, un front d'onde borné (BFS 8-connexe pondéré par la distance, plafonné à la portée)
étend l'accessibilité de 8 m. C'est l'équivalent porteur du treuillage, mais court et sans
contrainte de câble : une simple portée géométrique. La distance retenue reste la meilleure au
sens du coût composite.

### 4.4 Distance sur piste, et distance totale

La **distance sur piste** est celle du Lot 2 (`Dfwd_flat_forest_tracks`, pondérée par la
pente) : elle est mutualisée, pas réécrite. Le Lot 7 la précalcule globalement, le porteur en
hérite.

\deqn{distance\_debardage = distance\_conduite + distance\_grappin + distance\_trainage\_piste}

### 4.5 Classement

- `parcourable` : forêt, atteinte par la **conduite** (l'engin y roule).
- `accessible` : forêt, atteinte seulement par le **grappin** (l'engin ne roule pas dessus).
- `non_accessible` : forêt, hors de portée.
- `hors_foret` : non forestier.
- `indetermine` (`NA`) : bordures de pente, et cellules non certifiées sous tuilage (Lot 7).

### 4.6 Passage à l'échelle

Le porteur tuile **sans code spécifique** (`traiter_par_tuiles(moteur = porteur)`). Mieux que
le skidder, même : sa portée de conduite est bornée à `distance_pente_forte_max_m` (300 m) et
le grappin à 8 m, donc le halo suffisant est **connu et petit**. La seule propagation non
bornée reste la distance sur piste, déjà précalculée globalement (Lot 7 §4.3.1). Le certificat
du Lot 7 s'applique tel quel.

---

## 5. Critères d'acceptation

- **CA-3.1** Les seuils de pente sont comparés **en degrés** : une pente de 30 % (16,7°) passe
  le seuil montée de 30 % (16,7°) à l'égalité, une pente de 31 % le casse.
- **CA-3.2** Contrainte latérale : sur un plan incliné, un rayon **dans le sens de la pente**
  n'est jamais cassé par le dévers ; un rayon **en travers** l'est dès que la pente dépasse
  `pente_travers_max_pct`. Un rayon oblique casse à un seuil intermédiaire, conforme à la
  formule `θ_lat / cos(90 − Δ)`.
- **CA-3.3** Le sens amont/aval est respecté : sur un versant, la portée en montée et en
  descente diffèrent selon `pente_montee_max_pct` ≠ `pente_descente_max_pct`.
- **CA-3.4** L'accumulateur de pente forte plafonne la conduite : au-delà de
  `distance_pente_forte_max_m` cumulés en pente forte, le rayon s'arrête, même si les filtres
  de pente instantanée passent.
- **CA-3.5** Le grappin étend l'accessibilité d'exactement `portee_grue_m` autour de la zone
  conduite, et ces cellules sont classées `accessible`, non `parcourable`.
- **CA-3.6** La distance retenue est **3D** ; sur un plan incliné, elle dépasse la distance
  planimétrique du facteur `√(1 + (p/100)²)`.
- **CA-3.7** Les obstacles porteur excluent la conduite et reçoivent le surcoût additif.
- **CA-3.8** Le tableau récapitulatif conserve la surface ; ligne `indetermine` explicite.
- **CA-3.9** Sous tuilage, le résultat est identique au mono-bloc (hérité du Lot 7), et le
  halo suffisant vaut `distance_pente_forte_max_m + portee_grue_m + 1,5 × résolution`.

---

## 6. Tests (`testthat`)

- `test-porteur-pente.R` : conversion en degrés (CA-3.1), sens amont/aval (CA-3.3).
- `test-porteur-devers.R` : contrainte latérale selon l'azimut (CA-3.2), les trois régimes.
- `test-porteur-radial.R` : accumulateur de pente forte (CA-3.4), distance 3D (CA-3.6).
- `test-porteur-grappin.R` : extension de 8 m, classement `accessible` (CA-3.5).
- `test-porteur-regles.R` : obstacles (CA-3.7), classement, cas d'erreur.
- `test-porteur-recap.R` : conservation de surface (CA-3.8).
- `test-porteur-tuiles.R` : identité au mono-bloc, halo suffisant (CA-3.9).

**Oracle** : analytique, calibré sur le code source. Le jeu jouet à pente forte du Lot 2
(plan à 60 %) exerce déjà les contraintes de pente ; il faut lui adjoindre un **plan à dévers
variable** pour la contrainte latérale (CA-3.2), déterministe, en mémoire.

---

## 7. Fichiers (proposition)

```
R/porteur.R          → porteur() + classe foretaccess_porteur
R/conduite.R         → balayage radial (fwd_azimuts), contrainte de dévers
R/grappin.R          → extension bornee (fwd_add_hoist)
tests/testthat/…     → cf. §6
```

Le balayage radial de conduite partage l'infrastructure de `.rayons()` du treuillage (rayons
pré-calculés par azimut) : à factoriser, pas à dupliquer. **Aucune nouvelle dépendance.**

---

## 8. Risques & mitigations

| Risque | Mitigation |
|---|---|
| Ré-interpréter le sens amont/aval du filtre de pente | Reproduire le `.pyx` littéralement (§4.2, point 1), test dédié CA-3.3, ne pas « corriger » ce qui semble inversé. |
| La double passe (réseau puis contour) mal reproduite | La prouver équivalente à une passe amorcée, ou la garder telle quelle (§10.4). Oracle : distances d'ensemble. |
| Coût composite `dist + 0.1·d_piste + d_foret` mal transcrit | Valeurs de référence exactes lues dans le `.pyx`, test sur un cas à deux dessertes concurrentes. |
| Duplication avec le treuillage radial | Factoriser `.rayons()` ; le balayage porteur diffère par ses filtres, pas par sa géométrie. |

---

## 9. Definition of Done (Lot 3)

- [ ] `porteur()` livré, documenté, avec balayage radial, dévers, grappin, distances.
- [ ] CA-3.1 à CA-3.9 couverts par des tests (un par règle et par cas d'erreur).
- [ ] Tuilage vérifié : `traiter_par_tuiles(moteur = porteur)` identique au mono-bloc.
- [ ] `lintr` / `testthat` / `R CMD check` OK en CI ; couverture ≥ `main`.
- [ ] Chaînes du code R en **ASCII**.
- [ ] Doc roxygen ; entrée `NEWS.md` ; `PLAN.md` à jour.
- [ ] Branche dédiée + PR ; commits atomiques ; release `v0.5.0` (nouveau moteur).

---

## 10. Décisions (tranchées 2026-07-11, sur lecture du code source)

1. **Pas de Dijkstra pour la conduite** : c'est un **balayage radial** depuis le réseau, comme
   le treuillage. Le service least-cost du Lot 2 ne sert qu'à la distance sur piste. *Renverse
   l'hypothèse « porteur = skidder aux seuils différents ».*
2. **Pas de treuillage** : le porteur a un **grappin** de 8 m, une portée géométrique bornée,
   pas un câble avec contrainte de dégagement.
3. **Comparaisons en degrés** : les pentes sont converties par `arctan(p/100)` avant tout
   test. Écart de fond avec le skidder.
4. **Contrainte latérale dépendante de l'azimut** : `θ_lat / cos(90 − Δ)`, nulle dans le sens
   de la pente, maximale en travers. C'est la signature mécanique du porteur.
5. **Obstacles porteur distincts** : Sylvaccess a `Obstacles_forwarder`, séparés de ceux du
   skidder. À exposer dans `preprocess()` comme une couche d'obstacles propre au moteur, ou à
   réutiliser les obstacles génériques (question §10, non bloquante).

### Dette levée (2026-07-12)

- Le **saut hors forêt** (`distance_hors_desserte_max_m`, `f_dmax_outfor` = 200 m) est
  désormais implémenté dans `.zone_conduite()`, fidèle à `Pente_ok_forwarder` : forêt ∪ saut
  pondéré par la pente sur du terrain récoltable non forestier depuis le contour de la forêt.
  Au passage, un **vrai bug** a été corrigé : la zone bornait la pente par
  `min(travers, montée, descente)` = 15 %, alors que `Zone_OK` de Sylvaccess la borne par le
  **maximum** = 30 % (le balayage affine ensuite par le sens et le dévers). Le `min` excluait
  à tort les cellules roulables en montée dans le sens de la pente.

### Dette assumée restante (Lot 3)

- La **double passe** (`fwd_azimuts_forest_roadnet` puis `fwd_azimuts_contour`, §4.2) reste
  une **passe unique** amorcée depuis le réseau. La seconde passe relaie depuis le contour de
  la zone atteinte, ce qui étend la portée par zigzag (le porteur contourne un dévers en
  combinant une direction quasi-parallèle à la pente puis une direction dans le sens de la
  pente). Elle a été prototypée puis retirée : sur un plan uniforme elle rend le dévers non
  bloquant pour la *portée* (seulement pour la *distance*), et sans oracle Sylvaccess réel,
  son comportement exact — notamment le modèle de distance en composantes séparées
  (`Dpente`/`Dfor`/`Dpis`) — ne peut être validé sur les fixtures synthétiques. À reprendre
  quand une sortie Sylvaccess v3.6 de référence sera disponible.

### Questions restantes (non bloquantes)

6. **Double passe** (réseau puis contour) : la reproduire, ou prouver qu'une passe unique bien
   amorcée suffit. À trancher à l'implémentation, avec l'oracle d'ensemble.
7. **Coût composite** `dist + 0.1·d_piste + d_foret` : en vérifier la transcription exacte sur
   un cas à dessertes concurrentes avant de le figer.

---

## 11. Découpage du lot

- **3a** — balayage radial de conduite (pente signée, dévers, accumulateur pente forte),
  distance 3D, sans grappin. Le cœur, testable seul.
- **3b** — grappin, classement complet, distances totales, récap, tuilage.

---

## 12. Attribution

Les règles §4 dérivent du code source Sylvaccess v3.6 (`Sylvaccess_3_forwarder.py`,
`sylvaccess_cython3.pyx` : `fwd_azimuts_forest_roadnet`, `fwd_azimuts_contour`,
`fwd_add_hoist`), distribué sous GPL v3. ForêtAccess est distribué sous GPL v3 (règle 4 de
`CLAUDE.md`).
