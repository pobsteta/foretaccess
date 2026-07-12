//! Resolution des tensions du cable porteur.
//!
//! Portage fidele de `find_ThTvTmax` et `newton_ThTv`
//! (`sylvaccess_cython3.pyx`, CableHelp/INRAE, GPL v3). On cherche le couple
//! `(Th, Tv)` annulant simultanement `f_x` et `f_z` par Newton-Raphson a
//! Jacobien analytique, avec repli sur recherche par grille des qu'une tension
//! devient negative (hors domaine).

use super::catenaire::{df_dth, dg_dth, f_x, f_z};

/// Recherche par grille d'un amorçage `(Th, Tv)` sous la tension admissible.
///
/// Balaye `(Th, Tv)` de 0 a `tmax` par pas de `step` newtons et retient le
/// noeud dont `|f_x| + |f_z|` est minimal (arret anticipe sous 0,03). Renvoie
/// `(Th, Tv, faisable)` ou `faisable = 1` si `sqrt(Th^2 + Tv^2) <= tmax`, 0
/// sinon. `(Th, Tv) = (-1, -1)` si aucun noeud proche d'une racine.
#[allow(clippy::too_many_arguments)]
pub fn find_thtv_tmax(
    tmax: f64,
    w: f64,
    eao: f64,
    f: f64,
    pas: f64,
    d: f64,
    h: f64,
    lo: f64,
    step: u32,
) -> (f64, f64, u32) {
    let fx_min = 0.05;
    let gz_min = 0.05;
    let mut sum_min = 10.0;
    let mut th = -1.0;
    let mut tv = -1.0;
    let mut t = 1u32;
    let step = step as i64;
    let borne = tmax as i64;
    let mut i = 0i64;
    'outer: while i < borne {
        let mut j = 0i64;
        while j < borne {
            let fx = f_x(i as f64, j as f64, lo, eao, w, f, pas, d);
            if fx.abs() < fx_min {
                let gz = f_z(i as f64, j as f64, lo, eao, w, f, pas, h);
                if gz.abs() < gz_min && fx.abs() + gz.abs() < sum_min {
                    sum_min = (fx.abs() + gz.abs()).min(sum_min);
                    th = i as f64;
                    tv = j as f64;
                    if sum_min < 0.03 {
                        break 'outer;
                    }
                }
            }
            j += step;
        }
        i += step;
    }
    if (th * th + tv * tv).sqrt() > tmax {
        t = 0;
    }
    (th, tv, t)
}

/// Resout `f_x = f_z = 0` par Newton-Raphson a Jacobien analytique.
///
/// Amorce a `(th, tv)`. `h_alt` et `d` sont la difference d'altitude et la
/// portee horizontale entre supports ; `err` la precision sur le pas (defaut
/// 1,0 N). Repli sur recherche par grille (pas 100 N) des qu'une tension
/// devient negative ; au plus 20 iterations. Renvoie `(Th, Tv)`.
#[allow(clippy::too_many_arguments)]
pub fn newton_thtv(
    mut th: f64,
    mut tv: f64,
    h_alt: f64,
    d: f64,
    lo: f64,
    w: f64,
    s1: f64,
    f: f64,
    eao: f64,
    tmax: f64,
    err: f64,
) -> (f64, f64) {
    let mut h: f64 = 100.0;
    let mut k: f64 = 100.0;
    let mut it = 0u32;
    let step = 100i64;
    let fx_min = 0.05;
    let gz_min = 0.05;
    let mut sum_min = 10.0;
    while h.abs() > err && k.abs() > err {
        let fo = f_x(th, tv, lo, eao, w, f, s1, d);
        let go = f_z(th, tv, lo, eao, w, f, s1, h_alt);
        let rac1 = ((tv / th) * (tv / th) + 1.0).sqrt();
        let rac2 = (((tv - f - w) / th) * ((tv - f - w) / th) + 1.0).sqrt();
        let rac3 = (((tv - f - w * s1 / lo) / th) * ((tv - f - w * s1 / lo) / th) + 1.0).sqrt();
        let rac4 = (((tv - w * s1 / lo) / th) * ((tv - w * s1 / lo) / th) + 1.0).sqrt();
        let dftv = lo / w * (1.0 / rac1 - 1.0 / rac2 + 1.0 / rac3 - 1.0 / rac4);
        let dfth = df_dth(th, tv, f, w, s1, lo, eao, rac1, rac2, rac3, rac4);
        let dgtv = lo / eao
            + lo / (w * th)
                * (tv / rac1 - (tv - f - w) / rac2 + (tv - f - w * s1 / lo) / rac3
                    - (tv - w * s1 / lo) / rac4);
        let dgth = dg_dth(tv, th, lo, w, s1, f, rac1, rac2, rac3, rac4);
        let coeff = 1.0 / (dfth * dgtv - dftv * dgth);
        h = coeff * (-dgtv * fo + dftv * go);
        k = coeff * (dgth * fo - dfth * go);
        th += h;
        tv += k;
        it += 1;
        if th.min(tv) < 0.0 {
            // Hors domaine : repli sur recherche par grille (pas 100 N).
            it = 0;
            let borne = tmax.ceil() as i64;
            let mut i = 0i64;
            'grille: while i < borne {
                let mut j = 0i64;
                while j < borne {
                    let fx = f_x(i as f64, j as f64, lo, eao, w, f, s1, d);
                    if fx.abs() < fx_min {
                        let gz = f_z(i as f64, j as f64, lo, eao, w, f, s1, h_alt);
                        if gz.abs() < gz_min && fx.abs() + gz.abs() < sum_min {
                            sum_min = (fx.abs() + gz.abs()).min(sum_min);
                            th = i as f64;
                            tv = j as f64;
                            if sum_min < 0.03 {
                                break 'grille;
                            }
                        }
                    }
                    j += step;
                }
                i += step;
            }
        }
        if it > 20 {
            break;
        }
    }
    (th, tv)
}

