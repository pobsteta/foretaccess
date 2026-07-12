// Les fonctions de la mecanique cable portent la signature des equations
// physiques (Th, Tv, Lo, EAo, W, F, s1, ...) : leur nombre d'arguments reflete
// le modele et non un defaut de conception. On tait donc `too_many_arguments`
// pour tout le crate.
#![allow(clippy::too_many_arguments)]

use extendr_api::prelude::*;

mod cable;
use cable::catenaire;
use cable::faisabilite;
use cable::newton;
use cable::supports;

/// Version de la crate Rust `cablehelp` (noyau câble).
///
/// Fonction triviale du Lot 0 : elle prouve que la chaîne R <-> Rust
/// (extendr) fonctionne de bout en bout. La mécanique CableHelp arrivera
/// au Lot 4 (voir specs/004-cable.md).
/// @export
#[extendr]
fn cablehelp_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

// --- Noyau cable (Lot 4a) : catenaire elastique + Newton-Raphson ---------
// Frontiere minimale et typee (ADR-001) : scalaires f64 en entree, scalaire
// ou vecteur f64 en sortie. Aucun SIG dans le crate. Les tuples (Th, Tv) et
// (Th, Tv, faisable) sont renvoyes en vecteurs numeriques.

/// Equation horizontale de la caténaire élastique `f_x(Th, Tv)`, nulle à la
/// solution.
///
/// @param th Horizontal tension component at the upper support (N).
/// @param tv Vertical tension component at the upper support (N).
/// @param lo Unstretched cable length over the span (m).
/// @param eao Young's modulus times the cable section (N).
/// @param w Weight of the cable over its whole length (N).
/// @param f Gravity force of the load (N).
/// @param s1 Arc-length position of the load (m).
/// @param d Horizontal span between supports (m).
/// @return The horizontal residual (m); zero at the solution.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_f_x(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, d: f64) -> f64 {
    catenaire::f_x(th, tv, lo, eao, w, f, s1, d)
}

/// Equation verticale de la caténaire élastique `f_z(Th, Tv)`, nulle à la
/// solution.
///
/// @param th Horizontal tension component at the upper support (N).
/// @param tv Vertical tension component at the upper support (N).
/// @param lo Unstretched cable length over the span (m).
/// @param eao Young's modulus times the cable section (N).
/// @param w Weight of the cable over its whole length (N).
/// @param f Gravity force of the load (N).
/// @param s1 Arc-length position of the load (m).
/// @param h Altitude difference between supports (m).
/// @return The vertical residual (m); zero at the solution.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_f_z(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, h: f64) -> f64 {
    catenaire::f_z(th, tv, lo, eao, w, f, s1, h)
}

/// Position horizontale du câble à l'abscisse curviligne `s`.
///
/// @param th Horizontal tension component at the upper support (N).
/// @param tv Vertical tension component at the upper support (N).
/// @param lo Unstretched cable length over the span (m).
/// @param eao Young's modulus times the cable section (N).
/// @param w Weight of the cable over its whole length (N).
/// @param f Gravity force of the load (N).
/// @param s1 Arc-length position of the load (m).
/// @param s Arc-length position at which the cable is evaluated (m).
/// @return The horizontal position of the cable at `s` (m).
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_calcul_xs(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, s: f64) -> f64 {
    catenaire::calcul_xs(th, tv, lo, eao, w, f, s1, s)
}

/// Position verticale (chute depuis le support haut) à l'abscisse curviligne
/// `s` : c'est elle qui fournit la garde au sol du câble.
///
/// @param th Horizontal tension component at the upper support (N).
/// @param tv Vertical tension component at the upper support (N).
/// @param lo Unstretched cable length over the span (m).
/// @param eao Young's modulus times the cable section (N).
/// @param w Weight of the cable over its whole length (N).
/// @param f Gravity force of the load (N).
/// @param s1 Arc-length position of the load (m).
/// @param s Arc-length position at which the cable is evaluated (m).
/// @return The vertical drop of the cable below the upper support at `s` (m).
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_calcul_zs(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, s: f64) -> f64 {
    catenaire::calcul_zs(th, tv, lo, eao, w, f, s1, s)
}

