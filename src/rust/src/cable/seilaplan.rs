//! Optimisation de la hauteur des supports facon SEILAPLAN (spec 013).
//!
//! Transcription de l'algorithme de **Bont & Heinimann (2012)** tel que codé
//! dans le plugin QGIS SEILAPLAN (GPL, <https://github.com/piMoll/SEILAPLAN>).
//! On adopte son **modele de pre-tension globale** (une tension unique pour
//! toute la ligne, chaque travee la contraignant) tout en gardant **notre**
//! mecanique caténaire Newton/Irvine (via `supports::calc_cable`), pas la
//! mecanique de Zweifel — cf. `docs/comparaison-cable-seilaplan.md` et
//! `specs/013-seilaplan-hauteur.md`.
//!
//! **13a** — brique de plage de pre-tension : `calc_sta`, transcrit de
//! `core/opti_sta.py::calcSTA`. Rend, pour une travee, la plage `[MinSTA,
//! MaxSTA]` de pre-tension pour laquelle elle est faisable (garde au sol **et**
//! effort admissible). Le graphe + Dijkstra (13b) balaiera cette pre-tension.

// 13a fournit la brique mecanique isolee ; le cablage a `cable_scan` (donc les
// appelants hors tests) arrive en 13b/13c. Les tests l'exercent deja.
#![allow(dead_code)]

use super::faisabilite::check_droite;
use super::supports::{calc_cable, SpanGeom};

/// Plage de pre-tension admissible d'une travee (sortie de `calc_sta`).
pub struct StaRange {
    /// La travee est infaisable sur toute la plage `[t_min, t_max]`.
    pub impossible: bool,
    /// Borne basse de la pre-tension faisable (garde limitante en dessous).
    pub min_sta: f64,
    /// Borne haute de la pre-tension faisable (effort limitant au-dessus).
    pub max_sta: f64,
}

/// Cherche la plage `[MinSTA, MaxSTA]` de pre-tension pour laquelle la travee
/// `g` est faisable. Transcription de `calcSTA` (`opti_sta.py`) : bissection
/// entre `t_min` et `t_max`, `calc_cable` fournissant a chaque pre-tension
/// `(garde_ok, effort_ok)`.
///
/// `t_max` est l'analogue de `zul_SK` (tension admissible), `t_min` de `min_SK`
/// (pre-tension minimale exploree), `detail` la precision de la bissection (N),
/// analogue du `Detail` de SEILAPLAN. La logique — deux bissections (max puis
/// min) partageant un cache `Speicher`, puis `Min`/`Max` des pre-tensions ou
/// **les deux** criteres tiennent — suit le source au plus pres.
pub fn calc_sta(g: &SpanGeom, t_min: f64, t_max: f64, detail: f64) -> StaRange {
    // Cache (sta, garde_ok, effort_ok) — l'analogue de `Speicher`.
    let mut speicher: Vec<(f64, bool, bool)> = Vec::new();
    let mut impossible = false;

    // Evalue une pre-tension via `calc_cable`, ramenant la non-convergence a
    // une double infaisabilite (garde et effort faux).
    let eval = |sta: f64| {
        let r = calc_cable(g, sta);
        (r.converged && r.garde_ok, r.converged && r.effort_ok)
    };

    // 1. Test de la tension max admissible (cable le plus tendu : meilleure
    //    garde). Si la garde ne tient pas ici, la travee est infaisable partout.
    let (garde_max, effort_max) = eval(t_max);
    speicher.push((t_max, garde_max, effort_max));
    if !garde_max {
        impossible = true;
    } else {
        // 2. Test de la tension min : si meme la, l'effort casse, infaisable.
        let (g1, e1) = eval(t_min);
        speicher.push((t_min, g1, e1));
        if !e1 {
            impossible = true;
        } else {
            // 3. Une seule bissection : minSTA (seuil de garde au sol). Dans NOTRE
            //    mecanique, `effort_ok = (t_impose <= tmax)` est vrai pour toute
            //    tension <= tmax (t_impose EST la tension charge centree), donc
            //    MaxSTA = t_max toujours -- la bissection maxSTA de `calcSTA`
            //    (utile a Zweifel, ou ST_max = STA + surcharge peut depasser
            //    zul_SK) serait ici pur gaspillage. On la supprime (2x moins de
            //    Newton par arete). Ecart de mecanique documente (spec 013 §9).
            let mut delta = (t_max - t_min) / 2.0;
            let mut sta = t_min + delta;
            while delta > detail && sta >= t_min {
                // Reutilise une evaluation deja en cache (egalite exacte, fidele
                // a `element[1][0] == STA` du source).
                let hit = speicher.iter().find(|e| e.0 == sta).copied();
                let (cp, _ef) = match hit {
                    Some((_, cp, ef)) => (cp, ef),
                    None => {
                        let (cp, ef) = eval(sta);
                        speicher.push((sta, cp, ef));
                        (cp, ef)
                    }
                };
                // Seuil de garde : si la garde casse, il faut plus de tension.
                let vorzeichen = if !cp { 1.0 } else { -1.0 };
                sta += delta * vorzeichen;
                delta /= 2.0;
            }
        }
    }

    // Reihe = pre-tensions ou garde ET effort tiennent ; Min/Max de leurs bornes.
    let feasible: Vec<f64> = speicher
        .iter()
        .filter(|e| e.1 && e.2)
        .map(|e| e.0)
        .collect();
    if feasible.is_empty() {
        StaRange {
            impossible: true,
            min_sta: f64::NAN,
            max_sta: f64::NAN,
        }
    } else {
        let min_sta = feasible.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_sta = feasible.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        StaRange {
            impossible,
            min_sta,
            max_sta,
        }
    }
}

