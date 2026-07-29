# specs/025 — Contraintes d'intégrité du réseau de desserte, automatisées

> **Statut** : **VALIDÉE — À IMPLÉMENTER** (décisions §7 prises par l'utilisateur
> le 2026-07-29). Complète la spec
> [024](024-desserte-clsvac-regle-publiee.md) : celle-ci pose la **classification**
> ACCESSFOR, celle-là les **contraintes de connectivité** qui l'accompagnent.
> Version cible : `1.29.0` (feat, nouvelle sortie de diagnostic).
> **Source** : rapport ACCESSFOR, annexe p. 51, « Contrainte sur l'attribut
> CL_SVAC ».

## 1. Le problème que ça résout

L'annexe impose deux contraintes, sans dire comment les faire respecter :

> - La classe 1 doit être connectée à 2 ou 3
> - La classe 2 doit être connectée à 3

Elles ne sont pas décoratives. Elles expriment la **sémantique du modèle** : une
piste dont le bois ne peut atteindre aucune route est un cul-de-sac où le
débardage n'aboutit pas ; une route forestière qui ne rejoint aucun réseau public
n'a pas de point de chargement camion. Un réseau qui viole ces contraintes produit
des surfaces déclarées accessibles qui ne le sont pas.

ACCESSFOR les a fait respecter par **un script FME plus des retouches manuelles**
(annexe p. 51 : « des modifications manuelles ont été opérées le cas échéant »).
C'est précisément ce qui rend la conformité à 100 % structurellement hors
d'atteinte : leur couche porte des corrections humaines non reproductibles.

**Nous ne vérifions rien du tout aujourd'hui.**

## 2. Pourquoi une violation apparaît

Trois causes, de nature très différente, qu'il faut séparer avant de corriger
quoi que ce soit :

1. **Effet de bord.** Une piste connectée à une route située **hors de l'AOI**
   paraît orpheline. C'est un artefact de découpe, pas un défaut de donnée. Notre
   `acquire_inputs(buffer_m = 100)` élargit déjà l'emprise, mais 100 m ne suffit
   pas à garantir qu'on capte la route de rattachement.
2. **Défaut topologique.** Extrémités non nodées, écarts décimétriques,
   tronçons dupliqués en parallèle. La découpe sur l'AOI en fabrique aussi.
3. **Cul-de-sac réel.** Le réseau ne rejoint véritablement rien. C'est une
   information, pas une erreur — et la corriger automatiquement serait mentir.

Confondre les trois, c'est soit rafistoler des données saines, soit masquer un
vrai trou de desserte.

## 3. Ne pas réimplémenter : `dsr_reseau()`

**dessertR fait déjà le travail** (règle stricte 1 : on consomme, on ne
réimplémente pas). `dsr_reseau(traces, tol_noeud, largeur_dedupe, reseau_public,
tol_public)` :

- colle les nœuds partagés (`dsr_coller_noeuds()`, tolérance en mètres) ;
- déduplique les parallèles ;
- calcule les **composantes connexes** ;
- pose `connecte_public` **par arête** quand on lui passe le réseau public ;
- rend un `resume` avec le nombre de composantes et la **longueur non rattachée**.

Sa documentation énonce exactement notre besoin : « Une desserte qui ne rejoint
pas le réseau public est signalée comme artefact probable. »

C'est aussi cohérent avec le Lot 17, où le graphe de flux avait été fait en base R
faute de pouvoir installer `igraph`/`sfnetworks`. Ici la dépendance est portée par
dessertR, déjà optionnelle et déjà installée hors renv.

`dsr_reseau()` rend un `graphe` igraph, donc `igraph` est requis sur ce chemin.
**Installé le 2026-07-29 hors renv** (lib globale 4.6), comme dessertR :
dépendance optionnelle non déclarée, accédée dynamiquement. La CI n'exerce pas ce
chemin ; sans `igraph` le diagnostic se dégrade proprement.

## 4. Proposition — diagnostiquer d'abord, corriger ensuite

### 4.1. `verifier_integrite_desserte()` (nouvelle fonction exportée)

Prend la sortie d'`acquire_desserte(classification = "accessfor")`, rend un objet
de diagnostic :

- par tronçon : `composant`, `connecte_public`, et **`viole_contrainte`** —
  classe 1 sans 2/3 dans sa composante, ou classe 2 sans 3 ;
- un `resume` : nombre et longueur de tronçons en infraction, par classe ;
- un **verdict par cause probable** : `bord_aoi` (la composante touche le bord de
  l'emprise), `topologie` (l'infraction disparaît quand on relâche `tol_noeud`),
  `reel` (ni l'un ni l'autre).

C'est la distinction du §2 rendue mesurable. **Aucune modification de la donnée.**

### 4.2. Le levier du buffer — élargissement adaptatif

