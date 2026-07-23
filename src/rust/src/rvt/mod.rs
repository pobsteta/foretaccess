// Portage Rust des canaux de micro-relief RVT (Relief Visualization Toolbox,
// ZRC SAZU / Univ. Ljubljana, Apache 2.0) : sky-view factor et openness (+/-).
// TRANSLITTERE au mot pres de `rvt/vis.py` (EarthObservation/RVT_py) --
// `horizon_shift_vector` + `sky_view_factor_compute` -- et NON reimplemente
// depuis les articles (spec 021 sec.7 : evite les bugs de cas limite d'angle
// d'horizon). RVT_py sert d'oracle de non-regression pixel a pixel (data-raw).
//
// Attribution : Kokalj, Zaksek, Ostir, Coz et al. Conserver en cas de derive.
//
// Le noyau est un balayage `roll` + `fmax` : pour chaque direction et chaque
// rayon de recherche, on decale la grille et on garde l'angle d'horizon maximal.
// SVF (hemisphere) et openness (sphere) sortent du MEME balayage. Aucun SIG ici
// (regle stricte 3) : R fournit la grille d'altitude a plat, recupere les
// canaux et les recolle sur le MNT.
//
// Semantique NoData reproduite a l'identique (sinon ecarts de bord avec
// l'oracle) : `NaN` propage, `fmax` ignore les `NaN` (comme `f64::max`), masque
// NaN restaure en fin de calcul.

use rayon::prelude::*;
use std::f64::consts::PI;

/// Reflexion d'un indice hors bornes dans `[0, n)`, sans repetition du bord
/// (equivalent `numpy.pad(mode="reflect")` / "reflect101"). Pour `n == 1` tout
/// retombe sur 0.
#[inline]
fn reflect(i: i64, n: i64) -> usize {
    if n == 1 {
        return 0;
    }
    let period = 2 * (n - 1);
    let mut m = ((i % period) + period) % period;
    if m >= n {
        m = period - m;
    }
    m as usize
}

/// Un mouvement de recherche d'horizon : decalage entier `(ligne, colonne)` et
/// distance associee (en pixels). Prepare comme `np.roll` dans RVT_py.
#[derive(Clone, Copy)]
struct Move {
    shift_row: i64,
    shift_col: i64,
    distance: f64,
}

/// Porte `horizon_shift_vector` : pour chaque direction, l'ensemble MINIMAL de
/// decalages entiers uniques (sur un rayon affine par `scale = 3`), tries par
/// distance croissante. Le decalage de RVT est `(x=cos -> axe 0=lignes,
/// y=sin -> axe 1=colonnes)` : on respecte cette convention (axe0 = round(cos),
/// axe1 = round(sin)) pour coller a `np.roll(height, shift, axis=(0,1))`.
fn horizon_shift_vector(num_directions: usize, radius_pixels: f64, min_radius: f64) -> Vec<Vec<Move>> {
    let scale = 3.0_f64;
    // radii = arange((radius_pixels - min_radius)*scale + 1)/scale + min_radius
    let n_radii = ((radius_pixels - min_radius) * scale + 1.0).floor().max(0.0) as usize;
    let radii: Vec<f64> = (0..n_radii).map(|k| k as f64 / scale + min_radius).collect();

    let mut out = Vec::with_capacity(num_directions);
    for i in 0..num_directions {
        let angle = (2.0 * PI / num_directions as f64) * i as f64;
        let (c, s) = (angle.cos(), angle.sin());
        // Ensemble des couples entiers uniques (round(cos*r), round(sin*r)).
        // On deduplique comme RVT (set sur nombre complexe).
        let mut seen: Vec<(i64, i64)> = Vec::new();
        for &r in &radii {
            let xr = (c * r).round() as i64; // axe 0 (lignes)
            let yr = (s * r).round() as i64; // axe 1 (colonnes)
            if !seen.contains(&(xr, yr)) {
                seen.push((xr, yr));
            }
        }
        let mut moves: Vec<Move> = seen
            .into_iter()
            .map(|(sr, sc)| Move {
                shift_row: sr,
                shift_col: sc,
                distance: ((sr * sr + sc * sc) as f64).sqrt(),
            })
            .collect();
        // Tri par distance croissante (argsort stable comme numpy).
        moves.sort_by(|a, b| a.distance.partial_cmp(&b.distance).unwrap());
        out.push(moves);
    }
    out
}

