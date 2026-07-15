//! Balayage radial DFCI (portage de `debusq_dfci`).
//!
//! Deux etapes, comme Sylvaccess : un **gabarit de rayons** precalcule
//! (`build_dfci_rays`, portage de `create_buffer_skidder`), puis le balayage
//! proprement dit (`scan`) qui, pour chaque pixel-source et chaque azimut, deroule
//! la lance le long du gabarit en lisant le MNT.

/// Un rayon precalcule : cellules traversees (decalages ligne/colonne) et leur
/// distance planimetrique cumulee au depart (`D_line` chez Sylvaccess).
pub struct Ray {
    pub dl: Vec<i32>,
    pub dc: Vec<i32>,
    pub dline: Vec<f64>,
}

/// Gabarit des 360 azimuts (pas de 1 deg, comme `create_buffer_skidder`). Chaque
/// rayon est une ligne droite du depart vers `(sin az, cos az) * lmax`, discretisee
/// en cellules **connexes** (traversee de grille facon supercover), triee par
/// distance planimetrique croissante. La cellule de depart `(0, 0)` ouvre chaque
/// rayon avec `dline = 0` : le balayage compare des cellules consecutives, il lui
/// faut ce point d'ancrage.
pub fn build_dfci_rays(res: f64, lmax: f64) -> Vec<Ray> {
    let portee = lmax + 1.5 * res; // Lcote : marge d'une cellule et demie
    let mut rays = Vec::with_capacity(360);
    for az in 0..360 {
        let rad = az as f64 * std::f64::consts::PI / 180.0;
        // Direction unite en (colonne, ligne) : est = +col, nord = -ligne.
        let dcx = rad.sin();
        let dcy = -rad.cos();
        let (mut dl, mut dc, mut dline) = (vec![0i32], vec![0i32], vec![0.0f64]);
        // Traversee de grille (Amanatides-Woo) depuis le centre de la cellule (0,0) :
        // on avance de frontiere en frontiere, une cellule a la fois, ce qui donne un
        // chemin connexe -- indispensable pour que `dh` entre cellules consecutives
        // soit un vrai pas de terrain.
        let (mut col, mut row) = (0i32, 0i32);
        let step_c = if dcx > 0.0 { 1 } else { -1 };
        let step_r = if dcy > 0.0 { 1 } else { -1 };
        let inf = f64::INFINITY;
        // t (en cellules le long du rayon) jusqu'a la premiere frontiere (a 0.5),
        // puis increment d'une cellule.
        let mut tmax_c = if dcx != 0.0 { 0.5 / dcx.abs() } else { inf };
        let mut tmax_r = if dcy != 0.0 { 0.5 / dcy.abs() } else { inf };
        let tdelta_c = if dcx != 0.0 { 1.0 / dcx.abs() } else { inf };
        let tdelta_r = if dcy != 0.0 { 1.0 / dcy.abs() } else { inf };
        loop {
            if tmax_c < tmax_r {
                col += step_c;
                tmax_c += tdelta_c;
            } else {
                row += step_r;
                tmax_r += tdelta_r;
            }
            let d = res * ((row * row + col * col) as f64).sqrt();
            if d > portee {
                break;
            }
            dl.push(row);
            dc.push(col);
            dline.push(d);
        }
        rays.push(Ray { dl, dc, dline });
    }
    rays
}

/// Resultat du balayage : une valeur par cellule (row-major).
pub struct ScanOut {
    /// Longueur de lance (m), `NaN` hors portee ou hors foret.
    pub dist: Vec<f64>,
    /// Denivele cellule - source (m), `NaN` hors portee ou hors foret.
    pub deniv: Vec<f64>,
    /// Cellule-source de rattachement (1-based), 0 si aucune.
    pub lien: Vec<i32>,
    /// Foret atteinte (1) ou non (0).
    pub acc: Vec<i32>,
}

