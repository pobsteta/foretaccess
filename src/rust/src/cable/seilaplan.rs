//! Optimisation de la hauteur des supports facon SEILAPLAN (spec 013).
//!
//! Transcription de l'algorithme de **Bont & Heinimann (2012)** tel que codé
//! dans le plugin QGIS SEILAPLAN (GPL, <https://github.com/piMoll/SEILAPLAN>).
//! On adopte son **modele de pre-tension globale** (une tension unique pour
//! toute la ligne, chaque travee la contraignant) tout en gardant **notre**
//! mecanique caténaire Newton/Irvine (via `supports::calc_cable`), pas la
//! mecanique de Zweifel — cf. `docs/comparaison-cable-seilaplan.md` et
//! `specs/013-seilaplan-hauteur.md`.
//!
//! **13a** — brique de plage de pre-tension : `calc_sta`, transcrit de
//! `core/opti_sta.py::calcSTA`. Rend, pour une travee, la plage `[MinSTA,
//! MaxSTA]` de pre-tension pour laquelle elle est faisable (garde au sol **et**
//! effort admissible). Le graphe + Dijkstra (13b) balaiera cette pre-tension.

// 13a fournit la brique mecanique isolee ; le cablage a `cable_scan` (donc les
// appelants hors tests) arrive en 13b/13c. Les tests l'exercent deja.
#![allow(dead_code)]

use super::supports::{calc_cable, SpanGeom};

/// Plage de pre-tension admissible d'une travee (sortie de `calc_sta`).
pub struct StaRange {
    /// La travee est infaisable sur toute la plage `[t_min, t_max]`.
    pub impossible: bool,
    /// Borne basse de la pre-tension faisable (garde limitante en dessous).
    pub min_sta: f64,
    /// Borne haute de la pre-tension faisable (effort limitant au-dessus).
    pub max_sta: f64,
}

