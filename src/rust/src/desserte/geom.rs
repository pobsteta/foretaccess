//! Primitives geometriques du solveur de trace (portage SylvaRoad).
//!
//! `connect2` (rasterisation d'un segment facon DDA), `get_intersect` (test
//! d'intersection de deux segments) et `check_profile` (controle du profil en
//! long : garde a l'altitude theorique de la route, obstacles, cumul de devers
//! excessif). Toutes portees au mot pres de `SylvaRoad_1_cython.pyx`.

/// Distance planimetrique entre deux cellules (en cellules, non multipliee par la
/// resolution). Portage de `Distplan`.
pub fn distplan(y: f64, x: f64, ye: f64, xe: f64) -> f64 {
    ((y - ye) * (y - ye) + (x - xe) * (x - xe)).sqrt()
}

/// Rasterise le segment de `(yc, xc)` a `(y, x)` en cellules connexes (une par
/// ligne ou par colonne selon l'axe dominant). Portage de `connect2` : DDA a
/// division entiere tronquee vers zero, extremites incluses.
pub fn connect2(yc: i32, xc: i32, y: i32, x: i32) -> Vec<(i32, i32)> {
    let d0 = y - yc;
    let d1 = x - xc;
    let mut out = Vec::new();
    if d0.abs() > d1.abs() {
        let sign = if d0 < 0 { -1 } else { 1 };
        let ad0 = d0.abs();
        for k in 0..=ad0 {
            let row = yc + sign * k;
            let col = if d1 == 0 {
                xc
            } else {
                // arange(xc*ad0 + floor(ad0/2), ..., d1) / ad0, tronque vers zero.
                let num = xc * ad0 + ad0 / 2 + k * d1;
                num / ad0
            };
            out.push((row, col));
        }
    } else {
        let sign = if d1 < 0 { -1 } else { 1 };
        let ad1 = d1.abs();
        if ad1 == 0 {
            // (yc, xc) == (y, x) : une seule cellule.
            out.push((yc, xc));
            return out;
        }
        for k in 0..=ad1 {
            let col = xc + sign * k;
            let row = if d0 == 0 {
                yc
            } else {
                let num = yc * ad1 + ad1 / 2 + k * d0;
                num / ad1
            };
            out.push((row, col));
        }
    }
    out
}

/// Teste si les segments `[a1, a2]` et `[b1, b2]` (coordonnees `y, x`) se
/// coupent. Portage de `get_intersect` (coordonnees homogenes + bornes de boite).
#[allow(clippy::too_many_arguments)]
pub fn get_intersect(
    a1y: f64,
    a1x: f64,
    a2y: f64,
    a2x: f64,
    b1y: f64,
    b1x: f64,
    b2y: f64,
    b2x: f64,
) -> bool {
    let l1y = a1x - a2x;
    let l1x = a2y - a1y;
    let l1z = a1y * a2x - a1x * a2y;

    let l2y = b1x - b2x;
    let l2x = b2y - b1y;
    let l2z = b1y * b2x - b1x * b2y;

    let yy = l1x * l2z - l1z * l2x;
    let xx = l1z * l2y - l1y * l2z;
    let zz = l1y * l2x - l1x * l2y;

    if zz == 0.0 {
        return false; // paralleles
    }
    let (xi, yi) = (xx / zz, yy / zz);
    // Le point d'intersection des droites doit tomber dans la boite commune aux
    // deux segments (bornes de `get_intersect`).
    let x_lo = a1x.min(a2x).max(b1x.min(b2x));
    let x_hi = a1x.max(a2x).min(b1x.max(b2x));
    let y_lo = a1y.min(a2y).max(b1y.min(b2y));
    let y_hi = a1y.max(a2y).min(b1y.max(b2y));
    !(xi < x_lo || xi > x_hi || yi < y_lo || yi > y_hi)
}

/// Resultat de `check_profile` : faisabilite du segment et longueur cumulee de
/// devers excessif mise a jour.
pub struct ProfileCheck {
    pub ok: bool,
    pub new_lsl: f64,
}

