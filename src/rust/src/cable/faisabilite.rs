//! Faisabilite d'une travee de cable (Lot 4b).
//!
//! Port fidele de `check_droite` et `check_Hlinemin`
//! (`sylvaccess_cython3.pyx`, CableHelp/INRAE, GPL v3). Une travee est faisable
//! si, la charge balayant toute la longueur, le cable reste au-dessus de la
//! garde au sol `hline_min`, sous la garde haute `hline_max`, et la tension
//! sous `tmax`. On renvoie la garde au sol *minimale* rencontree (`hmin_ok`),
//! ou `-1` si la travee est infaisable.

use super::catenaire::{calcul_xs, calcul_zs, df_dth, dg_dth, f_x, f_z};

const G: f64 = 9.80665;

/// Newton-Raphson "chaud" : 20 iterations au plus, amorce a `(th, tv)`, sans
/// repli sur grille ni reinitialisation. C'est la variante utilisee dans le
/// balayage de la charge, ou chaque position s'amorce de la precedente.
fn newton_warm(
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
) -> (f64, f64) {
    let mut hh: f64 = 100.0;
    let mut kk: f64 = 100.0;
    let mut it = 0u32;
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
        if it > 20 {
            break;
        }
    }
    (th, tv)
}

/// Force de gravite sur le chariot a la position `s1` de la charge, tenant
/// compte des cables de traction (`q2`) et de retour (`q3`).
fn f_charge(lo: f64, f_o: f64, q2: f64, q3: f64, s1: f64, dsupdep: f64, dsupend: f64) -> f64 {
    0.5 * ((s1 + dsupdep) * q2 + ((lo - s1) + dsupend) * q3) * G + f_o
}

/// Pre-filtre rapide en ligne droite : le cable est approxime par la corde
/// entre supports, moins une fleche analytique. Renvoie 1 si aucun point du
/// profil `(line_x, line_z)` entre les indices `pg+1` et `pd-1` ne viole les
/// gardes, 0 sinon. Sert a ecarter les travees manifestement infaisables avant
/// le calcul complet.
#[allow(clippy::too_many_arguments)]
pub fn check_droite(
    fact: f64,
    h_alt: f64,
    d: f64,
    xup: f64,
    zup: f64,
    line_x: &[f64],
    line_z: &[f64],
    hline_min: f64,
    hline_max: f64,
    tmax: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    f_o: f64,
    pg: i64,
    pd: i64,
    dsupdep: f64,
    dsupend: f64,
) -> i32 {
    let l = (h_alt * h_alt + d * d).sqrt();
    let f = 0.5 * ((0.5 * l + dsupdep) * q2 + (0.5 * l + dsupend) * q3) * G + f_o;
    let fleche = 1.1 * (f * l / (4.0 * tmax) + q1 * G * l * l / (8.0 * tmax));
    let mut i = pg + 1;
    while i < pd {
        let idx = i as usize;
        if idx >= line_x.len() {
            return 0;
        }
        let droite = -fact * h_alt / d * (line_x[idx] - xup) + zup - line_z[idx];
        if droite < hline_min {
            return 0;
        }
        if droite - fleche > hline_max {
            return 0;
        }
        i += 1;
    }
    1
}

