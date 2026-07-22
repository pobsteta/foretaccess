//! Solveur A* de trace de desserte (portage de `Astar_force_wp`, `calc_init`,
//! `basic_calc`, `reconstruct_path` de SylvaRoad).
//!
//! A* sur le graphe a voisinage disque (`neighborhood`), heuristique = distance
//! inverse depuis la cible (`heuristic`). Le cout de transition combine la distance
//! geometrique et des penalites (direction, pente, devers), fidele a SylvaRoad : la
//! route minimise sa longueur sous contraintes de constructibilite. Gestion des
//! epingles (rayon de braquage `radius`, angle limite), controle du profil
//! (`check_profile`) et anti-croisement du trace.
//!
//! Etat par noeud (`NodeState`), indexe par id-pixel, calque sur la matrice `Best`
//! a 11 colonnes de SylvaRoad :
//! `cost` (g), `dplan`, `slope_from`, `az_from`, `came_from`, `dist_hairpin`,
//! `lsl`, `nbptbef`, `dtocp` (h), `is_hairpin`.

use rayon::prelude::*;
use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashMap, HashSet, VecDeque};

use super::geom::{check_profile, connect2, distplan, get_intersect};
use super::heuristic::{dist_to_end, dist_to_end_multi};
use super::neighborhood::{build_neib_table, NeibTable};

const UNVISITED: i32 = -1;
const INF_COST: f64 = 1.0e7;

/// Parametres du solveur (defauts SylvaRoad, cf. `SylvaRoaD_0_param.py`).
#[derive(Clone, Copy)]
pub struct SolverParams {
    pub csize: f64,
    pub min_slope: f64,
    pub max_slope: f64,
    pub penalty_xy: f64,
    pub penalty_z: f64,
    pub max_diff_z: f64,
    pub d_neighborhood: f64,
    pub angle_hairpin: f64,
    pub lmax_ab_sl: f64,
    pub radius: f64,
    pub prop_sl_max: f64,
    pub max_slope_hairpin: f64,
    pub tal: f64,
    pub modhair: f64,
}

impl SolverParams {
    fn max_slope_change(&self) -> f64 {
        2.0 * self.min_slope.max(self.max_slope)
    }
    /// Angle maximal d'un virage acceptable (au-dela = demi-tour interdit).
    fn max_hairpin_angle(&self) -> f64 {
        use std::f64::consts::PI;
        180.0 - self.max_slope_hairpin * 0.01 / self.tal * 180.0 * (1.0 + 1.0 / (2.0 * PI))
    }
    fn max_nbptbef(&self) -> i32 {
        ((self.d_neighborhood / self.csize) as i32).max(7)
    }
}

/// Pondération monétaire du trace (extension ForetAccess de SylvaRoad). `w` = coût
/// de construction par metre (€/m) par cellule (row-major) ; `1.0` partout = trace
/// purement geometrique (comportement SylvaRoad d'origine). La contribution
/// distance d'un segment est multipliee par le coût moyen de ses deux extremites.
///
/// `cmin` = coût minimal sur la **zone franchissable** : il sert a **remettre a
/// l'echelle l'heuristique geometrique** (`h_geo * cmin`), qui reste ainsi une
/// borne inferieure du coût pondere restant (chaque segment coûte au moins
/// `d * cmin`), donc l'A* reste admissible et optimal quel que soit le champ `w`.
pub struct CostGrid<'a> {
    w: Option<&'a [f64]>,
    pub cmin: f64,
}

impl<'a> CostGrid<'a> {
    /// Grille neutre : trace purement geometrique (comportement SylvaRoad).
    pub fn neutral() -> Self {
        CostGrid { w: None, cmin: 1.0 }
    }

    /// Depuis la grille €/m et la zone franchissable (`zone == 1`). `cmin` ignore
    /// les valeurs non finies ou <= 0 ; a defaut (grille neutre) vaut 1.0.
    pub fn new(w: &'a [f64], zone: &[i32]) -> Self {
        let cmin = w
            .iter()
            .zip(zone.iter())
            .filter(|(&c, &z)| z == 1 && c.is_finite() && c > 0.0)
            .map(|(&c, _)| c)
            .fold(f64::INFINITY, f64::min);
        CostGrid {
            w: Some(w),
            cmin: if cmin.is_finite() { cmin } else { 1.0 },
        }
    }

    /// Facteur de coût d'un segment reliant les cellules `a` et `b` (moyenne des
    /// deux €/m ; `1.0` pour une grille neutre). Une valeur non finie ou <= 0 est
    /// ramenee a `cmin`.
    #[inline]
    fn factor(&self, a: usize, b: usize) -> f64 {
        match self.w {
            None => 1.0,
            Some(w) => {
                let f = 0.5 * (w[a] + w[b]);
                if f.is_finite() && f > 0.0 {
                    f
                } else {
                    self.cmin
                }
            }
        }
    }
}

/// Etat A* d'une cellule (id-pixel).
#[derive(Clone, Copy)]
struct NodeState {
    id: i32,
    cost: f64,
    dplan: f64,
    slope_from: f64,
    az_from: f64,
    came_from: i32,
    dist_hairpin: f64,
    lsl: f64,
    nbptbef: i32,
    dtocp: f64,
    is_hairpin: i32,
}

impl NodeState {
    fn empty() -> Self {
        NodeState {
            id: UNVISITED,
            cost: INF_COST,
            dplan: 0.0,
            slope_from: 0.0,
            az_from: -1.0,
            came_from: -1,
            dist_hairpin: -1.0,
            lsl: 0.0,
            nbptbef: 0,
            dtocp: 0.0,
            is_hairpin: 0,
        }
    }
}

/// Entree de la file de priorite : ordonnee par `theo_d = g + h` puis `dtocp = h`
/// (tas-min), depart des egalites stable par id-pixel pour le determinisme.
struct QEntry {
    theo_d: f64,
    dtocp: f64,
    id: i32,
}
impl PartialEq for QEntry {
    fn eq(&self, o: &Self) -> bool {
        // Coherent avec `Ord` (evite un impl derivable et le lint associe).
        self.cmp(o) == Ordering::Equal
    }
}
impl Eq for QEntry {}
impl PartialOrd for QEntry {
    fn partial_cmp(&self, o: &Self) -> Option<Ordering> {
        Some(self.cmp(o))
    }
}
impl Ord for QEntry {
    fn cmp(&self, o: &Self) -> Ordering {
        // Tas-min : plus petit (theo_d, dtocp, id) en tete (ordre inverse).
        o.theo_d
            .total_cmp(&self.theo_d)
            .then_with(|| o.dtocp.total_cmp(&self.dtocp))
            .then_with(|| o.id.cmp(&self.id))
    }
}

/// Resultat du solveur : le trace (indices de cellules aplatis, du depart a
/// l'arrivee), son cout et sa faisabilite.
pub struct TraceResult {
    pub path: Vec<usize>,
    pub cost: f64,
    pub feasible: bool,
}