/// Amorçage `(Th, Tv, faisable)` par recherche sur grille sous la tension
/// admissible. Renvoie un vecteur de longueur 3 ; `faisable` vaut 1 si
/// `sqrt(Th^2 + Tv^2) <= tmax`, 0 sinon.
///
/// @param tmax Admissible cable tension (N).
/// @param w Weight of the cable over its whole length (N).
/// @param eao Young's modulus times the cable section (N).
/// @param f Gravity force of the load (N).
/// @param pas Arc-length position of the load used for the grid seed (m).
/// @param d Horizontal span between supports (m).
/// @param h Altitude difference between supports (m).
/// @param lo Unstretched cable length over the span (m).
/// @param step Grid step in tension (N).
/// @return A length-3 numeric vector `c(Th, Tv, faisable)`.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_find_thtv_tmax(
    tmax: f64,
    w: f64,
    eao: f64,
    f: f64,
    pas: f64,
    d: f64,
    h: f64,
    lo: f64,
    step: i32,
) -> Vec<f64> {
    let (th, tv, t) = newton::find_thtv_tmax(tmax, w, eao, f, pas, d, h, lo, step as u32);
    vec![th, tv, t as f64]
}

/// Résout `f_x = f_z = 0` (tensions `Th, Tv` au support haut) par
/// Newton-Raphson à Jacobien analytique, repli sur grille. Renvoie un vecteur
/// `c(Th, Tv)`.
///
/// @param th Initial guess for the horizontal tension component (N).
/// @param tv Initial guess for the vertical tension component (N).
/// @param h_alt Altitude difference between supports (m).
/// @param d Horizontal span between supports (m).
/// @param lo Unstretched cable length over the span (m).
/// @param w Weight of the cable over its whole length (N).
/// @param s1 Arc-length position of the load (m).
/// @param f Gravity force of the load (N).
/// @param eao Young's modulus times the cable section (N).
/// @param tmax Admissible cable tension (N), bounding the grid fallback.
/// @param err Tolerance on the Newton step (N).
/// @return A length-2 numeric vector `c(Th, Tv)`.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_newton_thtv(
    th: f64,
    tv: f64,
    h_alt: f64,
    d: f64,
    lo: f64,
    w: f64,
    s1: f64,
    f: f64,
    eao: f64,
    tmax: f64,
    err: f64,
) -> Vec<f64> {
    let (th, tv) = newton::newton_thtv(th, tv, h_alt, d, lo, w, s1, f, eao, tmax, err);
    vec![th, tv]
}

// --- Faisabilite d'une travee (Lot 4b) -----------------------------------

/// Pré-filtre géométrique : le câble est approximé par la corde entre supports
/// moins une flèche analytique. Renvoie 1 si le profil `(line_x, line_z)` reste
/// dans les gardes entre les indices `pg+1` et `pd-1`, 0 sinon. Sans supports
/// intermédiaires (Lot 4b).
///
/// @param fact Direction of the line (+1 or -1).
/// @param h_alt Altitude difference between supports (m).
/// @param d Horizontal span between supports (m).
/// @param xup Horizontal position of the upper support (m).
/// @param zup Altitude of the upper support (m).
/// @param line_x Horizontal positions along the terrain profile (m).
/// @param line_z Altitudes of the terrain profile (m).
/// @param hline_min Minimum ground clearance of the cable (m).
/// @param hline_max Maximum height of the cable (m).
/// @param tmax Admissible cable tension (N).
/// @param q1 Linear mass of the skyline (kg/m).
/// @param q2 Linear mass of the mainline / traction cable (kg/m).
/// @param q3 Linear mass of the return cable (kg/m).
/// @param f_o Gravity force of the load and carriage (N).
/// @param pg Index of the near support in the profile.
/// @param pd Index of the far support in the profile.
/// @return 1 if the span passes the pre-filter, 0 otherwise.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_check_droite(
    fact: f64,
    h_alt: f64,
    d: f64,
    xup: f64,
    zup: f64,
    line_x: Vec<f64>,
    line_z: Vec<f64>,
    hline_min: f64,
    hline_max: f64,
    tmax: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    f_o: f64,
    pg: i32,
    pd: i32,
) -> i32 {
    faisabilite::check_droite(
        fact,
        h_alt,
        d,
        xup,
        zup,
        &line_x,
        &line_z,
        hline_min,
        hline_max,
        tmax,
        q1,
        q2,
        q3,
        f_o,
        pg as i64,
        pd as i64,
        0.0,
        0.0,
    )
}