/// Faisabilite complete d'une travee : la charge balaie la longueur depuis le
/// milieu vers chaque support ; a chaque position on resout les tensions et on
/// mesure la garde au sol `zcoord - (alt + hline_min)`. Renvoie la garde
/// minimale rencontree, ou `-1` si une position viole une garde ou depasse la
/// tension admissible (`tmax + 1000`).
///
/// `alts` est le profil d'altitudes sous la ligne, echantillonne au demi-metre
/// (`ind = 2*xcoord`). `(xup, zup)` est le support haut, `fact` le sens (+/-1).
#[allow(clippy::too_many_arguments)]
pub fn check_hlinemin(
    alts: &[f64],
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
    dsupdep: f64,
    dsupend: f64,
) -> f64 {
    let end = lo - 10.0;
    let w = G * q1 * lo;
    let mut hmin_ok: f64 = 10000.0;
    let mut test = true;

    // Premiere demi-travee : du milieu vers le depart (s1 decroissant).
    let mut th = tho;
    let mut tv = tvo;
    let mut s1 = lo * 0.5 - csize;
    while s1 > 10.0 {
        let f = f_charge(lo, f_o, q2, q3, s1, dsupdep, dsupend);
        let (nth, ntv) = newton_warm(th, tv, lo, eao, w, f, s1, d, h_alt, 1.0);
        th = nth;
        tv = ntv;
        if f_x(th, tv, lo, eao, w, f, s1, d).abs() + f_z(th, tv, lo, eao, w, f, s1, h_alt).abs()
            > 0.03
        {
            test = false;
            break;
        }
        let xcoord = xup + fact * calcul_xs(th, tv, lo, eao, w, f, s1, s1);
        let zcoord = zup - calcul_zs(th, tv, lo, eao, w, f, s1, s1);
        let ind = (xcoord * 2.0 + 0.5) as usize;
        if ind >= alts.len() {
            // Hors profil : on refuse plutot que de paniquer (garde defensive).
            test = false;
            break;
        }
        let hmin = zcoord - (alts[ind] + hline_min);
        if hmin < 0.0 || hmin + hline_min > hline_max || (th * th + tv * tv).sqrt() > tmax + 1000.0 {
            test = false;
            break;
        }
        hmin_ok = hmin_ok.min(hmin);
        s1 -= csize;
    }

    // Seconde demi-travee : du milieu vers l'arrivee (s1 croissant), amorce
    // reinitialisee au couple central.
    if test {
        th = tho;
        tv = tvo;
        let mut s1 = ((lo * 0.5 + csize) as i64 as f64).min(end);
        while s1 < end {
            let f = f_charge(lo, f_o, q2, q3, s1, dsupdep, dsupend);
            let (nth, ntv) = newton_warm(th, tv, lo, eao, w, f, s1, d, h_alt, 1.0);
            th = nth;
            tv = ntv;
            if f_x(th, tv, lo, eao, w, f, s1, d).abs() + f_z(th, tv, lo, eao, w, f, s1, h_alt).abs()
                > 0.03
            {
                test = false;
                break;
            }
            let xcoord = xup + fact * calcul_xs(th, tv, lo, eao, w, f, s1, s1);
            let zcoord = zup - calcul_zs(th, tv, lo, eao, w, f, s1, s1);
            let ind = (xcoord * 2.0 + 0.5) as usize;
            if ind >= alts.len() {
                test = false;
                break;
            }
            let hmin = zcoord - (alts[ind] + hline_min);
            if hmin < 0.0
                || hmin + hline_min > hline_max
                || (th * th + tv * tv).sqrt() > tmax + 1000.0
            {
                test = false;
                break;
            }
            hmin_ok = hmin_ok.min(hmin);
            s1 += csize;
        }
    }

    if test {
        hmin_ok
    } else {
        -1.0
    }
}

#[cfg(test)]
mod tests {
    use super::super::catenaire::calcul_zs;
    use super::*;

    // Parametres v3.6 + cables de traction/retour (q2, q3), travee 200 m.
    fn params() -> (f64, f64, f64, f64, f64, f64) {
        let lo = 200.0;
        let q1 = 1.85;
        let w = G * q1 * lo;
        let f_o = G * (2500.0 + 400.0);
        let ao = 0.25 * std::f64::consts::PI * 18.0_f64.powi(2);
        let eao = 160000.0 * ao;
        (lo, q1, w, f_o, eao, 0.9) // q2 = q3 = 0,9 kg/m
    }

    // Geometrie manufacturee : (Tho, Tvo) au milieu de la travee => on en deduit
    // (D, H) qui annule f_x, f_z par construction (comme en 4a). Le balayage
    // s'amorce alors exactement, et la garde au sol depend du profil `alts`.
    struct Cas {
        lo: f64,
        eao: f64,
        d: f64,
        h_alt: f64,
        tho: f64,
        tvo: f64,
        z_mid: f64, // cote du cable sous la charge centree (avant retrait du sol)
        q1: f64,
        q2: f64,
        q3: f64,
        f_o: f64,
        zup: f64,
    }

    fn cas_manufacture() -> Cas {
        let (lo, q1, w, f_o, eao, q) = params();
        let (tho, tvo) = (60000.0, 25000.0);
        let s_mid = lo * 0.5;
        let f_mid = 0.5 * (s_mid * q + (lo - s_mid) * q) * G + f_o;
        // Geometrie qui annule f_x, f_z pour la charge au milieu.
        let d = super::calcul_xs(tho, tvo, lo, eao, w, f_mid, s_mid, lo);
        let h_alt = calcul_zs(tho, tvo, lo, eao, w, f_mid, s_mid, lo);
        // Cote du cable sous la charge centree, rapportee au support haut a zup.
        // On fixe zup pour que le point bas soit a 20 m au-dessus du zero terrain.
        let drop_mid = calcul_zs(tho, tvo, lo, eao, w, f_mid, s_mid, s_mid);
        let zup = 20.0 + drop_mid;
        let z_mid = zup - drop_mid; // = 20 par construction
        Cas {
            lo,
            eao,
            d,
            h_alt,
            tho,
            tvo,
            z_mid,
            q1,
            q2: q,
            q3: q,
            f_o,
            zup,
        }
    }