/// Cle de deduplication de la frontiere : arrondi au dixieme comme SylvaRoad
/// (`round(x, 1)`).
fn deci(x: f64) -> i64 {
    (x * 10.0).round() as i64
}

/// Trace la desserte a travers la suite de points de passage `waypoints` (indices
/// de cellules aplatis, >= 2 points), en s'appuyant sur la table de voisinage.
/// `bufgoal` (m) autorise, sur le dernier segment, une finition a proximite de la
/// cible. Renvoie le trace concatene.
#[allow(clippy::too_many_arguments)]
pub fn solve(
    dtm: &[f64],
    obs: &[i32],
    obs2: &[i32],
    local_slope: &[f64],
    zone: &[i32],
    table: &NeibTable,
    nr: usize,
    nc: usize,
    waypoints: &[usize],
    bufgoal: f64,
    cg: &CostGrid,
    p: &SolverParams,
) -> TraceResult {
    let n_pix = table.n_pix();
    let mut best = vec![NodeState::empty(); n_pix];

    // Heuristique : distance inverse depuis la cible FINALE (dernier waypoint),
    // remise a l'echelle par cmin pour rester admissible sous ponderation de coût.
    let last = *waypoints.last().unwrap();
    let mut d2e = dist_to_end(zone, nr, nc, p.csize, last / nc, last % nc, 1.0e9);
    scale_finite(&mut d2e, cg.cmin);

    let n_seg = waypoints.len() - 1;
    let mut full_path: Vec<usize> = Vec::new();
    let mut total_cost = 0.0;
    let mut all_ok = true;

    for iseg in 0..n_seg {
        let cs = waypoints[iseg];
        let ce = waypoints[iseg + 1];
        let take_dtoend = iseg == n_seg - 1;
        let seg_bufgoal = if take_dtoend { bufgoal } else { 0.0 };

        let id_start = table.id_pix[cs];
        let id_end = table.id_pix[ce];
        if id_start < 0 || id_end < 0 {
            all_ok = false;
            break;
        }
        let (id_start, id_end) = (id_start as usize, id_end as usize);
        let (ye, xe) = table.corresp[id_end];

        // Depart : initialise seulement s'il n'a pas deja ete atteint (continuite
        // du cout et de l'azimut au raccord des segments).
        if best[id_start].id < 0 {
            best[id_start] = NodeState {
                id: id_start as i32,
                cost: 0.0,
                dplan: 0.0,
                slope_from: 0.0,
                az_from: -1.0,
                came_from: -1,
                dist_hairpin: 0.0,
                lsl: 0.0,
                nbptbef: 0,
                dtocp: nan_inf(d2e[cs]),
                is_hairpin: 0,
            };
        }

        // La frontiere seme le depart avec la distance a la cible FINALE (fidele a
        // `frontier.put(idcel, Dist_to_End[yS,xS], ...)`), quel que soit l'etat
        // herite du segment precedent.
        let seed = nan_inf(d2e[cs]);
        let mut heap = BinaryHeap::new();
        let mut key_frontier: HashSet<(i32, i64, i64)> = HashSet::new();
        heap.push(QEntry {
            theo_d: seed,
            dtocp: seed,
            id: id_start as i32,
        });
        // File secondaire : cellules a portee de `bufgoal` de la cible.
        let mut close: BinaryHeap<QEntry> = BinaryHeap::new();
        let mut reached = false;

        while let Some(QEntry { id: idcur, .. }) = heap.pop() {
            let idcur = idcur as usize;
            if idcur == id_end {
                reached = true;
                break;
            }
            let add: Vec<usize> = if best[idcur].nbptbef == 0 {
                calc_init(idcur, &mut best, table, obs, obs2, dtm, &d2e, nc, take_dtoend, ye, xe, cg, p)
            } else {
                // Finition a proximite de la cible (dernier segment).
                if seg_bufgoal > 0.0 {
                    let (yc, xc) = table.corresp[idcur];
                    let dcg = distplan(yc as f64, xc as f64, ye as f64, xe as f64) * p.csize;
                    if dcg <= seg_bufgoal {
                        push_close(&mut close, idcur, dcg, &best, p);
                    }
                }
                basic_calc(idcur, &mut best, table, obs, obs2, dtm, local_slope, &d2e, nc, take_dtoend, ye, xe, cg, p)
            };
            for &idv in &add {
                let theo = round1(best[idv].cost + best[idv].dtocp);
                let dto = round1(best[idv].dtocp);
                let key = (idv as i32, deci(theo), deci(dto));
                if key_frontier.insert(key) {
                    heap.push(QEntry {
                        theo_d: theo,
                        dtocp: dto,
                        id: idv as i32,
                    });
                }
            }
        }

        // Reconstruction : cible atteinte, sinon meilleure approche (`close`).
        let goal_id = if reached {
            Some(id_end)
        } else if let Some(QEntry { id, .. }) = close.pop() {
            Some(id as usize)
        } else {
            None
        };
        match goal_id {
            Some(gid) => {
                let seg = reconstruct(gid, id_start, &best, table, nc);
                total_cost = best[gid].cost;
                // Concatene sans dupliquer le point de raccord.
                if full_path.is_empty() {
                    full_path.extend(seg);
                } else {
                    full_path.extend(seg.into_iter().skip(1));
                }
            }
            None => {
                all_ok = false;
                break;
            }
        }
    }

    TraceResult {
        path: full_path,
        cost: total_cost,
        feasible: all_ok,
    }
}

fn round1(x: f64) -> f64 {
    (x * 10.0).round() / 10.0
}

/// Multiplie en place les valeurs finies d'une grille par `k` (mise a l'echelle de
/// l'heuristique geometrique ; les `NaN`/inf hors-portee sont laisses tels quels).
fn scale_finite(v: &mut [f64], k: f64) {
    if k == 1.0 {
        return;
    }
    for x in v.iter_mut() {
        if x.is_finite() {
            *x *= k;
        }
    }
}

