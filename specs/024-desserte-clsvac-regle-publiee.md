# specs/024 — CL_SVAC sur la règle ACCESSFOR **publiée** (fin du calage empirique)

> **Statut** : **PROPOSÉE** — décisions §6 à prendre. Fait suite à la spec
> [022](022-desserte-clsvac-obstacles-accessfor.md), dont elle corrige
> l'hypothèse fondatrice. Version cible : `1.28.0` (feat, changement de
> classification) ou `2.0.0` si l'on juge la sortie `classe` rompue.
> **Source** : rapport final ACCESSFOR (INRAE/IGN/ADEME, février 2025),
> `docs/rapport_final_accessfor_vf_fev2025.pdf`, **annexe p. 51-52**.

## 1. Le problème que ça résout

La spec 022 §3.4 posait noir sur blanc :

> La correspondance exacte `nature`/`importance` → CL_SVAC n'est **pas publiée**
> telle quelle par ACCESSFOR (ils décrivent les 3 classes, pas la table de mapping
> BD Topo). À **caler empiriquement** contre la couche ACCESSFOR (maximiser
> l'accord), puis documenter.

**Cette hypothèse est fausse.** L'annexe du rapport final publie la table, dans
une notice opérationnelle destinée à être reproduite (« applicable à la fois pour
la production des cartes génériques sur toute la France par l'IGN mais aussi sur
des zones spécifiques par des acteurs locaux », §3.1.1).

Notre `clsvac` (v1.20.0) est donc un **calage empirique contre une sortie**, là où
la **règle de production** est disponible. Il en diverge sur 42 % des tronçons de
l'AOI oracle.

## 2. La règle publiée (annexe p. 51)

CL_SVAC se déduit de l'attribut **`NATURE` seul** — `importance` n'y figure pas :

| `NATURE` | CL_SVAC |
|---|---|
| Route à 2 chaussées | 3 (réseau public) |
| Route à 1 chaussée | 3 (réseau public) |
| Route empierrée | 2 (route forestière) |
| *Route forestière nommée* (couche liée) | 2 (route forestière) |
| Chemin | 1 (piste forestière) |
| **tout le reste** (dont Sentier, Rond-point) | **0 — hors desserte** |

La « Route forestière nommée » ne vient pas de `NATURE` : elle se récupère sur la
couche liée **« Route numérotée ou nommée »**, modalité `Route forestière nommée`
de l'attribut `Type de route`.

Deux **contraintes d'intégrité** accompagnent la table :

- la classe 1 doit être connectée à une classe 2 ou 3 ;
- la classe 2 doit être connectée à une classe 3.

ACCESSFOR les a fait respecter par un script FME + des retouches manuelles.

## 3. L'écart mesuré (AOI oracle, Chastel-Nouvel, 256 tronçons)

| `NATURE` | n | ACCESSFOR | nous (`clsvac` v1.20.0) | |
|---|---:|---|---|---|
| Route à 1 chaussée | 49 | **3** réseau public | 2 route forestière | ✗ |
| Route empierrée | 45 | 2 | 2 | ✓ |
| Chemin | 103 | 1 | 1 | ✓ |
| Sentier | 59 | **0** hors desserte | 1 piste | ✗ |

**108 / 256 tronçons (42 %) divergent.** Deux causes :

1. **Notre `reseau_public` est piloté par `importance ≤ 3`**, jamais atteint ici :
   les « Route à 1 chaussée » de l'AOI ont `importance` 4 (11) ou 5 (38). Notre
   AOI compte donc **0 `reseau_public`** là où la règle publiée en produit **49**.
   Or `reseau_public` est la **barrière/terminus** du traînage — c'est le levier
   le plus structurant du modèle skidder.
2. **Nous n'avons pas de classe 0.** Les 59 sentiers deviennent des pistes
   praticables, donc du linéaire de traînage qui n'existe pas.

## 4. Ce que ça change en aval

- `preprocess()` reçoit une desserte au `classe` différent → **tous** les moteurs
  terrestres bougent. Non-régression Sylvaccess à rejouer intégralement.
- Les bancs oracle (`aoi`, `aoi-ugf`) doivent être ré-exportés **et** Sylvaccess
  relancé, sinon la confrontation compare deux réseaux différents.
- `places_depot()` : plus de `reseau_public` = moins de départs lâches, l'effet
  recherché depuis la spec 004.
- L'accord ACCESSFOR (77,1 % en 9 classes après v1.20.0) devrait progresser ; la
  spec 022 avait identifié la classification comme **le** driver du biais de
  distance. C'est le juge de paix de cette spec.

## 5. Proposition

- `.mapper_classe_desserte()` gagne une classification **`"accessfor"`**,
  transcrite de l'annexe **à la lettre** (mémoire : *Sylvaccess, la lettre pas
  l'intention*), qui devient le défaut. `"clsvac"` (calage empirique) et
  `"heuristique"` (historique) restent accessibles pour la rétro-compatibilité et
  la comparaison.
- Nouvelle classe **`hors_desserte`** dans `.classes_desserte()`, exclue de la
  desserte transmise à `preprocess()` — à distinguer d'une absence de tronçon.
- Couche liée **`route_numerotee_ou_nommee`** interrogée pour récupérer les
  routes forestières nommées ; absente ou vide → pas de reclassement, sans échec.
- Les deux contraintes d'intégrité : **vérifiées et rapportées** (combien de
  classes 1 orphelines, combien de classes 2 non connectées à une 3), **pas**
  corrigées automatiquement dans un premier temps — ACCESSFOR y a mis de la
  retouche manuelle, on ne va pas inventer une heuristique silencieuse.

