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
//! remplace par une **grille grossiere bornee** (`seed_grid`, 40 x 40, cout
//! independant de `Tmax`) qui fournit un bon amorçage, puis Newton chaud raffine
//! et la marche sur `Lo` progresse en rechauffant chaque solve. On evite ainsi
//! le repli sur grille de `newton_thtv` (O(Tmax^2)), prohibitif dans la boucle
//! chaude du balayage 360 deg / pixel. Les tables ne sont qu'un accelerateur :
//! c'est un choix de performance, pas de correction (le noyau reste fidele).

use super::catenaire::{calcul_xs, calcul_zs, df_dth, dg_dth, f_x, f_z};
use super::faisabilite::{check_droite, check_hlinemin};

const G: f64 = 9.80665;

/// Force de gravite sur le chariot a la position `s1` de la charge.
fn f_charge(lo: f64, f_o: f64, q2: f64, q3: f64, s1: f64, dsupdep: f64, dsupend: f64) -> f64 {
    0.5 * ((s1 + dsupdep) * q2 + ((lo - s1) + dsupend) * q3) * G + f_o
}

/// Newton-Raphson "chaud" pour la charge centree a `Lo` donne : 20 iterations au
/// plus, amorce a `(th0, tv0)`, **sans repli sur grille**. Renvoie `(th, tv,
/// ok)` ; `ok = false` si une tension devient negative ou si le residu reste
/// grand. La marche sur `Lo` (pas fin, cf. `find_lomin`) garde chaque solve dans
/// le bassin : un repli sur grille y serait catastrophique (O(Tmax^2)) dans la
/// boucle chaude du balayage 360 deg / pixel. Un candidat qui ne converge pas
/// est traite comme infaisable.
#[allow(clippy::too_many_arguments)]
fn newton_centre(
    mut th: f64,
    mut tv: f64,
    lo: f64,
    eao: f64,
    w: f64,
    f: f64,
    s1: f64,
    d: f64,
    h_alt: f64,
    err: f64,
) -> (f64, f64, bool) {
    let mut hh: f64 = 100.0;
    let mut kk: f64 = 100.0;
    let mut it = 0u32;
    let mut ok = true;
    while hh.abs() > err && kk.abs() > err {
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
        hh = coeff * (-dgtv * fo + dftv * go);
        kk = coeff * (dgth * fo - dfth * go);
        th += hh;
        tv += kk;
        it += 1;
        if th.min(tv) < 0.0 {
            ok = false;
            break;
        }
        if it > 20 {
            ok = false;
            break;
        }
    }
    (th, tv, ok)
}