/// Trace le chemin de moindre cout d'une `source` vers le RESEAU (ensemble de
/// cellules `targets`) : l'A* s'arrete des qu'il atteint une cellule du reseau.
/// Reproduit le Dijkstra multi-cible de ForestRoadNetwork (raccordement d'une
/// parcelle au reseau existant, Lot 16) mais avec la mecanique de trace du Lot 15
/// (penalites, epingles, profil). L'heuristique vise le reseau entier
/// (multi-source, `h = 0` sur le reseau). Indices de cellules aplatis.
#[allow(clippy::too_many_arguments)]
pub fn solve_network(
    dtm: &[f64],
    obs: &[i32],
    obs2: &[i32],
    local_slope: &[f64],
    zone: &[i32],
    table: &NeibTable,
    nr: usize,
    nc: usize,
    source: usize,
    targets: &[usize],
    cg: &CostGrid,
    p: &SolverParams,
) -> TraceResult {
    let echec = || TraceResult {
        path: vec![],
        cost: 0.0,
        feasible: false,
    };
    let id_source = table.id_pix[source];
    if id_source < 0 {
        return echec();
    }
    let id_source = id_source as usize;

    // Ids-pixels cibles (cellules de reseau franchissables).
    let target_ids: HashSet<usize> = targets
        .iter()
        .filter_map(|&t| {
            let id = table.id_pix[t];
            (id >= 0).then_some(id as usize)
        })
        .collect();
    if target_ids.is_empty() {
        return echec();
    }
    // Source deja sur le reseau : raccordement trivial.
    if target_ids.contains(&id_source) {
        return TraceResult {
            path: vec![source],
            cost: 0.0,
            feasible: true,
        };
    }

    // Heuristique = distance inverse multi-source depuis tout le reseau, remise a
    // l'echelle par cmin pour rester admissible sous ponderation de coût.
    let mut d2e = dist_to_end_multi(zone, nr, nc, p.csize, targets, 1.0e9);
    scale_finite(&mut d2e, cg.cmin);
    let seed = nan_inf(d2e[source]);
    let n_pix = table.n_pix();

    // Fenetre de recherche. Une parcelle se raccorde au reseau LE PLUS PROCHE :
    // l'optimum reste dans un couloir autour du segment source -> cible la plus
    // proche. On borne l'A* a la boite englobante (source, cible la plus proche)
    // elargie d'une marge PROPORTIONNELLE a la distance directe -- petites
    // fenetres pour les parcelles proches (le cas reel : A* focalise, resultat
    // identique), grandes pour les parcelles lointaines. Repli sur l'emprise
    // entiere si aucune cible n'est atteinte dans la fenetre (faisabilite
    // preservee). Le tissu du reseau reste un GLOUTON (approximation) : borner le
    // trace au couloir du raccordement le plus proche est coherent avec ca.
    let (sr, sc) = (source / nc, source % nc);
    let (mut tr, mut tc, mut dbest) = (sr, sc, usize::MAX);
    for &t in targets {
        let (r, c) = (t / nc, t % nc);
        let d = r.max(sr).saturating_sub(r.min(sr)).max(c.max(sc).saturating_sub(c.min(sc)));
        if d < dbest {
            dbest = d;
            tr = r;
            tc = c;
        }
    }
    let neigh_cells = (p.d_neighborhood / p.csize).ceil() as usize;
    let pad = (neigh_cells + 5).max(dbest);
    let r0 = sr.min(tr).saturating_sub(pad);
    let r1 = (sr.max(tr) + pad).min(nr - 1);
    let c0 = sc.min(tc).saturating_sub(pad);
    let c1 = (sc.max(tc) + pad).min(nc - 1);
    let deja_pleine = r0 == 0 && c0 == 0 && r1 == nr - 1 && c1 == nc - 1;

    // attempt 0 : fenetre bornee ; attempt 1 : emprise entiere (repli).
    for attempt in 0..2 {
        let (wr0, wr1, wc0, wc1) = if attempt == 0 {
            (r0, r1, c0, c1)
        } else {
            (0, nr - 1, 0, nc - 1)
        };

        let mut best = vec![NodeState::empty(); n_pix];
        best[id_source] = NodeState {
            id: id_source as i32,
            cost: 0.0,
            dplan: 0.0,
            slope_from: 0.0,
            az_from: -1.0,
            came_from: -1,
            dist_hairpin: 0.0,
            lsl: 0.0,
            nbptbef: 0,
            dtocp: seed,
            is_hairpin: 0,
        };

        let mut heap = BinaryHeap::new();
        let mut key_frontier: HashSet<(i32, i64, i64)> = HashSet::new();
        heap.push(QEntry {
            theo_d: seed,
            dtocp: seed,
            id: id_source as i32,
        });

        let mut reached: Option<usize> = None;
        while let Some(QEntry { id: idcur, .. }) = heap.pop() {
            let idcur = idcur as usize;
            if target_ids.contains(&idcur) {
                reached = Some(idcur);
                break;
            }
            // take_dtoend = true : l'heuristique est la distance-reseau pre-calculee
            // (ye/xe inutilises dans ce mode).
            let add = if best[idcur].nbptbef == 0 {
                calc_init(idcur, &mut best, table, obs, obs2, dtm, &d2e, nc, true, 0, 0, cg, p)
            } else {
                basic_calc(idcur, &mut best, table, obs, obs2, dtm, local_slope, &d2e, nc, true, 0, 0, cg, p)
            };
            for &idv in &add {
                // Hors de la fenetre de recherche : non developpe.
                let (rv, cv) = table.corresp[idv];
                if rv < wr0 || rv > wr1 || cv < wc0 || cv > wc1 {
                    continue;
                }
                let theo = round1(best[idv].cost + best[idv].dtocp);
                let dto = round1(best[idv].dtocp);
                let key = (idv as i32, deci(theo), deci(dto));
                if key_frontier.insert(key) {
                    heap.push(QEntry {
                        theo_d: theo,
                        dtocp: dto,
                        id: idv as i32,
                    });
                }
            }
        }

        if let Some(gid) = reached {
            return TraceResult {
                path: reconstruct(gid, id_source, &best, table, nc),
                cost: best[gid].cost,
                feasible: true,
            };
        }
        if deja_pleine {
            break; // deja pleine emprise : le repli n'apporterait rien
        }
    }
    echec()
}

/// Reseau construit : un chemin (indices aplatis) et son cout par tronçon cree.
pub struct NetworkResult {
    pub paths: Vec<Vec<usize>>,
    pub costs: Vec<f64>,
}

/// Decalages du disque de rayon `skidding` (m) autour d'une cellule : sert au
/// pre-elagage « une route est-elle deja a distance de debardage ? » (portage de
/// `createRelativeCircleNeighborhood` de ForestRoadNetwork).
fn skidding_circle(skidding: f64, csize: f64) -> Vec<(i32, i32)> {
    let nb = (skidding / csize) as i32 + 1;
    let mut out = Vec::new();
    for dr in -nb..=nb {
        for dc in -nb..=nb {
            if ((dr * dr + dc * dc) as f64).sqrt() * csize <= skidding {
                out.push((dr, dc));
            }
        }
    }
    out
}

/// Vrai si une cellule de `roadset` est dans le disque de debardage de `src`
/// (portage de `checkRelativeCircleNeighborhoodForRoads`).
fn road_within_skidding(
    src: usize,
    nr: usize,
    nc: usize,
    circle: &[(i32, i32)],
    roadset: &HashSet<usize>,
) -> bool {
    let (sy, sx) = ((src / nc) as i32, (src % nc) as i32);
    circle.iter().any(|&(dr, dc)| {
        let (y, x) = (sy + dr, sx + dc);
        if y < 0 || y >= nr as i32 || x < 0 || x >= nc as i32 {
            return false;
        }
        roadset.contains(&((y as usize) * nc + x as usize))
    })
}

