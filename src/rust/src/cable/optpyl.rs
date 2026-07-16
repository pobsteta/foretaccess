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
#[derive(Clone, Copy)]
#[allow(clippy::too_many_arguments)]
pub struct OptParams<'a> {
    pub line_x: &'a [f64], // distance horizontale au depart, par pixel (m)
    pub line_z: &'a [f64], // altitude du terrain, par pixel (m)
    pub alts: &'a [f64],   // altitude du terrain au demi-metre (m)
    // Hauteurs de fixation aux deux extremites. Elles ne disent PAS ou est la machine :
    // « machine en haut » les prend dans l'ordre (mat, ancrage) ; « machine en bas »
    // travaille sur le profil RETOURNE et les prend a l'envers (ancrage, mat). C'est la
    // seule difference entre `OptPyl_Up_NoH` et `OptPyl_Up2_NoH` de Sylvaccess.
    pub h_debut: f64,      // hauteur du support a l'index 0 (m)
    pub h_fin: f64,        // hauteur du support terminal (m)
    pub hintsup: f64,      // hauteur de fixation sur support intermediaire (m)
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
    // La travee suivante herite-t-elle du plafond de tension de la precedente ?
    // `OptPyl_Up_NoH` : oui. `OptPyl_Down_init_NoH` : non -- chaque travee repart de
    // `tmax`. Ce n'est pas une symetrie : c'est ce que fait la source.
    pub heriter_tension: bool,
    // Optimise-t-on la hauteur de fixation (`c_option_h = 1`) ? Faux = variante `_NoH`
    // (hauteur fixe `hintsup`/`h_fin`), le defaut v3.6. Vrai = variantes `OptPyl_Up` /
    // `OptPyl_Down_init` : la hauteur terminale est ABAISSEE tant que la travee tient,
    // et chaque support intermediaire balaye `ceil(hline_min)..hintsup` (premiere
    // faisable). Le mat (`h_debut`) reste fixe.
    pub optim_h: bool,
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

    // Hauteur terminale ABAISSEE : part de `hmax` et descend d'un metre tant que la
    // travee tient (`while Hd>1` de Sylvaccess), garde la plus basse faisable de la
    // plage contigue depuis le haut. `None` si `hmax` lui-meme est infaisable.
    // En `_NoH` : un seul essai a `hmax` (equivalent au comportement fixe).
    #[allow(clippy::too_many_arguments)]
    fn essai_bas(
        &self,
        pg: usize,
        posi: usize,
        hg: f64,
        hmax: f64,
        tmax: f64,
        dsupdep: f64,
        slope_prev: f64,
    ) -> Option<(SpanResult, f64)> {
        if !self.optim_h {
            let r = self.essai(pg, posi, hg, hmax, tmax, dsupdep, slope_prev);
            return if r.test { Some((r, hmax)) } else { None };
        }
        let mut hd = hmax;
        let mut best = None;
        while hd > 1.0 {
            let r = self.essai(pg, posi, hg, hd, tmax, dsupdep, slope_prev);
            if r.test {
                best = Some((r, hd));
            } else {
                break;
            }
            hd -= 1.0;
        }
        best
    }

    // Hauteur MONTANTE : de `hmin` (arrondi au superieur) vers `hmax`, rend la
    // PREMIERE (plus basse) faisable. `None` si aucune ne tient.
    // En `_NoH` : un seul essai a `hmax`.
    #[allow(clippy::too_many_arguments)]
    fn essai_haut(
        &self,
        pg: usize,
        posi: usize,
        hg: f64,
        hmin: f64,
        hmax: f64,
        tmax: f64,
        dsupdep: f64,
        slope_prev: f64,
    ) -> Option<(SpanResult, f64)> {
        if !self.optim_h {
            let r = self.essai(pg, posi, hg, hmax, tmax, dsupdep, slope_prev);
            return if r.test { Some((r, hmax)) } else { None };
        }
        let mut hd = hmin.ceil();
        while hd <= hmax {
            let r = self.essai(pg, posi, hg, hd, tmax, dsupdep, slope_prev);
            if r.test {
                return Some((r, hd));
            }
            hd += 1.0;
        }
        None
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
pub fn optpyl(p: &OptParams) -> Vec<SpanRow> {
    let indmax = p.line_x.len() - 1;
    if indmax == 0 {
        return Vec::new();
    }
    let seuil = p.csize.max(p.lmin_span);

    // --- 1. Sans support intermediaire : la portee directe suffit-elle ? -----
    // Hauteur terminale abaissee (`essai_bas`) si `optim_h`, sinon fixe a `h_fin`.
    if let Some((r, hd)) = p.essai_bas(0, indmax, p.h_debut, p.h_fin, p.tmax, 0.0, -9999.0) {
        return vec![span_row(&r, hd, indmax, p.q1)];
    }

    // --- 2. Aucun support autorise : couper la ligne au plus loin. -----------
    if p.sup_max == 0 {
        let indmin = match premier_index_valide(p.line_x, 0, seuil) {
            Some(i) => i,
            None => return Vec::new(),
        };
        for posi in (indmin..indmax).rev() {
            if let Some((r, hd)) = p.essai_bas(0, posi, p.h_debut, p.h_fin, p.tmax, 0.0, -9999.0) {
                return vec![span_row(&r, hd, posi, p.q1)];
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
                None => (0usize, p.h_debut, p.tmax, 0.0, -9999.0, 0usize),
                Some(last) => {
                    let pg = last.posi();
                    let dsup: f64 = prefixe.iter().map(|s| s.diag()).sum();
                    let t = if p.heriter_tension { last.tcalc() } else { p.tmax };
                    (pg, last.hd(), t, dsup, last.slope(), pg)
                }
            };

            // Bornes du balayage de hauteur du support intermediaire. En `_NoH` :
            // hauteur fixe `hintsup` (un seul essai). En `optim_h` : de `ceil(hline_min)`
            // a `hintsup` (= `Line[posi,7]`, uniforme a `test_hfor=0`), premiere faisable
            // -- mais chaque hauteur faisable AJOUTE une configuration au faisceau (une
            // meme position peut ainsi generer plusieurs candidats de hauteurs distinctes).
            let (hmin_near, hmax_near) = if p.optim_h {
                (p.hline_min.ceil(), p.hintsup)
            } else {
                (p.hintsup, p.hintsup)
            };

            for posi in ((indmin + 1)..=indmaxmulti).rev() {
                let mut hd = hmin_near;
                while hd <= hmax_near {
                    let r1 = p.essai(pg, posi, hg, hd, tmax_c, dsupdep, slope_prev);
                    if r1.test {
                        // Tension transmise a la travee suivante : au support aval, sans
                        // la charge (les autres travees, elles, la portent a leur tour).
                        let tdown = (r1.th * r1.th + (r1.tv - p.q1 * G * r1.lo).powi(2)).sqrt();

                        let mut cfg = prefixe.clone();
                        cfg.push(span_row(&r1, hd, posi, p.q1));
                        niveau.push(cfg.clone());

                        // La derniere travee rejoint-elle le terminus ? Sa hauteur amont
                        // est `hd` (celle du support), sa hauteur aval balaie `1..h_fin`.
                        let t2 = if p.heriter_tension { tdown } else { p.tmax };
                        if let Some((r2, hd2)) = p.essai_haut(
                            posi,
                            indmax,
                            hd,
                            1.0,
                            p.h_fin,
                            t2,
                            r1.diag + dsupdep,
                            r1.slope,
                        ) {
                            cfg.push(span_row(&r2, hd2, indmax, p.q1));
                            return cfg;
                        }
                    }
                    hd += 1.0;
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
        let tmax_c = if p.heriter_tension { last.tcalc() } else { p.tmax };
        let dsupdep: f64 = prefixe.iter().map(|s| s.diag()).sum();
        let slope_prev = last.slope();
        let indmin = match premier_index_valide(p.line_x, pg, seuil) {
            Some(i) => i,
            None => continue,
        };
        for posi in (indmin..indmax).rev() {
            // Le terminus devient `posi` : il porte la hauteur terminale, balayee
            // `1..h_fin` (premiere faisable) en `optim_h`, fixe a `h_fin` sinon.
            if let Some((r, hd)) =
                p.essai_haut(pg, posi, hg, 1.0, p.h_fin, tmax_c, dsupdep, slope_prev)
            {
                let mut cfg = prefixe.clone();
                cfg.push(span_row(&r, hd, posi, p.q1));
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

/// Retourne un profil bout pour bout : le terminus devient le depart.
///
/// C'est `return_profile` de Sylvaccess. Les distances sont recomptees depuis le
/// nouveau depart (`Dmax - x`), les altitudes suivent. Une ligne « machine en bas »
/// se resout ainsi avec exactement le meme solveur que « machine en haut » -- il
/// suffit de la parcourir a l'envers.
pub fn retourner_profil(line_x: &[f64], line_z: &[f64]) -> (Vec<f64>, Vec<f64>) {
    let n = line_x.len();
    let dmax = line_x[n - 1];
    let x = (0..n).map(|i| dmax - line_x[n - 1 - i]).collect();
    let z = (0..n).map(|i| line_z[n - 1 - i]).collect();
    (x, z)
}

/// Optimise une ligne « machine en bas » sur un profil **deja retourne**
/// (`OptPyl_Down_NoH`).
///
/// Sylvaccess n'accepte ici aucune coupe : soit les supports portent la ligne jusqu'au
/// mat, soit il **raccourcit la ligne par le haut** (`Line = Line[1:]`, cote ancrage,
/// qui est le debut du profil retourne) et recommence. La machine est en bas : c'est
/// elle qui fixe le terminus, on ne peut pas rogner de son cote.
///
/// Rend les travees et le nombre de pixels rognes en tete -- soustraire ce nombre de
/// l'index du terminus donne la portee dans les indices du profil d'origine.
pub fn optpyl_down_noh(p: &OptParams) -> Option<(Vec<SpanRow>, usize)> {
    let n = p.line_x.len();
    for rogne in 0..n.saturating_sub(1) {
        let q = OptParams {
            line_x: &p.line_x[rogne..],
            line_z: &p.line_z[rogne..],
            ..*p
        };
        // Hauteur optimisee -> `OptPyl_Up2` (balaye l'ancrage) ; sinon `OptPyl_Up_NoH`.
        let spans = if p.optim_h { optpyl_up2(&q) } else { optpyl(&q) };
        if let Some(last) = spans.last() {
            if last.posi() == q.line_x.len() - 1 {
                return Some((spans, rogne));
            }
        }
    }
    None
}

/// **EXPERIMENTAL / non fidele.** Confronte a l'oracle (ColduPre, `c_option_h=true`),
/// ce chemin *reduit* la couverture (net -999 cellules) la ou Sylvaccess l'*augmente*
/// (+470) : un defaut subsiste ici (lignes trop courtes). N'est atteint que via le flag
/// `optim_h` (defaut faux). Conserve pour reprise ; cf. `PLAN.md`.
///
/// Optimise une ligne « machine en bas » AVEC optimisation de la hauteur de fixation
/// (`OptPyl_Up2`). Comme `optpyl`, mais la hauteur BALAYEE est celle du **depart**
/// (l'ancrage, index 0) ; le terminus (le mat) reste fixe a `h_fin`. Le balayage du
/// depart n'a lieu qu'au premier support (au-dela, la hauteur amont = hauteur aval du
/// support precedent). `get_Tabis2` a exactement la meme selection que `get_tabis`
/// (elle ne discrimine que sur `posi` puis une hauteur du dernier support) : on la
/// reutilise. La hauteur d'ancrage n'a pas besoin d'etre stockee -- elle ne sert qu'a
/// la faisabilite, le scan ne lit que l'index terminal.
pub fn optpyl_up2(p: &OptParams) -> Vec<SpanRow> {
    let indmax = p.line_x.len() - 1;
    if indmax == 0 {
        return Vec::new();
    }
    let seuil = p.csize.max(p.lmin_span);

    // --- 1. Sans support : hauteur d'ancrage ABAISSEE, terminus (mat) fixe. ----
    if let Some(r) = essai_depart_bas(p, 0, indmax, p.h_debut, p.h_fin, p.tmax, 0.0, -9999.0) {
        return vec![span_row(&r, p.h_fin, indmax, p.q1)];
    }

    // --- 2. Aucun support : couper, ancrage abaisse par position. -------------
    if p.sup_max == 0 {
        let indmin = match premier_index_valide(p.line_x, 0, seuil) {
            Some(i) => i,
            None => return Vec::new(),
        };
        for posi in (indmin..indmax).rev() {
            if let Some(r) = essai_depart_bas(p, 0, posi, p.h_debut, p.h_fin, p.tmax, 0.0, -9999.0) {
                return vec![span_row(&r, p.h_fin, posi, p.q1)];
            }
        }
        return Vec::new();
    }

    // --- 3. Recherche en faisceau. --------------------------------------------
    let mut indmaxmulti = indmax;
    let mut diff = 0.0;
    while diff < seuil && indmaxmulti > 0 {
        indmaxmulti -= 1;
        diff = p.line_x[indmax] - p.line_x[indmaxmulti];
    }
    if indmaxmulti == 0 {
        return Vec::new();
    }

    let mut faisceau: Vec<Vec<SpanRow>> = vec![Vec::new()];
    let mut intsup = 1usize;
    let hmin_near = p.hline_min.ceil();
    let hmax_near = p.hintsup;

    while intsup <= p.sup_max {
        let mut niveau: Vec<Vec<SpanRow>> = Vec::new();

        for prefixe in &faisceau {
            let (pg, tmax_c, dsupdep, slope_prev, indmin, hg_iter) = match prefixe.last() {
                // Niveau 1 : la hauteur d'ancrage (amont du 1er support) est BALAYEE
                // 1..h_debut. C'est la dimension d'optimisation propre a `OptPyl_Up2`.
                None => {
                    let mut hgs = Vec::new();
                    let mut h = 1.0;
                    while h <= p.h_debut {
                        hgs.push(h);
                        h += 1.0;
                    }
                    (0usize, p.tmax, 0.0, -9999.0, 0usize, hgs)
                }
                Some(last) => {
                    let pg = last.posi();
                    let dsup: f64 = prefixe.iter().map(|s| s.diag()).sum();
                    let t = if p.heriter_tension { last.tcalc() } else { p.tmax };
                    (pg, t, dsup, last.slope(), pg, vec![last.hd()])
                }
            };

            for &hg in &hg_iter {
                for posi in ((indmin + 1)..=indmaxmulti).rev() {
                    let mut hd = hmin_near;
                    while hd <= hmax_near {
                        let r1 = p.essai(pg, posi, hg, hd, tmax_c, dsupdep, slope_prev);
                        if r1.test {
                            let tdown = (r1.th * r1.th + (r1.tv - p.q1 * G * r1.lo).powi(2)).sqrt();
                            let mut cfg = prefixe.clone();
                            cfg.push(span_row(&r1, hd, posi, p.q1));
                            niveau.push(cfg.clone());
                            // Travee lointaine : le terminus (mat) est fixe a `h_fin`.
                            let t2 = if p.heriter_tension { tdown } else { p.tmax };
                            let r2 =
                                p.essai(posi, indmax, hd, p.h_fin, t2, r1.diag + dsupdep, r1.slope);
                            if r2.test {
                                cfg.push(span_row(&r2, p.h_fin, indmax, p.q1));
                                return cfg;
                            }
                        }
                        hd += 1.0;
                    }
                }
            }
        }

        if niveau.is_empty() {
            return faisceau.into_iter().next().unwrap_or_default();
        }
        faisceau = dedupe(get_tabis(&niveau, p.nbconfig, indmax));
        intsup += 1;
    }

    // --- 4. Couper au plus loin (terminus fixe). ------------------------------
    let mut candidats: Vec<Vec<SpanRow>> = Vec::new();
    for prefixe in &faisceau {
        let last = match prefixe.last() {
            Some(l) => l,
            None => continue,
        };
        let pg = last.posi();
        let hg = last.hd();
        let tmax_c = if p.heriter_tension { last.tcalc() } else { p.tmax };
        let dsupdep: f64 = prefixe.iter().map(|s| s.diag()).sum();
        let slope_prev = last.slope();
        let indmin = match premier_index_valide(p.line_x, pg, seuil) {
            Some(i) => i,
            None => continue,
        };
        for posi in (indmin..indmax).rev() {
            let r = p.essai(pg, posi, hg, p.h_fin, tmax_c, dsupdep, slope_prev);
            if r.test {
                let mut cfg = prefixe.clone();
                cfg.push(span_row(&r, p.h_fin, posi, p.q1));
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

// Balaye la hauteur de DEPART (ancrage, index `pg`) vers le bas depuis `hgmax`, terminus
// fixe a `hd`. Garde la plus basse faisable de la plage contigue depuis le haut.
// `None` si `hgmax` deja infaisable. (`OptPyl_Up2` sans support / coupe.)
#[allow(clippy::too_many_arguments)]
fn essai_depart_bas(
    p: &OptParams,
    pg: usize,
    posi: usize,
    hgmax: f64,
    hd: f64,
    tmax: f64,
    dsupdep: f64,
    slope_prev: f64,
) -> Option<SpanResult> {
    let mut hg = hgmax;
    let mut best = None;
    while hg > 1.0 {
        let r = p.essai(pg, posi, hg, hd, tmax, dsupdep, slope_prev);
        if r.test {
            best = Some(r);
        } else {
            break;
        }
        hg -= 1.0;
    }
    best
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

    // ---- Ligne « machine en bas » ----------------------------------------

    #[test]
    fn retourner_profil_inverse_distances_et_altitudes() {
        let x = [0.0, 10.0, 25.0, 40.0];
        let z = [100.0, 130.0, 160.0, 180.0];
        let (rx, rz) = retourner_profil(&x, &z);
        assert_eq!(rx, vec![0.0, 15.0, 30.0, 40.0]);
        assert_eq!(rz, vec![180.0, 160.0, 130.0, 100.0]);
    }

    // Profil « machine en bas » : depart en bas (mat), ancrage en haut. Une fois
    // retourne, il descend de l'ancrage vers le mat -- et la portee directe passe.
    fn params_down<'a>(x: &'a [f64], z: &'a [f64], alts: &'a [f64]) -> OptParams<'a> {
        let ao = 0.25 * std::f64::consts::PI * 18.0_f64.powi(2);
        OptParams {
            line_x: x,
            line_z: z,
            alts,
            h_debut: 5.0,   // ancrage (le profil est retourne)
            h_fin: 9.0,     // mat
            hintsup: 12.0,
            hline_min: 3.5,
            hline_max: 50.0,
            slope_min: -1.4,
            slope_max: 0.1,
            f_o: G * (2500.0 + 400.0),
            tmax: 35000.0 * G / 2.0,
            q1: 1.85,
            q2: 0.9,
            q3: 0.9,
            eao: 160000.0 * ao,
            csize: 5.0,
            angle_intsup: 30.0_f64.to_radians(),
            sup_max: 3,
            lmin_span: 50.0,
            nbconfig: 1,
            heriter_tension: true,
            optim_h: false,
        }
    }

    #[test]
    fn optpyl_down_porte_la_ligne_entiere_sans_rognage() {
        // 150 m de long, 30 m de denivele : le mat de 9 m tient la portee directe.
        let n = 31;
        let x: Vec<f64> = (0..n).map(|i| i as f64 * 5.0).collect();
        let z: Vec<f64> = (0..n).map(|i| 180.0 - i as f64).collect();
        // Meme terrain, au demi-metre : z(x) = 180 - x/5.
        let alts: Vec<f64> = (0..400).map(|k| 180.0 - 0.1 * k as f64).collect();
        let p = params_down(&x, &z, &alts);
        let (spans, rogne) = optpyl_down_noh(&p).expect("ligne faisable attendue");
        assert_eq!(rogne, 0, "aucun pixel ne devrait etre rogne");
        assert_eq!(spans.last().unwrap().posi(), n - 1);
    }

    // Le solveur ne peut pas couper une ligne « machine en bas » du cote machine :
    // s'il n'y arrive pas, il rogne l'**ancrage**. Ici une butte de 11 m barre les 40
    // premiers metres -- le cable y passerait sous le sol -- donc la ligne recule son
    // ancrage jusqu'a franchir l'obstacle, sans jamais deplacer le mat.
    // Avec `optim_h`, la portee directe sans support choisit la hauteur terminale la
    // plus BASSE qui tient encore (abaissement contigu depuis `h_fin`). Sur un profil
    // ou la portee passe deja, `optim_h` doit rendre une hauteur terminale <= `h_fin`.
    #[test]
    fn optim_h_abaisse_la_hauteur_terminale() {
        let n = 31;
        let x: Vec<f64> = (0..n).map(|i| i as f64 * 5.0).collect();
        let z: Vec<f64> = (0..n).map(|i| 180.0 - i as f64).collect();
        let alts: Vec<f64> = (0..400).map(|k| 180.0 - 0.1 * k as f64).collect();

        let noh = params_down(&x, &z, &alts); // optim_h = false
        let s_noh = optpyl(&noh);
        assert!(!s_noh.is_empty(), "ligne NoH faisable attendue");
        // h_fin vaut 9.0 dans params_down : sans optimisation, la hauteur terminale
        // reste 9.0.
        assert!((s_noh.last().unwrap().hd() - 9.0).abs() < 1e-9);

        let hopt = OptParams {
            optim_h: true,
            ..params_down(&x, &z, &alts)
        };
        let s_hopt = optpyl(&hopt);
        assert!(!s_hopt.is_empty(), "ligne h_opt faisable attendue");
        // La hauteur terminale retenue ne peut qu'etre <= celle du NoH (on abaisse).
        assert!(
            s_hopt.last().unwrap().hd() <= s_noh.last().unwrap().hd() + 1e-9,
            "optim_h ne doit pas relever la hauteur terminale"
        );
    }

    #[test]
    fn optpyl_down_rogne_par_lancrage_quand_le_depart_ne_passe_pas() {
        let n = 31;
        let x: Vec<f64> = (0..n).map(|i| i as f64 * 5.0).collect();
        let z: Vec<f64> = (0..n).map(|i| 180.0 - i as f64).collect();
        let alts: Vec<f64> = (0..400)
            .map(|k| 180.0 - 0.1 * k as f64 + if k <= 80 { 11.0 } else { 0.0 })
            .collect();
        let p = params_down(&x, &z, &alts);
        let (spans, rogne) = optpyl_down_noh(&p).expect("ligne faisable apres rognage");
        assert!(rogne > 0, "un rognage etait attendu");
        // Le terminus reste le dernier pixel du profil : la machine ne bouge pas.
        assert_eq!(spans.last().unwrap().posi(), n - 1 - rogne);
    }
}
