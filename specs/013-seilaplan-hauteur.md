# specs/013 — Optimisation de la hauteur des supports façon SEILAPLAN (Bont & Heinimann 2012)

> **Statut** : **proposé** (2026-07-16). Remplace le chantier `c_option_h` transcrit
> de Sylvaccess (`OptPyl_Up`/`OptPyl_Up2`), **shelvé** car bugué (réduit la couverture)
> et lent (~20× le `_NoH`) — cf. `PLAN.md` (journal 16/07), `specs/004` (§ Statut
> c_option_h).
> **Exigence** : fidélité du moteur câble (levier : optimisation de la hauteur).
> **Dépend de** : Lot 4 (noyau câble Rust `cablehelp` : caténaire Newton/Irvine,
> `test_span`, faisabilité de travée), Lot 5 (sélection de lignes, à terme).
> **Référence de conception** : `docs/comparaison-cable-seilaplan.md`.

---

## 1. Contexte et décision

L'optimisation de la hauteur de fixation des supports est une **dette du Lot 4**. Deux
voies :

1. **Transcrire `OptPyl_Up`/`Up2` de Sylvaccess** (`c_option_h=1`). *Tentée et
   abandonnée* : le port réduit la couverture (net −999) au lieu de l'augmenter (oracle
   +470), il est ~20× plus lent, et le **code d'origine plante lui-même** (bug de
   tampon `Tab`, chemin jamais exercé sur un vrai jeu — voilà pourquoi le défaut v3.6
   est `false`). L'heuristique de faisceau `get_Tabis` est fragile et dépendante de
   l'ordre.

