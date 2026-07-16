//! Table de voisinage etendu (disque) filtree par la pente en long.
//!
//! Portage de `build_NeibTable` (Python) et `build_Tab_neibs` (Cython) de
//! SylvaRoad. Pour un rayon `d_neighborhood`, on enumere tous les decalages du
//! **disque** autour d'une cellule (hors centre) avec leur azimut et leur distance
//! planimetrique. Puis, pour chaque cellule **franchissable**, on ne retient que
//! les voisins dont la **pente en long** `|dz / D| * 100` tient dans
//! `[min_slope, max_slope]` (contrainte dure, spec 015 §4.1, CA-15.2).
//!
//! Cette table alimente le solveur A* (15b) ; elle n'est pas encore exposee a R.

use super::calculate_azimut;

/// Un decalage de voisinage : position relative (ligne, colonne), azimut compas
/// (deg) et distance planimetrique (m) au centre.
#[derive(Clone, Copy, Debug)]
pub struct NeibOffset {
    pub drow: i32,
    pub dcol: i32,
    pub az: f64,
    pub dist: f64,
}

/// Enumere les decalages du disque de rayon `d_neighborhood` (m) sur une grille de
/// resolution `csize`, hors cellule centrale. Reproduit le maillage carre
/// `[-nb, nb]^2` de `build_NeibTable`, borne au disque `dist <= d_neighborhood`.
/// L'azimut suit la convention SylvaRoad `calculate_azimut(0, 0, dcol, -drow)`
/// (soit l'azimut compas naturel : +colonne = est, -ligne = nord).
pub fn build_offsets(d_neighborhood: f64, csize: f64) -> Vec<NeibOffset> {
    let nb = (d_neighborhood / csize + 0.5) as i32;
    let mut out = Vec::new();
    for drow in -nb..=nb {
        for dcol in -nb..=nb {
            if drow == 0 && dcol == 0 {
                continue;
            }
            let dist = ((drow * drow + dcol * dcol) as f64).sqrt() * csize;
            if dist > d_neighborhood {
                continue;
            }
            let az = calculate_azimut(0.0, 0.0, dcol as f64, -(drow as f64));
            out.push(NeibOffset {
                drow,
                dcol,
                az,
                dist,
            });
        }
    }
    out
}

/// Un voisin retenu pour une cellule : index du decalage dans `offsets`, id-pixel
/// du voisin, et pente en long signee (`* 100`, arrondie, comme le `Slope` int16
/// de SylvaRoad ; signe = sens de la montee).
#[derive(Clone, Copy, Debug)]
pub struct Neighbor {
    pub off: usize,
    pub id: i32,
    pub slope_x100: i32,
}

/// Table de voisinage complete pour une grille.
pub struct NeibTable {
    /// `nr * nc` : id-pixel de chaque cellule (ordre des cellules franchissables)
    /// ou `-1` si obstacle.
    pub id_pix: Vec<i32>,
    /// id-pixel -> (ligne, colonne).
    pub corresp: Vec<(usize, usize)>,
    /// Decalages du disque (partages par toutes les cellules).
    pub offsets: Vec<NeibOffset>,
    /// Pour chaque id-pixel, la liste de ses voisins franchissables et pentes.
    pub neighbors: Vec<Vec<Neighbor>>,
}

impl NeibTable {
    /// Nombre de cellules franchissables (= id-pixels).
    pub fn n_pix(&self) -> usize {
        self.corresp.len()
    }
    /// Nombre maximal de voisins retenus sur une cellule.
    pub fn max_degree(&self) -> usize {
        self.neighbors.iter().map(Vec::len).max().unwrap_or(0)
    }
}

