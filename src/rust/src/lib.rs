// Les fonctions de la mecanique cable portent la signature des equations
// physiques (Th, Tv, Lo, EAo, W, F, s1, ...) : leur nombre d'arguments reflete
// le modele et non un defaut de conception. On tait donc `too_many_arguments`
// pour tout le crate.
#![allow(clippy::too_many_arguments)]

use extendr_api::prelude::*;

mod cable;
mod desserte;
mod dfci;
use cable::catenaire;
use cable::faisabilite;
use cable::newton;
use cable::scan;
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

/// Balayage 360 deg / pixel du potentiel câble (0 support), porté en Rust.
///
/// Pour chaque cellule de desserte et chacun des 360 azimuts, extrait le profil
/// d'altitude, cherche la plus longue travée faisable ([cable_test_span()]) et
/// accumule couverture et lignes candidates. Parallèle (`rayon`) sur les
/// départs ; réduction fidèle au balayage R (mêmes départ/azimut/longueur).
///
/// @param alt Elevation values (row-major, NA as NaN).
/// @param nr Number of raster rows.
/// @param nc Number of raster columns.
/// @param res Cell size (m); square cells assumed.
/// @param foret Forest mask (1 = forest), row-major.
/// @param routes Desserte cell indices (1-based) used as line starts.
/// @param vol Volume per cell (row-major); ignored when `has_vol` is false.
/// @param has_vol Whether `vol` carries usable volume data.
/// @param htower Start-support height (m).
/// @param h_end Terminal-support height (m).
/// @param hline_min Minimum ground clearance of the carrying cable (m).
/// @param hline_max Maximum ground clearance of the carrying cable (m).
/// @param slope_min Minimum line slope, uphill yarding (rad).
/// @param slope_max Maximum line slope, uphill yarding (rad).
/// @param slope_min_aval Minimum line slope, downhill yarding (rad).
/// @param slope_max_aval Maximum line slope, downhill yarding (rad).
/// @param f_o Gravity force of load plus carriage (N).
/// @param tmax Maximum allowable tension (N).
/// @param q1 Linear mass of the carrying cable (kg/m).
/// @param q2 Linear mass of the hauling cable (kg/m).
/// @param q3 Linear mass of the return cable (kg/m).
/// @param eao Young's modulus times cable section (N).
/// @param angle_intsup Inter-support angle constraint (rad).
/// @param lmax Maximum line length (m).
/// @param lmin Minimum line length (m).
/// @param hintsup Attachment height on an intermediate support (m).
/// @param sup_max Maximum number of intermediate supports.
/// @param lmin_span Minimum distance between two supports (m).
/// @param nbconfig Beam width of the support-placement search.
/// @param pas_azimut Azimuth step of the sweep (degrees).
/// @param pas_depart Sample every `pas_depart`-th departure cell.
/// @param aspect Terrain aspect (degrees, NaN on flats), row-major.
/// @param pente Terrain slope (percent), row-major.
/// @param lsans_foret Longest stretch a line may cross outside the forest (m).
/// @param angle_transv Minimum angle to the contour line (degrees).
/// @param slope_trans Terrain slope above which a cross-slope stretch counts (percent).
/// @param l_slope Maximum cumulated length on a steep cross-slope (m).
/// @param prop_slope Maximum share of the line on a steep cross-slope.
/// @param l_hor Lateral yarding half-width buffered around each line (m).
/// @param methode_seilaplan Place supports with the SEILAPLAN graph (Bont &
///   Heinimann 2012) instead of Sylvaccess `OptPyl_NoH` (spec 013). Optimises
///   both support position and height.
/// @param hm_min Lowest intermediate-support height level (m), SEILAPLAN only.
/// @param hm_max Highest intermediate-support height level (m), SEILAPLAN only.
/// @param hm_delta Height step between levels (m), SEILAPLAN only.
/// @param min_dist_mast Minimum horizontal spacing between supports (m), SEILAPLAN only.
/// @param n_sk Number of pre-tension steps swept by the graph, SEILAPLAN only.
/// @return A list: `couvert`, `longueur`, `azimut` (per cell) and the candidate
///   line vectors `li_dep`, `li_az`, `li_lg`, `li_surf`, `li_sens`, `li_vol`,
///   `li_ipc`, `li_nsup`.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn cable_scan(
    alt: Vec<f64>,
    nr: i32,
    nc: i32,
    res: f64,
    foret: Vec<i32>,
    routes: Vec<i32>,
    vol: Vec<f64>,
    has_vol: bool,
    htower: f64,
    h_end: f64,
    hline_min: f64,
    hline_max: f64,
    slope_min: f64,
    slope_max: f64,
    slope_min_aval: f64,
    slope_max_aval: f64,
    f_o: f64,
    tmax: f64,
    q1: f64,
    q2: f64,
    q3: f64,
    eao: f64,
    angle_intsup: f64,
    lmax: f64,
    lmin: f64,
    hintsup: f64,
    sup_max: i32,
    lmin_span: f64,
    nbconfig: i32,
    pas_azimut: i32,
    pas_depart: i32,
    aspect: Vec<f64>,
    pente: Vec<f64>,
    lsans_foret: f64,
    angle_transv: f64,
    slope_trans: f64,
    l_slope: f64,
    prop_slope: f64,
    l_hor: f64,
    methode_seilaplan: bool,
    hm_min: f64,
    hm_max: f64,
    hm_delta: f64,
    min_dist_mast: f64,
    n_sk: i32,
) -> List {
    let vopt = if has_vol { Some(vol.as_slice()) } else { None };
    let out = scan::scan(
        &alt, nr as usize, nc as usize, res, &foret, &routes, vopt,
        htower, h_end, hline_min, hline_max, slope_min, slope_max,
        slope_min_aval, slope_max_aval, f_o, tmax, q1, q2, q3, eao, angle_intsup, lmax, lmin,
        hintsup, sup_max.max(0) as usize, lmin_span, nbconfig.max(1) as usize,
        pas_azimut.max(1) as usize, pas_depart.max(1) as usize,
        &aspect, &pente, lsans_foret, angle_transv, slope_trans, l_slope, prop_slope, l_hor,
        methode_seilaplan, hm_min, hm_max, hm_delta, min_dist_mast, n_sk.max(1) as usize,
    );
    let couvert: Vec<i32> = out.couvert.iter().map(|&b| b as i32).collect();
    let li_dep: Vec<i32> = out.lines.iter().map(|l| l.dep).collect();
    let li_az: Vec<i32> = out.lines.iter().map(|l| l.az).collect();
    let li_lg: Vec<f64> = out.lines.iter().map(|l| l.lg).collect();
    let li_surf: Vec<f64> = out.lines.iter().map(|l| l.surf).collect();
    let li_sens: Vec<i32> = out.lines.iter().map(|l| l.sens).collect();
    let li_vol: Vec<f64> = out.lines.iter().map(|l| l.vol).collect();
    let li_ipc: Vec<f64> = out.lines.iter().map(|l| l.ipc).collect();
    let li_nsup: Vec<i32> = out.lines.iter().map(|l| l.nsup).collect();
    list!(
        couvert = couvert,
        longueur = out.longueur,
        azimut = out.azimut,
        li_dep = li_dep,
        li_az = li_az,
        li_lg = li_lg,
        li_surf = li_surf,
        li_sens = li_sens,
        li_vol = li_vol,
        li_ipc = li_ipc,
        li_nsup = li_nsup
    )
}

