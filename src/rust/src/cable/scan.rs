//! Balayage 360 deg / pixel du potentiel cable (portage Rust de l'orchestration).
//!
//! Porte la boucle chaude de `potentiel_cable()` (R) dans le crate : pour chaque
//! cellule de desserte et chacun des 360 azimuts, extraction du profil, puis
//! placement des supports intermediaires (`optpyl::optpyl_up_noh`), qui coupe la
//! ligne au plus loin s'il ne peut pas la porter entiere. Parallelise sur les
//! cellules de desserte avec `rayon`.
//!
//! Le profil sert sous deux formes, comme chez Sylvaccess : **au pixel** pour poser
//! les supports (`Line`), **au demi-metre** pour la garde au sol (`Alts`).

use crate::cable::optpyl;
use rayon::prelude::*;

/// Un rayon precalcule : cellules traversees (decalages ligne/colonne) et leur
/// distance horizontale au depart.
pub struct Ray {
    pub dl: Vec<i32>,
    pub dc: Vec<i32>,
    pub hdist: Vec<f64>,
}

/// Rayons precalcules pour les 360 azimuts. Reproduit `.rayons()` (R) :
/// pas = res/3, portee = portee_m + 1.5*res, azimut horaire depuis le nord,
/// suppression du (0,0) et des doublons consecutifs.
pub fn build_rays(res: f64, portee_m: f64) -> Vec<Ray> {
    let lmax = portee_m + 1.5 * res;
    let pas = res / 3.0;
    // seq(pas, lmax, by = pas) : t_i = i*pas, i = 1.. tant que t_i <= lmax.
    let nstep = (lmax / pas + 1e-10).floor() as i64;
    let mut rays = Vec::with_capacity(360);
    for az in 0..360 {
        let rad = az as f64 * std::f64::consts::PI / 180.0;
        let dx = rad.sin();
        let dy = rad.cos();
        let (mut dl, mut dc, mut hd) = (Vec::new(), Vec::new(), Vec::new());
        let (mut prev_l, mut prev_c) = (i32::MIN, i32::MIN);
        let mut first = true;
        for i in 1..=nstep {
            let t = i as f64 * pas;
            let cc = round_half_even(t * dx / res) as i32;
            let ll = round_half_even(-t * dy / res) as i32;
            if cc == 0 && ll == 0 {
                continue; // (0,0) exclu
            }
            if !first && cc == prev_c && ll == prev_l {
                continue; // doublon consecutif
            }
            first = false;
            prev_l = ll;
            prev_c = cc;
            let h = res * ((ll * ll + cc * cc) as f64).sqrt();
            if h <= lmax {
                dl.push(ll);
                dc.push(cc);
                hd.push(h);
            }
        }
        rays.push(Ray { dl, dc, hdist: hd });
    }
    rays
}

/// Arrondi au plus proche, demi vers le pair (comme `round()` de R / IEC 60559),
/// la ou `f64::round` arrondit demi loin de zero. Determine l'exactitude du
/// balayage vis-a-vis de l'ancienne boucle R.
fn round_half_even(x: f64) -> f64 {
    let f = x.floor();
    let diff = x - f;
    if diff < 0.5 {
        f
    } else if diff > 0.5 {
        f + 1.0
    } else if (f as i64) % 2 == 0 {
        f
    } else {
        f + 1.0
    }
}

/// Interpolation lineaire type `stats::approx(na.rm = TRUE, rule = 1)` : les
/// paires (x, y) dont y est NaN sont retirees ; hors de l'intervalle des x
/// valides, le resultat est NaN.
fn interp_dropna(hd: &[f64], za: &[f64], xs: &[f64]) -> Vec<f64> {
    let mut px = Vec::with_capacity(hd.len());
    let mut py = Vec::with_capacity(hd.len());
    for i in 0..hd.len() {
        if !za[i].is_nan() {
            px.push(hd[i]);
            py.push(za[i]);
        }
    }
    let n = px.len();
    let mut out = vec![f64::NAN; xs.len()];
    if n < 2 {
        return out;
    }
    let (xmin, xmax) = (px[0], px[n - 1]);
    let mut j = 0usize;
    for (k, &x) in xs.iter().enumerate() {
        if x < xmin || x > xmax {
            continue; // rule = 1 -> NaN hors bornes
        }
        while j + 1 < n && px[j + 1] < x {
            j += 1;
        }
        // px[j] <= x <= px[j+1]
        let (x0, x1) = (px[j], px[j + 1]);
        let (y0, y1) = (py[j], py[j + 1]);
        out[k] = if x1 == x0 { y0 } else { y0 + (y1 - y0) * (x - x0) / (x1 - x0) };
    }
    out
}

