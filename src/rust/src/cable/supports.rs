//! Optimisation d'une travee cable avec supports (Lot 4c).
//!
//! Port de `Find_Lomin` et `test_Span` (`sylvaccess_cython3.pyx`,
//! CableHelp/INRAE, GPL v3). `find_lomin` cherche la longueur a vide `Lo`
//! minimale telle que la tension du cable, la charge au milieu, atteigne la
//! tension admissible `Tmax` ; puis verifie la garde au sol sur toute la
//! travee. `test_span` teste un segment entre deux points du profil, avec la
//! contrainte d'angle entre spans consecutifs (angle au support intermediaire).
//!
//! **Deviation d'amorçage assumee** : Sylvaccess amorce Newton depuis des
//! tables precalculees (`Tabmesh` -> `rastTh`, `rastTv`, `rastLosup`). On les
//! remplace par l'estimation initiale `(Th, Tv) = (0,9*Tmax, 0,1*Tmax)` — celle
//! meme que `Tabmesh` utilise pour son premier point — et un `Lo` de depart
//! egal a la corde plus une petite reserve. Les tables ne sont qu'un
//! accelerateur : la boucle d'ajustement de `Lo` et Newton convergent quel que
//! soit l'amorçage dans le bassin. C'est un choix de performance, pas de
//! correction (le noyau reste fidele).

use super::catenaire::{calcul_xs, calcul_zs, f_x, f_z};
use super::faisabilite::{check_droite, check_hlinemin};
use super::newton::newton_thtv;

const G: f64 = 9.80665;

/// Force de gravite sur le chariot a la position `s1` de la charge.
fn f_charge(lo: f64, f_o: f64, q2: f64, q3: f64, s1: f64, dsupdep: f64, dsupend: f64) -> f64 {
    0.5 * ((s1 + dsupdep) * q2 + ((lo - s1) + dsupend) * q3) * G + f_o
}

/// Resout la catenaire pour la charge centree a `Lo` donne, avec repli sur
/// grille (via `newton_thtv`). Renvoie `(th, tv, ok)` ; `ok = false` si la
/// solution est hors domaine (tension negative) ou si le residu reste grand.
///
/// C'est ici que se joue la deviation d'amorçage (cf. en-tete) : `newton_thtv`
/// est le Newton fidele *avec* son repli sur grille, ce qui rend la marche sur
/// `Lo` robuste sans les tables `Tabmesh`.
#[allow(clippy::too_many_arguments)]
fn newton_centre(
    th0: f64,
    tv0: f64,
    lo: f64,
    eao: f64,
    w: f64,
    f: f64,
    s1: f64,
    d: f64,
    h_alt: f64,
    tmax: f64,
    err: f64,
) -> (f64, f64, bool) {
    let (th, tv) = newton_thtv(th0, tv0, h_alt, d, lo, w, s1, f, eao, tmax, err);
    let residu = f_x(th, tv, lo, eao, w, f, s1, d).abs() + f_z(th, tv, lo, eao, w, f, s1, h_alt).abs();
    let ok = th > 0.0 && tv > 0.0 && residu < 0.03;
    (th, tv, ok)
}

/// Resultat de `find_lomin`.
pub struct Lomin {
    pub test: bool,
    pub lo: f64,
    pub th: f64,
    pub tv: f64,
    pub tcalc: f64,
    pub f: f64,
}