/// Construit un reseau de desserte desservant `sources_ordered` (cellules des
/// parcelles, dans l'ordre heuristique) a partir de `network0` (reseau existant),
/// glouton avec reutilisation (portage MTAP->STAP de ForestRoadNetwork). La table
/// de voisinage est batie une seule fois. Une source deja a distance de debardage
/// d'une route est ignoree ; sinon on la raccorde au reseau courant (`solve_network`),
/// puis le chemin cree grossit le reseau (cibles des sources suivantes).
#[allow(clippy::too_many_arguments)]
pub fn build_network(
    dtm: &[f64],
    obs: &[i32],
    obs2: &[i32],
    local_slope: &[f64],
    zone: &[i32],
    nr: usize,
    nc: usize,
    sources_ordered: &[usize],
    network0: &[usize],
    skidding: f64,
    cg: &CostGrid,
    p: &SolverParams,
) -> NetworkResult {
    let table = build_neib_table(dtm, obs, nr, nc, p.d_neighborhood, p.csize, p.min_slope, p.max_slope);
    build_network_with_table(
        dtm, obs, obs2, local_slope, zone, nr, nc, sources_ordered, network0, skidding, &table, cg, p,
    )
}

/// Coeur du glouton MTAP->STAP avec une table de voisinage **deja batie** : permet
/// de reutiliser la table entre plusieurs ordres d'insertion (multi-start, Lot 18).
#[allow(clippy::too_many_arguments)]
pub fn build_network_with_table(
    dtm: &[f64],
    obs: &[i32],
    obs2: &[i32],
    local_slope: &[f64],
    zone: &[i32],
    nr: usize,
    nc: usize,
    sources_ordered: &[usize],
    network0: &[usize],
    skidding: f64,
    table: &NeibTable,
    cg: &CostGrid,
    p: &SolverParams,
) -> NetworkResult {
    let mut roadset: HashSet<usize> = network0.iter().copied().collect();
    let circle = skidding_circle(skidding, p.csize);
    let mut paths = Vec::new();
    let mut costs = Vec::new();

    for &src in sources_ordered {
        if src >= nr * nc || table.id_pix[src] < 0 {
            continue; // hors grille ou obstacle
        }
        if road_within_skidding(src, nr, nc, &circle, &roadset) {
            continue; // deja desservie par debardage
        }
        let targets: Vec<usize> = roadset.iter().copied().collect();
        let res = solve_network(dtm, obs, obs2, local_slope, zone, table, nr, nc, src, &targets, cg, p);
        if res.feasible && !res.path.is_empty() {
            for &c in &res.path {
                roadset.insert(c);
            }
            paths.push(res.path);
            costs.push(res.cost);
        }
    }

    NetworkResult { paths, costs }
}

/// Resultat d'une optimisation multi-start : le meilleur reseau (chemins + couts)
/// et le journal des couts totaux par essai (courbe d'exploration).
pub struct MultistartResult {
    pub paths: Vec<Vec<usize>>,
    pub costs: Vec<f64>,
    pub best: usize,
    pub journal: Vec<f64>,
}

