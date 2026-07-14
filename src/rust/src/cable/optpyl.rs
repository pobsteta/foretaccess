//! Placement des supports intermediaires (`OptPyl_Up_NoH` de Sylvaccess v3.6).
//!
//! Une ligne de cable-mat ne se resume pas a une travee : quand la portee directe
//! mat -> ancrage ne passe pas (garde au sol, tension, pente), on insere jusqu'a
//! `sup_max` supports intermediaires. Sylvaccess les place par une **recherche en
//! faisceau** : a chaque niveau de support, il retient les `nbconfig` meilleures
//! configurations partielles (celles qui portent le plus loin, a hauteur de
//! fixation minimale) et repart de la. Si aucune configuration ne rejoint le bout
//! de la ligne, il **coupe** la ligne au point le plus lointain atteint.
//!
//! Variante `_NoH` (`c_option_h = 0`, le defaut) : la hauteur de fixation sur
//! chaque support n'est PAS optimisee -- elle vaut `hintsup` sur les supports
//! intermediaires et `hend` au terminus. C'est le chemin qu'emprunte Sylvaccess
//! dans son scenario de reference.
//!
//! Le profil `line_*` est indexe **au pixel** (comme `Line` chez Sylvaccess) ;
//! `alts` est le meme terrain echantillonne au demi-metre, pour la garde au sol.

use super::supports::{test_span, SpanResult};

const G: f64 = 9.80665;

/// Nombre de champs d'une travee, dans l'ordre de Sylvaccess (`Tab`) :
/// `D, H, diag, slope, fact, Xup, Zup, Lo, Th, Tv, Tcalc, Tload, Hd, posi`.
pub const NF: usize = 14;

/// Une travee resolue.
#[derive(Clone, Copy, Debug)]
pub struct SpanRow {
    pub v: [f64; NF],
}

impl SpanRow {
    /// Index (pixel) du support aval de la travee.
    pub fn posi(&self) -> usize {
        self.v[13] as usize
    }
    /// Hauteur de fixation au support aval (m).
    pub fn hd(&self) -> f64 {
        self.v[12]
    }
    /// Tension retenue par `find_lomin` -- c'est elle que Sylvaccess reporte en
    /// plafond (`newTmax`) sur la travee suivante de la recherche en faisceau.
    pub fn tcalc(&self) -> f64 {
        self.v[10]
    }
    /// Longueur diagonale de la travee (m).
    pub fn diag(&self) -> f64 {
        self.v[2]
    }
    /// Pente de la travee (rad).
    pub fn slope(&self) -> f64 {
        self.v[3]
    }
}

fn span_row(r: &SpanResult, hd: f64, posi: usize, q1: f64) -> SpanRow {
    let tload = (r.th * r.th + (r.tv - r.f - r.lo * G * q1).powi(2)).sqrt();
    SpanRow {
        v: [
            r.d, r.h, r.diag, r.slope, r.fact, r.xup, r.zup, r.lo, r.th, r.tv, r.tcalc, tload, hd,
            posi as f64,
        ],
    }
}

/// Parametres constants d'une optimisation de ligne.
#[allow(clippy::too_many_arguments)]
pub struct OptParams<'a> {
    pub line_x: &'a [f64], // distance horizontale au depart, par pixel (m)
    pub line_z: &'a [f64], // altitude du terrain, par pixel (m)
    pub alts: &'a [f64],   // altitude du terrain au demi-metre (m)
    pub htower: f64,       // hauteur du mat de depart (m)
    pub hintsup: f64,      // hauteur de fixation sur support intermediaire (m)
    pub hend: f64,         // hauteur du support terminal (m)
    pub hline_min: f64,
    pub hline_max: f64,
    pub slope_min: f64,
    pub slope_max: f64,
    pub f_o: f64,
    pub tmax: f64,
    pub q1: f64,
    pub q2: f64,
    pub q3: f64,
    pub eao: f64,
    pub csize: f64, // pas de balayage de la charge (m) = taille de cellule
    pub angle_intsup: f64,
    pub sup_max: usize,
    pub lmin_span: f64, // distance minimale entre deux supports (m)
    pub nbconfig: usize,
}