L'idée proposée par l'utilisateur, rendue systématique. On ne devine pas un
buffer : on le fait **converger**.

```
b <- buffer_initial            # 100 m
repeter :
  classer la desserte sur AOI + b
  mesurer L(b) = longueur en infraction, ramenee a l'AOI STRICTE
  si L(b) cesse de decroitre (< seuil_gain) ou b > buffer_max : arreter
  b <- b * facteur             # 2x
```

Deux points qui font la validité de la méthode :

- **La mesure se fait toujours sur l'AOI stricte.** Sinon élargir ajoute du
  réseau, donc des infractions, et la suite ne converge pas.
- **La décroissance de `L(b)` sépare les causes** : ce qui disparaît en
  élargissant était un effet de bord ; ce qui **résiste** à un buffer large est
  soit topologique, soit réel. La courbe `L(b)` est le diagnostic.

Coût : chaque itération est une requête WFS sur une emprise croissante. Avec un
doublement et un plafond à ~3 km, c'est 5-6 requêtes. Acceptable, et cachable.

### 4.3. Les remédiations, par ordre de violence croissante

Rien n'est appliqué sans que l'utilisateur l'ait demandé.

| niveau | action | risque |
|---|---|---|
| 0 | rapporter seulement (**défaut**) | nul |
| 1 | élargir le buffer jusqu'à convergence | nul sur la donnée, coût réseau |
| 2 | recoller les nœuds (`tol_noeud`, défaut 1 m) | faible ; peut fusionner deux voies réellement distinctes |
| 3 | retirer les composantes en infraction résiduelle | **fort** — supprime du réseau réel si le diagnostic se trompe |

Le niveau 3 est ce qu'ACCESSFOR a fait à la main. **Je ne recommande pas de
l'automatiser par défaut** : sur une donnée où le diagnostic confond « cul-de-sac
réel » et « artefact », il retire silencieusement de la desserte existante. À
réserver à un opt-in explicite, et à ne juger qu'après avoir vu la courbe `L(b)`
sur plusieurs AOI.

## 5. Ce que ça n'est PAS

- Pas une reprise de la classification (spec 024).
- Pas une correction géométrique de la BD TOPO : on ne déplace aucun tronçon,
  on colle au plus des extrémités déjà quasi coïncidentes.
- Pas une garantie de conformité à la **couche** ACCESSFOR : leurs retouches
  manuelles ne sont pas reproductibles. Au mieux on converge vers leur *notice*.

## 6. Critères d'acceptation

- [ ] **CA-25.1** — `verifier_integrite_desserte()` rend, par tronçon,
      `composant` / `connecte_public` / `viole_contrainte`, et un `resume`
      chiffré. Sans `dessertR`, dégradation propre (diagnostic vide + message),
      jamais d'échec.
- [ ] **CA-25.2** — La cause probable (`bord_aoi` / `topologie` / `reel`) est
      attribuée à chaque infraction.
- [ ] **CA-25.3** — L'élargissement adaptatif mesure `L(b)` **sur l'AOI stricte**
      et s'arrête sur convergence ou plafond ; la courbe est retournée.
- [ ] **CA-25.4** — Sur l'AOI oracle : publier `L(b)`, et la part des infractions
      imputables au bord. C'est le chiffre qui dira si le buffer suffit.
- [ ] **CA-25.5** — Le niveau 2 (recollage) n'est jamais appliqué sans demande
      explicite, et le niveau 3 (suppression) n'existe pas dans le code.
- [ ] **CA-25.6** — Les infractions `reel` portent une colonne de marquage, et
      `preprocess()` sait les écarter sur option (défaut : les conserve).

## 7. Décisions prises (2026-07-29)

1. **Niveaux 0-1 par défaut, 2 sur demande.** Diagnostic + élargissement adaptatif
   par défaut ; recollage des nœuds (`tol_noeud`) sur demande explicite. **Le
   niveau 3 n'est pas implémenté** : aucune suppression automatique de composante.
2. **`buffer_max` = 3 km** (décision de ma part, révisable) : au-delà on
   téléchargerait un département pour rattacher une piste.
3. **`igraph` installé hors renv**, comme dessertR. Fait.
4. **Infractions `reel` : laissées dans la desserte, mais MARQUÉES.** Une colonne
   les signale, pour que `preprocess()` puisse les écarter **sur option** et
   qu'on puisse chiffrer leur poids. Statu quo par défaut dans les moteurs : on
   ne retire pas une information terrain potentiellement juste, mais on cesse de
   la subir en aveugle.

## 8. Sources

- Rapport ACCESSFOR, annexe p. 51 (« Contrainte sur l'attribut CL_SVAC », script
  FME + retouches manuelles).
- `dessertR` : `?dsr_reseau`, `?dsr_coller_noeuds`, `?dsr_sfnetwork`.
- `specs/024` (classification), `specs/017` (graphe de flux en base R).
