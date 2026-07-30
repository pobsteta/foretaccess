# specs/024 — CL_SVAC sur la règle ACCESSFOR **publiée** (fin du calage empirique)

> **Statut** : **VALIDÉE — IMPLÉMENTÉE** (décisions utilisateur du 2026-07-29 :
> suivre la table publiée, ajouter la route forestière nommée ; MNT LiDAR HD et
> zonages INPN **conservés** comme écarts assumés ; contraintes d'intégrité
> renvoyées en [spec 025](025-integrite-reseau-desserte.md)). Version `1.28.0`
> (mineure : `classification = "clsvac"` reste accessible, la rétro-compatibilité
> est à un argument près). Fait suite à la spec
> [022](022-desserte-clsvac-obstacles-accessfor.md), dont elle corrige
> l'hypothèse fondatrice.
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
- Le banc oracle `aoi` doit être ré-exporté **et** Sylvaccess relancé, sinon la
  confrontation compare deux réseaux différents. (Le banc `aoi-ugf` a été
  abandonné le 2026-07-29, cf. `PLAN.md`.)
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
- Les tronçons CL_SVAC = 0 sont marqués `hors_desserte` puis **retirés** de la
  couche rendue (`garder_hors_desserte = TRUE` pour les inspecter). Ils ne sont
  **pas** ajoutés à `.classes_desserte()` : `.rasteriser_desserte()` code les
  classes par leur **rang** et prend le `max` — la barrière l'emporte — donc une
  5ᵉ classe passerait devant `reseau_public`. C'est aussi ce que fait ACCESSFOR,
  dont la couche Sylvaccess ne contient que les classes 1/2/3.
- Couche liée **`route_numerotee_ou_nommee`** interrogée pour récupérer les
  routes forestières nommées ; absente ou vide → pas de reclassement, sans échec.
- Les deux contraintes d'intégrité : **vérifiées et rapportées** (combien de
  classes 1 orphelines, combien de classes 2 non connectées à une 3), **pas**
  corrigées automatiquement dans un premier temps — ACCESSFOR y a mis de la
  retouche manuelle, on ne va pas inventer une heuristique silencieuse.

## 6. Décisions prises (2026-07-29)

1. **`"accessfor"` est le défaut.** C'est la règle de production publiée.
2. **Bump mineur `1.28.0`**, pas majeur : `classification = "clsvac"` et
   `"heuristique"` restent accessibles, la rétro-compatibilité tient en un
   argument. À rehausser en `2.0.0` sur simple demande.
3. **Contraintes d'intégrité** : sorties de cette spec, traitées en
   [spec 025](025-integrite-reseau-desserte.md) — automatisation par
   élargissement adaptatif du buffer + `dsr_reseau()`.
4. **Écarts assumés, non corrigés** : MNT LiDAR HD (au lieu du RGE Alti 5 m) et
   zonages INPN/Patrinat avec APB + réserve intégrale de PN (au lieu de
   `PARC_OU_RESERVE` filtré sur `NAT_DETAIL`). Décision utilisateur.
5. **Les bancs oracle** : Sylvaccess se relance à la main
   (`0_Lance_sylvaccess.py -file <banc>/param*.csv`), hors de portée d'ici.

## 7. Critères d'acceptation

- [x] **CA-24.1** — `acquire_desserte(classification = "accessfor")` reproduit la
      table de l'annexe p. 51 à la lettre, y compris la classe 0.
- [x] **CA-24.2** — Rétro-compat : `"clsvac"` et `"heuristique"` inchangées,
      bit-pour-bit.
- [x] **CA-24.3** — Les routes forestières nommées sont récupérées via la couche
      liée ; absence de la couche = dégradation silencieuse, pas d'erreur.
- [ ] **CA-24.4** — Les contraintes d'intégrité sont mesurées et publiées sur
      l'AOI oracle. *Déplacé en spec 025.*
- [x] **CA-24.5 (juge de paix) — ATTEINT** (2026-07-29, AOI Chastel-Nouvel,
      608,5 ha comparés) :

      | | v1.20.0 `clsvac` | v1.28.0 `accessfor` | |
      |---|---|---|---|
      | skidder, 9 classes | 77,1 % | **81,5 %** | +4,4 pts |
      | skidder, agrégé | ~81 % | **88,3 %** | **+7,3 pts** |
      | porteur, 9 classes | — | 89,3 % | |
      | porteur, agrégé | — | 92,0 % | |

      Le gain est plus fort sur l'**agrégé** que sur les 9 classes : cohérent,
      faire de 49 tronçons une barrière change d'abord la décision
      accessible/inaccessible, pas le rangement en bandes.

      **L'artefact de masque est écarté** : entre les variantes `défaut` et
      `MASQUE-FORETV3`, l'accord ne bouge que de 0,3 pt (skidder) et 0,1 pt
      (porteur), alors que l'emprise change beaucoup (« ACCESSFOR hors notre
      forêt » : 3,9 → 28,0 ha). Les désaccords résiduels ne viennent pas du
      masque forêt.

      **Résidus expliqués : c'est le MNT** (mesure du 2026-07-30,
      `data-raw/diag_residu_mnt.R`). Protocole : rejouer chaque moteur à entrées
      **strictement identiques**, en ne changeant que le MNT — LiDAR HD contre
      les dalles départementales RGE Alti d'ACCESSFOR.

      | | skidder | porteur |
      |---|---:|---:|
      | flips « nous inaccessible / eux accessible » | 22,3 ha | 29,7 ha |
      | dont déplacés par le seul changement de MNT | **16,3 ha (73 %)** | **27,6 ha (93 %)** |
      | effet net sur la surface accessible | +3,7 ha | +13,7 ha |

      Notre MNT LiDAR HD, plus fin, crée des **micro-barrières** que le RGE Alti
      lisse. L'effet n'est pas symétrique en accessibilité même quand le
      désaccord *par cellule* l'est : une cellule bloquée condamne tout ce qui
      est derrière elle.

      Le résidu n'est donc **pas un défaut** mais la conséquence mesurée de
      l'**écart n° 4**, assumé (§6.4). L'accord plafonnera tant qu'ACCESSFOR
      restera sur le RGE Alti — que son propre rapport (p. 16) annonce comme
      remplacé à brève échéance par le LiDAR HD.

      **Hypothèses écartées en chemin** : les composantes orphelines (réfutées,
      spec 025 — aucune infraction dans l'AOI stricte) et une non-monotonie
      supposée du porteur (**inexistante** : artefact d'un bug de comptage,
      Sylvaccess passant de 133,8 à 263,8 ha quand on relâche `f_slope_up` de
      30 à 50 %).

## 8. Ce que ça n'est PAS

- Pas un changement des moteurs (règle 1) : seule la classification d'entrée bouge.
- Pas la conformité des **obstacles** ni du **masque forêt** : écarts mécaniques
  du même rapport, corrigés séparément (PR #132, cycle dev).
- Pas une reprise du LiDAR (specs 020/021/023) : `qualifier_desserte()` continue
  de corriger la desserte **après** classification.

## 9. Sources

- Rapport final ACCESSFOR, février 2025 — corps §2.3.2 (définition des trois
  classes) et **annexe p. 51-52** (table `NATURE` → CL_SVAC, contraintes).
- `specs/022` §3.2-3.4 (l'hypothèse corrigée ici), `R/acquire-ign.R`
  (`.mapper_classe_desserte()`).
