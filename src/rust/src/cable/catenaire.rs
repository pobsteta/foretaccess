//! Caténaire élastique du câble porteur.
//!
//! Portage fidèle des fonctions de `sylvaccess_cython3.pyx` (CableHelp, INRAE,
//! GPL v3) : `f_x`, `f_z`, `calcul_xs`, `calcul_zs` et leurs dérivées `df_dTh`,
//! `dg_dTh`. Le câble n'est pas une caténaire idéale : le terme `Lo/EAo`
//! traduit son allongement élastique sous tension (`EAo` = module de Young x
//! section). Toutes les tensions sont en newtons, les longueurs en mètres.
//!
//! Convention des arguments (identique au `.pyx`) :
//! - `th`, `tv` : composantes horizontale et verticale de la tension au support
//!   le plus haut, la charge etant a l'abscisse curviligne `s1` ;
//! - `lo` : longueur a vide (sans elasticite) du cable sur la travee ;
//! - `eao` : module de Young multiplie par la section du cable (N) ;
//! - `w` : poids du cable sur toute sa longueur (N) ;
//! - `f` : force de gravite exercee par la charge (N) ;
//! - `s1` : abscisse curviligne de la charge ; `s` : abscisse testee.

/// Equation horizontale `f_x(Th, Tv)`, nulle a la solution.
///
/// `d` est la portee horizontale visee entre les deux supports.
pub fn f_x(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, d: f64) -> f64 {
    let mut x = th * lo / eao - d;
    x += th * lo / w
        * ((tv / th).asinh() - ((tv - f - w) / th).asinh() + ((tv - f - w * s1 / lo) / th).asinh()
            - ((tv - w * s1 / lo) / th).asinh());
    x
}

/// Equation verticale `f_z(Th, Tv)`, nulle a la solution.
///
/// `h` est la difference d'altitude visee entre les deux supports.
pub fn f_z(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, h: f64) -> f64 {
    let mut z = w * lo / eao * (tv / w - 0.5) - h;
    let mut temp = (1.0 + (tv / th).powi(2)).sqrt() - (1.0 + ((tv - f - w) / th).powi(2)).sqrt()
        + f * w / (th * eao) * (s1 / lo - 1.0);
    temp += (1.0 + ((tv - f - w * s1 / lo) / th).powi(2)).sqrt()
        - (1.0 + ((tv - w * s1 / lo) / th).powi(2)).sqrt();
    z += th * lo / w * temp;
    z
}

/// Position horizontale du cable a l'abscisse curviligne `s`.
pub fn calcul_xs(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, s: f64) -> f64 {
    let mut x = th * s / eao;
    x += th * lo / w
        * ((tv / th).asinh() - ((tv - f - w * s / lo) / th).asinh()
            + ((tv - f - w * s1 / lo) / th).asinh()
            - ((tv - w * s1 / lo) / th).asinh());
    x
}

/// Position verticale (chute depuis le support haut) a l'abscisse curviligne `s`.
pub fn calcul_zs(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, s: f64) -> f64 {
    let mut z = w * s / eao * (tv / w - s / (2.0 * lo));
    let mut temp = (1.0 + (tv / th).powi(2)).sqrt()
        - (1.0 + ((tv - f - w * s / lo) / th).powi(2)).sqrt()
        + f * w / (th * eao) * (s1 / lo - s / lo);
    temp += (1.0 + ((tv - f - w * s1 / lo) / th).powi(2)).sqrt()
        - (1.0 + ((tv - w * s1 / lo) / th).powi(2)).sqrt();
    z += th * lo / w * temp;
    z
}

/// Derivee de `f_x` selon `Th` (Jacobien analytique du Newton).
///
/// `rac1..rac4` sont les racines `sqrt(1 + (.)^2)` mutualisees avec `f_z`.
#[allow(clippy::too_many_arguments)]
pub fn df_dth(
    th: f64,
    tv: f64,
    f: f64,
    w: f64,
    s1: f64,
    lo: f64,
    eao: f64,
    rac1: f64,
    rac2: f64,
    rac3: f64,
    rac4: f64,
) -> f64 {
    let mut a = 1.0 / th
        * (-tv / rac1 + (tv - f - w) / rac2 - (tv - f - w * s1 / lo) / rac3
            + (tv - w * s1 / lo) / rac4);
    a += (tv / th).asinh() - ((tv - f - w) / th).asinh() + ((tv - f - w * s1 / lo) / th).asinh()
        - ((tv - w * s1 / lo) / th).asinh();
    a *= lo / w;
    a += lo / eao;
    a
}

/// Derivee de `f_z` selon `Th` (Jacobien analytique du Newton).
#[allow(clippy::too_many_arguments)]
pub fn dg_dth(
    tv: f64,
    th: f64,
    lo: f64,
    w: f64,
    s1: f64,
    f: f64,
    rac1: f64,
    rac2: f64,
    rac3: f64,
    rac4: f64,
) -> f64 {
    let mut a = 1.0 / (th * th)
        * (-tv * tv / rac1 + (tv - f - w) * (tv - f - w) / rac2
            - (tv - f - w * s1 / lo) * (tv - f - w * s1 / lo) / rac3
            + (tv - w * s1 / lo) * (tv - w * s1 / lo) / rac4);
    a += (1.0 + (tv / th).powi(2)).sqrt() - (1.0 + ((tv - f - w) / th).powi(2)).sqrt()
        + (1.0 + ((tv - f - w * s1 / lo) / th).powi(2)).sqrt()
        - (1.0 + ((tv - w * s1 / lo) / th).powi(2)).sqrt();
    a *= lo / w;
    a
}

#[cfg(test)]
mod tests {
    use super::*;

    // Cas de reference : parametres materiels v3.6 (q1=1,85 kg/m, d=18 mm,
    // c_E=160000 N/mm2, charge 2500 kg + chariot 400 kg), travee de 200 m.
    const G: f64 = 9.80665;
    fn params() -> (f64, f64, f64, f64, f64) {
        let lo = 200.0;
        let w = 1.85 * G * lo; // poids du cable
        let f = G * (2500.0 + 400.0); // force de la charge
        let ao = 0.25 * std::f64::consts::PI * 18.0_f64.powi(2); // section en mm2
        let eao = 160000.0 * ao; // N/mm2 * mm2 = N
        let s1 = 100.0; // charge a mi-travee
        (lo, w, f, eao, s1)
    }

    // Identite de fermeture : par construction des equations,
    // calcul_xs(s=Lo) = f_x + D et calcul_zs(s=Lo) = f_z + H. On la verifie a
    // la machine : c'est ce qui relie la position du cable a la solution.
    #[test]
    fn fermeture_xs_egale_fx_plus_d() {
        let (lo, w, f, eao, s1) = params();
        let (th, tv, d) = (60000.0, 25000.0, 190.0);
        let xs_lo = calcul_xs(th, tv, lo, eao, w, f, s1, lo);
        let fx = f_x(th, tv, lo, eao, w, f, s1, d);
        assert!((xs_lo - (fx + d)).abs() < 1e-6, "xs(Lo)={xs_lo}, fx+D={}", fx + d);
    }

    #[test]
    fn fermeture_zs_egale_fz_plus_h() {
        let (lo, w, f, eao, s1) = params();
        let (th, tv, h) = (60000.0, 25000.0, 12.0);
        let zs_lo = calcul_zs(th, tv, lo, eao, w, f, s1, lo);
        let fz = f_z(th, tv, lo, eao, w, f, s1, h);
        assert!((zs_lo - (fz + h)).abs() < 1e-6, "zs(Lo)={zs_lo}, fz+H={}", fz + h);
    }
}