// ============================================================================
// 13b — graphe + Dijkstra (Bont & Heinimann 2012), transcrit de main_opti.py
// ============================================================================

use std::collections::BinaryHeap;

/// Materiel du cable, partage par toutes les travees d'un profil (evite de
/// repasser 11 scalaires a chaque arete). Memes champs que `SpanGeom` hors
/// geometrie.
pub struct CableMat {
    pub f_o: f64,
    pub tmax: f64,
    pub q1: f64,
    pub q2: f64,
    pub q3: f64,
    pub eao: f64,
    pub hline_min: f64,
    pub hline_max: f64,
    pub csize: f64,
    pub dsupdep: f64,
    pub dsupend: f64,
}

/// Reglages du graphe d'optimisation (spec 013 §2).
pub struct GraphParams {
    /// Niveaux de hauteur des supports intermediaires : `min_hm..=max_hm` au pas
    /// `dhm` (le `δh ≈ 1 m` de SEILAPLAN).
    pub min_hm: f64,
    pub max_hm: f64,
    pub dhm: f64,
    /// Espacement horizontal minimal entre supports (m) — sauf aretes
    /// depart/arrivee (`Min_Dist_Mast`).
    pub min_dist_mast: f64,
    /// Hauteur d'arbre-support disponible : au-dela, penalite ×5 (`HM_nat`).
    pub hm_nat: f64,
    /// Hauteurs fixes des extremites (mat de depart, ancrage/mat d'arrivee).
    pub h_start: f64,
    pub h_end: f64,
    /// Plage de pre-tension balayee `[t_min, t_max]` et nombre de pas `n_sk`
    /// (l'analogue de `range(min_SK, zul_SK)`), `detail` = precision `calc_sta`.
    pub t_min: f64,
    pub t_max: f64,
    pub n_sk: usize,
    pub detail: f64,
}

/// Un nœud du graphe : une position (index dans le profil) et une hauteur.
#[derive(Clone, Copy)]
struct Node {
    pos: usize,
    h: f64,
}

/// Une arete faisable : nœuds amont/aval, plage de pre-tension, cout.
struct Edge {
    from: usize,
    to: usize,
    min_sta: f64,
    max_sta: f64,
    cost: f64,
}

