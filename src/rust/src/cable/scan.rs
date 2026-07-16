//! Balayage 360 deg / pixel du potentiel cable (portage Rust de l'orchestration).
//!
//! Porte la boucle chaude de `potentiel_cable()` (R) dans le crate : pour chaque
//! cellule de desserte et chacun des 360 azimuts, extraction du profil, puis
//! placement des supports (`optpyl`), qui coupe la ligne ou la retourne (machine en bas). Il
//! coupe au plus loin s'il ne peut pas la porter entiere. Parallelise sur les
//! cellules de desserte avec `rayon`.
//!
//! Le profil sert sous deux formes, comme chez Sylvaccess : **au pixel** pour poser
//! les supports (`Line`), **au demi-metre** pour la garde au sol (`Alts`).

use crate::cable::ligne;
use crate::cable::optpyl;
use crate::cable::seilaplan;
use rayon::prelude::*;

/// Un rayon precalcule : cellules traversees (decalages ligne/colonne) et leur
/// distance horizontale au depart.
pub struct Ray {
    pub dl: Vec<i32>,
    pub dc: Vec<i32>,
    pub hdist: Vec<f64>,
}

/// Rayons precalcules pour les 360 azimuts. Reproduit `.rayons()` (R) :
/// pas = res/3, portee = portee_m + 1.5*res, azimut horaire depuis le nord,
/// suppression du (0,0) et des doublons consecutifs.
pub fn build_rays(res: f64, portee_m: f64) -> Vec<Ray> {
    let lmax = portee_m + 1.5 * res;
    let pas = res / 3.0;
    // seq(pas, lmax, by = pas) : t_i = i*pas, i = 1.. tant que t_i <= lmax.
    let nstep = (lmax / pas + 1e-10).floor() as i64;
    let mut rays = Vec::with_capacity(360);
    for az in 0..360 {
        let rad = az as f64 * std::f64::consts::PI / 180.0;
        let dx = rad.sin();
        let dy = rad.cos();
        let (mut dl, mut dc, mut hd) = (Vec::new(), Vec::new(), Vec::new());
        let (mut prev_l, mut prev_c) = (i32::MIN, i32::MIN);
        let mut first = true;
        for i in 1..=nstep {
            let t = i as f64 * pas;
            let cc = round_half_even(t * dx / res) as i32;
            let ll = round_half_even(-t * dy / res) as i32;
            if cc == 0 && ll == 0 {
                continue; // (0,0) exclu
            }
            if !first && cc == prev_c && ll == prev_l {
                continue; // doublon consecutif
            }
            first = false;
            prev_l = ll;
            prev_c = cc;
            let h = res * ((ll * ll + cc * cc) as f64).sqrt();
            if h <= lmax {
                dl.push(ll);
                dc.push(cc);
                hd.push(h);
            }
        }
        rays.push(Ray { dl, dc, hdist: hd });
    }
    rays
}

/// Bande de pechage lateral precalculee pour un azimut : cellules du tampon
/// perpendiculaire, avec leur distance *le long* de la ligne (`dalong`, qui borne
/// la couverture a la longueur faisable) et leur decalage ligne/colonne.
pub struct LatRay {
    pub dl: Vec<i32>,
    pub dc: Vec<i32>,
    pub dalong: Vec<f64>,
}