/// Balayage radial DFCI (`debusq_dfci`).
///
/// `sources` : indices 1-based (row-major) des cellules du reseau DFCI, DANS
/// L'ORDRE de balayage de Sylvaccess (row-major). L'ordre fixe le depart des
/// egalites : la comparaison est `>` stricte, donc a longueur egale **la premiere
/// source traitee garde la cellule** (impacte `lien` et `deniv`).
///
/// `zone_ok` : 1 la ou la lance peut passer (pente <= seuil, pas d'obstacle, MNT
/// non nodata). Une cellule `zone_ok == 0` arrete le rayon.
///
/// `foret` : masque de foret (`Foret2` = foret INTER zone d'etude). Seule la foret
/// atteinte est defendable ; le reste finit `NaN`.
///
/// Divergence assumee vs Sylvaccess : le bug de masquage de `Deniv` (pyx L4807,
/// mauvais indices) est **corrige** -- `deniv` est bien remis a `NaN` sur toute
/// cellule non defendable.
#[allow(clippy::too_many_arguments)]
pub fn scan(
    alt: &[f64],
    nr: usize,
    nc: usize,
    res: f64,
    foret: &[i32],
    sources: &[i32],
    zone_ok: &[i32],
    lmax: f64,
) -> ScanOut {
    let n = nr * nc;
    let rays = build_dfci_rays(res, lmax);
    // Distance cumulee en centimetres (comme Sylvaccess, `int(Lcum*100+0.5)`), pour
    // que l'arrondi et le tie-break soient bit-a-bit ceux de l'oracle.
    const INF_CM: i64 = i64::MAX;
    let mut out = vec![INF_CM; n];
    let mut lien = vec![0i32; n];
    let mut deniv = vec![f64::NAN; n];

    for &src1 in sources {
        let src = (src1 - 1) as usize;
        let alt_rf = alt[src];
        if alt_rf.is_nan() {
            continue; // source sur un trou de MNT : altitude de reference absente
        }
        let (r0, c0) = ((src / nc) as i32, (src % nc) as i32);
        let mut touche = false;
        for ray in &rays {
            let mut lcum = 0.0f64;
            // Derniere cellule retenue : au depart, la source.
            let mut alt_prec = alt_rf;
            for i in 1..ray.dl.len() {
                let y = r0 + ray.dl[i];
                if y < 0 || y as usize >= nr {
                    break;
                }
                let x = c0 + ray.dc[i];
                if x < 0 || x as usize >= nc {
                    break;
                }
                let cell = y as usize * nc + x as usize;
                if zone_ok[cell] == 0 {
                    break;
                }
                let ddist = ray.dline[i] - ray.dline[i - 1];
                let dh = alt[cell] - alt_prec;
                lcum += (dh * dh + ddist * ddist).sqrt();
                if lcum > lmax {
                    break;
                }
                alt_prec = alt[cell];
                let lcum2 = (lcum * 100.0 + 0.5).floor() as i64;
                if out[cell] > lcum2 {
                    out[cell] = lcum2;
                    lien[cell] = src1;
                    let dif = alt[cell] - alt_rf;
                    deniv[cell] = if dif < 0.0 { (dif - 0.5).trunc() } else { (dif + 0.5).trunc() };
                    touche = true;
                }
            }
        }
        // La source qui a defendu au moins une cellule se dessert elle-meme (0 m).
        if touche {
            out[src] = 0;
            lien[src] = src1;
            deniv[src] = 0.0;
        }
    }

    // Finalisation : hors portee ou hors foret -> NaN ; sinon cm -> m (half-up).
    let mut dist = vec![f64::NAN; n];
    let mut acc = vec![0i32; n];
    for cell in 0..n {
        if out[cell] == INF_CM || foret[cell] == 0 {
            dist[cell] = f64::NAN;
            deniv[cell] = f64::NAN; // bug de masquage corrige (indices Y,X)
            lien[cell] = 0;
        } else {
            dist[cell] = (out[cell] as f64 / 100.0 + 0.5).floor();
            acc[cell] = 1;
        }
    }

    ScanOut { dist, deniv, lien, acc }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rays_are_connected_and_distance_sorted() {
        let rays = build_dfci_rays(5.0, 100.0);
        assert_eq!(rays.len(), 360);
        for ray in &rays {
            assert_eq!((ray.dl[0], ray.dc[0]), (0, 0));
            assert_eq!(ray.dline[0], 0.0);
            for i in 1..ray.dl.len() {
                // Distance croissante.
                assert!(ray.dline[i] >= ray.dline[i - 1] - 1e-9);
                // Cellules consecutives adjacentes (4-connexite : un seul pas).
                let dstep = (ray.dl[i] - ray.dl[i - 1]).abs() + (ray.dc[i] - ray.dc[i - 1]).abs();
                assert_eq!(dstep, 1);
            }
        }
    }

    #[test]
    fn cardinal_rays_go_straight() {
        let rays = build_dfci_rays(5.0, 50.0);
        // Est (az 90) : que des colonnes positives, ligne nulle.
        let est = &rays[90];
        for i in 1..est.dl.len() {
            assert_eq!(est.dl[i], 0);
            assert!(est.dc[i] > 0);
        }
        // Nord (az 0) : que des lignes negatives (vers le haut), colonne nulle.
        let nord = &rays[0];
        for i in 1..nord.dl.len() {
            assert_eq!(nord.dc[i], 0);
            assert!(nord.dl[i] < 0);
        }
    }

    #[test]
    fn flat_terrain_reaches_lmax_disc() {
        // Terrain plat 41x41, source au centre, portee 100 m, res 5 m -> 20 cellules.
        let (nr, nc, res) = (41usize, 41usize, 5.0);
        let n = nr * nc;
        let alt = vec![0.0f64; n];
        let foret = vec![1i32; n];
        let zone_ok = vec![1i32; n];
        let centre = (20 * nc + 20 + 1) as i32; // 1-based
        let out = scan(&alt, nr, nc, res, &foret, &[centre], &zone_ok, 100.0);
        // Source : 0 m.
        assert_eq!(out.dist[20 * nc + 20], 0.0);
        // Cellule a 10 cellules a l'est (50 m) : atteinte, ~50 m.
        let c50 = 20 * nc + 30;
        assert_eq!(out.acc[c50], 1);
        assert!((out.dist[c50] - 50.0).abs() <= 1.0);
        // Coin lointain (>100 m planimetrique) : hors portee.
        assert_eq!(out.acc[0], 0);
        assert!(out.dist[0].is_nan());
    }

    #[test]
    fn steep_cell_stops_the_ray() {
        // Une barriere zone_ok=0 juste a l'est de la source coupe la defense au-dela.
        let (nr, nc, res) = (11usize, 11usize, 5.0);
        let n = nr * nc;
        let alt = vec![0.0f64; n];
        let foret = vec![1i32; n];
        let mut zone_ok = vec![1i32; n];
        let src_rc = (5usize, 5usize);
        // Barriere sur toute la colonne a l'est immediat.
        for r in 0..nr {
            zone_ok[r * nc + 6] = 0;
        }
        let src = (src_rc.0 * nc + src_rc.1 + 1) as i32;
        let out = scan(&alt, nr, nc, res, &foret, &[src], &zone_ok, 100.0);
        // Cellule juste derriere la barriere (col 7) par l'est : non atteinte.
        assert_eq!(out.acc[5 * nc + 7], 0);
        // La barriere elle-meme : non atteinte.
        assert_eq!(out.acc[5 * nc + 6], 0);
        // A l'ouest, libre : atteinte.
        assert_eq!(out.acc[5 * nc + 3], 1);
    }
}