/// Solution d'optimisation des supports (sortie de `optimize_supports`).
pub struct SupportSolution {
    /// Indices des supports retenus dans le profil (depart .. arrivee).
    pub positions: Vec<usize>,
    /// Hauteurs correspondantes (m).
    pub heights: Vec<f64>,
    /// Pre-tension optimale associee (N).
    pub opt_sta: f64,
    /// Valeur objectif (cout total de la ligne retenue).
    pub value: f64,
    /// La ligne couvre tout le profil (arrivee atteinte).
    pub full_span: bool,
    /// Index du support le plus lointain atteint (coupe native si `!full_span`).
    pub reach_idx: usize,
}

/// Cout d'un support de hauteur `h` (`KostStue`, main_opti.py) : au moins
/// `100² = 10000` par support (→ minimise le **nombre**), croissant en `(h+100)²`
/// (→ minimise la **hauteur**), penalise ×5 au-dela de l'arbre naturel `hm_nat`.
/// Hauteur 0 → cout 1 (jamais 0, sinon « pas d'arete »).
fn kost_stue(h: f64, hm_nat: f64) -> f64 {
    let base = if h == 0.0 { 1.0 } else { (h + 100.0).powi(2) };
    let pen = if h > hm_nat { 5.0 } else { 1.0 };
    base * pen
}

/// Detection des positions candidates = **maxima** (cretes) du profil, port de
/// `peakdetect` (billauer.co.il/peakdet.html, via SEILAPLAN). `lookahead` = fenetre
/// de confirmation (echantillons), `delta` = saillance minimale. Un support a un
/// sens sur une crete ; les creux (minima) sont ignores.
pub fn peak_positions(zi: &[f64], lookahead: usize, delta: f64) -> Vec<usize> {
    let n = zi.len();
    let mut maxima = Vec::new();
    if lookahead < 1 || n <= lookahead {
        return maxima;
    }
    let mut mn = f64::INFINITY;
    let mut mx = f64::NEG_INFINITY;
    let mut mxpos = 0usize;
    let mut first_dump: Option<bool> = None; // le 1er pic (max/min) est un faux

    for index in 0..(n - lookahead) {
        let y = zi[index];
        if y > mx {
            mx = y;
            mxpos = index;
        }
        if y < mn {
            mn = y;
        }
        // Candidat maximum : y redescend sous mx, confirme par la fenetre avant.
        if y < mx - delta && mx.is_finite() {
            let ahead_max = zi[index..index + lookahead]
                .iter()
                .cloned()
                .fold(f64::NEG_INFINITY, f64::max);
            if ahead_max < mx {
                maxima.push(mxpos);
                first_dump.get_or_insert(true);
                mx = f64::INFINITY;
                mn = f64::INFINITY;
                if index + lookahead >= n {
                    break;
                }
                continue;
            }
        }
        // Candidat minimum : reset seul (on ne collecte pas les creux).
        if y > mn + delta && mn.is_finite() {
            let ahead_min = zi[index..index + lookahead]
                .iter()
                .cloned()
                .fold(f64::INFINITY, f64::min);
            if ahead_min > mn {
                first_dump.get_or_insert(false);
                mn = f64::NEG_INFINITY;
                mx = f64::NEG_INFINITY;
                if index + lookahead >= n {
                    break;
                }
            }
        }
    }
    // Retire le faux-positif initial s'il etait un maximum.
    if first_dump == Some(true) && !maxima.is_empty() {
        maxima.remove(0);
    }
    maxima
}