/// Faisabilité complète d'une travée : la charge balaie la longueur, on résout
/// les tensions à chaque position et on mesure la garde au sol. Renvoie la
/// garde minimale rencontrée (m), ou `-1` si la travée est infaisable (garde
/// hors `[hline_min, hline_max]` ou tension au-delà de `tmax + 1000`). Sans
/// supports intermédiaires (Lot 4b).
///
/// @param alts Terrain altitudes under the line, sampled every 0.5 m (m).
/// @param h_alt Altitude difference between supports (m).
/// @param d Horizontal span between supports (m).
/// @param lo Unstretched cable length over the span (m).
/// @param fact Direction of the line (+1 or -1).
/// @param tho Horizontal tension with the load centred (N).
/// @param tvo Vertical tension with the load centred (N).
/// @param xup Horizontal position of the upper support (m).
/// @param zup Altitude of the upper support (m).
/// @param f_o Gravity force of the load and carriage (N).
/// @param tmax Admissible cable tension (N).
/// @param hline_min Minimum ground clearance of the cable (m).
/// @param hline_max Maximum height of the cable (m).
/// @param q1 Linear mass of the skyline (kg/m).
/// @param q2 Linear mass of the mainline / traction cable (kg/m).
/// @param q3 Linear mass of the return cable (kg/m).
/// @param csize Sweep step of the load position (m).
/// @param eao Young's modulus times the cable section (N).
/// @return The minimum ground clearance (m), or `-1` if infeasible.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_check_hlinemin(
    alts: Vec<f64>,
    h_alt: f64,
    d: f64,
    lo: f64,
    fact: f64,
    tho: f64,
    tvo: f64,
    xup: f64,
    zup: f64,
    f_o: f64,
    tmax: f64,
    hline_min: f64,
    hline_max: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    csize: f64,
    eao: f64,
) -> f64 {
    faisabilite::check_hlinemin(
        &alts, h_alt, d, lo, fact, tho, tvo, xup, zup, f_o, tmax, hline_min, hline_max, q1, q2, q3,
        csize, eao, 0.0, 0.0,
    )
}

// --- Optimisation d'une travee avec supports (Lot 4c) --------------------

/// Cherche la longueur à vide minimale `Lo` telle que la tension du câble, la
/// charge au milieu, atteigne `tmax`, puis vérifie la garde au sol sur toute la
/// travée. Renvoie un vecteur `c(faisable, Lo, Th, Tv, Tcalc, F)` ; `faisable`
/// vaut 1 ou 0. Sans supports intermédiaires (Lot 4c).
///
/// Amorçage substitué aux tables Sylvaccess (`(Th, Tv) = (0.9*tmax, 0.1*tmax)`,
/// `Lo = corde + réserve`) : choix de performance, pas de correction.
///
/// @param d Horizontal span between supports (m).
/// @param h Altitude difference between supports (m).
/// @param xup Horizontal position of the upper support (m).
/// @param zup Altitude of the upper support (m).
/// @param fact Direction of the line (+1 or -1).
/// @param alts Terrain altitudes under the line, sampled every 0.5 m (m).
/// @param f_o Gravity force of the load and carriage (N).
/// @param tmax Admissible cable tension (N).
/// @param q1 Linear mass of the skyline (kg/m).
/// @param q2 Linear mass of the mainline / traction cable (kg/m).
/// @param q3 Linear mass of the return cable (kg/m).
/// @param eao Young's modulus times the cable section (N).
/// @param hline_min Minimum ground clearance of the cable (m).
/// @param hline_max Maximum height of the cable (m).
/// @param csize Sweep step of the load position (m).
/// @return A length-6 numeric vector `c(faisable, Lo, Th, Tv, Tcalc, F)`.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_find_lomin(
    d: f64,
    h: f64,
    xup: f64,
    zup: f64,
    fact: f64,
    alts: Vec<f64>,
    f_o: f64,
    tmax: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    eao: f64,
    hline_min: f64,
    hline_max: f64,
    csize: f64,
) -> Vec<f64> {
    let r = supports::find_lomin(
        d, h, xup, zup, fact, &alts, f_o, tmax, q1, q2, q3, eao, hline_min, hline_max, csize, 0.0,
        0.0,
    );
    vec![r.test as i32 as f64, r.lo, r.th, r.tv, r.tcalc, r.f]
}

