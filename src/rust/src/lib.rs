use extendr_api::prelude::*;

mod cable;
use cable::catenaire;
use cable::newton;

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
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_f_x(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, d: f64) -> f64 {
    catenaire::f_x(th, tv, lo, eao, w, f, s1, d)
}

/// Equation verticale de la caténaire élastique `f_z(Th, Tv)`, nulle à la
/// solution.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_f_z(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, h: f64) -> f64 {
    catenaire::f_z(th, tv, lo, eao, w, f, s1, h)
}

/// Position horizontale du câble à l'abscisse curviligne `s`.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_calcul_xs(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, s: f64) -> f64 {
    catenaire::calcul_xs(th, tv, lo, eao, w, f, s1, s)
}

/// Position verticale (chute depuis le support haut) à l'abscisse curviligne
/// `s` : c'est elle qui fournit la garde au sol du câble.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_calcul_zs(th: f64, tv: f64, lo: f64, eao: f64, w: f64, f: f64, s1: f64, s: f64) -> f64 {
    catenaire::calcul_zs(th, tv, lo, eao, w, f, s1, s)
}

/// Amorçage `(Th, Tv, faisable)` par recherche sur grille sous la tension
/// admissible. Renvoie un vecteur de longueur 3 ; `faisable` vaut 1 si
/// `sqrt(Th^2 + Tv^2) <= tmax`, 0 sinon.
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
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_not_empty() {
        assert!(!cablehelp_version().is_empty());
    }
}