2. **Transcrire SEILAPLAN** (algorithme **Bont & Heinimann 2012**). *Voie retenue.*
   Publié, validé contre des mesures (Bont et al. 2022), open-source (GPL,
   <https://github.com/piMoll/SEILAPLAN>). Il pose le problème comme un **graphe** —
   plus court chemin, donc **polynomial et déterministe**, sans l'explosion du double
   balayage `Hg×Hd`.

**Décision** : coder l'optimisation position+hauteur des supports **à la SEILAPLAN**,
en **réutilisant notre mécanique caténaire** (Newton/Irvine déjà validée à l'oracle),
et non celle de Zweifel. On découple *optimisation* (nouvelle) et *mécanique*
(inchangée).

---

## 2. Le modèle SEILAPLAN (Bont & Heinimann 2012)

D'après Bont et al. (2022, §3.2) — **à confirmer/préciser sur le papier B&H 2012 et le
source du plugin** (cf. §5 Prérequis) :

Le problème « placer les supports intermédiaires (position **et** hauteur) qui
minimisent leur **nombre** puis leur **hauteur** » est représenté comme un **graphe
orienté acyclique** sur le profil de terrain :

- **Nœuds** : positions candidates de support le long du profil, discrétisées au pas
  `δl ≈ 10 m`, chacune déclinée en hauteurs candidates au pas `δh ≈ 1 m`
  (de `hline_min` à une hauteur max). Plus le mât (départ) et l'ancrage (arrivée),
  hauteurs fixées.
- **Arêtes** : une arête relie deux nœuds consécutifs `(pos_i, h_i) → (pos_j, h_j)` si
  la **travée** entre eux est **faisable** — vérifiée par la mécanique caténaire :
  1. garde au sol ≥ minimum (`hline_min..hline_max`) ;
  2. tension du câble ≤ admissible (`Tmax`) ;
  3. gradient minimal du câble respecté (cas gravitaire).
  Le **coût** d'une arête encode la préférence : d'abord *nombre* de supports (chaque
  support intermédiaire = +1), puis *hauteur* (départage lexicographique ou coût
  pondéré `nb·K + Σ hauteurs`).
- **Solution** : le **plus court chemin** (Dijkstra / DAG shortest-path) de l'ancrage
  amont à l'ancrage aval minimise nombre puis hauteur des supports.

Contraintes vérifiées au niveau global (Fig. 2 du papier) : (I) garde au sol min,
(II) tension admissible non dépassée, (III) gradient minimal (gravité).

**Réglages** : `δl ≈ 10 m`, `δh ≈ 1 m` (recommandés B&H 2012). Exposés en config.

---

## 3. Périmètre et frontières

**Ce qu'on garde (inchangé, déjà validé)** :
- La **caténaire** Newton/Irvine (`cablehelp::newton`, `catenaire`) et le test de
  faisabilité d'une travée `test_span` (garde au sol via `calcul_zs`, tension `Tmax`,
  bornes de pente). C'est lui qui décide si une arête existe.
- L'orchestration R (`potentiel_cable`), le balayage 360°/pixel, la couverture, le
  pêchage latéral, `check_line` (validité géométrique de la ligne).

**Ce qu'on remplace** :
- Le placement des supports `OptPyl_*` (faisceau `get_Tabis`) → **graphe + plus court
  chemin** à la B&H, avec optimisation de la hauteur.

**Ce qui reste hors périmètre** :
- La mécanique de **Zweifel** (on ne la porte pas ; on garde Irvine).
- La **friction** au sabot (absente de Sylvaccess v3.6 comme de notre port ; SEILAPLAN
  l'a, effet mineur et conservateur — décision séparée si un jour souhaité).
- La **sélection de lignes** (Lot 5) et le dimensionnement des arbres-supports (DBH).

---

## 4. Décisions à trancher (avant implémentation)

1. **Remplacement ou coexistence ?** Le graphe B&H remplace-t-il `OptPyl` **partout**
   (y compris `c_option_h=0`, hauteur fixe = un seul niveau `δh`), ou seulement quand
   l'utilisateur active l'optimisation de hauteur ? *Recommandation* : un sélecteur
   `cable$methode_supports = c("sylvaccess", "seilaplan")` ; `sylvaccess` reste le
   défaut (fidélité ColduPre garantie), `seilaplan` active le graphe. Le flag
   expérimental `optimiser_hauteur_fixation` est **retiré** (remplacé).
2. **Coût des arêtes** : lexicographique (nombre puis hauteur) ou pondéré (`nb·K + Σh`) ?
   À caler sur B&H 2012.
3. **Machine en haut / en bas** : le graphe traite-t-il les deux sens par retournement
   du profil (comme aujourd'hui) ? *A priori oui*, le graphe est symétrique.
4. **Coupe de ligne** : quand aucun chemin ancrage→ancrage n'existe, couper au plus
   loin atteignable (comme `OptPyl`) — nœud puits = position la plus lointaine reliée.
5. **Rust ou R ?** Le graphe (nœuds ≤ `L/δl × H/δh`, arêtes = travées faisables) reste
   petit ; l'implémenter en **Rust** dans `cablehelp` (à côté de `optpyl.rs`), appelé
   par `cable_scan`, cohérent avec ADR-003 (frontière minimale).

---

## 5. Prérequis (à faire avant de coder)

1. **Obtenir Bont & Heinimann (2012)**, *Optimum geometric layout of a single cable
   road*, Eur. J. For. Res. 131(5):1439-1448 — pour la formulation exacte du graphe
   (coûts, contraintes, gestion du gradient gravitaire).
2. **Lire le source SEILAPLAN** (module d'optimisation, `github.com/piMoll/SEILAPLAN`,
   sous-dossier hors `gui/`) : l'algorithme y est en Python/NumPy, lisible. Identifier
   la construction du graphe et le solveur.
3. **Banc de référence** : réutiliser l'oracle `c_option_h=true` déjà régénéré
   (`data-raw/oracle/coldupre/sylvaccess_hopt/`, cf.
   [[regenerer-oracle-sylvaccess]]) **comme repère de direction** (la couverture doit
   *augmenter*), et — idéalement — **exécuter SEILAPLAN** sur quelques profils pour
   comparer position/hauteur des supports ligne à ligne.

---

## 6. Critères d'acceptation

- **CA-13.1** : sur un profil manufacturé où un support abaissé rend une travée
  faisable, le graphe trouve la solution ; test `cargo` déterministe.
- **CA-13.2** : à hauteur fixe (`δh` = un seul niveau), le graphe reproduit le
  placement de position de `OptPyl_NoH` (non-régression : mêmes lignes que le défaut
  actuel sur un jeu de profils témoins).
- **CA-13.3** : **direction correcte** — sur ColduPre, activer l'optimisation de
  hauteur **augmente** la couverture câble vs le `_NoH` (contrairement au port
  `OptPyl_Up2` shelvé qui la réduisait), et se rapproche de l'oracle `c_option_h=true`
  (+470 cellules attendues), sans excès de trop-optimiste au-delà du corollaire connu
  (absence de sélection de lignes, Lot 5).
- **CA-13.4** : **perf** — le balayage complet reste du même ordre que le `_NoH`
  (objectif : < 5× le `_NoH`, contre ~20× pour `OptPyl_Up2`).
- **CA-13.5** : si SEILAPLAN est exécutable, **comparaison ligne à ligne** sur ≥ 3
  profils (position et hauteur des supports, faisabilité) — écart documenté.

---

## 7. Découpage

- **13a** — graphe + plus court chemin en Rust (`cablehelp`), réutilisant `test_span`
  comme oracle de faisabilité d'arête ; tests `cargo` (CA-13.1, CA-13.2).
- **13b** — câblage `cable_scan` / config (`methode_supports`), sens haut/bas, coupe ;
  confrontation ColduPre (CA-13.3, CA-13.4).
- **13c** — comparaison ligne à ligne à SEILAPLAN (CA-13.5) ; retrait du flag
  `optimiser_hauteur_fixation` expérimental et du code `OptPyl_Up2` shelvé.

---

## 8. Definition of Done

- [ ] Graphe B&H implémenté en Rust, réutilisant la caténaire existante.
- [ ] Non-régression : à hauteur fixe, mêmes lignes que le `_NoH` (CA-13.2).
- [ ] Sur ColduPre, l'optimisation de hauteur **augmente** la couverture (CA-13.3) et
      la perf reste raisonnable (CA-13.4).
- [ ] `docs/comparaison-cable-seilaplan.md` et `specs/004` (§ Statut c_option_h) mis à
      jour (renvoi vers ce spec, retrait de la dette).
- [ ] Le code `OptPyl_Up2` shelvé et son flag sont retirés (ou explicitement conservés
      en annexe si utile).
- [ ] `PLAN.md` à jour (dette câble → résolue par la voie SEILAPLAN).

---

## 9. Risques

- **Algorithme mal transcrit** : le graphe B&H a des subtilités (gestion du gradient
  gravitaire, coût lexicographique). Mitigé par la lecture du source SEILAPLAN et la
  comparaison ligne à ligne (CA-13.5).
- **Pas d'oracle exact** : SEILAPLAN (B&H) ≠ Sylvaccess (`OptPyl_Up2`) — on ne cherche
  pas l'égalité cellule à cellule avec l'oracle `c_option_h=true`, mais la **bonne
  direction** (couverture en hausse) et l'accord ligne à ligne avec SEILAPLAN.
- **Divergence de mécanique** : SEILAPLAN utilise Zweifel, nous Irvine — les seuils de
  faisabilité d'arête diffèrent légèrement. Documenté comme écart assumé (cf.
  `docs/comparaison-cable-seilaplan.md`).