/// Teste un segment de câble entre les points `pg` et `posi` du profil, portant
/// des supports de hauteurs `hg` et `hd` : pré-filtre, pente dans
/// `[slope_min, slope_max]`, contrainte d'angle au support intermédiaire
/// (`angle_intsup`) vis-à-vis du segment précédent (`slope_prev`, `-9999` si
/// aucun), puis `find_lomin`. Renvoie un vecteur
/// `c(faisable, D, H, diag, slope, fact, Xup, Zup, Lo, Th, Tv, Tcalc, F)`.
///
/// @param line_x Horizontal positions along the terrain profile (m).
/// @param line_z Terrain altitudes along the profile (m).
/// @param pg Index of the near support in the profile.
/// @param posi Index of the far support in the profile.
/// @param hg Height of the near support (m).
/// @param hd Height of the far support (m).
/// @param hline_min Minimum ground clearance of the cable (m).
/// @param hline_max Maximum height of the cable (m).
/// @param slope_min Minimum admissible slope of the span (rad).
/// @param slope_max Maximum admissible slope of the span (rad).
/// @param alts Terrain altitudes under the line, sampled every 0.5 m (m).
/// @param f_o Gravity force of the load and carriage (N).
/// @param tmax Admissible cable tension (N).
/// @param q1 Linear mass of the skyline (kg/m).
/// @param q2 Linear mass of the mainline / traction cable (kg/m).
/// @param q3 Linear mass of the return cable (kg/m).
/// @param eao Young's modulus times the cable section (N).
/// @param csize Sweep step of the load position (m).
/// @param angle_intsup Maximum slope change allowed at an intermediate support (rad).
/// @param dsupdep Extra cable length on the departure side (m).
/// @param slope_prev Slope of the previous span (rad), or -9999 if none.
/// @return A length-13 numeric vector (see the description for the fields).
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_test_span(
    line_x: Vec<f64>,
    line_z: Vec<f64>,
    pg: i32,
    posi: i32,
    hg: f64,
    hd: f64,
    hline_min: f64,
    hline_max: f64,
    slope_min: f64,
    slope_max: f64,
    alts: Vec<f64>,
    f_o: f64,
    tmax: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    eao: f64,
    csize: f64,
    angle_intsup: f64,
    dsupdep: f64,
    slope_prev: f64,
) -> Vec<f64> {
    let r = supports::test_span(
        &line_x,
        &line_z,
        pg as i64,
        posi as i64,
        hg,
        hd,
        hline_min,
        hline_max,
        slope_min,
        slope_max,
        &alts,
        f_o,
        tmax,
        q1,
        q2,
        q3,
        eao,
        csize,
        angle_intsup,
        dsupdep,
        slope_prev,
    );
    vec![
        r.test as i32 as f64,
        r.d,
        r.h,
        r.diag,
        r.slope,
        r.fact,
        r.xup,
        r.zup,
        r.lo,
        r.th,
        r.tv,
        r.tcalc,
        r.f,
    ]
}

// Macro to generate exports.
// This ensures exported functions are registered with R.
// See corresponding C code in `entrypoint.c`.
extendr_module! {
    mod foretaccess;
    fn cablehelp_version;
    fn cable_f_x;
    fn cable_f_z;
    fn cable_calcul_xs;
    fn cable_calcul_zs;
    fn cable_find_thtv_tmax;
    fn cable_newton_thtv;
    fn cable_check_droite;
    fn cable_check_hlinemin;
    fn cable_find_lomin;
    fn cable_test_span;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_not_empty() {
        assert!(!cablehelp_version().is_empty());
    }
}