/// Bandes de pechage lateral pour les 360 azimuts. Reproduit `create_rast_couv`
/// (Sylvaccess) : la couverture d'une ligne n'est pas le seul axe mais un
/// **rectangle** de demi-largeur `l_hor` autour du segment desserte -> bout de
/// ligne. On precalcule, par azimut, toutes les cellules du demi-plan a distance
/// laterale <= `l_hor` et a distance le long de la ligne dans `[0, lmax]`, triees
/// par `dalong` : au balayage, la ligne faisable de longueur L couvre celles dont
/// `dalong <= L`. Aucune contrainte geometrique (denivele, pente, visibilite) --
/// c'est un simple tampon, fidele a la lettre.
pub fn build_lat_rays(res: f64, portee_m: f64, l_hor: f64) -> Vec<LatRay> {
    let lmax = portee_m + 1.5 * res;
    // Rayon de recherche en cellules : portee le long + tampon lateral.
    let rmax = ((lmax + l_hor) / res).ceil() as i32 + 1;
    let mut lats = Vec::with_capacity(360);
    for az in 0..360 {
        let rad = az as f64 * std::f64::consts::PI / 180.0;
        let (sa, ca) = (rad.sin(), rad.cos());
        let (mut dl, mut dc, mut da) = (Vec::new(), Vec::new(), Vec::new());
        for ll in -rmax..=rmax {
            for cc in -rmax..=rmax {
                if ll == 0 && cc == 0 {
                    continue; // depart exclu
                }
                // Deplacement metrique : est = cc*res, nord = -ll*res.
                let e = cc as f64 * res;
                let north = -(ll as f64) * res;
                let dalong = e * sa + north * ca; // projection le long de l'azimut
                let dlat = (e * ca - north * sa).abs(); // ecart perpendiculaire
                if dalong >= 0.0 && dalong <= lmax && dlat <= l_hor {
                    dl.push(ll);
                    dc.push(cc);
                    da.push(dalong);
                }
            }
        }
        // Tri par distance le long de la ligne : la coupe `dalong <= L` devient un
        // simple prefixe.
        let mut idx: Vec<usize> = (0..da.len()).collect();
        idx.sort_by(|&i, &j| da[i].partial_cmp(&da[j]).unwrap());
        lats.push(LatRay {
            dl: idx.iter().map(|&i| dl[i]).collect(),
            dc: idx.iter().map(|&i| dc[i]).collect(),
            dalong: idx.iter().map(|&i| da[i]).collect(),
        });
    }
    lats
}

/// Arrondi au plus proche, demi vers le pair (comme `round()` de R / IEC 60559),
/// la ou `f64::round` arrondit demi loin de zero. Determine l'exactitude du
/// balayage vis-a-vis de l'ancienne boucle R.
fn round_half_even(x: f64) -> f64 {
    let f = x.floor();
    let diff = x - f;
    if diff < 0.5 {
        f
    } else if diff > 0.5 {
        f + 1.0
    } else if (f as i64) % 2 == 0 {
        f
    } else {
        f + 1.0
    }
}

/// Interpolation lineaire type `stats::approx(na.rm = TRUE, rule = 1)` : les
/// paires (x, y) dont y est NaN sont retirees ; hors de l'intervalle des x
/// valides, le resultat est NaN.
fn interp_dropna(hd: &[f64], za: &[f64], xs: &[f64]) -> Vec<f64> {
    let mut px = Vec::with_capacity(hd.len());
    let mut py = Vec::with_capacity(hd.len());
    for i in 0..hd.len() {
        if !za[i].is_nan() {
            px.push(hd[i]);
            py.push(za[i]);
        }
    }
    let n = px.len();
    let mut out = vec![f64::NAN; xs.len()];
    if n < 2 {
        return out;
    }
    let (xmin, xmax) = (px[0], px[n - 1]);
    let mut j = 0usize;
    for (k, &x) in xs.iter().enumerate() {
        if x < xmin || x > xmax {
            continue; // rule = 1 -> NaN hors bornes
        }
        while j + 1 < n && px[j + 1] < x {
            j += 1;
        }
        // px[j] <= x <= px[j+1]
        let (x0, x1) = (px[j], px[j + 1]);
        let (y0, y1) = (py[j], py[j + 1]);
        out[k] = if x1 == x0 { y0 } else { y0 + (y1 - y0) * (x - x0) / (x1 - x0) };
    }
    out
}