/// Construit la travee (`SpanGeom`) de l'arete `a→e` avec supports de hauteurs
/// `ha`/`he`. Profil au demi-metre : `alts = &zi[a..=e]` s'indexe directement par
/// `2·xcoord` dans le repere local de la travee.
#[allow(clippy::too_many_arguments)]
fn edge_span<'a>(
    di: &[f64],
    zi: &'a [f64],
    a: usize,
    e: usize,
    ha: f64,
    he: f64,
    mat: &CableMat,
) -> SpanGeom<'a> {
    let d = di[e] - di[a];
    let za = zi[a] + ha;
    let ze = zi[e] + he;
    let h = (za - ze).abs();
    let (xup, zup, fact) = if za >= ze { (0.0, za, 1.0) } else { (d, ze, -1.0) };
    SpanGeom {
        d,
        h,
        xup,
        zup,
        fact,
        alts: &zi[a..=e],
        f_o: mat.f_o,
        tmax: mat.tmax,
        q1: mat.q1,
        q2: mat.q2,
        q3: mat.q3,
        eao: mat.eao,
        hline_min: mat.hline_min,
        hline_max: mat.hline_max,
        csize: mat.csize,
        dsupdep: mat.dsupdep,
        dsupend: mat.dsupend,
    }
}

/// Etat de la file de priorite du Dijkstra (min-heap sur le cout).
struct State {
    cost: f64,
    node: usize,
}
impl PartialEq for State {
    fn eq(&self, other: &Self) -> bool {
        self.cost == other.cost
    }
}
impl Eq for State {}
impl Ord for State {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        // Min-heap : on inverse pour que le plus petit cout soit en tete.
        other.cost.total_cmp(&self.cost)
    }
}
impl PartialOrd for State {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

/// Dijkstra maison (pas de dependance scipy). `adj[u] = [(v, cout)]`. Renvoie
/// `(dist, pred)` depuis `source`.
fn dijkstra(adj: &[Vec<(usize, f64)>], source: usize) -> (Vec<f64>, Vec<usize>) {
    let n = adj.len();
    let mut dist = vec![f64::INFINITY; n];
    let mut pred = vec![usize::MAX; n];
    let mut heap = BinaryHeap::new();
    dist[source] = 0.0;
    heap.push(State {
        cost: 0.0,
        node: source,
    });
    while let Some(State { cost, node }) = heap.pop() {
        if cost > dist[node] {
            continue;
        }
        for &(v, w) in &adj[node] {
            let nd = cost + w;
            if nd < dist[v] {
                dist[v] = nd;
                pred[v] = node;
                heap.push(State { cost: nd, node: v });
            }
        }
    }
    (dist, pred)
}

/// Optimise la position **et** la hauteur des supports d'une ligne cable a la
/// Bont & Heinimann (spec 013 §2), en reutilisant notre mecanique caténaire
/// (`calc_sta`, 13a). Transcription de `main_opti.py::optimization`.
///
/// `di`/`zi` : profil au **demi-metre** (distances et altitudes terrain).
/// `candidates` : positions candidates interieures (indices dans le profil,
/// hors extremites) — typiquement `peak_positions`. Depart (index 0) et arrivee
/// (index `n-1`) sont ajoutes d'office, a hauteur fixe (`h_start`, `h_end`).
///
/// Modele de **pre-tension globale** : chaque arete fournit `[MinSTA, MaxSTA]`
/// (via `calc_sta`) ; on balaie `n_sk` pre-tensions `sk`, activant les aretes ou
/// `MinSTA < sk < MaxSTA`, puis Dijkstra. On retient la pre-tension qui
/// **maximise la portee** puis **minimise le cout**. Coupe native : si l'arrivee
/// n'est jamais atteinte, on garde la portee maximale.
pub fn optimize_supports(
    di: &[f64],
    zi: &[f64],
    candidates: &[usize],
    p: &GraphParams,
    mat: &CableMat,
) -> SupportSolution {
    let n = di.len();
    let end_pos = n - 1;

    // Niveaux de hauteur des supports intermediaires.
    let mut levels = Vec::new();
    let mut h = p.min_hm;
    while h <= p.max_hm + 1e-9 {
        levels.push(h);
        h += p.dhm;
    }

    // Nœuds : depart (index 0), puis chaque candidat (positions croissantes) x
    // chaque niveau de hauteur, puis arrivee (dernier index). L'ordre rend
    // l'index de nœud monotone en position (utile pour la portee).
    let mut nodes = vec![Node { pos: 0, h: p.h_start }];
    let start = 0usize;
    let mut cand_sorted: Vec<usize> = candidates
        .iter()
        .cloned()
        .filter(|&c| c > 0 && c < end_pos)
        .collect();
    cand_sorted.sort_unstable();
    cand_sorted.dedup();
    for &pos in &cand_sorted {
        for &hl in &levels {
            nodes.push(Node { pos, h: hl });
        }
    }
    nodes.push(Node {
        pos: end_pos,
        h: p.h_end,
    });
    let end = nodes.len() - 1;

    // Aretes faisables : (a→e) avec pos_e > pos_a et (espacement suffisant OU
    // a=depart OU e=arrivee) ; faisabilite mecanique via calc_sta.
    let mut edges: Vec<Edge> = Vec::new();
    for i in 0..nodes.len() {
        for j in 0..nodes.len() {
            if i == j {
                continue;
            }
            let (na, ne) = (nodes[i], nodes[j]);
            if di[ne.pos] <= di[na.pos] {
                continue; // sens avant uniquement
            }
            let spacing_ok = di[ne.pos] - di[na.pos] > p.min_dist_mast;
            let is_start = i == start;
            let is_end = j == end;
            if !(spacing_ok || is_start || is_end) {
                continue;
            }
            // Pre-filtre geometrique (check_droite) : ecarte a peu de frais les
            // travees dont la corde passe deja sous la garde -- meme gate que
            // `test_span`, avant le couteux `calc_sta` (marches de Newton).
            let za = zi[na.pos] + na.h;
            let ze = zi[ne.pos] + ne.h;
            let hh = (za - ze).abs();
            let dd = di[ne.pos] - di[na.pos];
            let (xup_g, zup_g, fact) = if za >= ze {
                (di[na.pos], za, 1.0)
            } else {
                (di[ne.pos], ze, -1.0)
            };
            if check_droite(
                fact, hh, dd, xup_g, zup_g, di, zi, mat.hline_min, mat.hline_max,
                mat.tmax, mat.q1, mat.q2, mat.q3, mat.f_o, na.pos as i64, ne.pos as i64,
                mat.dsupdep, mat.dsupend,
            ) == 0
            {
                continue;
            }
            let span = edge_span(di, zi, na.pos, ne.pos, na.h, ne.h, mat);
            let range = calc_sta(&span, p.t_min, p.t_max, p.detail);
            if range.impossible {
                continue;
            }
            let cost = kost_stue(ne.h, p.hm_nat)
                + if is_start { kost_stue(na.h, p.hm_nat) } else { 0.0 };
            edges.push(Edge {
                from: i,
                to: j,
                min_sta: range.min_sta,
                max_sta: range.max_sta,
                cost,
            });
        }
    }

    // Balayage de la pre-tension : pour chaque sk, activer les aretes
    // compatibles, Dijkstra, retenir (portee max, puis cout min).
    let mut best_reach_pos = f64::NEG_INFINITY;
    let mut best_cost = f64::INFINITY;
    let mut best_target = start;
    let mut best_sk = p.t_min;
    let mut best_pred: Vec<usize> = vec![usize::MAX; nodes.len()];

    let nsk = p.n_sk.max(1);
    for step in 0..nsk {
        let sk = if nsk == 1 {
            0.5 * (p.t_min + p.t_max)
        } else {
            p.t_min + (p.t_max - p.t_min) * (step as f64) / ((nsk - 1) as f64)
        };
        // Adjacence des aretes actives a cette pre-tension.
        let mut adj = vec![Vec::new(); nodes.len()];
        for e in &edges {
            if e.min_sta < sk && sk < e.max_sta {
                adj[e.from].push((e.to, e.cost));
            }
        }
        let (dist, pred) = dijkstra(&adj, start);

        // Portee = position la plus lointaine atteinte ; cible = ce nœud (arrivee
        // preferee a portee egale), cout = distance associee.
        let mut reach_pos = f64::NEG_INFINITY;
        let mut target = start;
        let mut target_cost = 0.0;
        for (idx, d) in dist.iter().enumerate() {
            if !d.is_finite() {
                continue;
            }
            let pos = di[nodes[idx].pos];
            if pos > reach_pos || (pos == reach_pos && *d < target_cost) {
                reach_pos = pos;
                target = idx;
                target_cost = *d;
            }
        }

        let better = reach_pos > best_reach_pos
            || (reach_pos == best_reach_pos && target_cost < best_cost);
        if better {
            best_reach_pos = reach_pos;
            best_cost = target_cost;
            best_target = target;
            best_sk = sk;
            best_pred = pred;
        }
    }

    // Reconstruction du chemin depuis la cible retenue.
    let mut path = Vec::new();
    let mut cur = best_target;
    while cur != usize::MAX {
        path.push(cur);
        if cur == start {
            break;
        }
        cur = best_pred[cur];
    }
    path.reverse();

    let positions = path.iter().map(|&i| nodes[i].pos).collect::<Vec<_>>();
    let heights = path.iter().map(|&i| nodes[i].h).collect::<Vec<_>>();
    let reach_idx = nodes[best_target].pos;

    SupportSolution {
        positions,
        heights,
        opt_sta: best_sk,
        value: best_cost,
        full_span: reach_idx == end_pos,
        reach_idx,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const G: f64 = 9.80665;
    const TMAX_TEST: f64 = 35000.0 * G / 2.0;

    fn params() -> (f64, f64, f64, f64) {
        let q1 = 1.85;
        let f_o = G * (2500.0 + 400.0);
        let ao = 0.25 * std::f64::consts::PI * 18.0_f64.powi(2);
        let eao = 160000.0 * ao;
        (q1, f_o, eao, 0.9)
    }

    fn span_genereux(alts: &[f64]) -> SpanGeom<'_> {
        let (q1, f_o, eao, q) = params();
        SpanGeom {
            d: 150.0,
            h: 20.0,
            xup: 0.0,
            zup: 45.0,
            fact: 1.0,
            alts,
            f_o,
            tmax: TMAX_TEST,
            q1,
            q2: q,
            q3: q,
            eao,
            hline_min: 3.5,
            hline_max: 50.0,
            csize: 5.0,
            dsupdep: 0.0,
            dsupend: 0.0,
        }
    }

    // Travee genereuse : une plage [MinSTA, MaxSTA] non vide, bornee par tmax en
    // haut (effort) et par la garde en bas.
    #[test]
    fn calc_sta_rend_une_plage_bornee() {
        let alts = vec![0.0; 1000];
        let g = span_genereux(&alts);
        let r = calc_sta(&g, 0.3 * TMAX_TEST, TMAX_TEST, 1000.0);
        assert!(!r.impossible, "travee genereuse attendue faisable");
        assert!(r.min_sta <= r.max_sta, "[{}, {}]", r.min_sta, r.max_sta);
        assert!(r.max_sta <= TMAX_TEST + 1.0, "max_sta = {}", r.max_sta);
        assert!(r.min_sta >= 0.3 * TMAX_TEST - 1.0, "min_sta = {}", r.min_sta);
    }

    // Sol trop haut : infaisable a toute pre-tension (garde violee meme tendu).
    #[test]
    fn calc_sta_infaisable_si_sol_trop_haut() {
        let alts = vec![44.0; 1000]; // supports a 45 m, garde 3,5 m impossible
        let g = span_genereux(&alts);
        let r = calc_sta(&g, 0.3 * TMAX_TEST, TMAX_TEST, 1000.0);
        assert!(r.impossible, "travee attendue infaisable");
    }

    // La borne haute est bien limitee par l'effort : si tmax est genereux et la
    // garde tient largement, MaxSTA colle a la tension max exploree.
    #[test]
    fn calc_sta_borne_haute_pilotee_par_effort() {
        let alts = vec![0.0; 1000];
        let g = span_genereux(&alts);
        let r = calc_sta(&g, 0.3 * TMAX_TEST, TMAX_TEST, 1000.0);
        assert!(!r.impossible);
        // MaxSTA atteint la tension max (a la resolution de bissection pres).
        assert!(
            (r.max_sta - TMAX_TEST).abs() < 5000.0,
            "max_sta = {} attendu proche de tmax = {}",
            r.max_sta,
            TMAX_TEST
        );
    }

    // --- Graphe + Dijkstra (13b) ---------------------------------------------

    fn mat() -> CableMat {
        let (q1, f_o, eao, q) = params();
        CableMat {
            f_o,
            tmax: TMAX_TEST,
            q1,
            q2: q,
            q3: q,
            eao,
            hline_min: 3.5,
            hline_max: 50.0,
            csize: 5.0,
            dsupdep: 0.0,
            dsupend: 0.0,
        }
    }

    // Profil au demi-metre.
    fn di_demimetre(n: usize) -> Vec<f64> {
        (0..n).map(|k| 0.5 * k as f64).collect()
    }

    // Terrain triangulaire : 0 aux extremites, crete `sommet` au milieu.
    fn terrain_triangle(n: usize, sommet: f64) -> Vec<f64> {
        let mid = (n - 1) as f64 / 2.0;
        (0..n)
            .map(|k| sommet * (1.0 - (k as f64 - mid).abs() / mid))
            .collect()
    }

    // Le cout d'un support croit avec la hauteur, penalise ×5 au-dela de hm_nat.
    #[test]
    fn kost_stue_penalise_hauteur_et_depassement() {
        assert_eq!(kost_stue(0.0, 15.0), 1.0); // hauteur nulle : cout 1
        assert!(kost_stue(10.0, 15.0) > kost_stue(5.0, 15.0)); // croit avec h
        // Penalite ×5 au franchissement de hm_nat.
        let sous = kost_stue(15.0, 15.0);
        let sur = kost_stue(16.0, 15.0);
        assert!(sur > 4.0 * sous, "penalite arbre attendue : {sous} -> {sur}");
    }

    // peakdetect : sur un profil creux-puis-crete, la crete interieure ressort
    // (le premier extreme — le creux — est le faux-positif ecarte).
    #[test]
    fn peak_positions_trouve_la_crete_interieure() {
        let n = 250;
        let zi: Vec<f64> = (0..n)
            .map(|k| {
                if k <= 50 {
                    20.0 - 20.0 * k as f64 / 50.0 // 20 -> 0 (creux a 50)
                } else if k <= 150 {
                    30.0 * (k - 50) as f64 / 100.0 // 0 -> 30 (crete a 150)
                } else {
                    30.0 - 30.0 * (k - 150) as f64 / 100.0 // 30 -> 0
                }
            })
            .collect();
        let peaks = peak_positions(&zi, 20, 0.0);
        assert!(
            peaks.iter().any(|&p| p > 100 && p < 200),
            "crete interieure attendue vers 150, obtenu {peaks:?}"
        );
    }

    // CA-13.1 : le span direct ne passe pas (corde sous la crete), mais un
    // support intermediaire sur la crete rend la ligne faisable.
    #[test]
    fn optimize_pose_un_support_quand_le_direct_echoue() {
        let n = 401; // 200 m au demi-metre, crete a l'index 200
        let zi = terrain_triangle(n, 35.0);
        let di = di_demimetre(n);
        let m = mat();

        // Direct depart(20 m) -> arrivee(20 m) : corde a 20 m sous la crete 35 m.
        let direct = edge_span(&di, &zi, 0, n - 1, 20.0, 20.0, &m);
        assert!(
            calc_sta(&direct, 0.3 * TMAX_TEST, TMAX_TEST, 1000.0).impossible,
            "le span direct devrait etre infaisable"
        );

        let p = GraphParams {
            min_hm: 3.0,
            max_hm: 15.0,
            dhm: 3.0,
            min_dist_mast: 10.0,
            hm_nat: 15.0,
            h_start: 20.0,
            h_end: 20.0,
            t_min: 0.3 * TMAX_TEST,
            t_max: TMAX_TEST,
            n_sk: 20,
            detail: 1000.0,
        };
        let sol = optimize_supports(&di, &zi, &[200], &p, &m);
        assert!(sol.full_span, "attendu ligne complete, portee = {}", sol.reach_idx);
        assert!(
            sol.positions.contains(&200),
            "support intermediaire attendu sur la crete, positions = {:?}",
            sol.positions
        );
        assert_eq!(sol.positions.first(), Some(&0));
        assert_eq!(sol.positions.last(), Some(&(n - 1)));
    }

    // Aucun support inutile : si le direct passe, la minimisation du cout (chaque
    // support coute >= 10000) evite d'en ajouter un.
    #[test]
    fn optimize_evite_un_support_inutile() {
        let n = 301; // 150 m
        let zi = vec![0.0; n];
        let di = di_demimetre(n);
        let m = mat();
        let p = GraphParams {
            min_hm: 3.0,
            max_hm: 15.0,
            dhm: 3.0,
            min_dist_mast: 10.0,
            hm_nat: 15.0,
            h_start: 45.0,
            h_end: 45.0,
            t_min: 0.3 * TMAX_TEST,
            t_max: TMAX_TEST,
            n_sk: 20,
            detail: 1000.0,
        };
        let sol = optimize_supports(&di, &zi, &[150], &p, &m);
        assert!(sol.full_span);
        assert_eq!(
            sol.positions,
            vec![0, n - 1],
            "aucun support intermediaire attendu, positions = {:?}",
            sol.positions
        );
    }

    // CA-13.2 (esprit) : a hauteur fixe (un seul niveau), le graphe optimise la
    // POSITION seule et reste deterministe — il pose le support sur la crete.
    #[test]
    fn optimize_a_hauteur_fixe_optimise_la_position() {
        let n = 401;
        let zi = terrain_triangle(n, 35.0);
        let di = di_demimetre(n);
        let m = mat();
        let p = GraphParams {
            min_hm: 9.0,
            max_hm: 9.0, // un seul niveau => hauteur fixe
            dhm: 3.0,
            min_dist_mast: 10.0,
            hm_nat: 15.0,
            h_start: 20.0,
            h_end: 20.0,
            t_min: 0.3 * TMAX_TEST,
            t_max: TMAX_TEST,
            n_sk: 20,
            detail: 1000.0,
        };
        // Plusieurs positions candidates : le graphe doit retenir la crete (200).
        let sol = optimize_supports(&di, &zi, &[120, 200, 280], &p, &m);
        assert!(sol.full_span, "portee = {}", sol.reach_idx);
        assert!(
            sol.positions.contains(&200),
            "la crete (200) attendue, positions = {:?}",
            sol.positions
        );
        // Determinisme : deux appels identiques donnent la meme ligne.
        let sol2 = optimize_supports(&di, &zi, &[120, 200, 280], &p, &m);
        assert_eq!(sol.positions, sol2.positions);
        assert_eq!(sol.heights, sol2.heights);
    }

    // Coupe native : si rien ne permet d'atteindre l'arrivee, on garde la portee
    // maximale (ligne partielle) plutot que d'echouer.
    #[test]
    fn optimize_coupe_a_la_portee_maximale() {
        // Crete infranchissable pres de l'arrivee (mur a 80 m) : le debut passe,
        // la fin non.
        let n = 401;
        let mut zi = vec![0.0; n];
        for k in 300..320 {
            zi[k] = 80.0; // mur infranchissable a ~150-160 m
        }
        let di = di_demimetre(n);
        let m = mat();
        let p = GraphParams {
            min_hm: 3.0,
            max_hm: 15.0,
            dhm: 3.0,
            min_dist_mast: 10.0,
            hm_nat: 15.0,
            h_start: 45.0,
            h_end: 45.0,
            t_min: 0.3 * TMAX_TEST,
            t_max: TMAX_TEST,
            n_sk: 20,
            detail: 1000.0,
        };
        let sol = optimize_supports(&di, &zi, &[100, 200], &p, &m);
        assert!(!sol.full_span, "l'arrivee ne devrait pas etre atteignable");
        assert!(sol.reach_idx < n - 1);
    }
}