/// Une ligne candidate faisable (une par depart / azimut).
pub struct Line {
    pub dep: i32,   // cellule de depart (1-based)
    pub az: i32,    // azimut (deg)
    pub lg: f64,    // longueur faisable (m)
    pub surf: f64,  // surface foret couverte (ha)
    pub sens: i32,  // +1 aval, -1 amont, 0 plat
    pub vol: f64,   // volume (m3) ou NaN
    pub ipc: f64,   // volume / longueur ou NaN
    pub nsup: i32,  // nombre de supports intermediaires poses
}

/// Resultat du balayage.
pub struct ScanOut {
    pub couvert: Vec<bool>,
    pub longueur: Vec<f64>,
    pub azimut: Vec<f64>, // NaN si non couvert
    pub lines: Vec<Line>,
}

// Contribution d'une seule ligne a la couverture (cellule 0-based, longueur, az).
struct Cover {
    cell: usize,
    lg: f64,
    az: i32,
}

struct RouteResult {
    covers: Vec<Cover>,
    lines: Vec<Line>,
}

/// Balayage complet. `alt` et `vol` sont en ordre ligne-majeur (NaN = NA).
/// `foret[i]` vaut 1 en foret. `routes` liste les departs (1-based).
#[allow(clippy::too_many_arguments)]
pub fn scan(
    alt: &[f64],
    nr: usize,
    nc: usize,
    res: f64,
    foret: &[i32],
    routes: &[i32],
    vol: Option<&[f64]>,
    htower: f64,
    h_end: f64,
    hline_min: f64,
    hline_max: f64,
    slope_min: f64,
    slope_max: f64,
    f_o: f64,
    tmax: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    eao: f64,
    angle_intsup: f64,
    lmax: f64,
    lmin: f64,
    hintsup: f64,
    sup_max: usize,
    lmin_span: f64,
    nbconfig: usize,
) -> ScanOut {
    let n = nr * nc;
    let aire_cell = res * res;
    let rays = build_rays(res, lmax);

    // Traitement d'un depart : renvoie ses contributions de couverture + lignes.
    let une_route = |&dep_1based: &i32| -> RouteResult {
        let dep = (dep_1based - 1) as usize; // 0-based
        let dl0 = dep / nc; // ligne 0-based
        let dc0 = dep % nc; // colonne 0-based
        let mut covers = Vec::new();
        let mut lines = Vec::new();

        for (az, ray) in rays.iter().enumerate() {
            // Cellules du rayon dans la grille.
            let mut cel = Vec::with_capacity(ray.dl.len());
            let mut hd = Vec::with_capacity(ray.dl.len());
            for i in 0..ray.dl.len() {
                let l = dl0 as i64 + ray.dl[i] as i64;
                let c = dc0 as i64 + ray.dc[i] as i64;
                if l >= 0 && (l as usize) < nr && c >= 0 && (c as usize) < nc {
                    cel.push((l as usize) * nc + c as usize);
                    hd.push(ray.hdist[i]);
                }
            }
            if cel.is_empty() {
                continue;
            }
            let smax = hd.iter().cloned().fold(f64::MIN, f64::max);
            if smax < lmin {
                continue;
            }

            // Profil AU PIXEL : c'est lui qui porte les travees (`Line` chez
            // Sylvaccess). Les supports se posent sur une cellule, pas au demi-metre.
            let mut prof_hd = Vec::with_capacity(cel.len() + 1);
            let mut prof_za = Vec::with_capacity(cel.len() + 1);
            prof_hd.push(0.0);
            prof_za.push(alt[dep]);
            for i in 0..cel.len() {
                if hd[i] > lmax {
                    break;
                }
                prof_hd.push(hd[i]);
                prof_za.push(alt[cel[i]]);
            }
            if prof_hd.len() < 2 || *prof_hd.last().unwrap() < lmin {
                continue;
            }
            // Un NA d'altitude coupe le profil : on ne pose pas de cable sur un trou.
            if prof_za.iter().any(|z| z.is_nan()) {
                continue;
            }

            // Meme terrain, echantillonne au demi-metre : c'est la garde au sol
            // (`Alts`), indexee par `int(x * 2)` dans la mecanique.
            let lline = *prof_hd.last().unwrap();
            let m = (lline / 0.5).floor() as usize + 2;
            let xs: Vec<f64> = (0..m).map(|i| i as f64 * 0.5).collect();
            let zs = interp_dropna(&prof_hd, &prof_za, &xs);

            // Placement des supports intermediaires, avec coupe de la ligne a defaut.
            let par = optpyl::OptParams {
                line_x: &prof_hd,
                line_z: &prof_za,
                alts: &zs,
                htower,
                hintsup,
                hend: h_end,
                hline_min,
                hline_max,
                slope_min,
                slope_max,
                f_o,
                tmax,
                q1,
                q2,
                q3,
                eao,
                csize: res,
                angle_intsup,
                sup_max,
                lmin_span,
                nbconfig,
            };
            let spans = optpyl::optpyl_up_noh(&par);
            if spans.is_empty() {
                continue;
            }
            let longueur = prof_hd[spans.last().unwrap().posi()];
            if longueur < lmin {
                continue;
            }
            let nb_sup = spans.len() - 1;

            // Cellules couvertes (hdist <= longueur).
            let mut couv = Vec::new();
            let mut far_cell = cel[0];
            let mut far_h = f64::MIN;
            for i in 0..cel.len() {
                if hd[i] <= longueur {
                    couv.push(cel[i]);
                    covers.push(Cover { cell: cel[i], lg: longueur, az: az as i32 });
                    if hd[i] > far_h {
                        far_h = hd[i];
                        far_cell = cel[i];
                    }
                }
            }
            if couv.is_empty() {
                continue;
            }

            // Cellules forestieres couvertes.
            let cf: Vec<usize> = couv.iter().cloned().filter(|&c| foret[c] == 1).collect();
            if cf.is_empty() {
                continue;
            }
            let surf = cf.len() as f64 * aire_cell / 10000.0;
            let sens = (alt[far_cell] - alt[dep]).signum();
            let sens = if (alt[far_cell] - alt[dep]) == 0.0 { 0 } else { sens as i32 };
            let (vol_l, ipc_l) = match vol {
                Some(v) => {
                    let s: f64 = cf.iter().map(|&c| if v[c].is_nan() { 0.0 } else { v[c] }).sum();
                    let vv = s * aire_cell / 10000.0;
                    (vv, vv / longueur)
                }
                None => (f64::NAN, f64::NAN),
            };
            lines.push(Line {
                dep: dep_1based,
                az: az as i32,
                lg: longueur,
                surf,
                sens,
                vol: vol_l,
                ipc: ipc_l,
                nsup: nb_sup as i32,
            });
        }
        RouteResult { covers, lines }
    };

    // Parallelise sur les departs, ordre preserve pour une reduction fidele au R.
    let per_route: Vec<RouteResult> = routes.par_iter().map(une_route).collect();

    let mut couvert = vec![false; n];
    let mut longueur = vec![0.0f64; n];
    let mut azimut = vec![f64::NAN; n];
    let mut lines = Vec::new();
    for rr in per_route {
        for cv in rr.covers {
            couvert[cv.cell] = true;
            if cv.lg > longueur[cv.cell] {
                longueur[cv.cell] = cv.lg;
                azimut[cv.cell] = cv.az as f64;
            }
        }
        lines.extend(rr.lines);
    }

    ScanOut { couvert, longueur, azimut, lines }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rays_cover_360_and_exclude_center() {
        let rays = build_rays(5.0, 100.0);
        assert_eq!(rays.len(), 360);
        for r in &rays {
            for i in 0..r.dl.len() {
                assert!(!(r.dl[i] == 0 && r.dc[i] == 0));
            }
            // hdist croissant.
            for i in 1..r.hdist.len() {
                assert!(r.hdist[i] >= r.hdist[i - 1] - 1e-9);
            }
        }
    }

    #[test]
    fn interp_linear_and_dropna() {
        let hd = [0.0, 1.0, 2.0];
        let za = [0.0, f64::NAN, 4.0];
        let xs = [0.0, 1.0, 2.0, 3.0];
        let zs = interp_dropna(&hd, &za, &xs);
        assert!((zs[0] - 0.0).abs() < 1e-9);
        assert!((zs[1] - 2.0).abs() < 1e-9); // interpole a travers le NaN
        assert!((zs[2] - 4.0).abs() < 1e-9);
        assert!(zs[3].is_nan()); // hors bornes
    }
}