/// Cherche `Lo` minimale telle que la tension (charge au milieu) atteigne
/// `tmax`, puis verifie la garde au sol sur toute la travee. Amorçage
/// `(0,9*tmax, 0,1*tmax)` et `Lo = corde + reserve` (cf. deviation en tete).
#[allow(clippy::too_many_arguments)]
pub fn find_lomin(
    d: f64,
    h: f64,
    xup: f64,
    zup: f64,
    fact: f64,
    alts: &[f64],
    f_o: f64,
    tmax: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    eao: f64,
    hline_min: f64,
    hline_max: f64,
    csize: f64,
    dsupdep: f64,
    dsupend: f64,
) -> Lomin {
    let err = 1.0;
    let error = 50.0; // tolerance sur |Tcalc - Tmax|
    let diag = (d * d + h * h).sqrt();
    // Amorçage (deviation assumee) : cf. Tabmesh (Tho = 0,9*Tmax, Tvo = 0,1*Tmax).
    let mut th = 0.9 * tmax;
    let mut tv = 0.1 * tmax;
    let mut lo = diag + 2.0; // corde + reserve
    let mut w = q1 * G * lo;
    let mut s1 = 0.5 * lo;
    let mut f = f_charge(lo, f_o, q2, q3, s1, dsupdep, dsupend);
    let mut test;

    // Premiere convergence a Lo de depart.
    let (nth, ntv, ok) = newton_centre(th, tv, lo, eao, w, f, s1, d, h, tmax, err);
    th = nth;
    tv = ntv;
    test = ok;
    let mut tcalc = (th * th + tv * tv).sqrt();

    if test {
        // Ajuste Lo pour que Tcalc ne depasse pas Tmax (dichotomie a pas variable).
        let mut incr = 0.01;
        let mut signe = (tcalc - tmax) / (tcalc - tmax).abs();
        while (tcalc - tmax).abs() > error && test {
            lo += signe * incr;
            w = q1 * G * lo;
            s1 = lo * 0.5;
            f = f_charge(lo, f_o, q2, q3, s1, dsupdep, dsupend);
            let (nth, ntv, ok) = newton_centre(th, tv, lo, eao, w, f, s1, d, h, tmax, err);
            th = nth;
            tv = ntv;
            if !ok {
                test = false;
                break;
            }
            tcalc = (th * th + tv * tv).sqrt();
            if signe * (tcalc - tmax) < 0.0 {
                incr *= 0.1;
                signe *= -1.0;
            }
            if (lo - diag).abs() > 100.0 {
                test = false;
                break;
            }
        }
    }

    if test {
        f = f_charge(lo, f_o, q2, q3, lo * 0.5, dsupdep, dsupend);
        let xcoord = xup + fact * calcul_xs(th, tv, lo, eao, w, f, lo * 0.5, lo * 0.5);
        let zcoord = zup - calcul_zs(th, tv, lo, eao, w, f, lo * 0.5, lo * 0.5);
        let ind = (xcoord * 2.0 + 0.5).floor();
        if ind < 0.0 || ind as usize >= alts.len() {
            test = false;
        } else {
            let hmin0 = zcoord - (alts[ind as usize] + hline_min);
            if hmin0 >= 0.0 {
                let hmin = check_hlinemin(
                    alts, h, d, lo, fact, th, tv, xup, zup, f_o, tmax, hline_min, hline_max, q1, q2,
                    q3, csize, eao, dsupdep, dsupend,
                );
                if hmin < 0.0 {
                    test = false;
                }
            } else {
                test = false;
            }
        }
    }

    Lomin {
        test,
        lo,
        th,
        tv,
        tcalc,
        f,
    }
}

/// Resultat de `test_span` : faisabilite et geometrie du segment.
pub struct SpanResult {
    pub test: bool,
    pub d: f64,
    pub h: f64,
    pub diag: f64,
    pub slope: f64,
    pub fact: f64,
    pub xup: f64,
    pub zup: f64,
    pub lo: f64,
    pub th: f64,
    pub tv: f64,
    pub tcalc: f64,
    pub f: f64,
}