## 6. Décisions à prendre

1. **`"accessfor"` par défaut ?** Oui à mon sens : c'est la règle de production
   publiée, notre `clsvac` n'était qu'un proxy faute de mieux.
2. **Bump** : `1.28.0` (feat) ou `2.0.0` ? La sortie `classe` d'`acquire_desserte()`
   gagne une modalité et 42 % des tronçons changent de valeur — défendable en
   majeur. **Demande confirmation** (règle CLAUDE.md).
3. **Les contraintes d'intégrité** : rapportées seulement, ou appliquées ?
4. **Les bancs oracle** : qui relance Sylvaccess ? Sans ça la validation §7 est
   impossible.

## 7. Critères d'acceptation

- [ ] **CA-24.1** — `acquire_desserte(classification = "accessfor")` reproduit la
      table de l'annexe p. 51 à la lettre, y compris la classe 0.
- [ ] **CA-24.2** — Rétro-compat : `"clsvac"` et `"heuristique"` inchangées,
      bit-pour-bit.
- [ ] **CA-24.3** — Les routes forestières nommées sont récupérées via la couche
      liée ; absence de la couche = dégradation silencieuse, pas d'erreur.
- [ ] **CA-24.4** — Les contraintes d'intégrité sont mesurées et publiées sur
      l'AOI oracle.
- [ ] **CA-24.5 (juge de paix)** — accord 9 classes vs ACCESSFOR **supérieur** aux
      77,1 % de la v1.20.0, biais de distance non dégradé. Sinon, la règle
      publiée ne décrit pas la couche diffusée et il faut le documenter.

## 8. Ce que ça n'est PAS

- Pas un changement des moteurs (règle 1) : seule la classification d'entrée bouge.
- Pas la conformité des **obstacles** ni du **masque forêt** : écarts mécaniques
  du même rapport, traités séparément (voir NEWS `1.27.1`).
- Pas une reprise du LiDAR (specs 020/021/023) : `qualifier_desserte()` continue
  de corriger la desserte **après** classification.

## 9. Sources

- Rapport final ACCESSFOR, février 2025 — corps §2.3.2 (définition des trois
  classes) et **annexe p. 51-52** (table `NATURE` → CL_SVAC, contraintes).
- `specs/022` §3.2-3.4 (l'hypothèse corrigée ici), `R/acquire-ign.R`
  (`.mapper_classe_desserte()`).
