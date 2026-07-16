//! Noyau de conception de desserte (epic Lots 14-18).
//!
//! Porte le solveur de trace de **SylvaRoad** (S. Dupire / SylvaLab / ONF, 2021,
//! GPL v3) et de **Forest Road Designer** (PANOimagen, GPL v3) : un A* sur graphe
//! a voisinage disque, avec penalites paraboliques (direction, pente), epingles et
//! controle de profil. La frontiere R<->Rust reste minimale et typee (ADR-001) :
//! R rasterise cout, franchissabilite et MNT, le crate calcule le trace, R
//! reassemble les polylignes SIG.
//!
//! Lot 15a (present) : **table de voisinage etendu** (`neighborhood`) et
//! **distance-de-cout inverse** depuis la cible (`heuristic`, l'heuristique `h` de
//! l'A*). Le solveur A* complet (15b) et l'orchestration R (15c) suivent.
//!
// La table de voisinage et quelques helpers trig ne sont consommes que par le
// solveur A* (15b) et les tests : on tolere le code mort d'ici la.
#![allow(dead_code)]

pub mod heuristic;
pub mod neighborhood;

/// Azimut compas (deg, [0, 360)) du vecteur `(x1, y1) -> (x2, y2)`, `y` oriente
/// vers le haut. Portage de `calculate_azimut` de SylvaRoad : `acos(DY / Deuc)`,
/// signe donne par `x2 > x1`, ramene dans `[0, 360)`.
pub fn calculate_azimut(x1: f64, y1: f64, x2: f64, y2: f64) -> f64 {
    let dx = x2 - x1;
    let dy = y2 - y1;
    let deuc = (dx * dx + dy * dy).sqrt();
    if deuc == 0.0 {
        return 0.0;
    }
    let fact = if x2 > x1 { 1.0 } else { -1.0 };
    let angle = (dy / deuc).clamp(-1.0, 1.0).acos() * 180.0 / std::f64::consts::PI * fact;
    modulo(angle, 360.0)
}

/// Reste positif de `a` modulo `b` (>= 0), comme le `modulo` de SylvaRoad.
pub fn modulo(a: f64, b: f64) -> f64 {
    let r = a % b;
    if r < 0.0 {
        r + b
    } else {
        r
    }
}

/// Ecart angulaire non oriente entre deux azimuts (deg, [0, 180]). Portage de
/// `diff_az` : le plus court des deux arcs.
pub fn diff_az(az_to: f64, az_from: f64) -> f64 {
    let d = (az_to - az_from).abs();
    d.min(360.0 - d)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn azimut_cardinal() {
        // Est (+x) = 90 deg, Nord (+y) = 0 deg, Ouest = 270, Sud = 180.
        assert!((calculate_azimut(0.0, 0.0, 1.0, 0.0) - 90.0).abs() < 1e-6);
        assert!((calculate_azimut(0.0, 0.0, 0.0, 1.0) - 0.0).abs() < 1e-6);
        assert!((calculate_azimut(0.0, 0.0, -1.0, 0.0) - 270.0).abs() < 1e-6);
        assert!((calculate_azimut(0.0, 0.0, 0.0, -1.0) - 180.0).abs() < 1e-6);
    }

    #[test]
    fn diff_az_wraps() {
        assert!((diff_az(10.0, 350.0) - 20.0).abs() < 1e-9);
        assert!((diff_az(350.0, 10.0) - 20.0).abs() < 1e-9);
        assert!((diff_az(0.0, 180.0) - 180.0).abs() < 1e-9);
    }

    #[test]
    fn modulo_positive() {
        assert!((modulo(-90.0, 360.0) - 270.0).abs() < 1e-9);
        assert!((modulo(370.0, 360.0) - 10.0).abs() < 1e-9);
    }
}
