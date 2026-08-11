# Epic « conception de desserte » (Lots 14-18, docs/ROADMAP-desserte.md).
# Extension du Lot 14 : le terme de PENTE de la surface de cout, aujourd'hui un
# bareme en escalier, devient un cout de TERRASSEMENT (spec 029).
#
# Le modele de profil en travers -- point de niveau, ripage, talus -- est celui
# de CubaRoad (Dupire, SylvaLab / ONF Pole RDI Chambery, 2021, GPL-3), deja
# reimplemente cote mesure dans dessertR::dsr_cubature(). Formulation propre.
#
# CE QUI REND LE MODELE UTILISABLE DANS UN RASTER. Sur un profil en travers
# PLAN, les sections en deblai et en remblai ont une forme fermee : elles se
# calculent par une expression algebrique sur la pente, sans echantillonner de
# transect. Un portage du moteur par profil, lui, demanderait un transect par
# cellule et serait hors de portee a l'echelle d'un massif.

#' Earthwork cost of one metre of forest road
#'
#' Cost, in euros per metre of road, of the cut and fill required to lay a
#' platform of width `largeur_m` across a hillside of transverse slope
#' `pente_pct`. Replaces the step-function slope surcharge of Lot 14 by a
#' continuous, width-aware quantity (spec 029).
#'
#' @details
#' **Forme fermee.** Sur un profil en travers plan de pente `p`, plateforme de
#' largeur `L` posee au niveau du terrain sous l'axe, talus amont `A` et aval
#' `B`, ripage nul :
#'
#' \deqn{S_{deblai} = p L^2/8 + \frac{1}{2}\frac{(pL/2)^2}{A - p}}
#' \deqn{S_{remblai} = p L^2/8 + \frac{1}{2}\frac{(pL/2)^2}{B - p}}
#'
#' C'est l'oracle analytique des tests de cubature de `dessertR`. Les sections
#' sont en m2, donc en **m3 par metre lineaire** de route.
#'
#' **Ripage.** Le partage deblai / remblai n'est pas fixe : au-dela d'un devers,
#' le remblai ne tient pas. Le ripage ne transfere pas un VOLUME, il deplace la
#' **plateforme** -- une part croissante de sa largeur est creusee plutot que
#' remblayee, comme `assise_deblai` / `assise_remblai` dans
#' [dessertR::dsr_cubature()]. Les sections se recalculent alors sur des
#' demi-largeurs asymetriques `a = L/2 (1 + r)` et `b = L/2 (1 - r)` ; a ripage
#' nul on retrouve la forme fermee ci-dessus.
#'
#' La distinction n'est pas theorique : transferer la section de remblai vers le
#' deblai transfererait une quantite qui **diverge** quand le terrain approche la
#' pente du talus aval, alors que cette configuration est justement celle ou il
#' n'y a plus de remblai du tout.
#'
#' Le deblai se reemploie sur place a hauteur du remblai ; l'excedent part en
#' evacuation, et c'est ce **transport** qui coute, pas le deblai lui-meme.
#'
#' **La pente transversale n'est pas la pente du terrain** -- elle en depend par
#' l'azimut de la route, qu'un cout pre-calcule par cellule ignore. On pose
#' `p_transversale = p_terrain`, c'est-a-dire une route qui suit la courbe de
#' niveau. C'est le cas dominant en desserte de versant, ou la pente en long est
#' bornee a 12 % quand le versant en fait 30 a 60 %, et c'est **majorant** :
#' toute route qui s'en ecarte terrasse moins. Voir spec 029 section 5.
#'
#' @param pente_pct Terrain slope in percent: a `SpatRaster` or a numeric vector.
#' @param largeur_m Target platform width, in metres.
#' @param config A `foretaccess_config`; prices live in
#'   `config$desserte$cout$terrassement`.
#' @return Same shape as `pente_pct` (a `SpatRaster` or a numeric vector), in
#'   euros per metre of road. `NA` where the slope makes construction
#'   impossible -- when the terrain is at least as steep as a cut or fill slope,
#'   the batter never meets the ground again and no finite volume exists.
#' @seealso [surface_cout_construction()], `vignette` spec 029.
#' @examples
#' # Terrain plat : rien a terrasser.
#' cout_terrassement(0, largeur_m = 4)
#' # Versant a 30 % : le cout croit avec le carre de la largeur.
#' cout_terrassement(30, largeur_m = 3)
#' cout_terrassement(30, largeur_m = 6)
#' @export
cout_terrassement <- function(pente_pct, largeur_m,
                              config = foretaccess_config()) {
  te <- config$desserte$cout$terrassement
  if (is.null(te)) {
    stop("`config$desserte$cout$terrassement` est absent : voir foretaccess_config().",
         call. = FALSE)
  }
  checkmate::assert_number(largeur_m, lower = 0, finite = TRUE)

  if (inherits(pente_pct, "SpatRaster")) {
    return(terra::app(pente_pct, function(v)
      .cout_terrassement_num(v, largeur_m, te)))
  }
  .cout_terrassement_num(pente_pct, largeur_m, te)
}