impl OptParams<'_> {
    #[allow(clippy::too_many_arguments)]
    fn essai(
        &self,
        pg: usize,
        posi: usize,
        hg: f64,
        hd: f64,
        tmax: f64,
        dsupdep: f64,
        slope_prev: f64,
    ) -> SpanResult {
        test_span(
            self.line_x,
            self.line_z,
            pg as i64,
            posi as i64,
            hg,
            hd,
            self.hline_min,
            self.hline_max,
            self.slope_min,
            self.slope_max,
            self.alts,
            self.f_o,
            tmax,
            self.q1,
            self.q2,
            self.q3,
            self.eao,
            self.csize,
            self.angle_intsup,
            dsupdep,
            slope_prev,
        )
    }
}

/// Selection en faisceau (`get_Tabis`) : retient jusqu'a `nbconfig` configurations,
/// par positions de support aval decroissantes -- la plus lointaine d'abord.
///
/// Le parcours de Sylvaccess est reproduit tel quel, y compris sa **dependance a
/// l'ordre d'entree**. `idline` ne bouge que si la hauteur passe *strictement* sous le
/// minimum courant (`Tab[j,colH] < Hmin`) ; or dans la variante `_NoH` toutes les
/// hauteurs valent `hintsup`. Tant que `tab` arrive trie par position decroissante --
/// ce qui est le cas au premier niveau, ou un seul prefixe alimente la table --, la
/// selection est correcte. Aux niveaux suivants, plusieurs prefixes concatenent chacun
/// leur suite decroissante : la table n'est plus globalement triee, et la selection
/// peut alors retenir deux fois la meme configuration. C'est un defaut de la source,
/// pas du portage ; on le conserve, et l'on deduplique en sortie -- ce qui ne change
/// aucun resultat, et evite d'explorer plusieurs fois le meme prefixe.
fn get_tabis(tab: &[Vec<SpanRow>], nbconfig: usize, indmax: usize) -> Vec<Vec<SpanRow>> {
    let linemax = tab.len().min(nbconfig);
    let mut out = Vec::with_capacity(linemax);
    let mut idmax2 = (indmax + 1) as f64;

    for _ in 0..linemax {
        let mut idmax = 0.0f64;
        let mut hmin = 100.0f64;
        let mut idline = 0usize;
        for (j, cfg) in tab.iter().enumerate() {
            let last = cfg.last().expect("configuration vide");
            let posi = last.v[13];
            if posi >= idmax && posi < idmax2 {
                idmax = posi.ceil();
                if last.hd() < hmin {
                    hmin = last.hd();
                    idline = j;
                }
            }
        }
        out.push(tab[idline].clone());
        idmax2 = idmax;
    }
    out
}

// Retire les configurations en double (memes positions de support). Pure economie :
// `get_tabis` en rend `nbconfig` copies identiques des que les hauteurs sont uniformes.
fn dedupe(faisceau: Vec<Vec<SpanRow>>) -> Vec<Vec<SpanRow>> {
    let mut vues: Vec<Vec<usize>> = Vec::new();
    let mut out = Vec::new();
    for cfg in faisceau {
        let cle: Vec<usize> = cfg.iter().map(|s| s.posi()).collect();
        if !vues.contains(&cle) {
            vues.push(cle);
            out.push(cfg);
        }
    }
    out
}

// Premier index dont la distance a `depuis` atteint le pas minimal entre supports.
// `None` si le profil est trop court.
fn premier_index_valide(line_x: &[f64], depuis: usize, seuil: f64) -> Option<usize> {
    let mut i = depuis;
    loop {
        i += 1;
        if i >= line_x.len() {
            return None;
        }
        if line_x[i] - line_x[depuis] >= seuil {
            return Some(i);
        }
    }
}