#[cfg(test)]
mod tests {
    use super::super::catenaire::{calcul_xs, calcul_zs};
    use super::*;

    const G: f64 = 9.80665;

    // Meme cas de reference que catenaire.rs (parametres v3.6, travee 200 m).
    fn params() -> (f64, f64, f64, f64, f64) {
        let lo = 200.0;
        let w = 1.85 * G * lo;
        let f = G * (2500.0 + 400.0);
        let ao = 0.25 * std::f64::consts::PI * 18.0_f64.powi(2);
        let eao = 160000.0 * ao;
        let s1 = 100.0;
        (lo, w, f, eao, s1)
    }

    // Solution manufacturee : on choisit (Th0, Tv0), on en deduit la geometrie
    // (D, H) = (calcul_xs(Lo), calcul_zs(Lo)) qui annule f_x, f_z par
    // construction, puis on verifie que Newton la retrouve depuis un amorçage
    // perturbe. Oracle exact, sans execution Sylvaccess.
    #[test]
    fn newton_retrouve_la_solution_manufacturee() {
        let (lo, w, f, eao, s1) = params();
        let (th0, tv0) = (60000.0, 25000.0);
        let d = calcul_xs(th0, tv0, lo, eao, w, f, s1, lo);
        let h = calcul_zs(th0, tv0, lo, eao, w, f, s1, lo);
        let tmax = 35000.0 * G / 2.0;

        // Amorçage a +3 % : Newton doit converger vers (Th0, Tv0) a +-1 N.
        let (th, tv) = newton_thtv(th0 * 1.03, tv0 * 1.03, h, d, lo, w, s1, f, eao, tmax, 0.01);
        assert!((th - th0).abs() < 1.0, "Th={th} attendu {th0}");
        assert!((tv - tv0).abs() < 1.0, "Tv={tv} attendu {tv0}");

        // Residus quasi nuls a la solution (CA-4.2).
        assert!(f_x(th, tv, lo, eao, w, f, s1, d).abs() < 0.05);
        assert!(f_z(th, tv, lo, eao, w, f, s1, h).abs() < 0.05);

        // Fermeture geometrique : le cable rejoint le support oppose (CA-4.3).
        assert!((calcul_xs(th, tv, lo, eao, w, f, s1, lo) - d).abs() < 0.01);
        assert!((calcul_zs(th, tv, lo, eao, w, f, s1, lo) - h).abs() < 0.01);
    }

    // La grille retrouve le noeud (Th0, Tv0) place sur le pas de 50 N, et
    // marque la travee faisable (sqrt(Th^2+Tv^2) < Tmax).
    #[test]
    fn grille_trouve_le_noeud_et_juge_faisable() {
        let (lo, w, f, eao, s1) = params();
        let (th0, tv0) = (60000.0, 25000.0); // multiples de 50
        let d = calcul_xs(th0, tv0, lo, eao, w, f, s1, lo);
        let h = calcul_zs(th0, tv0, lo, eao, w, f, s1, lo);
        // Tmax juste au-dessus du noeud pour borner le balayage.
        let (th, tv, faisable) = find_thtv_tmax(80000.0, w, eao, f, s1, d, h, lo, 50);
        assert!((th - th0).abs() < 1e-9 && (tv - tv0).abs() < 1e-9, "({th}, {tv})");
        assert_eq!(faisable, 1);
    }

    // Tension trouvee au-dessus d'un Tmax trop faible : travee infaisable.
    #[test]
    fn grille_juge_infaisable_sous_tmax_faible() {
        let (lo, w, f, eao, s1) = params();
        let (th0, tv0) = (60000.0, 25000.0);
        let d = calcul_xs(th0, tv0, lo, eao, w, f, s1, lo);
        let h = calcul_zs(th0, tv0, lo, eao, w, f, s1, lo);
        // sqrt(60000^2 + 25000^2) = 65000 > 64000 => infaisable.
        let (_, _, faisable) = find_thtv_tmax(64000.0, w, eao, f, s1, d, h, lo, 50);
        assert_eq!(faisable, 0);
    }
}