/// Amorçage `(Th, Tv)` par grille *grossiere bornee* (40 x 40) : on retient le
/// noeud de residu `|f_x| + |f_z|` minimal. Substitut aux tables `Tabmesh`, avec
/// un cout **independant** de `tmax` (40^2 evaluations), la ou le repli sur
/// grille de `newton_thtv` coute O((tmax/pas)^2) -- prohibitif dans la boucle
/// chaude du balayage. Le noeud sert d'amorçage a `newton_centre` qui raffine.
#[allow(clippy::too_many_arguments)]
fn seed_grid(
    lo: f64,
    eao: f64,
    w: f64,
    f: f64,
    s1: f64,
    d: f64,
    h_alt: f64,
    tmax: f64,
) -> (f64, f64) {
    let step = tmax / 40.0;
    let mut best = (0.9 * tmax, 0.1 * tmax);
    let mut best_res = f64::INFINITY;
    let mut i = step;
    while i < tmax {
        let mut j = step;
        while j < tmax {
            let res = f_x(i, j, lo, eao, w, f, s1, d).abs() + f_z(i, j, lo, eao, w, f, s1, h_alt).abs();
            if res < best_res {
                best_res = res;
                best = (i, j);
            }
            j += step;
        }
        i += step;
    }
    best
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
/// `tmax`, puis verifie la garde au sol sur toute la travee. Amorçage par
/// `seed_grid` a `Lo = corde + reserve` (cf. deviation en tete).
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
    let mut lo = diag + 2.0; // corde + reserve : proche de la solution a Tmax
    let mut w = q1 * G * lo;
    let mut s1 = 0.5 * lo;
    let mut f = f_charge(lo, f_o, q2, q3, s1, dsupdep, dsupend);
    let mut test;

    // Amorçage par grille grossiere (substitut a Tabmesh), puis Newton chaud.
    let (sth, stv) = seed_grid(lo, eao, w, f, s1, d, h, tmax);
    let (mut th, mut tv);
    let ok0;
    {
        let (nth, ntv, ok) = newton_centre(sth, stv, lo, eao, w, f, s1, d, h, err);
        th = nth;
        tv = ntv;
        ok0 = ok;
    }
    test = ok0;
    let mut tcalc = (th * th + tv * tv).sqrt();

    if test {
        // Ajuste Lo pour que Tcalc atteigne Tmax (pas variable : 1 m, puis
        // raffine par 0,1 a chaque depassement). Chaque solve est rechauffe.
        let mut incr = 1.0;
        let mut signe = (tcalc - tmax) / (tcalc - tmax).abs();
        while (tcalc - tmax).abs() > error && test {
            lo += signe * incr;
            w = q1 * G * lo;
            s1 = lo * 0.5;
            f = f_charge(lo, f_o, q2, q3, s1, dsupdep, dsupend);
            let (nth, ntv, ok) = newton_centre(th, tv, lo, eao, w, f, s1, d, h, err);
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

/// Geometrie d'une travee pour l'evaluation a **tension imposee** (brique
/// mecanique SEILAPLAN, spec 013 §4.1a). Regroupe les memes entrees que
/// `find_lomin` — profil, materiel, gardes — pour un appel repete par `calc_sta`
/// sans dupliquer 18 arguments. `alts` est le profil d'altitudes sous la ligne,
/// echantillonne au demi-metre ; `(xup, zup)` le support haut, `fact` le sens.
///
/// Brique 13a (spec 013) : cablee a `cable_scan` en 13b/13c, exercee par les
/// tests d'ici la — d'ou l'`allow(dead_code)`.
#[allow(dead_code)]
pub struct SpanGeom<'a> {
    pub d: f64,
    pub h: f64,
    pub xup: f64,
    pub zup: f64,
    pub fact: f64,
    pub alts: &'a [f64],
    pub f_o: f64,
    pub tmax: f64,
    pub q1: f64,
    pub q2: f64,
    pub q3: f64,
    pub eao: f64,
    pub hline_min: f64,
    pub hline_max: f64,
    pub csize: f64,
    pub dsupdep: f64,
    pub dsupend: f64,
}

/// Resultat de `calc_cable` : faisabilite d'une travee a une tension imposee.
///
/// Trois sorties dont le graphe de Bont & Heinimann a besoin (via `calc_sta`),
/// dans l'esprit de `calcCable`/`checkCable` de SEILAPLAN (garde au sol et
/// effort admissible fournis **separement**).
#[allow(dead_code)]
pub struct CalcCable {
    /// La marche sur `Lo` a atteint la tension imposee (catenaire resoluble).
    pub converged: bool,
    /// Garde au sol respectee sur toute la travee (`hline_min..hline_max`).
    pub garde_ok: bool,
    /// Effort admissible : tension imposee `<= tmax` (l'analogue de `zul_SK`).
    pub effort_ok: bool,
    /// Fleche (m) sous la charge centree : chute du cable sous la corde.
    pub sag: f64,
    /// Longueur a vide obtenue pour cette tension.
    pub lo: f64,
}

/// Evalue une travee a une **pre-tension imposee** `t_impose` (brique SEILAPLAN,
/// decision spec 013 §4.1a). Contrairement a `find_lomin` — qui cherche la `Lo`
/// amenant la tension (charge centree) a `tmax` — on cherche ici la `Lo` amenant
/// cette tension a `t_impose`, puis on renvoie **separement** la garde au sol,
/// l'effort et la fleche.
///
/// La mecanique reste la notre (Newton/Irvine, oracle-validee) : c'est
/// l'*optimisation* (a la B&H) qu'on adopte de SEILAPLAN, pas sa mecanique de
/// Zweifel (cf. `docs/comparaison-cable-seilaplan.md`). L'amorçage et la marche
/// sur `Lo` sont identiques a `find_lomin` (grille grossiere puis Newton chaud).
#[allow(dead_code)] // cablee a `cable_scan` en 13b/13c ; exercee par les tests.
pub fn calc_cable(g: &SpanGeom, t_impose: f64) -> CalcCable {
    let (sth, stv) = seed_for_span(g);
    calc_cable_seeded(g, t_impose, sth, stv)
}

/// Amorçage `(Th, Tv)` d'une travee a `Lo = corde + 2` -- le point de depart de
/// la marche de `calc_cable`. **Identique pour toute tension imposee** sur cette
/// travee (meme `Lo` de depart), donc calculable **une seule fois** et partage
/// entre les appels d'une bissection `calc_sta` (perf : `seed_grid` = 40x40
/// evaluations de catenaire, sinon refaites a chaque tension). Voir
/// `calc_cable_seeded`.
#[allow(dead_code)]
pub fn seed_for_span(g: &SpanGeom) -> (f64, f64) {
    let diag = (g.d * g.d + g.h * g.h).sqrt();
    let lo = diag + 2.0;
    let w = g.q1 * G * lo;
    let s1 = 0.5 * lo;
    let f = f_charge(lo, g.f_o, g.q2, g.q3, s1, g.dsupdep, g.dsupend);
    seed_grid(lo, g.eao, w, f, s1, g.d, g.h, g.tmax)
}

/// Variante de `calc_cable` a **amorçage fourni** (`sth`, `stv` = sortie de
/// `seed_for_span`). Resultat identique a `calc_cable` -- l'amorçage n'affecte que
/// le point de depart du Newton chaud, pas la racine. Permet de partager le seed
/// entre les evaluations d'une meme travee (cf. `calc_sta`).
#[allow(dead_code)]
pub fn calc_cable_seeded(g: &SpanGeom, t_impose: f64, sth: f64, stv: f64) -> CalcCable {
    let err = 1.0;
    let error = 50.0; // tolerance sur |Tcalc - t_impose|
    let diag = (g.d * g.d + g.h * g.h).sqrt();
    let mut lo = diag + 2.0;
    let mut w = g.q1 * G * lo;
    let mut s1 = 0.5 * lo;
    let mut f = f_charge(lo, g.f_o, g.q2, g.q3, s1, g.dsupdep, g.dsupend);

    // Amorçage partage (substitut a Tabmesh), puis Newton chaud.
    let (mut th, mut tv, ok0) = newton_centre(sth, stv, lo, g.eao, w, f, s1, g.d, g.h, err);
    let mut converged = ok0;
    let mut tcalc = (th * th + tv * tv).sqrt();

    if converged {
        // Ajuste Lo pour que Tcalc atteigne t_impose (pas variable : 1 m, puis
        // raffine par 0,1 a chaque depassement). Chaque solve est rechauffe.
        let mut incr = 1.0;
        let mut signe = (tcalc - t_impose) / (tcalc - t_impose).abs();
        while (tcalc - t_impose).abs() > error && converged {
            lo += signe * incr;
            w = g.q1 * G * lo;
            s1 = lo * 0.5;
            f = f_charge(lo, g.f_o, g.q2, g.q3, s1, g.dsupdep, g.dsupend);
            let (nth, ntv, ok) = newton_centre(th, tv, lo, g.eao, w, f, s1, g.d, g.h, err);
            th = nth;
            tv = ntv;
            if !ok {
                converged = false;
                break;
            }
            tcalc = (th * th + tv * tv).sqrt();
            if signe * (tcalc - t_impose) < 0.0 {
                incr *= 0.1;
                signe *= -1.0;
            }
            if (lo - diag).abs() > 100.0 {
                converged = false;
                break;
            }
        }
    }

    // Effort : la tension imposee (= tension charge centree) sous l'admissible.
    let effort_ok = converged && t_impose <= g.tmax;

    let mut garde_ok = false;
    let mut sag = 0.0;
    if converged {
        f = f_charge(lo, g.f_o, g.q2, g.q3, lo * 0.5, g.dsupdep, g.dsupend);
        let xcoord = g.xup + g.fact * calcul_xs(th, tv, lo, g.eao, w, f, lo * 0.5, lo * 0.5);
        let zcoord = g.zup - calcul_zs(th, tv, lo, g.eao, w, f, lo * 0.5, lo * 0.5);
        let ind = (xcoord * 2.0 + 0.5).floor();
        if ind >= 0.0 && (ind as usize) < g.alts.len() {
            let hmin0 = zcoord - (g.alts[ind as usize] + g.hline_min);
            if hmin0 >= 0.0 {
                let hmin = check_hlinemin(
                    g.alts, g.h, g.d, lo, g.fact, th, tv, g.xup, g.zup, g.f_o, g.tmax, g.hline_min,
                    g.hline_max, g.q1, g.q2, g.q3, g.csize, g.eao, g.dsupdep, g.dsupend,
                );
                garde_ok = hmin >= 0.0;
            }
        }
        // Fleche sous la charge centree : chute du cable sous la corde reliant
        // les deux supports, a l'abscisse horizontale du point centre.
        let xlow = g.xup + g.fact * g.d;
        let zlow = g.zup - g.h;
        let chord = if (xlow - g.xup).abs() > 1e-9 {
            g.zup + (zlow - g.zup) * (xcoord - g.xup) / (xlow - g.xup)
        } else {
            g.zup
        };
        sag = chord - zcoord;
    }

    CalcCable {
        converged,
        garde_ok,
        effort_ok,
        sag,
        lo,
    }
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

    // Tests au `tmax` **materiel** (~172 kN = 35000 kgF * g / 2). Le Newton chaud
    // du balayage y converge : la seule contrainte au bord est *geometrique* (un
    // cable tendu depuis un support tres haut violerait `hline_max`), pas
    // numerique. On choisit donc un support de 45 m (garde <= hline_max = 50 m).
    const TMAX_TEST: f64 = 35000.0 * 9.80665 / 2.0;

    #[test]
    fn find_lomin_atteint_tmax_et_ferme_la_geometrie() {
        let (q1, f_o, eao, _tmax, q) = params();
        let (d, h) = (150.0, 20.0);
        let alts = vec![0.0; 1000];
        // Support a 45 m sur sol a 0 : le cable tendu reste dans [3,5 ; 50] m.
        let r = find_lomin(
            d, h, 0.0, 45.0, 1.0, &alts, f_o, TMAX_TEST, q1, q, q, eao, 3.5, 50.0, 5.0, 0.0, 0.0,
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
        // Sol releve a 40 m : le cable, qui descend vers ~25 m au support bas,
        // passe sous la garde -> infaisable.
        let alts = vec![40.0; 1000];
        let r = find_lomin(
            d, h, 0.0, 45.0, 1.0, &alts, f_o, TMAX_TEST, q1, q, q, eao, 3.5, 50.0, 5.0, 0.0, 0.0,
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

    // --- Brique mecanique SEILAPLAN (calc_cable, spec 013 §4.1a) --------------

    // Travee genereuse : support a 45 m, sol plat a 0, tmax materiel.
    fn span_genereux(alts: &[f64]) -> SpanGeom<'_> {
        let (q1, f_o, eao, _t, q) = params();
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

    // A la tension max (= tmax), calc_cable doit reproduire la faisabilite que
    // find_lomin trouve a tmax : catenaire resolue, garde et effort tenus.
    #[test]
    fn calc_cable_faisable_a_tension_max() {
        let alts = vec![0.0; 1000];
        let g = span_genereux(&alts);
        let r = calc_cable(&g, TMAX_TEST);
        assert!(r.converged, "attendu convergent, Lo = {}", r.lo);
        assert!(r.garde_ok, "garde au sol attendue tenue");
        assert!(r.effort_ok, "effort attendu admissible a t = tmax");
    }

    // Monotonie mecanique : abaisser la tension imposee AUGMENTE la fleche
    // (cable plus mou). C'est le levier meme du graphe B&H.
    #[test]
    fn calc_cable_fleche_croit_quand_la_tension_baisse() {
        let alts = vec![0.0; 1000];
        let g = span_genereux(&alts);
        let haut = calc_cable(&g, TMAX_TEST);
        let bas = calc_cable(&g, 0.7 * TMAX_TEST);
        assert!(haut.converged && bas.converged, "les deux tensions doivent converger");
        assert!(
            bas.sag > haut.sag,
            "fleche a 0,7 tmax ({}) attendue > fleche a tmax ({})",
            bas.sag,
            haut.sag
        );
    }

    // Effort refuse au-dela de l'admissible : imposer t > tmax => effort_ok faux.
    #[test]
    fn calc_cable_effort_refuse_au_dessus_de_tmax() {
        let alts = vec![0.0; 1000];
        let g = span_genereux(&alts);
        let r = calc_cable(&g, 1.05 * TMAX_TEST);
        assert!(!r.effort_ok, "t > tmax doit violer l'effort");
    }

    // Sol trop haut : meme a tension max, la garde au sol est violee.
    #[test]
    fn calc_cable_garde_violee_si_sol_trop_haut() {
        let alts = vec![44.0; 1000]; // sol a 44 m, supports a 45 m
        let g = span_genereux(&alts);
        let r = calc_cable(&g, TMAX_TEST);
        assert!(!r.garde_ok, "garde attendue violee (sol a 44 m sous supports 45 m)");
    }
}