/// Construit la table de voisinage. `dtm` = altitude (m, aplatie ligne par ligne),
/// `obs[i] != 0` = cellule non franchissable (obstacle). Les pentes en long hors
/// `[min_slope, max_slope]` (en %) sont ecartees.
pub fn build_neib_table(
    dtm: &[f64],
    obs: &[i32],
    nr: usize,
    nc: usize,
    d_neighborhood: f64,
    csize: f64,
    min_slope: f64,
    max_slope: f64,
) -> NeibTable {
    let offsets = build_offsets(d_neighborhood, csize);

    // 1. Numerotation des cellules franchissables (id-pixel), comme `IdPix`.
    let mut id_pix = vec![-1i32; nr * nc];
    let mut corresp: Vec<(usize, usize)> = Vec::new();
    for y in 0..nr {
        for x in 0..nc {
            if obs[y * nc + x] == 0 {
                id_pix[y * nc + x] = corresp.len() as i32;
                corresp.push((y, x));
            }
        }
    }

    // 2. Voisins retenus par cellule, filtres par la pente en long.
    let mut neighbors: Vec<Vec<Neighbor>> = Vec::with_capacity(corresp.len());
    for &(y, x) in &corresp {
        let z = dtm[y * nc + x];
        let mut list = Vec::new();
        for (io, o) in offsets.iter().enumerate() {
            let y1 = y as i32 + o.drow;
            let x1 = x as i32 + o.dcol;
            if y1 < 0 || y1 >= nr as i32 || x1 < 0 || x1 >= nc as i32 {
                continue;
            }
            let (y1, x1) = (y1 as usize, x1 as usize);
            let idn = id_pix[y1 * nc + x1];
            if idn < 0 {
                continue; // voisin obstacle
            }
            let z1 = dtm[y1 * nc + x1];
            let sl = (z1 - z) / o.dist * 100.0;
            let abssl = sl.abs();
            if abssl >= min_slope && abssl <= max_slope {
                let sign = if sl < 0.0 { -1 } else { 1 };
                let slope_x100 = (abssl * 100.0 + 0.5) as i32 * sign;
                list.push(Neighbor {
                    off: io,
                    id: idn,
                    slope_x100,
                });
            }
        }
        neighbors.push(list);
    }

    NeibTable {
        id_pix,
        corresp,
        offsets,
        neighbors,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offsets_are_within_disk_and_exclude_center() {
        let off = build_offsets(20.0, 10.0); // nb = 2
        assert!(!off.iter().any(|o| o.drow == 0 && o.dcol == 0));
        // Tous dans le disque de 20 m.
        assert!(off.iter().all(|o| o.dist <= 20.0 + 1e-9));
        // Le voisin (0, +1) est plein est -> azimut 90.
        let est = off.iter().find(|o| o.drow == 0 && o.dcol == 1).unwrap();
        assert!((est.az - 90.0).abs() < 1e-6);
    }

    #[test]
    fn flat_terrain_below_min_slope_keeps_no_neighbor() {
        // MNT plat : pente 0 partout, min_slope = 2 % -> aucun voisin retenu.
        let n = 25;
        let dtm = vec![100.0; n];
        let obs = vec![0i32; n];
        let t = build_neib_table(&dtm, &obs, 5, 5, 15.0, 10.0, 2.0, 12.0);
        assert_eq!(t.max_degree(), 0);
        assert_eq!(t.n_pix(), 25);
    }

    #[test]
    fn inclined_plane_keeps_only_in_range_slopes() {
        // Plan incline 10 % vers l'est (dz = +1 m par cellule de 10 m).
        let (nr, nc) = (3usize, 5usize);
        let mut dtm = vec![0.0; nr * nc];
        for y in 0..nr {
            for x in 0..nc {
                dtm[y * nc + x] = x as f64 * 1.0; // +1 m / 10 m = 10 %
            }
        }
        let obs = vec![0i32; nr * nc];
        // Fenetre d'un pas : voisins orthogonaux/diagonaux immediats.
        let t = build_neib_table(&dtm, &obs, nr, nc, 15.0, 10.0, 5.0, 12.0);
        // Cellule centrale (1,2) : ses voisins est/ouest ont pente 10 % (retenus),
        // nord/sud pente 0 % (ecartes car < 5 %).
        let idc = t.id_pix[1 * nc + 2] as usize;
        let slopes: Vec<i32> = t.neighbors[idc].iter().map(|n| n.slope_x100).collect();
        assert!(!slopes.is_empty());
        // Toutes les pentes retenues sont dans [5 %, 12 %] en valeur absolue.
        assert!(slopes.iter().all(|&s| {
            let a = (s.abs() as f64) / 100.0;
            a >= 5.0 && a <= 12.0
        }));
        // La pente plein est vaut ~10 % (1000 en centiemes de %).
        assert!(slopes.iter().any(|&s| (s.abs() - 1000).abs() <= 1));
    }

    #[test]
    fn obstacle_neighbor_is_skipped() {
        let (nr, nc) = (3usize, 3usize);
        // Plan incline pour que la pente passe le filtre.
        let mut dtm = vec![0.0; 9];
        for y in 0..nr {
            for x in 0..nc {
                dtm[y * nc + x] = x as f64;
            }
        }
        let mut obs = vec![0i32; 9];
        obs[5] = 1; // (1,2) obstacle
        let t = build_neib_table(&dtm, &obs, nr, nc, 15.0, 10.0, 5.0, 12.0);
        // Le pixel (1,2) n'a pas d'id, et aucun voisin ne pointe vers lui.
        assert_eq!(t.id_pix[5], -1);
        let idc = t.id_pix[1 * nc + 1] as usize; // (1,1)
        assert!(t.neighbors[idc].iter().all(|nb| {
            let (ry, rx) = t.corresp[nb.id as usize];
            !(ry == 1 && rx == 2)
        }));
    }
}