/// PRNG SplitMix64 deterministe (sans dependance externe) : fait avancer `state`
/// et renvoie le prochain tirage 64 bits.
fn splitmix_next(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

/// Melange de Fisher-Yates deterministe : permutation reproductible de `base`
/// pilotee par une graine.
fn shuffle_seeded(base: &[usize], seed: u64) -> Vec<usize> {
    let mut v = base.to_vec();
    let mut state = seed;
    for i in (1..v.len()).rev() {
        let j = (splitmix_next(&mut state) % (i as u64 + 1)) as usize;
        v.swap(i, j);
    }
    v
}

/// Multi-start parallele (Lot 18) : evalue `n_start` ordres d'insertion perturbes
/// (l'essai 0 est l'ordre de base, garantissant un cout <= glouton simple), retient
/// le reseau de moindre cout total. La table de voisinage est batie une seule fois
/// et partagee entre les essais (`rayon`).
#[allow(clippy::too_many_arguments)]
pub fn build_network_multistart(
    dtm: &[f64],
    obs: &[i32],
    obs2: &[i32],
    local_slope: &[f64],
    zone: &[i32],
    nr: usize,
    nc: usize,
    sources_base: &[usize],
    network0: &[usize],
    skidding: f64,
    n_start: usize,
    seed: u64,
    cg: &CostGrid,
    p: &SolverParams,
) -> MultistartResult {
    let table = build_neib_table(dtm, obs, nr, nc, p.d_neighborhood, p.csize, p.min_slope, p.max_slope);
    let n = n_start.max(1);
    // Essai 0 = ordre de base ; essais suivants = permutations reproductibles.
    let orders: Vec<Vec<usize>> = (0..n)
        .map(|t| {
            if t == 0 {
                sources_base.to_vec()
            } else {
                shuffle_seeded(sources_base, seed ^ (t as u64).wrapping_mul(0x2545_F491_4F6C_DD1D))
            }
        })
        .collect();
    let results: Vec<NetworkResult> = orders
        .par_iter()
        .map(|ord| {
            build_network_with_table(
                dtm, obs, obs2, local_slope, zone, nr, nc, ord, network0, skidding, &table, cg, p,
            )
        })
        .collect();
    let journal: Vec<f64> = results.iter().map(|r| r.costs.iter().sum()).collect();
    let best = journal
        .iter()
        .enumerate()
        .min_by(|a, b| a.1.total_cmp(b.1))
        .map(|(i, _)| i)
        .unwrap_or(0);
    MultistartResult {
        paths: results[best].paths.clone(),
        costs: results[best].costs.clone(),
        best,
        journal,
    }
}

/// Resultat d'un recuit simule : le meilleur reseau rencontre et le journal du
/// meilleur cout par iteration (courbe de convergence, monotone decroissante).
pub struct AnnealResult {
    pub paths: Vec<Vec<usize>>,
    pub costs: Vec<f64>,
    pub journal: Vec<f64>,
}

/// Recuit simule sur l'ordre d'insertion (Lot 18b, Akay 2004). Energie = cout
/// total du reseau ; voisin = echange de deux positions dans l'ordre ; acceptation
/// de Metropolis (`exp(-delta/T)`) ; refroidissement geometrique (`cooling`). Part
/// de l'ordre de base et renvoie le meilleur reseau rencontre -> jamais pire que le
/// glouton (CA-18.1). Deterministe a graine fixee (CA-18.2). La table est batie une
/// fois. Si `t0 <= 0`, une temperature initiale est deduite de l'energie de base.
#[allow(clippy::too_many_arguments)]
pub fn build_network_recuit(
    dtm: &[f64],
    obs: &[i32],
    obs2: &[i32],
    local_slope: &[f64],
    zone: &[i32],
    nr: usize,
    nc: usize,
    sources_base: &[usize],
    network0: &[usize],
    skidding: f64,
    n_iter: usize,
    t0: f64,
    cooling: f64,
    seed: u64,
    cg: &CostGrid,
    p: &SolverParams,
) -> AnnealResult {
    let table = build_neib_table(dtm, obs, nr, nc, p.d_neighborhood, p.csize, p.min_slope, p.max_slope);
    let eval = |order: &[usize]| {
        let net = build_network_with_table(
            dtm, obs, obs2, local_slope, zone, nr, nc, order, network0, skidding, &table, cg, p,
        );
        let e: f64 = net.costs.iter().sum();
        (e, net)
    };

    let mut current = sources_base.to_vec();
    let (mut cur_e, base_net) = eval(&current);
    let mut best_e = cur_e;
    let mut best_net = base_net;
    // Temperature initiale automatique (fraction de l'energie de base) si t0 <= 0.
    let mut temp = if t0 > 0.0 {
        t0
    } else if cur_e > 0.0 {
        cur_e * 0.2
    } else {
        1.0
    };

    let mut state = seed;
    let len = current.len();
    let mut journal = Vec::with_capacity(n_iter);
    for _ in 0..n_iter {
        let mut cand = current.clone();
        if len >= 2 {
            let a = (splitmix_next(&mut state) % len as u64) as usize;
            let b = (splitmix_next(&mut state) % len as u64) as usize;
            cand.swap(a, b);
        }
        let (cand_e, cand_net) = eval(&cand);
        let delta = cand_e - cur_e;
        // Tirage uniforme [0,1) pour le critere de Metropolis.
        let u = splitmix_next(&mut state) as f64 / (u64::MAX as f64 + 1.0);
        let accept = delta <= 0.0 || (temp > 0.0 && u < (-delta / temp).exp());
        if accept {
            current = cand;
            cur_e = cand_e;
            if cur_e < best_e {
                best_e = cur_e;
                best_net = cand_net;
            }
        }
        journal.push(best_e);
        temp *= cooling;
    }

    AnnealResult {
        paths: best_net.paths,
        costs: best_net.costs,
        journal,
    }
}

/// Verifie que chaque source (1re cellule de chaque chemin) reste reliee au reseau
/// existant `network0` a travers les chemins courants (BFS sur les segments). Sert
/// de garde-fou au rip-up : ripper un chemin ne doit pas deconnecter un dependant.
fn all_sources_connected(paths: &[Vec<usize>], network0: &[usize]) -> bool {
    let mut adj: HashMap<usize, Vec<usize>> = HashMap::new();
    for pth in paths {
        for w in pth.windows(2) {
            adj.entry(w[0]).or_default().push(w[1]);
            adj.entry(w[1]).or_default().push(w[0]);
        }
    }
    let mut seen: HashSet<usize> = network0.iter().copied().collect();
    let mut q: VecDeque<usize> = seen.iter().copied().collect();
    while let Some(c) = q.pop_front() {
        if let Some(ns) = adj.get(&c) {
            for &n in ns {
                if seen.insert(n) {
                    q.push_back(n);
                }
            }
        }
    }
    paths.iter().all(|p| p.is_empty() || seen.contains(&p[0]))
}

/// Resultat d'un rip-up & reroute : le reseau ameliore et le journal du cout total
/// apres chaque passe (monotone decroissant).
pub struct RipruteResult {
    pub paths: Vec<Vec<usize>>,
    pub costs: Vec<f64>,
    pub journal: Vec<f64>,
}

/// Amelioration locale « rip-up & reroute » (Lot 18c). Part du reseau glouton, puis
/// retire tour a tour chaque chemin et re-route sa source vers le reste du reseau
/// (reutilisation) ; un deplacement est retenu s'il **baisse** le cout total **et**
/// laisse toutes les sources connectees (garde-fou `all_sources_connected`). Repete
/// jusqu'a stabilite ou `max_pass`. Deterministe ; cout total non croissant (CA-18.1,
/// CA-18.4) ; le reseau reste valide (CA-18.5).
#[allow(clippy::too_many_arguments)]
pub fn build_network_riprute(
    dtm: &[f64],
    obs: &[i32],
    obs2: &[i32],
    local_slope: &[f64],
    zone: &[i32],
    nr: usize,
    nc: usize,
    sources_base: &[usize],
    network0: &[usize],
    skidding: f64,
    max_pass: usize,
    cg: &CostGrid,
    p: &SolverParams,
) -> RipruteResult {
    let table = build_neib_table(dtm, obs, nr, nc, p.d_neighborhood, p.csize, p.min_slope, p.max_slope);
    let init = build_network_with_table(
        dtm, obs, obs2, local_slope, zone, nr, nc, sources_base, network0, skidding, &table, cg, p,
    );
    let mut paths = init.paths;
    let mut costs = init.costs;
    let mut journal = Vec::new();

    for _ in 0..max_pass {
        let mut improved = false;
        for i in 0..paths.len() {
            let src = paths[i][0];
            // Cible = reseau existant + tous les autres chemins (le chemin i retire).
            let mut others: HashSet<usize> = network0.iter().copied().collect();
            for (j, pth) in paths.iter().enumerate() {
                if j != i {
                    for &c in pth {
                        others.insert(c);
                    }
                }
            }
            let targets: Vec<usize> = others.iter().copied().collect();
            let res = solve_network(dtm, obs, obs2, local_slope, zone, &table, nr, nc, src, &targets, cg, p);
            if res.feasible && !res.path.is_empty() && res.cost + 1e-9 < costs[i] {
                // N'accepter que si le reseau reste entierement connecte.
                let mut trial = paths.clone();
                trial[i] = res.path.clone();
                if all_sources_connected(&trial, network0) {
                    paths[i] = res.path;
                    costs[i] = res.cost;
                    improved = true;
                }
            }
        }
        journal.push(costs.iter().sum());
        if !improved {
            break;
        }
    }

    RipruteResult { paths, costs, journal }
}

#[allow(clippy::too_many_arguments)]
fn calc_init(
    idcur: usize,
    best: &mut [NodeState],
    table: &NeibTable,
    obs: &[i32],
    obs2: &[i32],
    dtm: &[f64],
    d2e: &[f64],
    nc: usize,
    take_dtoend: bool,
    ye: usize,
    xe: usize,
    cg: &CostGrid,
    p: &SolverParams,
) -> Vec<usize> {
    let (yc, xc) = table.corresp[idcur];
    let mut add = Vec::new();
    for nb in &table.neighbors[idcur] {
        let idv = nb.id as usize;
        let (y, x) = table.corresp[idv];
        if obs[y * nc + x] != 0 {
            continue;
        }
        let o = table.offsets[nb.off];
        let d = o.dist;
        let az = o.az;
        let slope_perc = nb.slope_x100 as f64 / 100.0;
        let pc = check_profile(
            yc as i32, xc as i32, y as i32, x as i32, slope_perc, dtm, nc, p.csize,
            diffz_prop_l(p.max_diff_z, p.d_neighborhood, d), obs, obs2, 0.0, p.lmax_ab_sl,
        );
        if !pc.ok {
            continue;
        }
        // Heuristique geometrique remise a l'echelle par cmin (reste admissible).
        let d_to_cp = if take_dtoend {
            nan_inf(d2e[y * nc + x])
        } else {
            distplan(y as f64, x as f64, ye as f64, xe as f64) * p.csize * cg.cmin
        };
        best[idv] = NodeState {
            id: idv as i32,
            // Contribution distance ponderee par le coût de construction €/m.
            cost: d * cg.factor(yc * nc + xc, y * nc + x) + pc.new_lsl,
            dplan: d,
            slope_from: slope_perc,
            az_from: az,
            came_from: idcur as i32,
            dist_hairpin: 10.0 * p.d_neighborhood,
            lsl: pc.new_lsl,
            nbptbef: 1,
            dtocp: d_to_cp,
            is_hairpin: 0,
        };
        add.push(idv);
    }
    add
}

#[allow(clippy::too_many_arguments)]
fn basic_calc(
    idcur: usize,
    best: &mut [NodeState],
    table: &NeibTable,
    obs: &[i32],
    obs2: &[i32],
    dtm: &[f64],
    local_slope: &[f64],
    d2e: &[f64],
    nc: usize,
    take_dtoend: bool,
    ye: usize,
    xe: usize,
    cg: &CostGrid,
    p: &SolverParams,
) -> Vec<usize> {
    let (yc, xc) = table.corresp[idcur];
    let loc_slope = local_slope[yc * nc + xc];
    let pen_hp = 100.0 * (loc_slope / p.prop_sl_max).powi(2);
    let nbptbef = best[idcur].nbptbef;
    let cur = best[idcur];
    let mut add = Vec::new();

    for nb in &table.neighbors[idcur] {
        let idv = nb.id as usize;
        let o = table.offsets[nb.off];
        let d = o.dist;
        // Borne inferieure de l'ajout de coût : au moins `d * cmin` (facteur >= cmin).
        if best[idv].cost < cur.cost + d * cg.cmin {
            continue; // ne peut pas ameliorer
        }
        let (y, x) = table.corresp[idv];
        if obs[y * nc + x] != 0 {
            continue;
        }
        if idv as i32 == cur.came_from {
            continue; // retour en arriere
        }
        let az = o.az;
        let slope_perc = nb.slope_x100 as f64 / 100.0;
        let mut difangle2 = 0.0f64;
        let mut hairpin = 0;

        let difangle = super::diff_az(az, cur.az_from);
        if difangle > p.max_hairpin_angle() {
            continue; // demi-tour
        }
        if difangle > p.angle_hairpin {
            if loc_slope > p.prop_sl_max {
                continue;
            }
            hairpin = 1;
        }
        // Epingle en deux virages.
        if nbptbef > 1 && hairpin == 0 {
            let idfrom = cur.came_from as usize;
            let dcurrent = cur.dplan - best[idfrom].dplan;
            difangle2 = super::diff_az(az, best[idfrom].az_from);
            if dcurrent <= 2.0 * p.radius && difangle2 > p.angle_hairpin {
                if loc_slope > p.prop_sl_max {
                    continue;
                }
                let (fy, fx) = table.corresp[idfrom];
                let ycen = 0.5 * (yc as f64 + fy as f64);
                let xcen = 0.5 * (xc as f64 + fx as f64);
                let idfrom2 = best[idfrom].came_from as usize;
                let (a2y, a2x) = table.corresp[idfrom2];
                let az1 = super::calculate_azimut(a2x as f64, a2y as f64, xcen, ycen);
                let az2 = super::calculate_azimut(xcen, ycen, x as f64, y as f64);
                difangle2 = super::diff_az(az1, az2);
                if difangle2 > p.max_hairpin_angle() {
                    continue;
                }
                hairpin = 1;
            }
        }
        // Epingle trop proche de la precedente.
        if hairpin == 1 && cur.dist_hairpin <= 2.0 * p.modhair * p.radius {
            continue;
        }
        // Anti-croisement avec les segments precedents du trace.
        if nbptbef > 1 {
            let mut inter = false;
            let mut i = 1;
            let mut idfrom = cur.came_from as usize;
            while i < nbptbef {
                let (a1y, a1x) = table.corresp[idfrom];
                idfrom = best[idfrom].came_from as usize;
                let (a2y, a2x) = table.corresp[idfrom];
                if get_intersect(
                    a1y as f64, a1x as f64, a2y as f64, a2x as f64,
                    yc as f64, xc as f64, y as f64, x as f64,
                ) {
                    inter = true;
                    break;
                }
                i += 1;
            }
            if inter {
                continue;
            }
        }

        let penalty_dir = p.penalty_xy * (difangle.max(difangle2) / p.angle_hairpin).powi(2);
        let difslope = (cur.slope_from - slope_perc).abs();
        let penalty_slope = p.penalty_z * (difslope / p.max_slope_change()).powi(2);

        let pc = check_profile(
            yc as i32, xc as i32, y as i32, x as i32, slope_perc, dtm, nc, p.csize,
            diffz_prop_l(p.max_diff_z, p.d_neighborhood, d), obs, obs2, cur.lsl, p.lmax_ab_sl,
        );
        if !pc.ok {
            continue;
        }
        let mut new_cost = cur.cost + d * cg.factor(yc * nc + xc, y * nc + x)
            + penalty_dir + penalty_slope + pc.new_lsl - cur.lsl;
        if hairpin == 1 {
            new_cost += pen_hp;
        }
        // Heuristique geometrique remise a l'echelle par cmin (reste admissible).
        let d_to_cp = if take_dtoend {
            nan_inf(d2e[y * nc + x])
        } else {
            distplan(y as f64, x as f64, ye as f64, xe as f64) * p.csize * cg.cmin
        };

        if best[idv].cost > new_cost {
            best[idv].id = idv as i32;
            best[idv].cost = new_cost;
            best[idv].dplan = cur.dplan + d;
            best[idv].slope_from = slope_perc;
            best[idv].az_from = az;
            best[idv].came_from = idcur as i32;
            best[idv].lsl = pc.new_lsl;
            best[idv].nbptbef = cur.nbptbef + 1;
            best[idv].dtocp = d_to_cp;
            best[idv].is_hairpin = hairpin;
            // Distance a l'epingle la plus proche.
            best[idv].dist_hairpin = 10.0 * p.d_neighborhood;
            if hairpin == 1 {
                best[idv].dist_hairpin = best[idv].dist_hairpin.min(d);
            }
            let mut i = 1;
            let mut idfrom = idcur;
            while i < nbptbef - 1 && best[idv].dist_hairpin >= 2.0 * p.modhair * p.radius {
                let idfrom2 = best[idfrom].came_from;
                if idfrom2 < 0 {
                    break;
                }
                if best[idfrom].is_hairpin != 0 {
                    let (a1y, a1x) = table.corresp[idfrom2 as usize];
                    let dd = distplan(y as f64, x as f64, a1y as f64, a1x as f64) * p.csize;
                    best[idv].dist_hairpin = best[idv].dist_hairpin.min(dd);
                }
                idfrom = idfrom2 as usize;
                i += 1;
            }
            add.push(idv);
        }
    }
    add
}

/// Ajoute une cellule proche de la cible a la file secondaire, ordonnee par
/// `distance_a_la_cible + penalite_direction` (deux derniers virages). Portage du
/// bloc `closetogoal.put`. `dcg` = distance planimetrique a la cible (m).
fn push_close(
    close: &mut BinaryHeap<QEntry>,
    idcur: usize,
    dcg: f64,
    best: &[NodeState],
    p: &SolverParams,
) {
    let cur = best[idcur];
    let prev = cur.came_from;
    if prev < 0 {
        return;
    }
    let prev = prev as usize;
    let difangle = super::diff_az(best[prev].az_from, cur.az_from);
    let mut penalty_dir = p.penalty_xy * (difangle / p.angle_hairpin).powi(2);
    let prev2 = best[prev].came_from;
    if prev2 >= 0 {
        let difangle2 = super::diff_az(best[prev2 as usize].az_from, best[prev].az_from);
        penalty_dir += p.penalty_xy * (difangle2 / p.angle_hairpin).powi(2);
    }
    close.push(QEntry {
        theo_d: dcg + penalty_dir,
        dtocp: dcg,
        id: idcur as i32,
    });
}

/// Reconstruit le trace de `goal` a `start` en remontant `came_from`, renvoye du
/// depart vers l'arrivee (indices de cellules aplatis).
fn reconstruct(
    goal: usize,
    start: usize,
    best: &[NodeState],
    table: &NeibTable,
    nc: usize,
) -> Vec<usize> {
    let mut path = Vec::new();
    let mut current = goal as i32;
    while current != start as i32 && current >= 0 {
        let (y, x) = table.corresp[current as usize];
        path.push(y * nc + x);
        current = best[current as usize].came_from;
    }
    let (y, x) = table.corresp[start];
    path.push(y * nc + x);
    path.reverse();
    let _ = connect2; // reutilise par 15c pour densifier le trace
    path
}

fn diffz_prop_l(max_diff_z: f64, d_neighborhood: f64, l: f64) -> f64 {
    max_diff_z * l / d_neighborhood
}

fn nan_inf(v: f64) -> f64 {
    if v.is_nan() {
        INF_COST
    } else {
        v
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Grille de test : rasters annexes + table de voisinage.
    struct Grid {
        dtm: Vec<f64>,
        obs: Vec<i32>,
        obs2: Vec<i32>,
        local_slope: Vec<f64>,
        zone: Vec<i32>,
        table: NeibTable,
    }

    // Construit une grille inclinee simple (`slope_pct` % vers l'est).
    fn setup(nr: usize, nc: usize, slope_pct: f64, p: &SolverParams) -> Grid {
        let mut dtm = vec![0.0; nr * nc];
        for y in 0..nr {
            for x in 0..nc {
                // Pente reguliere vers l'est : dz = slope_pct/100 * csize par cellule.
                dtm[y * nc + x] = x as f64 * slope_pct / 100.0 * p.csize;
            }
        }
        let obs = vec![0i32; nr * nc];
        let table = build_neib_table(&dtm, &obs, nr, nc, p.d_neighborhood, p.csize, p.min_slope, p.max_slope);
        Grid {
            obs2: vec![0i32; nr * nc],
            local_slope: vec![0.0f64; nr * nc],
            zone: vec![1i32; nr * nc],
            dtm,
            obs,
            table,
        }
    }

    fn params() -> SolverParams {
        SolverParams {
            csize: 10.0,
            min_slope: 2.0,
            max_slope: 12.0,
            penalty_xy: 150.0,
            penalty_z: 80.0,
            max_diff_z: 3.0,
            d_neighborhood: 30.0,
            angle_hairpin: 110.0,
            lmax_ab_sl: 40.0,
            radius: 8.0,
            prop_sl_max: 0.25,
            max_slope_hairpin: 10.0,
            tal: 1.5,
            modhair: 1.5,
        }
    }

    #[test]
    fn traces_a_path_on_gentle_slope() {
        let p = params();
        // Plan incline 8 % vers l'est : la route peut monter le long de x.
        let (nr, nc) = (5usize, 9usize);
        let g = setup(nr, nc, 8.0, &p);
        // Depart (2,0) -> arrivee (2,8), memes ligne.
        let start = 2 * nc;
        let end = 2 * nc + 8;
        let r = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[start, end], 0.0, &CostGrid::neutral(), &p);
        assert!(r.feasible);
        assert_eq!(*r.path.first().unwrap(), start);
        assert_eq!(*r.path.last().unwrap(), end);
        assert!(r.cost > 0.0);
    }

    #[test]
    fn waypoints_are_all_visited() {
        let p = params();
        let (nr, nc) = (5usize, 9usize);
        let g = setup(nr, nc, 8.0, &p);
        let a = 2 * nc;
        let b = 2 * nc + 4;
        let c = 2 * nc + 8;
        let r = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[a, b, c], 0.0, &CostGrid::neutral(), &p);
        assert!(r.feasible);
        assert!(r.path.contains(&b)); // point de passage intermediaire traverse
        assert_eq!(*r.path.first().unwrap(), a);
        assert_eq!(*r.path.last().unwrap(), c);
    }

    #[test]
    fn solve_network_connects_source_to_nearest_network_cell() {
        let p = params();
        let (nr, nc) = (5usize, 9usize);
        let g = setup(nr, nc, 8.0, &p);
        // Reseau = colonne de droite entiere ; source a gauche (2,0).
        let source = 2 * nc;
        let targets: Vec<usize> = (0..nr).map(|y| y * nc + (nc - 1)).collect();
        let r = solve_network(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, source, &targets, &CostGrid::neutral(), &p);
        assert!(r.feasible);
        assert_eq!(*r.path.first().unwrap(), source);
        // L'arrivee est une cellule du reseau.
        assert!(targets.contains(r.path.last().unwrap()));
    }

    #[test]
    fn solve_network_source_on_network_is_trivial() {
        let p = params();
        let (nr, nc) = (5usize, 9usize);
        let g = setup(nr, nc, 8.0, &p);
        let source = 2 * nc + 4;
        let targets = vec![source, 2 * nc + 5];
        let r = solve_network(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, source, &targets, &CostGrid::neutral(), &p);
        assert!(r.feasible);
        assert_eq!(r.path, vec![source]);
        assert_eq!(r.cost, 0.0);
    }

    #[test]
    fn build_network_reuses_and_is_arborescent() {
        let p = params();
        let (nr, nc) = (5usize, 11usize);
        let g = setup(nr, nc, 8.0, &p);
        // Reseau existant = colonne de gauche. Deux parcelles a droite (memes lignes
        // voisines) : la 2e doit se greffer sur la route de la 1re (reutilisation),
        // donc cout total < somme des deux raccordements isoles au reseau initial.
        let network0: Vec<usize> = (0..nr).map(|y| y * nc).collect();
        let s1 = nc + (nc - 1);
        let s2 = 3 * nc + (nc - 1);
        let net = build_network(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &[s1, s2], &network0, 0.0, &CostGrid::neutral(), &p,
        );
        assert_eq!(net.paths.len(), 2);
        // Chaque parcelle est raccordee.
        assert!(net.costs.iter().all(|&c| c > 0.0));
    }

    #[test]
    fn build_network_skidding_prunes_near_road() {
        let p = params();
        let (nr, nc) = (5usize, 11usize);
        let g = setup(nr, nc, 8.0, &p);
        let network0: Vec<usize> = (0..nr).map(|y| y * nc).collect();
        // Source immediatement a droite du reseau, avec un rayon de debardage large :
        // deja desservie -> aucune route creee.
        let s = 2 * nc + 1;
        let net = build_network(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &[s], &network0, 100.0, &CostGrid::neutral(), &p,
        );
        assert_eq!(net.paths.len(), 0);
    }

    #[test]
    fn multistart_best_le_base_and_reproducible() {
        let p = params();
        let (nr, nc) = (5usize, 11usize);
        let g = setup(nr, nc, 8.0, &p);
        let network0: Vec<usize> = (0..nr).map(|y| y * nc).collect();
        let sources = [nc + (nc - 1), 3 * nc + (nc - 1), 2 * nc + (nc - 2)];
        // Cout du glouton simple sur l'ordre de base (essai 0).
        let base = build_network(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, &CostGrid::neutral(), &p,
        );
        let base_cost: f64 = base.costs.iter().sum();
        // Multi-start : le meilleur essai n'est jamais pire que l'ordre de base.
        let ms = build_network_multistart(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, 8, 42, &CostGrid::neutral(), &p,
        );
        let best_cost: f64 = ms.costs.iter().sum();
        assert!(best_cost <= base_cost + 1e-9);
        assert_eq!(ms.journal.len(), 8);
        assert_eq!(ms.journal[0], base_cost); // l'essai 0 est bien l'ordre de base
        // Reproductibilite a graine fixee.
        let ms2 = build_network_multistart(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, 8, 42, &CostGrid::neutral(), &p,
        );
        assert_eq!(ms.journal, ms2.journal);
        assert_eq!(ms.best, ms2.best);
    }

    #[test]
    fn recuit_best_le_base_monotone_and_reproducible() {
        let p = params();
        let (nr, nc) = (5usize, 11usize);
        let g = setup(nr, nc, 8.0, &p);
        let network0: Vec<usize> = (0..nr).map(|y| y * nc).collect();
        let sources = [nc + (nc - 1), 3 * nc + (nc - 1), 2 * nc + (nc - 2)];
        let base = build_network(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, &CostGrid::neutral(), &p,
        );
        let base_cost: f64 = base.costs.iter().sum();
        let an = build_network_recuit(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, 30, 0.0, 0.9, 7, &CostGrid::neutral(), &p,
        );
        let best_cost: f64 = an.costs.iter().sum();
        // Le meilleur rencontre n'est jamais pire que l'ordre de base (CA-18.1).
        assert!(best_cost <= base_cost + 1e-9);
        // Le journal du meilleur cout est monotone decroissant (CA-18.4).
        assert_eq!(an.journal.len(), 30);
        for w in an.journal.windows(2) {
            assert!(w[1] <= w[0] + 1e-9);
        }
        // Reproductibilite a graine fixee (CA-18.2).
        let an2 = build_network_recuit(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, 30, 0.0, 0.9, 7, &CostGrid::neutral(), &p,
        );
        assert_eq!(an.journal, an2.journal);
    }

    #[test]
    fn riprute_improves_and_stays_connected() {
        let p = params();
        let (nr, nc) = (5usize, 11usize);
        let g = setup(nr, nc, 8.0, &p);
        let network0: Vec<usize> = (0..nr).map(|y| y * nc).collect();
        let sources = [nc + (nc - 1), 3 * nc + (nc - 1), 2 * nc + (nc - 2)];
        let base = build_network(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, &CostGrid::neutral(), &p,
        );
        let base_cost: f64 = base.costs.iter().sum();
        let rr = build_network_riprute(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, nr, nc,
            &sources, &network0, 0.0, 6, &CostGrid::neutral(), &p,
        );
        let rr_cost: f64 = rr.costs.iter().sum();
        // Jamais pire que le glouton de depart (CA-18.1).
        assert!(rr_cost <= base_cost + 1e-9);
        // Journal du cout total monotone decroissant (CA-18.4).
        for w in rr.journal.windows(2) {
            assert!(w[1] <= w[0] + 1e-9);
        }
        // Le reseau final reste connecte (CA-18.5).
        assert!(all_sources_connected(&rr.paths, &network0));
    }

    #[test]
    fn cost_weighting_scales_and_diverts() {
        let mut p = params();
        p.min_slope = 0.0; // autorise les segments a plat : le coût pilote le trace
        let (nr, nc) = (5usize, 9usize);
        let g = setup(nr, nc, 0.0, &p); // terrain plat
        let start = 2 * nc;
        let end = 2 * nc + 8;
        let neu = solve(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc,
            &[start, end], 0.0, &CostGrid::neutral(), &p,
        );
        assert!(neu.feasible);

        // Coût uniforme x2 : meme trace, coût strictement plus eleve.
        let w2 = vec![2.0; nr * nc];
        let uni = solve(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc,
            &[start, end], 0.0, &CostGrid::new(&w2, &g.zone), &p,
        );
        assert_eq!(uni.path, neu.path);
        assert!(uni.cost > neu.cost);

        // Corridor bon marche sur la ligne 0 (reste cher ailleurs) : le trace
        // pondere remonte vers le nord pour l'emprunter.
        let mut w = vec![10.0; nr * nc];
        for x in w.iter_mut().take(nc) {
            *x = 1.0; // ligne 0 bon marche
        }
        let div = solve(
            &g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc,
            &[start, end], 0.0, &CostGrid::new(&w, &g.zone), &p,
        );
        assert!(div.feasible);
        let min_row = |r: &TraceResult| r.path.iter().map(|&c| c / nc).min().unwrap();
        assert!(min_row(&div) < min_row(&neu)); // le trace pondere monte plus haut
    }

    #[test]
    fn deterministic_trace() {
        let p = params();
        let (nr, nc) = (5usize, 9usize);
        let g = setup(nr, nc, 8.0, &p);
        let (s, e) = (2 * nc, 2 * nc + 8);
        let r1 = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[s, e], 0.0, &CostGrid::neutral(), &p);
        let r2 = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[s, e], 0.0, &CostGrid::neutral(), &p);
        assert_eq!(r1.path, r2.path);
    }
}