# Coeur numerique : vectorise sur la pente, sans dependance a terra.
#' @noRd
.cout_terrassement_num <- function(pente_pct, largeur_m, te) {
  p <- as.numeric(pente_pct) / 100          # % -> pente (1 = 100 %)
  L <- largeur_m
  A <- te$talus_deblai
  B <- te$talus_remblai

  # Le talus doit etre plus raide que le terrain, sinon il ne le recoupe jamais
  # et le volume diverge. C'est une impossibilite de construction, pas un cout
  # eleve : on rend NA plutot qu'un nombre astronomique qui se propagerait dans
  # le solveur comme un chemin merveilleusement evitable.
  r0 <- pmin(pmax((p - te$ripage_min) / (te$ripage_max - te$ripage_min), 0), 1)
  hors <- !is.finite(p) | p < 0 | p >= A | (r0 < 1 & p >= B)

  # ASSIETTE ASYMETRIQUE. Le ripage ne transfere pas un VOLUME du remblai vers
  # le deblai -- ce serait transferer une quantite qui diverge quand le terrain
  # approche la pente du talus aval. Il deplace la PLATEFORME : une part
  # croissante de sa largeur est creusee plutot que remblayee, exactement comme
  # `assise_deblai` / `assise_remblai` dans dessertR::dsr_cubature().
  r <- (p - te$ripage_min) / (te$ripage_max - te$ripage_min)
  r <- pmin(pmax(r, 0), 1)
  a <- L / 2 * (1 + r)   # demi-largeur creusee
  b <- L / 2 * (1 - r)   # demi-largeur remblayee ; nulle a ripage plein

  # Sur chaque cote : le coin sous la demi-plateforme (p * cote^2 / 2), puis le
  # talus qui resorbe le denivele p * cote au taux (talus - p). A ripage nul,
  # a = b = L/2 et l'on retrouve p*L^2/8 + (1/2)(pL/2)^2/(A-p), la forme fermee
  # qui sert d'oracle aux tests de cubature de dessertR.
  s_deblai <- p * a^2 / 2 + 0.5 * (p * a)^2 / (A - p)
  s_remblai <- ifelse(b > 0, p * b^2 / 2 + 0.5 * (p * b)^2 / (B - p), 0)

  # Le deblai se reemploie en remblai sur place a hauteur du plus petit des
  # deux ; l'excedent part en evacuation, et c'est ce transport qui coute.
  s_evacue <- pmax(s_deblai - s_remblai, 0)

  out <- s_deblai * te$prix_deblai_m3 +
    s_remblai * te$prix_remblai_m3 +
    s_evacue * te$prix_evacuation_m3
  out[hors] <- NA_real_
  out
}