/// Une ligne candidate faisable (une par depart / azimut).
pub struct Line {
    pub dep: i32,   // cellule de depart (1-based)
    pub az: i32,    // azimut (deg)
    pub lg: f64,    // longueur faisable (m)
    pub surf: f64,  // surface foret couverte (ha)
    pub sens: i32,  // +1 aval, -1 amont, 0 plat
    pub vol: f64,   // volume (m3) ou NaN
    pub ipc: f64,   // volume / longueur ou NaN
    pub nsup: i32,  // nombre de supports intermediaires poses
}

/// Resultat du balayage.
pub struct ScanOut {
    pub couvert: Vec<bool>,
    pub longueur: Vec<f64>,
    pub azimut: Vec<f64>, // NaN si non couvert
    pub lines: Vec<Line>,
}

// Contribution d'une seule ligne a la couverture (cellule 0-based, longueur, az).
struct Cover {
    cell: usize,
    lg: f64,
    az: i32,
}

struct RouteResult {
    covers: Vec<Cover>,
    lines: Vec<Line>,
}

/// Balayage complet. `alt` et `vol` sont en ordre ligne-majeur (NaN = NA).
/// `foret[i]` vaut 1 en foret. `routes` liste les departs (1-based).
#[allow(clippy::too_many_arguments)]
pub fn scan(
    alt: &[f64],
    nr: usize,
    nc: usize,
    res: f64,
    foret: &[i32],
    routes: &[i32],
    vol: Option<&[f64]>,
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
    sup_max: usize,
    lmin_span: f64,
    nbconfig: usize,
    pas_azimut: usize,
    pas_depart: usize,
    aspect: &[f64],
    pente: &[f64],
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
    n_sk: usize,
) -> ScanOut {
    let n = nr * nc;
    let aire_cell = res * res;
    let rays = build_rays(res, lmax);
    let lat_rays = build_lat_rays(res, lmax, l_hor);
    let pas_az = pas_azimut.max(1);
    let pas_dep = pas_depart.max(1);

    // Traitement d'un depart : renvoie ses contributions de couverture + lignes.
    let une_route = |&dep_1based: &i32| -> RouteResult {
        let dep = (dep_1based - 1) as usize; // 0-based
        let dl0 = dep / nc; // ligne 0-based
        let dc0 = dep % nc; // colonne 0-based
        let mut covers = Vec::new();
        let mut lines = Vec::new();

        // Pas angulaire : Sylvaccess ne balaie pas les 360 azimuts en precision
        // grossiere, mais un sur `pas_az` (`Dir_list = range(0, 360, 2)`).
        for (az, ray) in rays.iter().enumerate().filter(|(a, _)| a % pas_az == 0) {
            // Cellules du rayon dans la grille.
            let mut cel = Vec::with_capacity(ray.dl.len());
            let mut hd = Vec::with_capacity(ray.dl.len());
            for i in 0..ray.dl.len() {
                let l = dl0 as i64 + ray.dl[i] as i64;
                let c = dc0 as i64 + ray.dc[i] as i64;
                if l >= 0 && (l as usize) < nr && c >= 0 && (c as usize) < nc {
                    cel.push((l as usize) * nc + c as usize);
                    hd.push(ray.hdist[i]);
                }
            }
            if cel.is_empty() {
                continue;
            }
            let smax = hd.iter().cloned().fold(f64::MIN, f64::max);
            if smax < lmin {
                continue;
            }

            // Profil AU PIXEL : c'est lui qui porte les travees (`Line` chez
            // Sylvaccess). Les supports se posent sur une cellule, pas au demi-metre.
            let mut prof_hd = Vec::with_capacity(cel.len() + 1);
            let mut prof_za = Vec::with_capacity(cel.len() + 1);
            let mut prof_fo = Vec::with_capacity(cel.len() + 1);
            let mut prof_as = Vec::with_capacity(cel.len() + 1);
            let mut prof_pe = Vec::with_capacity(cel.len() + 1);
            prof_hd.push(0.0);
            prof_za.push(alt[dep]);
            prof_fo.push(foret[dep] == 1);
            prof_as.push(aspect[dep]);
            prof_pe.push(pente[dep]);
            for i in 0..cel.len() {
                if hd[i] > lmax {
                    break;
                }
                prof_hd.push(hd[i]);
                prof_za.push(alt[cel[i]]);
                prof_fo.push(foret[cel[i]] == 1);
                prof_as.push(aspect[cel[i]]);
                prof_pe.push(pente[cel[i]]);
            }
            // Un NA d'altitude coupe le profil : on ne pose pas de cable sur un trou.
            if prof_za.iter().any(|z| z.is_nan()) {
                continue;
            }

            // Validite geometrique de la ligne (`check_line`) : elle finit en foret, ne
            // traverse pas trop de non-foret, et ne court pas en travers d'un versant
            // raide. C'est ce filtre qui donne sa longueur utile a la ligne -- sans lui,
            // elle file jusqu'a `lmax` a travers n'importe quoi.
            let prof = ligne::Profil {
                hd: &prof_hd,
                alt: &prof_za,
                foret: &prof_fo,
                aspect: &prof_as,
                pente: &prof_pe,
            };
            let garde = match ligne::check_line(&prof, &ligne::Seuils {
                az: az as f64,
                lmax,
                lmin,
                lsans_foret,
                angle_transv,
                slope_trans,
                l_slope,
                prop_slope,
            }) {
                Some(k) => k,
                None => continue,
            };
            prof_hd.truncate(garde);
            prof_za.truncate(garde);
            if prof_hd.len() < 2 {
                continue;
            }

            // Meme terrain, echantillonne au demi-metre : c'est la garde au sol
            // (`Alts`), indexee par `int(x * 2)` dans la mecanique.
            let lline = *prof_hd.last().unwrap();
            let m = (lline / 0.5).floor() as usize + 2;
            let xs: Vec<f64> = (0..m).map(|i| i as f64 * 0.5).collect();
            let zs = interp_dropna(&prof_hd, &prof_za, &xs);

            // Sens de la ligne. Sylvaccess ne compare pas les altitudes brutes : il
            // regarde si le mat, depuis la desserte, **domine** le point le plus haut
            // de la ligne augmente de l'ancrage. Si oui la machine est en haut, sinon
            // elle est en bas -- et la ligne se resout alors a l'envers.
            let idlinemin = prof_hd.iter().position(|&d| d >= lmin).unwrap_or(0);
            let zmax = prof_za[idlinemin..].iter().cloned().fold(f64::MIN, f64::max);
            let machine_en_haut = prof_za[0] + htower >= zmax + h_end;

            let base = optpyl::OptParams {
                line_x: &prof_hd,
                line_z: &prof_za,
                alts: &zs,
                h_debut: htower,
                hintsup,
                h_fin: h_end,
                hline_min,
                hline_max,
                slope_min,
                slope_max,
                f_o,
                tmax,
                q1,
                q2,
                q3,
                eao,
                csize: res,
                angle_intsup,
                sup_max,
                lmin_span,
                nbconfig,
                heriter_tension: true,
            };

            // Portee retenue, en index du profil aller, et nombre de supports poses.
            let (iterm, nb_sup) = if methode_seilaplan {
                // Placement des supports a la SEILAPLAN (graphe + Dijkstra, spec
                // 013). Le graphe est symetrique : un seul passage, sans la
                // gymnastique machine-en-haut / machine-en-bas de Sylvaccess.
                // Positions candidates = cretes du profil au demi-metre (`zs`).
                let step_idx = ((min_dist_mast / 0.5).round() as usize).max(1);
                let mut cands = seilaplan::peak_positions(&zs, step_idx, 0.0);
                // Complement : grille reguliere au pas `min_dist_mast`. Les cretes
                // seules ne suffisent pas sur terrain lisse -- il faut des points
                // ou le graphe puisse poser un support ou couper la ligne a une
                // longueur faisable (l'equivalent de la coupe de `OptPyl`).
                let mut k = step_idx;
                while k + 1 < zs.len() {
                    cands.push(k);
                    k += step_idx;
                }
                let gp = seilaplan::GraphParams {
                    min_hm: hm_min,
                    max_hm: hm_max,
                    dhm: hm_delta,
                    min_dist_mast,
                    // Pas de donnee d'arbres-supports : hm_nat = max => pas de
                    // penalite de depassement (spec 013 §4.4).
                    hm_nat: hm_max,
                    h_start: htower,
                    h_end,
                    // Plage de pre-tension balayee : de 30 % de l'admissible a
                    // l'admissible, `detail` proportionne a `tmax`.
                    t_min: 0.3 * tmax,
                    t_max: tmax,
                    n_sk,
                    detail: (tmax / 100.0).max(500.0),
                };
                let cm = seilaplan::CableMat {
                    f_o,
                    tmax,
                    q1,
                    q2,
                    q3,
                    eao,
                    hline_min,
                    hline_max,
                    csize: res,
                    dsupdep: 0.0,
                    dsupend: 0.0,
                };
                let sol = seilaplan::optimize_supports(&xs, &zs, &cands, &gp, &cm);
                // Prolonge la portee au-dela du dernier support (coupe au pas
                // raster, comme OptPyl) : le graphe s'arrete au dernier support
                // candidat, mais le cable porte encore jusqu'a un ancrage plus
                // loin. Sans ca, ~8100 cellules de bout de ligne sont perdues.
                let reach_idx = if sol.full_span {
                    sol.reach_idx
                } else {
                    let h_last = *sol.heights.last().unwrap_or(&h_end);
                    let step = ((res / 0.5).round() as usize).max(1);
                    seilaplan::extend_reach(&xs, &zs, sol.reach_idx, h_last, h_end, &cm, step)
                };
                // Portee (distance) -> dernier index du profil aller couvert.
                let longueur_sp = reach_idx as f64 * 0.5;
                let iterm = prof_hd
                    .iter()
                    .rposition(|&d| d <= longueur_sp)
                    .unwrap_or(0);
                let nb_sup = sol.positions.len().saturating_sub(2); // hors extremites
                (iterm, nb_sup)
            } else if machine_en_haut {
                // Placement des supports, avec coupe de la ligne a defaut.
                let spans = optpyl::optpyl(&base);
                match spans.last() {
                    Some(l) => (l.posi(), spans.len() - 1),
                    None => continue,
                }
            } else {
                // Machine en bas. Deux passes, comme Sylvaccess.
                //
                // 1. Amorce (`OptPyl_Down_init_NoH`) sur le profil ALLER, bornes de
                //    pente aval : elle ne sert qu'a savoir jusqu'ou la ligne peut
                //    raisonnablement porter. Chaque travee y repart de `tmax` -- la
                //    tension n'est pas heritee, l'amorce n'est pas une vraie ligne.
                let init = optpyl::optpyl(&optpyl::OptParams {
                    slope_min: slope_min_aval,
                    slope_max: slope_max_aval,
                    heriter_tension: false,
                    ..base
                });
                let extent = match init.last() {
                    Some(l) => l.posi(),
                    None => continue,
                };
                if init.iter().map(|s| s.diag()).sum::<f64>() < lmin {
                    continue;
                }
                // 2. Ligne reelle sur le profil RETOURNE (`OptPyl_Down_NoH`). Les
                //    hauteurs d'extremite s'echangent (l'ancrage ouvre, le mat ferme) et
                //    les bornes de pente changent de signe avec le sens de parcours.
                let ilast = (extent + 2).min(prof_hd.len() - 1);
                let (rx, rz) = optpyl::retourner_profil(&prof_hd[..=ilast], &prof_za[..=ilast]);
                let rlline = *rx.last().unwrap();
                let rm = (rlline / 0.5).floor() as usize + 2;
                let rxs: Vec<f64> = (0..rm).map(|i| i as f64 * 0.5).collect();
                let rzs = interp_dropna(&rx, &rz, &rxs);
                let res_down = optpyl::optpyl_down_noh(&optpyl::OptParams {
                    line_x: &rx,
                    line_z: &rz,
                    alts: &rzs,
                    h_debut: h_end,
                    h_fin: htower,
                    slope_min: (-slope_min_aval).min(-slope_max_aval),
                    slope_max: (-slope_min_aval).max(-slope_max_aval),
                    ..base
                });
                match res_down {
                    // `rogne` pixels ont ete retires en tete du profil retourne, donc
                    // au bout de la ligne aller : la portee recule d'autant.
                    Some((spans, rogne)) => (ilast - rogne, spans.len() - 1),
                    None => continue,
                }
            };

            let longueur = prof_hd[iterm];
            if longueur < lmin {
                continue;
            }

            // Cellules couvertes (hdist <= longueur).
            let mut couv = Vec::new();
            let mut far_cell = cel[0];
            let mut far_h = f64::MIN;
            for i in 0..cel.len() {
                if hd[i] <= longueur {
                    couv.push(cel[i]);
                    covers.push(Cover { cell: cel[i], lg: longueur, az: az as i32 });
                    if hd[i] > far_h {
                        far_h = hd[i];
                        far_cell = cel[i];
                    }
                }
            }
            if couv.is_empty() {
                continue;
            }

            // Pechage lateral (`create_rast_couv`) : la ligne faisable couvre aussi
            // le rectangle de demi-largeur `l_hor` autour de son axe, jusqu'a sa
            // longueur retenue. On ne l'ajoute qu'a la couverture (couvert/longueur/
            // azimut) -- la surface/volume de la ligne, eux, restent sur l'axe.
            if l_hor > 0.0 {
                let lat = &lat_rays[az];
                for i in 0..lat.dalong.len() {
                    if lat.dalong[i] > longueur {
                        break; // trie par dalong : au-dela, plus rien
                    }
                    let l = dl0 as i64 + lat.dl[i] as i64;
                    let c = dc0 as i64 + lat.dc[i] as i64;
                    if l >= 0 && (l as usize) < nr && c >= 0 && (c as usize) < nc {
                        let cell = (l as usize) * nc + c as usize;
                        covers.push(Cover { cell, lg: longueur, az: az as i32 });
                    }
                }
            }

            // Cellules forestieres couvertes.
            let cf: Vec<usize> = couv.iter().cloned().filter(|&c| foret[c] == 1).collect();
            if cf.is_empty() {
                continue;
            }
            let surf = cf.len() as f64 * aire_cell / 10000.0;
            let sens = (alt[far_cell] - alt[dep]).signum();
            let sens = if (alt[far_cell] - alt[dep]) == 0.0 { 0 } else { sens as i32 };
            let (vol_l, ipc_l) = match vol {
                Some(v) => {
                    let s: f64 = cf.iter().map(|&c| if v[c].is_nan() { 0.0 } else { v[c] }).sum();
                    let vv = s * aire_cell / 10000.0;
                    (vv, vv / longueur)
                }
                None => (f64::NAN, f64::NAN),
            };
            lines.push(Line {
                dep: dep_1based,
                az: az as i32,
                lg: longueur,
                surf,
                sens,
                vol: vol_l,
                ipc: ipc_l,
                nsup: nb_sup as i32,
            });
        }
        RouteResult { covers, lines }
    };

    // Pas entre cellules de depart (`step_route`) : en precision grossiere,
    // Sylvaccess n'essaie qu'une cellule de desserte sur deux.
    let departs: Vec<i32> = routes.iter().step_by(pas_dep).cloned().collect();

    // Parallelise sur les departs, ordre preserve pour une reduction deterministe.
    let per_route: Vec<RouteResult> = departs.par_iter().map(une_route).collect();

    let mut couvert = vec![false; n];
    let mut longueur = vec![0.0f64; n];
    let mut azimut = vec![f64::NAN; n];
    let mut lines = Vec::new();
    for rr in per_route {
        for cv in rr.covers {
            couvert[cv.cell] = true;
            if cv.lg > longueur[cv.cell] {
                longueur[cv.cell] = cv.lg;
                azimut[cv.cell] = cv.az as f64;
            }
        }
        lines.extend(rr.lines);
    }

    ScanOut { couvert, longueur, azimut, lines }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rays_cover_360_and_exclude_center() {
        let rays = build_rays(5.0, 100.0);
        assert_eq!(rays.len(), 360);
        for r in &rays {
            for i in 0..r.dl.len() {
                assert!(!(r.dl[i] == 0 && r.dc[i] == 0));
            }
            // hdist croissant.
            for i in 1..r.hdist.len() {
                assert!(r.hdist[i] >= r.hdist[i - 1] - 1e-9);
            }
        }
    }

    #[test]
    fn lat_rays_form_a_sorted_perpendicular_band() {
        let res = 5.0;
        let l_hor = 40.0;
        let lats = build_lat_rays(res, 100.0, l_hor);
        assert_eq!(lats.len(), 360);
        // Marge d'un demi-diagonale de cellule sur l'ecart lateral mesure au centre.
        let marge = res * std::f64::consts::SQRT_2 * 0.5;
        for (az, lat) in lats.iter().enumerate() {
            let rad = az as f64 * std::f64::consts::PI / 180.0;
            let (sa, ca) = (rad.sin(), rad.cos());
            // dalong trie et jamais negatif.
            for i in 0..lat.dalong.len() {
                assert!(lat.dalong[i] >= 0.0);
                if i > 0 {
                    assert!(lat.dalong[i] >= lat.dalong[i - 1] - 1e-9);
                }
                // Toute cellule retenue est dans la bande |dlat| <= l_hor.
                let e = lat.dc[i] as f64 * res;
                let north = -(lat.dl[i] as f64) * res;
                let dlat = (e * ca - north * sa).abs();
                assert!(dlat <= l_hor + marge);
                assert!(!(lat.dl[i] == 0 && lat.dc[i] == 0));
            }
        }
        // Le long de l'est (az 90), une cellule a l'est de meme rangee est dans la
        // bande, une cellule loin au nord (perpendiculaire) au-dela de l_hor non.
        let est = &lats[90];
        assert!(est.dl.iter().zip(&est.dc).any(|(&l, &c)| l == 0 && c == 1));
        assert!(!est.dl.iter().zip(&est.dc).any(|(&l, &c)| c == 1 && (l as f64 * res) > l_hor));
    }

    #[test]
    fn lat_rays_empty_when_no_buffer() {
        let lats = build_lat_rays(5.0, 100.0, 0.0);
        assert_eq!(lats.len(), 360);
        // Sans tampon, seule la cellule d'axe exact (dlat == 0) survit -- jamais (0,0).
        for lat in &lats {
            for i in 0..lat.dl.len() {
                assert!(!(lat.dl[i] == 0 && lat.dc[i] == 0));
            }
        }
    }

    #[test]
    fn interp_linear_and_dropna() {
        let hd = [0.0, 1.0, 2.0];
        let za = [0.0, f64::NAN, 4.0];
        let xs = [0.0, 1.0, 2.0, 3.0];
        let zs = interp_dropna(&hd, &za, &xs);
        assert!((zs[0] - 0.0).abs() < 1e-9);
        assert!((zs[1] - 2.0).abs() < 1e-9); // interpole a travers le NaN
        assert!((zs[2] - 4.0).abs() < 1e-9);
        assert!(zs[3].is_nan()); // hors bornes
    }
}
