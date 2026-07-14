//! Validite geometrique d'une ligne de cable (`check_line` de Sylvaccess v3.6).
//!
//! Avant meme de savoir si le cable TIENT mecaniquement, il faut savoir jusqu'ou la
//! ligne a un SENS. Sylvaccess la coupe sur trois criteres, tous geometriques :
//!
//! 1. **Elle finit en foret.** L'index retenu est la derniere cellule forestiere : on
//!    n'installe pas un cable pour desservir un pre. Et elle ne traverse pas plus de
//!    `lsans_foret` metres de non-foret d'affilee -- au-dela, le massif suivant n'est
//!    plus le meme chantier.
//! 2. **Elle ne court pas en travers d'un versant raide.** Une ligne « en devers »
//!    (azimut eloigne de plus de `angle_transv` de la ligne de plus grande pente) sur un
//!    terrain a plus de `slope_trans` accumule de la longueur « mauvaise » : le cable
//!    casse au-dela de `l_slope` metres cumules, et la ligne est coupee des que cette
//!    longueur depasse la proportion `prop_slope` du total.
//! 3. **Elle reste sous `lmax`** en distance 3D depuis le depart, et dans la grille.
//!
//! Sans ce filtre, les lignes filent jusqu'a `lmax` a travers n'importe quel terrain :
//! mesure sur ColduPre, c'est 10 % de la foret declaree accessible a tort.

/// Profil d'une ligne, au pixel.
pub struct Profil<'a> {
    pub hd: &'a [f64],    // distance horizontale au depart (m)
    pub alt: &'a [f64],   // altitude du terrain (m)
    pub foret: &'a [bool],
    pub aspect: &'a [f64], // exposition (deg), NaN sur un replat
    pub pente: &'a [f64],  // pente du terrain (%)
}

/// Seuils de validite d'une ligne.
pub struct Seuils {
    pub az: f64,           // azimut de la ligne (deg)
    pub lmax: f64,         // longueur max de la ligne (m), en 3D
    pub lmin: f64,         // longueur min (m)
    pub lsans_foret: f64,  // longueur max traversee sans foret (m)
    pub angle_transv: f64, // angle min a la courbe de niveau (deg)
    pub slope_trans: f64,  // pente au-dela de laquelle le devers compte (%)
    pub l_slope: f64,      // longueur cumulee max en devers raide (m)
    pub prop_slope: f64,   // proportion max de la ligne en devers raide
}