/// Cherche la plage `[MinSTA, MaxSTA]` de pre-tension pour laquelle la travee
/// `g` est faisable. Transcription de `calcSTA` (`opti_sta.py`) : bissection
/// entre `t_min` et `t_max`, `calc_cable` fournissant a chaque pre-tension
/// `(garde_ok, effort_ok)`.
///
/// `t_max` est l'analogue de `zul_SK` (tension admissible), `t_min` de `min_SK`
/// (pre-tension minimale exploree), `detail` la precision de la bissection (N),
/// analogue du `Detail` de SEILAPLAN. La logique — deux bissections (max puis
/// min) partageant un cache `Speicher`, puis `Min`/`Max` des pre-tensions ou
/// **les deux** criteres tiennent — suit le source au plus pres.
pub fn calc_sta(g: &SpanGeom, t_min: f64, t_max: f64, detail: f64) -> StaRange {
    // Cache (sta, garde_ok, effort_ok) — l'analogue de `Speicher`.
    let mut speicher: Vec<(f64, bool, bool)> = Vec::new();
    let mut impossible = false;

    // Evalue une pre-tension via `calc_cable`, ramenant la non-convergence a
    // une double infaisabilite (garde et effort faux).
    let eval = |sta: f64| {
        let r = calc_cable(g, sta);
        (r.converged && r.garde_ok, r.converged && r.effort_ok)
    };

    // 1. Test de la tension max admissible (cable le plus tendu : meilleure
    //    garde). Si la garde ne tient pas ici, la travee est infaisable partout.
    let (garde_max, effort_max) = eval(t_max);
    speicher.push((t_max, garde_max, effort_max));
    if !garde_max {
        impossible = true;
    } else {
        // 2. Test de la tension min : si meme la, l'effort casse, infaisable.
        let (g1, e1) = eval(t_min);
        speicher.push((t_min, g1, e1));
        if !e1 {
            impossible = true;
        } else {
            // 3. Deux bissections : maxSTA (pilotee par l'effort), puis minSTA
            //    (pilotee par la garde), partageant le cache `speicher`.
            for which_max in [true, false] {
                let mut delta = (t_max - t_min) / 2.0;
                let mut sta = t_min + delta;
                while delta > detail && sta >= t_min {
                    // Reutilise une evaluation deja en cache (egalite exacte,
                    // fidele a `element[1][0] == STA` du source).
                    let hit = speicher.iter().find(|e| e.0 == sta).copied();
                    let (cp, ef) = match hit {
                        Some((_, cp, ef)) => (cp, ef),
                        None => {
                            let (cp, ef) = eval(sta);
                            speicher.push((sta, cp, ef));
                            (cp, ef)
                        }
                    };
                    let vorzeichen = if which_max {
                        if ef {
                            1.0
                        } else {
                            -1.0
                        }
                    } else if !cp {
                        1.0
                    } else {
                        -1.0
                    };
                    sta += delta * vorzeichen;
                    delta /= 2.0;
                }
            }
        }
    }

    // Reihe = pre-tensions ou garde ET effort tiennent ; Min/Max de leurs bornes.
    let feasible: Vec<f64> = speicher
        .iter()
        .filter(|e| e.1 && e.2)
        .map(|e| e.0)
        .collect();
    if feasible.is_empty() {
        StaRange {
            impossible: true,
            min_sta: f64::NAN,
            max_sta: f64::NAN,
        }
    } else {
        let min_sta = feasible.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_sta = feasible.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        StaRange {
            impossible,
            min_sta,
            max_sta,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const G: f64 = 9.80665;
    const TMAX_TEST: f64 = 35000.0 * G / 2.0;

    fn params() -> (f64, f64, f64, f64) {
        let q1 = 1.85;
        let f_o = G * (2500.0 + 400.0);
        let ao = 0.25 * std::f64::consts::PI * 18.0_f64.powi(2);
        let eao = 160000.0 * ao;
        (q1, f_o, eao, 0.9)
    }

    fn span_genereux(alts: &[f64]) -> SpanGeom<'_> {
        let (q1, f_o, eao, q) = params();
        SpanGeom {
            d: 150.0,
            h: 20.0,
            xup: 0.0,
            zup: 45.0,
            fact: 1.0,
            alts,
            f_o,
            tmax: TMAX_TEST,
            q1,
            q2: q,
            q3: q,
            eao,
            hline_min: 3.5,
            hline_max: 50.0,
            csize: 5.0,
            dsupdep: 0.0,
            dsupend: 0.0,
        }
    }

    // Travee genereuse : une plage [MinSTA, MaxSTA] non vide, bornee par tmax en
    // haut (effort) et par la garde en bas.
    #[test]
    fn calc_sta_rend_une_plage_bornee() {
        let alts = vec![0.0; 1000];
        let g = span_genereux(&alts);
        let r = calc_sta(&g, 0.3 * TMAX_TEST, TMAX_TEST, 1000.0);
        assert!(!r.impossible, "travee genereuse attendue faisable");
        assert!(r.min_sta <= r.max_sta, "[{}, {}]", r.min_sta, r.max_sta);
        assert!(r.max_sta <= TMAX_TEST + 1.0, "max_sta = {}", r.max_sta);
        assert!(r.min_sta >= 0.3 * TMAX_TEST - 1.0, "min_sta = {}", r.min_sta);
    }

    // Sol trop haut : infaisable a toute pre-tension (garde violee meme tendu).
    #[test]
    fn calc_sta_infaisable_si_sol_trop_haut() {
        let alts = vec![44.0; 1000]; // supports a 45 m, garde 3,5 m impossible
        let g = span_genereux(&alts);
        let r = calc_sta(&g, 0.3 * TMAX_TEST, TMAX_TEST, 1000.0);
        assert!(r.impossible, "travee attendue infaisable");
    }

    // La borne haute est bien limitee par l'effort : si tmax est genereux et la
    // garde tient largement, MaxSTA colle a la tension max exploree.
    #[test]
    fn calc_sta_borne_haute_pilotee_par_effort() {
        let alts = vec![0.0; 1000];
        let g = span_genereux(&alts);
        let r = calc_sta(&g, 0.3 * TMAX_TEST, TMAX_TEST, 1000.0);
        assert!(!r.impossible);
        // MaxSTA atteint la tension max (a la resolution de bissection pres).
        assert!(
            (r.max_sta - TMAX_TEST).abs() < 5000.0,
            "max_sta = {} attendu proche de tmax = {}",
            r.max_sta,
            TMAX_TEST
        );
    }
}