/// Optimise le placement des supports d'une ligne « machine en haut », hauteurs de
/// fixation fixes (`OptPyl_Up_NoH`).
///
/// Rend les travees de la ligne retenue, du mat vers l'aval. Vide si aucune ligne
/// n'est faisable. La derniere travee porte l'index du terminus : c'est lui qui donne
/// la longueur effective de la ligne, eventuellement **coupee** en deca du profil.
pub fn optpyl_up_noh(p: &OptParams) -> Vec<SpanRow> {
    let indmax = p.line_x.len() - 1;
    if indmax == 0 {
        return Vec::new();
    }
    let seuil = p.csize.max(p.lmin_span);

    // --- 1. Sans support intermediaire : la portee directe suffit-elle ? -----
    let r = p.essai(0, indmax, p.htower, p.hend, p.tmax, 0.0, -9999.0);
    if r.test {
        return vec![span_row(&r, p.hend, indmax, p.q1)];
    }

    // --- 2. Aucun support autorise : couper la ligne au plus loin. -----------
    if p.sup_max == 0 {
        let indmin = match premier_index_valide(p.line_x, 0, seuil) {
            Some(i) => i,
            None => return Vec::new(),
        };
        for posi in (indmin..indmax).rev() {
            let r = p.essai(0, posi, p.htower, p.hend, p.tmax, 0.0, -9999.0);
            if r.test {
                return vec![span_row(&r, p.hend, posi, p.q1)];
            }
        }
        return Vec::new();
    }

    // --- 3. Recherche en faisceau du placement des supports. -----------------
    // Dernier index respectant le pas minimal avant le terminus.
    let mut indmaxmulti = indmax;
    let mut diff = 0.0;
    while diff < seuil && indmaxmulti > 0 {
        indmaxmulti -= 1;
        diff = p.line_x[indmax] - p.line_x[indmaxmulti];
    }
    if indmaxmulti == 0 {
        return Vec::new(); // la ligne est trop courte pour porter un support
    }

    // Configurations partielles du niveau courant. La configuration vide est le
    // point de depart : le mat seul.
    let mut faisceau: Vec<Vec<SpanRow>> = vec![Vec::new()];
    let mut intsup = 1usize;

    while intsup <= p.sup_max {
        let mut niveau: Vec<Vec<SpanRow>> = Vec::new();

        for prefixe in &faisceau {
            // Etat porte par la configuration partielle.
            let (pg, hg, tmax_c, dsupdep, slope_prev, indmin) = match prefixe.last() {
                None => (0usize, p.htower, p.tmax, 0.0, -9999.0, 0usize),
                Some(last) => {
                    let pg = last.posi();
                    let dsup: f64 = prefixe.iter().map(|s| s.diag()).sum();
                    (pg, last.hd(), last.tcalc(), dsup, last.slope(), pg)
                }
            };

            for posi in ((indmin + 1)..=indmaxmulti).rev() {
                let r1 = p.essai(pg, posi, hg, p.hintsup, tmax_c, dsupdep, slope_prev);
                if !r1.test {
                    continue;
                }
                // Tension transmise a la travee suivante : au support aval, sans la
                // charge (les autres travees, elles, la portent a leur tour).
                let tdown = (r1.th * r1.th + (r1.tv - p.q1 * G * r1.lo).powi(2)).sqrt();

                let mut cfg = prefixe.clone();
                cfg.push(span_row(&r1, p.hintsup, posi, p.q1));
                niveau.push(cfg.clone());

                // La derniere travee rejoint-elle le terminus ?
                let r2 = p.essai(
                    posi,
                    indmax,
                    p.hintsup,
                    p.hend,
                    tdown,
                    r1.diag + dsupdep,
                    r1.slope,
                );
                if r2.test {
                    cfg.push(span_row(&r2, p.hend, indmax, p.q1));
                    return cfg;
                }
            }
        }

        if niveau.is_empty() {
            // Plus rien ne passe : on garde la meilleure configuration partielle.
            return faisceau.into_iter().next().unwrap_or_default();
        }
        faisceau = dedupe(get_tabis(&niveau, p.nbconfig, indmax));
        intsup += 1;
    }

    // --- 4. Aucune configuration ne rejoint le terminus : couper la ligne. ---
    let mut candidats: Vec<Vec<SpanRow>> = Vec::new();
    for prefixe in &faisceau {
        let last = match prefixe.last() {
            Some(l) => l,
            None => continue,
        };
        let pg = last.posi();
        let hg = last.hd();
        let tmax_c = last.tcalc();
        let dsupdep: f64 = prefixe.iter().map(|s| s.diag()).sum();
        let slope_prev = last.slope();
        let indmin = match premier_index_valide(p.line_x, pg, seuil) {
            Some(i) => i,
            None => continue,
        };
        for posi in (indmin..indmax).rev() {
            // Le terminus devient `posi` : il porte donc la hauteur terminale.
            let r = p.essai(pg, posi, hg, p.hend, tmax_c, dsupdep, slope_prev);
            if r.test {
                let mut cfg = prefixe.clone();
                cfg.push(span_row(&r, p.hend, posi, p.q1));
                candidats.push(cfg);
                break;
            }
        }
    }
    if candidats.is_empty() {
        return faisceau.into_iter().next().unwrap_or_default();
    }
    get_tabis(&candidats, 1, indmax)
        .into_iter()
        .next()
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(posi: usize, hd: f64) -> SpanRow {
        let mut v = [0.0; NF];
        v[12] = hd;
        v[13] = posi as f64;
        SpanRow { v }
    }

    // Entree triee (un seul prefixe alimente la table) : selection correcte, de la
    // position la plus lointaine a la plus proche.
    #[test]
    fn get_tabis_retient_les_positions_les_plus_lointaines_dabord() {
        let tab = vec![vec![row(30, 12.0)], vec![row(20, 12.0)], vec![row(10, 12.0)]];
        let out = get_tabis(&tab, 3, 40);
        let posis: Vec<usize> = out.iter().map(|c| c.last().unwrap().posi()).collect();
        assert_eq!(posis, vec![30, 20, 10]);
    }

    // Entree NON triee (plusieurs prefixes concatenent leurs suites) : `idline` reste
    // bloque sur la premiere ligne, faute d'une hauteur strictement plus basse. La
    // meme configuration ressort alors plusieurs fois. Defaut de la source, fige ici
    // parce que c'est lui que l'oracle mesure ; `dedupe` en absorbe le cout.
    #[test]
    fn get_tabis_repete_une_configuration_sur_une_entree_non_triee() {
        let tab = vec![vec![row(10, 12.0)], vec![row(30, 12.0)], vec![row(20, 12.0)]];
        let out = get_tabis(&tab, 3, 40);
        let posis: Vec<usize> = out.iter().map(|c| c.last().unwrap().posi()).collect();
        assert_eq!(posis, vec![10, 10, 10]);
        assert_eq!(dedupe(out).len(), 1);
    }

    #[test]
    fn get_tabis_departage_par_la_hauteur_minimale() {
        let tab = vec![vec![row(30, 12.0)], vec![row(30, 8.0)]];
        let out = get_tabis(&tab, 1, 40);
        assert_eq!(out.len(), 1);
        assert!((out[0].last().unwrap().hd() - 8.0).abs() < 1e-9);
    }

    #[test]
    fn get_tabis_plafonne_a_nbconfig() {
        let tab: Vec<Vec<SpanRow>> = (1..=20).rev().map(|i| vec![row(i, 12.0)]).collect();
        assert_eq!(get_tabis(&tab, 5, 40).len(), 5);
    }

    #[test]
    fn premier_index_respecte_le_pas_minimal() {
        let x: Vec<f64> = (0..20).map(|i| i as f64 * 5.0).collect();
        assert_eq!(premier_index_valide(&x, 0, 50.0), Some(10));
        assert_eq!(premier_index_valide(&x, 15, 50.0), None);
    }
}