/// Controle du profil en long entre `(yc, xc)` et `(y, x)`, pente `slope_perc`
/// (%). Portage de `check_profile` :
/// * rejet si un obstacle (`obs > 0`) est traverse ;
/// * rejet si l'ecart entre l'altitude theorique de la route (`slope * Dhor + zo`)
///   et le terrain depasse `max_diff_z` (deja proportionnalise a la longueur) ;
/// * accumulation de devers excessif (`obs2`) plafonnee a `lmax_ab_sl`.
///
/// `dtm`/`obs`/`obs2` sont aplaties ligne par ligne (grille `nc` colonnes).
#[allow(clippy::too_many_arguments)]
pub fn check_profile(
    yc: i32,
    xc: i32,
    y: i32,
    x: i32,
    slope_perc: f64,
    dtm: &[f64],
    nc: usize,
    csize: f64,
    max_diff_z: f64,
    obs: &[i32],
    obs2: &[i32],
    ls: f64,
    lmax_ab_sl: f64,
) -> ProfileCheck {
    let cells = connect2(yc, xc, y, x);
    let zo = dtm[yc as usize * nc + xc as usize];
    let mut diffz = 0.0f64;
    let mut sumobs2 = 0i64;
    let mut dhor = 0.0f64;
    let mut ok = true;
    for (i, &(cy, cx)) in cells.iter().enumerate() {
        let idx = cy as usize * nc + cx as usize;
        if obs[idx] > 0 {
            ok = false;
            break;
        }
        dhor = (((cx - xc) * (cx - xc) + (cy - yc) * (cy - yc)) as f64).sqrt() * csize;
        if i > 0 {
            sumobs2 += obs2[idx] as i64;
        }
        let z = dtm[idx];
        let zline = slope_perc / 100.0 * dhor + zo;
        diffz = diffz.max((zline - z).abs());
        if diffz > max_diff_z {
            ok = false;
            break;
        }
    }
    let mut new_lsl = ls;
    if ok {
        new_lsl += (sumobs2 as f64 * csize).min(dhor);
        if new_lsl > lmax_ab_sl {
            ok = false;
        }
    }
    ProfileCheck { ok, new_lsl }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connect2_horizontal_and_diagonal() {
        // Horizontal : meme ligne.
        let h = connect2(2, 0, 2, 3);
        assert_eq!(h, vec![(2, 0), (2, 1), (2, 2), (2, 3)]);
        // Diagonale exacte.
        let d = connect2(0, 0, 3, 3);
        assert_eq!(d, vec![(0, 0), (1, 1), (2, 2), (3, 3)]);
    }

    #[test]
    fn connect2_single_cell() {
        assert_eq!(connect2(4, 4, 4, 4), vec![(4, 4)]);
    }

    #[test]
    fn get_intersect_crossing_and_parallel() {
        // Deux diagonales qui se croisent.
        assert!(get_intersect(0.0, 0.0, 2.0, 2.0, 0.0, 2.0, 2.0, 0.0));
        // Deux segments paralleles.
        assert!(!get_intersect(0.0, 0.0, 0.0, 2.0, 1.0, 0.0, 1.0, 2.0));
    }

    #[test]
    fn check_profile_flat_ok_obstacle_blocks() {
        // Terrain plat, pente 0 : le profil colle, aucun obstacle -> ok.
        let nc = 5;
        let dtm = vec![100.0; 25];
        let obs = vec![0i32; 25];
        let obs2 = vec![0i32; 25];
        let r = check_profile(0, 0, 0, 4, 0.0, &dtm, nc, 10.0, 3.0, &obs, &obs2, 0.0, 40.0);
        assert!(r.ok);
        // Un obstacle sur le trajet -> rejet.
        let mut obs_b = vec![0i32; 25];
        obs_b[2] = 1; // (0,2) sur la ligne
        let r2 = check_profile(0, 0, 0, 4, 0.0, &dtm, nc, 10.0, 3.0, &obs_b, &obs2, 0.0, 40.0);
        assert!(!r2.ok);
    }

    #[test]
    fn check_profile_elevation_gap_rejected() {
        // Terrain plat mais on impose une pente 50 % : l'altitude theorique
        // s'ecarte vite du terrain -> rejet quand diffz > max_diff_z.
        let nc = 5;
        let dtm = vec![100.0; 25];
        let obs = vec![0i32; 25];
        let obs2 = vec![0i32; 25];
        let r = check_profile(0, 0, 0, 4, 50.0, &dtm, nc, 10.0, 3.0, &obs, &obs2, 0.0, 40.0);
        assert!(!r.ok);
    }
}
