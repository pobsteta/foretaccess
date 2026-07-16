//! Solveur A* de trace de desserte (portage de `Astar_force_wp`, `calc_init`,
//! `basic_calc`, `reconstruct_path` de SylvaRoad).
//!
//! A* sur le graphe a voisinage disque (`neighborhood`), heuristique = distance
//! inverse depuis la cible (`heuristic`). Le cout de transition est **geometrique
//! + penalites** (direction, pente, devers), fidele a SylvaRoad : la route
//! minimise sa longueur sous contraintes de constructibilite. Gestion des epingles
//! (rayon de braquage `radius`, angle limite), controle du profil (`check_profile`)
//! et anti-croisement du trace.
//!
//! Etat par noeud (`NodeState`), indexe par id-pixel, calque sur la matrice `Best`
//! a 11 colonnes de SylvaRoad :
//! `cost` (g), `dplan`, `slope_from`, `az_from`, `came_from`, `dist_hairpin`,
//! `lsl`, `nbptbef`, `dtocp` (h), `is_hairpin`.

use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashSet};

use super::geom::{check_profile, connect2, distplan, get_intersect};
use super::heuristic::dist_to_end;
use super::neighborhood::NeibTable;

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
    p: &SolverParams,
) -> TraceResult {
    let n_pix = table.n_pix();
    let mut best = vec![NodeState::empty(); n_pix];

    // Heuristique : distance inverse depuis la cible FINALE (dernier waypoint).
    let last = *waypoints.last().unwrap();
    let d2e = dist_to_end(zone, nr, nc, p.csize, last / nc, last % nc, 1.0e9);

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
                calc_init(idcur, &mut best, table, obs, obs2, dtm, &d2e, nc, take_dtoend, ye, xe, p)
            } else {
                // Finition a proximite de la cible (dernier segment).
                if seg_bufgoal > 0.0 {
                    let (yc, xc) = table.corresp[idcur];
                    let dcg = distplan(yc as f64, xc as f64, ye as f64, xe as f64) * p.csize;
                    if dcg <= seg_bufgoal {
                        push_close(&mut close, idcur, dcg, &best, p);
                    }
                }
                basic_calc(idcur, &mut best, table, obs, obs2, dtm, local_slope, &d2e, nc, take_dtoend, ye, xe, p)
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
        let d_to_cp = if take_dtoend {
            nan_inf(d2e[y * nc + x])
        } else {
            distplan(y as f64, x as f64, ye as f64, xe as f64) * p.csize
        };
        best[idv] = NodeState {
            id: idv as i32,
            cost: d + pc.new_lsl,
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
        if best[idv].cost < cur.cost + d {
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
        let mut new_cost = cur.cost + d + penalty_dir + penalty_slope + pc.new_lsl - cur.lsl;
        if hairpin == 1 {
            new_cost += pen_hp;
        }
        let d_to_cp = if take_dtoend {
            nan_inf(d2e[y * nc + x])
        } else {
            distplan(y as f64, x as f64, ye as f64, xe as f64) * p.csize
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
    use crate::desserte::neighborhood::build_neib_table;

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
        let r = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[start, end], 0.0, &p);
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
        let r = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[a, b, c], 0.0, &p);
        assert!(r.feasible);
        assert!(r.path.contains(&b)); // point de passage intermediaire traverse
        assert_eq!(*r.path.first().unwrap(), a);
        assert_eq!(*r.path.last().unwrap(), c);
    }

    #[test]
    fn deterministic_trace() {
        let p = params();
        let (nr, nc) = (5usize, 9usize);
        let g = setup(nr, nc, 8.0, &p);
        let (s, e) = (2 * nc, 2 * nc + 8);
        let r1 = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[s, e], 0.0, &p);
        let r2 = solve(&g.dtm, &g.obs, &g.obs2, &g.local_slope, &g.zone, &g.table, nr, nc, &[s, e], 0.0, &p);
        assert_eq!(r1.path, r2.path);
    }
}