/// Rend le nombre de pixels a conserver (`indmax + 1`), ou `None` si la ligne est trop
/// courte pour valoir un cable.
pub fn check_line(p: &Profil, s: &Seuils) -> Option<usize> {
    let npix = p.hd.len();
    let mut indmax = 0usize; // derniere cellule de foret
    let mut indmax2 = 0usize; // dernier index sous la proportion de devers admise
    let mut dcum = 0.0f64; // longueur cumulee en devers raide
    let mut dsansforet = 0.0f64;

    for i in 0..npix {
        // Longueur 3D depuis le depart.
        let dz = p.alt[i] - p.alt[0];
        if (p.hd[i] * p.hd[i] + dz * dz).sqrt() > s.lmax {
            break;
        }

        // --- Devers : la ligne court-elle en travers d'un versant raide ? -----
        // `aligne` vaut 1 quand l'azimut est a moins de `angle_transv` de la ligne de
        // plus grande pente (ou de son oppose) : la ligne suit la pente, tout va bien.
        let alignee = if p.aspect[i].is_nan() {
            true
        } else {
            let a = (((s.az - p.aspect[i].trunc()) + 180.0).rem_euclid(360.0) - 180.0).abs();
            a > 90.0 + s.angle_transv || a < 90.0 - s.angle_transv
        };
        let pente_douce = !p.pente[i].is_nan() && p.pente[i].trunc() < s.slope_trans;

        if i > 0 {
            if !alignee && !pente_douce {
                dcum += p.hd[i] - p.hd[i - 1];
            }
            if dcum > s.l_slope {
                break;
            }
            if dcum / p.hd[i] < s.prop_slope {
                indmax2 = i;
            }
        }

        // --- Longueur sans foret ---------------------------------------------
        if p.foret[i] {
            indmax = i;
            dsansforet = 0.0;
        } else {
            if i > 0 {
                dsansforet += p.hd[i] - p.hd[i - 1];
            }
            if dsansforet >= s.lsans_foret {
                break;
            }
        }
    }

    let ind = indmax.min(indmax2);
    if p.hd[ind] <= s.lmin {
        return None;
    }
    Some(ind + 1)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seuils(az: f64) -> Seuils {
        Seuils {
            az,
            lmax: 750.0,
            lmin: 150.0,
            lsans_foret: 75.0,
            angle_transv: 60.0,
            slope_trans: 30.0,
            l_slope: 75.0,
            prop_slope: 0.15,
        }
    }

    // Profil de `n` pixels au pas de 5 m, tout en foret, plat.
    fn plat(n: usize) -> (Vec<f64>, Vec<f64>, Vec<bool>, Vec<f64>, Vec<f64>) {
        let hd: Vec<f64> = (0..n).map(|i| i as f64 * 5.0).collect();
        (hd, vec![100.0; n], vec![true; n], vec![f64::NAN; n], vec![0.0; n])
    }

    #[test]
    fn une_ligne_entierement_en_foret_est_gardee_entiere() {
        let (hd, alt, foret, asp, pente) = plat(101); // 500 m
        let p = Profil { hd: &hd, alt: &alt, foret: &foret, aspect: &asp, pente: &pente };
        assert_eq!(check_line(&p, &seuils(0.0)), Some(101));
    }

    #[test]
    fn la_ligne_est_coupee_a_la_derniere_cellule_de_foret() {
        let (hd, alt, mut foret, asp, pente) = plat(101);
        // La foret s'arrete au pixel 60 (300 m) ; au-dela, un pre.
        for f in foret.iter_mut().skip(61) {
            *f = false;
        }
        let p = Profil { hd: &hd, alt: &alt, foret: &foret, aspect: &asp, pente: &pente };
        assert_eq!(check_line(&p, &seuils(0.0)), Some(61)); // indices 0..=60
    }

    #[test]
    fn une_trouee_courte_est_franchie_une_longue_coupe_la_ligne() {
        let (hd, alt, mut foret, asp, pente) = plat(101);
        // Trouee de 50 m (< 75) : franchie, la foret reprend et la ligne continue.
        for f in foret.iter_mut().take(51).skip(41) {
            *f = false;
        }
        let p = Profil { hd: &hd, alt: &alt, foret: &foret, aspect: &asp, pente: &pente };
        assert_eq!(check_line(&p, &seuils(0.0)), Some(101));

        // Trouee de 100 m (>= 75) : la ligne s'arrete a la derniere foret d'avant.
        let (hd, alt, mut foret, asp, pente) = plat(101);
        for f in foret.iter_mut().take(61).skip(41) {
            *f = false;
        }
        let p = Profil { hd: &hd, alt: &alt, foret: &foret, aspect: &asp, pente: &pente };
        assert_eq!(check_line(&p, &seuils(0.0)), Some(41)); // derniere foret : index 40
    }

    #[test]
    fn une_ligne_en_travers_dun_versant_raide_est_refusee() {
        let (hd, alt, foret, _asp, _pente) = plat(101);
        // Terrain a 50 % expose au nord (aspect 0) ; ligne plein est (az 90) : elle
        // court exactement le long de la courbe de niveau -> devers maximal.
        let asp = vec![0.0; 101];
        let pente = vec![50.0; 101];
        let p = Profil { hd: &hd, alt: &alt, foret: &foret, aspect: &asp, pente: &pente };
        assert_eq!(check_line(&p, &seuils(90.0)), None);
    }

    #[test]
    fn la_meme_ligne_dans_le_sens_de_la_pente_passe() {
        let (hd, alt, foret, _asp, _pente) = plat(101);
        let asp = vec![0.0; 101];
        let pente = vec![50.0; 101];
        // Ligne plein nord (az 0) : elle suit la ligne de plus grande pente.
        let p = Profil { hd: &hd, alt: &alt, foret: &foret, aspect: &asp, pente: &pente };
        assert_eq!(check_line(&p, &seuils(0.0)), Some(101));
    }

    #[test]
    fn une_ligne_trop_courte_est_refusee() {
        let (hd, alt, foret, asp, pente) = plat(21); // 100 m < lmin 150
        let p = Profil { hd: &hd, alt: &alt, foret: &foret, aspect: &asp, pente: &pente };
        assert_eq!(check_line(&p, &seuils(0.0)), None);
    }
}