/// Balayage radial DFCI (`debusq_dfci`), porté en Rust.
///
/// Depuis chaque pixel du réseau DFCI, déroule une lance 360 deg / 1 deg qui épouse
/// le relief (`Lcum += sqrt(dh² + ddist²)`), plafonnée à `lmax`, arrêtée par la
/// pente / un obstacle (`zone_ok == 0`) ou le bord. Balayage séquentiel dans l'ordre
/// des sources (tie-break `>` strict : à longueur égale, la première source gagne).
///
/// @param alt Elevation values (row-major, NA as NaN).
/// @param nr Number of raster rows.
/// @param nc Number of raster columns.
/// @param res Cell size (m); square cells assumed.
/// @param foret Forest mask (1 = forest, `Foret2`), row-major.
/// @param sources DFCI network cell indices (1-based, row-major order).
/// @param zone_ok Passable mask (1 = slope ok, no obstacle, non-nodata), row-major.
/// @param lmax Maximum hose length (m).
/// @return A list: `dist` (m), `deniv` (m), `lien` (1-based source cell), `acc`.
/// @export
#[extendr]
#[allow(clippy::too_many_arguments)]
fn dfci_scan(
    alt: Vec<f64>,
    nr: i32,
    nc: i32,
    res: f64,
    foret: Vec<i32>,
    sources: Vec<i32>,
    zone_ok: Vec<i32>,
    lmax: f64,
) -> List {
    let out = dfci::scan::scan(
        &alt, nr as usize, nc as usize, res, &foret, &sources, &zone_ok, lmax,
    );
    list!(dist = out.dist, deniv = out.deniv, lien = out.lien, acc = out.acc)
}

/// Inverse cost-distance from a target cell (road-design A\* heuristic, Lot 15a).
///
/// Ports SylvaRoad's `calcul_distance_de_cout`: geometric 8-neighbour distance
/// (step = resolution, or `resolution * sqrt(2)` on the diagonal) propagated from
/// the target over the passable zone (`zone == 1`). The step cost is unit
/// (distance only), so the result is a lower bound of the remaining road cost —
/// an admissible A\* heuristic (spec 015, CA-15.8).
///
/// @param zone Passable mask (1 = passable, 0 = blocked), row-major.
/// @param nr Number of raster rows.
/// @param nc Number of raster columns.
/// @param csize Cell size (m); square cells assumed.
/// @param y_end Target row (0-based).
/// @param x_end Target column (0-based).
/// @param max_distance Propagation ceiling (m); cells beyond it stay `NA`.
/// @return A row-major numeric vector: 0 at the target, cumulated distance
///   elsewhere, `NA` for unreached cells.
/// @export
#[extendr]
fn desserte_dist_to_end(
    zone: Vec<i32>,
    nr: i32,
    nc: i32,
    csize: f64,
    y_end: i32,
    x_end: i32,
    max_distance: f64,
) -> Vec<f64> {
    desserte::heuristic::dist_to_end(
        &zone, nr as usize, nc as usize, csize, y_end as usize, x_end as usize, max_distance,
    )
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
    fn cable_scan;
    fn dfci_scan;
    fn desserte_dist_to_end;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_is_not_empty() {
        assert!(!cablehelp_version().is_empty());
    }
}