/// Teste un segment de cable entre les points `pg` et `posi` du profil, portant
/// des supports de hauteurs `hg` et `hd`. Enchaine : pre-filtre `check_droite`,
/// pente du segment dans `[slope_min, slope_max]`, contrainte d'angle au support
/// intermediaire (`angle_intsup`) vis-a-vis du segment precedent (`slope_prev`,
/// `-9999` si aucun), puis `find_lomin`. Renvoie geometrie et tensions.
///
/// La contrainte d'angle refuse un changement de pente `>= angle_intsup`, ou une
/// inversion de pente avec un ecart `>= 0,1` rad : un support ne peut ployer le
/// cable au-dela de sa capacite mecanique.
#[allow(clippy::too_many_arguments)]
pub fn test_span(
    line_x: &[f64],
    line_z: &[f64],
    pg: i64,
    posi: i64,
    hg: f64,
    hd: f64,
    hline_min: f64,
    hline_max: f64,
    slope_min: f64,
    slope_max: f64,
    alts: &[f64],
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
) -> SpanResult {
    let (ig, ip) = (pg as usize, posi as usize);
    let d = line_x[ip] - line_x[pg as usize];
    let h = (line_z[ig] + hg - (line_z[ip] + hd)).abs();
    let (xup, zup, fact) = if line_z[ig] + hg >= line_z[ip] + hd {
        (line_x[ig], line_z[ig] + hg, 1.0)
    } else {
        (line_x[ip], line_z[ip] + hd, -1.0)
    };

    let mut res = SpanResult {
        test: false,
        d,
        h,
        diag: 0.0,
        slope: 0.0,
        fact,
        xup,
        zup,
        lo: 0.0,
        th: 0.0,
        tv: 0.0,
        tcalc: 0.0,
        f: 0.0,
    };

    if check_droite(
        fact, h, d, xup, zup, line_x, line_z, hline_min, hline_max, tmax, q1, q2, q3, f_o, pg, posi,
        dsupdep, 0.0,
    ) == 0
    {
        return res;
    }

    res.diag = (h * h + d * d).sqrt();
    let slope = -fact * (h / d).atan();
    res.slope = slope;
    if slope < slope_min || slope > slope_max {
        return res;
    }
    // Contrainte d'angle au support intermediaire vis-a-vis du segment precedent.
    if slope_prev > -9999.0
        && ((slope - slope_prev).abs() >= angle_intsup
            || (slope * slope_prev < 0.0 && (slope - slope_prev).abs() >= 0.1))
    {
        return res;
    }

    let l = find_lomin(
        d, h, xup, zup, fact, alts, f_o, tmax, q1, q2, q3, eao, hline_min, hline_max, csize,
        dsupdep, 0.0,
    );
    res.test = l.test;
    res.lo = l.lo;
    res.th = l.th;
    res.tv = l.tv;
    res.tcalc = l.tcalc;
    res.f = l.f;
    res
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params() -> (f64, f64, f64, f64, f64) {
        let q1 = 1.85;
        let f_o = G * (2500.0 + 400.0);
        let ao = 0.25 * std::f64::consts::PI * 18.0_f64.powi(2);
        let eao = 160000.0 * ao;
        let tmax = 35000.0 * G / 2.0;
        (q1, f_o, eao, tmax, 0.9)
    }

    // On teste avec un `tmax` modere (50 kN) : le Lo minimal est alors une
    // catenaire a sag raisonnable, bien conditionnee. Au tmax materiel
    // (~172 kN) le cable est quasi tendu et le Newton chaud du balayage devient
    // fragile -- c'est le comportement au bord, a surveiller en 4d.
    const TMAX_TEST: f64 = 50000.0;

    #[test]
    fn find_lomin_atteint_tmax_et_ferme_la_geometrie() {
        let (q1, f_o, eao, _tmax, q) = params();
        // Travee moderee, sol tres bas (garde large) : faisable.
        let (d, h) = (150.0, 20.0);
        let alts = vec![0.0; 1000];
        // Support haut a 60 m : le cable reste largement au-dessus du sol a 0.
        let r = find_lomin(
            d, h, 0.0, 60.0, 1.0, &alts, f_o, TMAX_TEST, q1, q, q, eao, 3.5, 50.0, 5.0, 0.0, 0.0,
        );
        assert!(r.test, "attendu faisable, Lo = {}", r.lo);
        // La tension a la charge centree atteint tmax a l'erreur pres (50 N).
        assert!((r.tcalc - TMAX_TEST).abs() < 50.0, "Tcalc = {}", r.tcalc);
        // Cable elastique : Lo peut etre un peu sous la corde (etirement), mais
        // reste dans la fenetre de recherche.
        let diag = (d * d + h * h).sqrt();
        assert!(r.lo > diag - 5.0 && r.lo < diag + 100.0, "Lo = {}", r.lo);
        // Solution de catenaire valide : residus quasi nuls.
        let w = q1 * G * r.lo;
        assert!(f_x(r.th, r.tv, r.lo, eao, w, r.f, r.lo * 0.5, d).abs() < 0.05);
        assert!(f_z(r.th, r.tv, r.lo, eao, w, r.f, r.lo * 0.5, h).abs() < 0.05);
    }

    #[test]
    fn find_lomin_infaisable_si_sol_trop_haut() {
        let (q1, f_o, eao, _tmax, q) = params();
        let (d, h) = (150.0, 20.0);
        // Sol releve juste sous le support : le cable touche -> infaisable.
        let alts = vec![58.0; 1000];
        let r = find_lomin(
            d, h, 0.0, 60.0, 1.0, &alts, f_o, TMAX_TEST, q1, q, q, eao, 3.5, 50.0, 5.0, 0.0, 0.0,
        );
        assert!(!r.test, "attendu infaisable, Lo = {}", r.lo);
    }

    // Profil plat au demi-metre : line_z sert a la fois de profil (check_droite)
    // et d'altitudes (find_lomin, echantillonnage 0,5 m).
    fn profil_plat(n: usize, z: f64) -> (Vec<f64>, Vec<f64>) {
        let x: Vec<f64> = (0..n).map(|i| i as f64 * 0.5).collect();
        (x, vec![z; n])
    }

    #[test]
    fn test_span_faisable_travee_courte_tours_hautes() {
        let (q1, f_o, eao, _tmax, q) = params();
        // Span de 80 m (posi = 160), terrain plat a 0, tours de 40 m : la fleche
        // sous la charge reste au-dessus de la garde.
        let (line_x, line_z) = profil_plat(400, 0.0);
        let r = test_span(
            &line_x, &line_z, 0, 160, 40.0, 40.0, 3.5, 50.0, -1.5, 1.5, &line_z, f_o, TMAX_TEST,
            q1, q, q, eao, 5.0, 0.5, 0.0, -9999.0,
        );
        assert!(r.test, "attendu faisable, Lo = {}", r.lo);
        assert!((r.d - 80.0).abs() < 1e-9);
        assert!(r.slope.abs() < 1e-9); // travee plate
    }

    #[test]
    fn test_span_refuse_une_pente_hors_bornes() {
        let (q1, f_o, eao, _tmax, q) = params();
        // Terrain en pente (z = 2*x, ~63 deg) avec des tours modestes : la corde
        // reste a 10 m au-dessus du sol (check_droite passe), mais la pente du
        // segment (~1,107 rad) depasse slope_max = 0,6 rad -> refus par la pente.
        let x: Vec<f64> = (0..400).map(|i| i as f64 * 0.5).collect();
        let z: Vec<f64> = x.iter().map(|xi| 2.0 * xi).collect();
        let r = test_span(
            &x, &z, 0, 100, 10.0, 10.0, 3.5, 50.0, -0.6, 0.6, &z, f_o, TMAX_TEST, q1, q, q, eao,
            5.0, 0.5, 0.0, -9999.0,
        );
        assert!(!r.test);
        assert!(r.slope.abs() > 0.6); // pente hors bornes, calculee (check_droite a passe)
    }

    #[test]
    fn test_span_refuse_un_angle_trop_ferme_au_support() {
        let (q1, f_o, eao, _tmax, q) = params();
        // Meme span plat faisable, mais le segment precedent a une pente de
        // 0,5 rad : l'ecart d'angle au support (0,5 >= angle_intsup = 0,3) refuse.
        let (line_x, line_z) = profil_plat(400, 0.0);
        let r = test_span(
            &line_x, &line_z, 0, 160, 40.0, 40.0, 3.5, 50.0, -1.5, 1.5, &line_z, f_o, TMAX_TEST,
            q1, q, q, eao, 5.0, 0.3, 0.0, 0.5,
        );
        assert!(!r.test, "l'angle au support aurait du refuser la travee");
    }
}