    // Terrain plat a l'altitude `sol` sur toute la portee (indexe au demi-metre).
    fn terrain_plat(sol: f64) -> Vec<f64> {
        vec![sol; 1000]
    }

    #[test]
    fn travee_faisable_sur_terrain_bas() {
        let c = cas_manufacture();
        // Sol a 0 : le cable culmine a ~20 m => garde ~16,5 m, sous hline_max.
        let alts = terrain_plat(0.0);
        let hmin = check_hlinemin(
            &alts, c.h_alt, c.d, c.lo, 1.0, c.tho, c.tvo, 0.0, c.zup, c.f_o, 171616.0, 3.5, 50.0,
            c.q1, c.q2, c.q3, 5.0, c.eao, 0.0, 0.0,
        );
        // Faisable : garde minimale positive, bornee par la garde sous la charge
        // centree (z_mid - hline_min = 16,5 m), le point le plus bas de la ligne.
        assert!(hmin > 0.0, "attendu faisable, hmin_ok = {hmin}");
        assert!(hmin < c.z_mid - 3.5 + 0.1, "hmin_ok = {hmin}");
        assert!(hmin > 5.0, "garde etonnamment faible : {hmin}");
    }

    #[test]
    fn travee_infaisable_terrain_trop_haut() {
        let c = cas_manufacture();
        // Sol releve a 25 m : au-dessus du cable (20 m) => garde negative => -1.
        let alts = terrain_plat(25.0);
        let hmin = check_hlinemin(
            &alts, c.h_alt, c.d, c.lo, 1.0, c.tho, c.tvo, 0.0, c.zup, c.f_o, 171616.0, 3.5, 50.0,
            c.q1, c.q2, c.q3, 5.0, c.eao, 0.0, 0.0,
        );
        assert_eq!(hmin, -1.0);
    }

    #[test]
    fn travee_infaisable_cable_trop_haut() {
        let c = cas_manufacture();
        // Sol tres bas (-100 m) : garde ~120 m > hline_max (50) => -1.
        let alts = terrain_plat(-100.0);
        let hmin = check_hlinemin(
            &alts, c.h_alt, c.d, c.lo, 1.0, c.tho, c.tvo, 0.0, c.zup, c.f_o, 171616.0, 3.5, 50.0,
            c.q1, c.q2, c.q3, 5.0, c.eao, 0.0, 0.0,
        );
        assert_eq!(hmin, -1.0);
    }

    // check_droite est un pre-filtre purement geometrique (corde - fleche) :
    // il n'a pas besoin d'une vraie solution de cable. On teste sur une travee
    // plate (h_alt = 0) ou la garde vaut zup - terrain partout.
    #[test]
    fn check_droite_ecarte_une_corde_trop_basse() {
        let (_, q1, _, f_o, _, q) = params();
        let n = 220usize; // 110 m de portee au demi-metre
        let line_x: Vec<f64> = (0..n).map(|i| i as f64 * 0.5).collect();
        // Terrain a 1 m sous le support : garde ~1 m < hline_min (3,5) => rejet.
        let line_z: Vec<f64> = vec![9.0; n];
        let ok = check_droite(
            1.0, 0.0, 100.0, 0.0, 10.0, &line_x, &line_z, 3.5, 50.0, 171616.0, q1, q, q, f_o, 0,
            (n - 1) as i64, 0.0, 0.0,
        );
        assert_eq!(ok, 0);
    }

    #[test]
    fn check_droite_accepte_un_profil_degage() {
        let (_, q1, _, f_o, _, q) = params();
        let n = 220usize;
        let line_x: Vec<f64> = (0..n).map(|i| i as f64 * 0.5).collect();
        // Terrain a 0, support a 20 m : garde ~20 m, entre hline_min et hline_max.
        let line_z: Vec<f64> = vec![0.0; n];
        let ok = check_droite(
            1.0, 0.0, 100.0, 0.0, 20.0, &line_x, &line_z, 3.5, 50.0, 171616.0, q1, q, q, f_o, 0,
            (n - 1) as i64, 0.0, 0.0,
        );
        assert_eq!(ok, 1);
    }
}