/// Resultat du balayage : SVF et/ou openness (degres), memes dimensions que
/// l'entree, `NaN` la ou l'altitude d'origine est `NaN`.
pub struct SvfOpns {
    pub svf: Option<Vec<f64>>,
    pub opns: Option<Vec<f64>>,
}

/// Balayage SVF / openness (translitteration de `sky_view_factor` +
/// `sky_view_factor_compute`). `height` est en ordre ligne-major (row-major),
/// `NaN` pour NoData. `resolution` corrige l'angle vertical (le calcul suppose
/// 1 px == 1 m). `radius_max`/`radius_min` en PIXELS.
///
/// Parallele (`rayon`) par pixel de sortie : chaque pixel somme les directions
/// dans le meme ordre que l'oracle -> pas de reordonnancement de la reduction.
#[allow(clippy::too_many_arguments)]
pub fn svf_opns(
    height: &[f64],
    nrow: usize,
    ncol: usize,
    resolution: f64,
    radius_max: f64,
    radius_min: f64,
    num_directions: usize,
    compute_svf: bool,
    compute_opns: bool,
) -> SvfOpns {
    let n = nrow * ncol;
    let (nr, nc) = (nrow as i64, ncol as i64);

    // Altitude corrigee de la resolution (dem / resolution). NaN se propage.
    let h: Vec<f64> = height.iter().map(|&z| z / resolution).collect();
    let moves = horizon_shift_vector(num_directions, radius_max, radius_min);
    let ndir = num_directions as f64;

    // Calcul d'un pixel : renvoie (svf, opns_deg). Reproduit la boucle de RVT.
    let per_pixel = |idx: usize| -> (f64, f64) {
        let i = (idx / ncol) as i64;
        let j = (idx % ncol) as i64;
        let center = h[idx];
        let mut svf_acc = 0.0_f64;
        let mut opns_acc = 0.0_f64;
        for dir in &moves {
            // max_slope initial = -1000 (comme RVT), pas -inf.
            let mut max_slope = -1000.0_f64;
            for mv in dir {
                // np.roll(height, shift)[p] = height[p - shift].
                let ni = reflect(i - mv.shift_row, nr);
                let nj = reflect(j - mv.shift_col, nc);
                let neighbor = h[ni * ncol + nj];
                let slope = (neighbor - center) / mv.distance;
                // np.fmax : ignore les NaN (identique a f64::max en Rust).
                max_slope = max_slope.max(slope);
            }
            let ang = max_slope.atan();
            if compute_svf {
                // Hemisphere : angle minimal 0 (fmax(ang, 0)).
                svf_acc += 1.0 - ang.max(0.0).sin();
            }
            if compute_opns {
                // Sphere entiere.
                opns_acc += ang;
            }
        }
        let svf = svf_acc / ndir;
        // opns = rad2deg(pi/2 - opns/ndir).
        let opns = (0.5 * PI - opns_acc / ndir).to_degrees();
        (svf, opns)
    };

    let results: Vec<(f64, f64)> = (0..n).into_par_iter().map(per_pixel).collect();

    // Restauration du masque NaN (sur l'altitude d'origine, resolution comprise).
    let mut svf = if compute_svf { Some(vec![0.0; n]) } else { None };
    let mut opns = if compute_opns { Some(vec![0.0; n]) } else { None };
    for (idx, &(s, o)) in results.iter().enumerate() {
        let is_nan = height[idx].is_nan();
        if let Some(v) = svf.as_mut() {
            v[idx] = if is_nan { f64::NAN } else { s };
        }
        if let Some(v) = opns.as_mut() {
            v[idx] = if is_nan { f64::NAN } else { o };
        }
    }
    SvfOpns { svf, opns }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Terrain parfaitement plat : toutes les pentes d'horizon nulles ->
    // SVF = 1 partout, openness = 90 deg (pi/2 - 0). Invariant analytique.
    #[test]
    fn flat_terrain_svf_one_opns_ninety() {
        let (nr, nc) = (12usize, 12usize);
        let h = vec![100.0_f64; nr * nc];
        let r = svf_opns(&h, nr, nc, 1.0, 5.0, 1.0, 16, true, true);
        let svf = r.svf.unwrap();
        let opns = r.opns.unwrap();
        for k in 0..nr * nc {
            assert!((svf[k] - 1.0).abs() < 1e-9, "svf[{k}] = {}", svf[k]);
            assert!((opns[k] - 90.0).abs() < 1e-9, "opns[{k}] = {}", opns[k]);
        }
    }

    // Un pic isole (altitude plus haute au centre) : le centre voit un horizon
    // qui DESCEND partout -> SVF = 1 (rien ne le masque). Un creux ferait < 1.
    #[test]
    fn peak_center_is_fully_open() {
        let (nr, nc) = (11usize, 11usize);
        let mut h = vec![100.0_f64; nr * nc];
        let cidx = 5 * nc + 5;
        h[cidx] = 110.0; // pic
        let r = svf_opns(&h, nr, nc, 1.0, 5.0, 1.0, 16, true, false);
        let svf = r.svf.unwrap();
        assert!((svf[cidx] - 1.0).abs() < 1e-9, "pic svf = {}", svf[cidx]);
    }

    // Un puits (centre plus bas) : les bords remontent -> horizon positif ->
    // SVF < 1 au centre. Confirme le signe de la pente d'horizon.
    #[test]
    fn pit_center_is_partially_closed() {
        let (nr, nc) = (11usize, 11usize);
        let mut h = vec![100.0_f64; nr * nc];
        let cidx = 5 * nc + 5;
        h[cidx] = 90.0; // creux
        let r = svf_opns(&h, nr, nc, 1.0, 5.0, 1.0, 16, true, true);
        let svf = r.svf.unwrap();
        let opns = r.opns.unwrap();
        assert!(svf[cidx] < 1.0, "creux svf = {} (attendu < 1)", svf[cidx]);
        assert!(opns[cidx] < 90.0, "creux opns = {} (attendu < 90)", opns[cidx]);
    }

    // NoData : une entree NaN reste NaN en sortie (masque restaure).
    #[test]
    fn nan_input_stays_nan() {
        let (nr, nc) = (8usize, 8usize);
        let mut h = vec![100.0_f64; nr * nc];
        h[3 * nc + 3] = f64::NAN;
        let r = svf_opns(&h, nr, nc, 1.0, 4.0, 1.0, 8, true, true);
        assert!(r.svf.unwrap()[3 * nc + 3].is_nan());
        assert!(r.opns.unwrap()[3 * nc + 3].is_nan());
    }

    // La resolution change l'angle vertical : a resolution plus grande (pixels
    // plus larges), une meme denivelee donne un angle plus faible -> SVF plus
    // proche de 1 pour un creux. Monotonie verifiee.
    #[test]
    fn coarser_resolution_opens_a_pit() {
        let (nr, nc) = (11usize, 11usize);
        let mut h = vec![100.0_f64; nr * nc];
        h[5 * nc + 5] = 90.0;
        let fine = svf_opns(&h, nr, nc, 1.0, 5.0, 1.0, 16, true, false).svf.unwrap();
        let coarse = svf_opns(&h, nr, nc, 5.0, 5.0, 1.0, 16, true, false).svf.unwrap();
        let cidx = 5 * nc + 5;
        assert!(coarse[cidx] > fine[cidx], "coarse {} <= fine {}", coarse[cidx], fine[cidx]);
    }

    // horizon_shift_vector : 4 directions, rayon 2 -> decalages entiers connus.
    #[test]
    fn shift_vector_cardinal_directions() {
        let moves = horizon_shift_vector(4, 2.0, 1.0);
        assert_eq!(moves.len(), 4);
        // Direction 0 (angle 0) : cos=1,sin=0 -> lignes varient, colonnes 0.
        for mv in &moves[0] {
            assert_eq!(mv.shift_col, 0);
        }
        // Chaque direction est triee par distance croissante.
        for dir in &moves {
            for w in dir.windows(2) {
                assert!(w[0].distance <= w[1].distance);
            }
        }
    }
}
