# Oracles de non-regression RVT_py (spec 021, J3). Documentaire / reproductible
# -- PAS execute en CI (dependance Python). Deux fixtures :
#   * tests/testthat/fixtures/rvt_oracle.rds : MNT synthetique + SVF / openness
#     (+/-) de RVT_py, contre lesquels le crate rvt_svf_opns() est valide pixel a
#     pixel (test-micro-relief.R). Ecart ~2e-6 (SVF), ~2e-4 deg (openness).
#   * tests/testthat/fixtures/vat_oracle.rds : 4 canaux synthetiques + le VAT
#     ("VAT - Archaeological") calcule par le fold de rvt.blend, contre lequel
#     blend_rvt() est valide (test-vat-archeo.R).
#
#   Rscript data-raw/oracle_rvt.R
#
# Prerequis : python3 + numpy (+ matplotlib pour rvt.blend_func), et le source
# RVT_py (Apache 2.0) :  git clone https://github.com/EarthObservation/RVT_py
# Section SVF : on n'importe PAS rvt.vis en entier (il tire scipy) ; seules
# horizon_shift_vector, sky_view_factor_compute et sky_view_factor (numpy pur)
# sont extraites. TRANSLITTERE au mot pres dans src/rust/src/rvt/mod.rs.
# Section VAT : on IMPORTE rvt.blend_func (numpy + matplotlib, pas scipy) et on
# reproduit le fold exact de BlenderCombination.render_all_images (normalize_image
# -> blend_images -> render_images, du bas vers le haut). REPRODUIT au mot pres
# dans R/vat_archeo.R (y compris la neutralisation d'opacite d'Overlay).

# --- 1. Genere l'oracle via RVT_py (numpy seul) ------------------------------
# Adapter RVT_SRC au clone local de RVT_py.
rvt_src <- Sys.getenv("RVT_PY_SRC", "~/dev/RVT_py/rvt/vis.py")
py <- "
import numpy as np, re, sys
src = open(sys.argv[1]).read()
# Extraire les 3 fonctions numpy-pures (entre 'def horizon_shift_vector' et la
# fonction suivante non necessaire) et les executer dans un namespace numpy.
def grab(name):
    m = re.search(r'\\ndef '+name+r'\\(.*?\\n(?=def |\\Z)', src, re.S)
    return m.group(0)
ns = {'np': np}
for fn in ['horizon_shift_vector','sky_view_factor_compute','sky_view_factor']:
    exec(grab(fn), ns)
sky_view_factor = ns['sky_view_factor']
yy, xx = np.mgrid[0:24, 0:20].astype(np.float64)
dem = 100.0 + 0.3*xx - 0.2*yy + 5.0*np.sin(xx/3.0)*np.cos(yy/4.0)
dem[10:13, 8:11] -= 6.0
d  = sky_view_factor(dem.astype(np.float32), 1.0, compute_svf=True, compute_opns=True,
                     svf_n_dir=16, svf_r_max=8, svf_noise=0)
dn = sky_view_factor((-dem).astype(np.float32), 1.0, compute_svf=False, compute_opns=True,
                     svf_n_dir=16, svf_r_max=8)
np.savetxt(sys.argv[2]+'/or_dem.txt', dem.ravel())
np.savetxt(sys.argv[2]+'/or_svf.txt', d['svf'].ravel())
np.savetxt(sys.argv[2]+'/or_opns.txt', d['opns'].ravel())
np.savetxt(sys.argv[2]+'/or_opns_neg.txt', dn['opns'].ravel())
"
tmp <- tempfile("rvt_oracle_")
dir.create(tmp)
pyf <- file.path(tmp, "gen.py")
writeLines(py, pyf)
status <- system2("python3", c(pyf, path.expand(rvt_src), tmp))
if (status != 0) stop("RVT_py oracle generation failed (verifier numpy + RVT_PY_SRC)")

# --- 2. Gele la fixture ------------------------------------------------------
oracle <- list(
  dem      = scan(file.path(tmp, "or_dem.txt"), quiet = TRUE),
  svf      = scan(file.path(tmp, "or_svf.txt"), quiet = TRUE),
  opns     = scan(file.path(tmp, "or_opns.txt"), quiet = TRUE),
  opns_neg = scan(file.path(tmp, "or_opns_neg.txt"), quiet = TRUE),
  nr = 24L, nc = 20L, resolution = 1.0, radius_max_px = 8L,
  radius_min_px = 1L, num_directions = 16L
)
saveRDS(oracle, "tests/testthat/fixtures/rvt_oracle.rds", version = 2)
cat(sprintf("Fixture RVT ecrite : %d cellules.\n", length(oracle$dem)))

# --- 3. Verifie l'accord (optionnel, si le paquet est charge) ----------------
if (requireNamespace("pkgload", quietly = TRUE)) {
  pkgload::load_all(quiet = TRUE)
  r <- rvt_svf_opns(oracle$dem, oracle$nr, oracle$nc, oracle$resolution,
                    oracle$radius_max_px, oracle$radius_min_px,
                    oracle$num_directions, TRUE, TRUE)
  cat(sprintf("Accord SVF  : max|delta| = %.2e\n", max(abs(r$svf - oracle$svf))))
  cat(sprintf("Accord OPNS : max|delta| = %.2e deg\n", max(abs(r$opns - oracle$opns))))
}

# --- 4. Oracle VAT : fold de la fusion RVT (rvt.blend) -----------------------
# On importe rvt.blend_func et on reproduit render_all_images() : pour la couche
# du bas (Hillshade) rendered = norm ; pour chaque couche au-dessus, top =
# blend_images(mode, active=norm, background=rendered) puis rendered =
# render_images(top, rendered, opacity). Les canaux sont SYNTHETIQUES (l'oracle
# valide la fusion, pas la derivation des canaux -- deja couverte par SVF et par
# terra). Racine du clone RVT_py = parent du dossier rvt/ (deduit de RVT_PY_SRC).
rvt_root <- dirname(dirname(path.expand(rvt_src)))
py_vat <- sprintf("
import numpy as np, sys
sys.path.insert(0, %s)
import rvt.blend_func as bf
ny, nx = 24, 20
yy, xx = np.mgrid[0:ny, 0:nx].astype(np.float64)
# Canaux dans leurs unites brutes, avec de la variete de part et d'autre des
# seuils de normalisation (l'overlay branche a bg=0.5, le soft_light a top=0.5).
svf   = 0.60 + 0.40 * (xx / (nx - 1))                       # 0.60 .. 1.00
opns  = 60.0 + 35.0 * (yy / (ny - 1))                       # 60 .. 95 deg
slope = 60.0 * (0.5 + 0.5 * np.sin(xx / 3.0) * np.cos(yy / 4.0))  # ~0 .. 60 deg
hs    = 0.20 + 0.60 * (1.0 - yy / (ny - 1))                 # 0.20 .. 0.80
# Pile HAUT -> BAS du preset settings/blender_VAT.json ('VAT - Archaeological').
layers = [
    ('Sky-View Factor',      svf,   0.7, 1.0, 'multiply',   25),
    ('Openness - Positive',  opns,  68,  93,  'overlay',    50),
    ('Slope gradient',       slope, 0,   50,  'luminosity', 50),
    ('Hillshade',            hs,    0,   1,   'normal',     100),
]
rendered = None
for (vis, img, mn, mx, mode, op) in reversed(layers):
    norm = bf.normalize_image(vis, np.float32(img.copy()), mn, mx, 'value')
    if rendered is None:
        rendered = norm
    else:
        top = bf.blend_images(mode, norm, rendered)  # peut muter rendered (overlay)
        rendered = bf.render_images(top, rendered, op)
out = sys.argv[1]
np.savetxt(out + '/vat_svf.txt',   svf.ravel())
np.savetxt(out + '/vat_opns.txt',  opns.ravel())
np.savetxt(out + '/vat_slope.txt', slope.ravel())
np.savetxt(out + '/vat_hs.txt',    hs.ravel())
np.savetxt(out + '/vat_out.txt',   np.asarray(rendered).ravel())
", shQuote(paste0("r'", rvt_root, "'")))
tmp2 <- tempfile("vat_oracle_")
dir.create(tmp2)
pyf2 <- file.path(tmp2, "gen_vat.py")
writeLines(py_vat, pyf2)
status2 <- system2("python3", c(pyf2, tmp2))
if (status2 != 0) stop("RVT_py VAT oracle failed (verifier numpy+matplotlib, RVT_PY_SRC)")

vat_oracle <- list(
  svf          = scan(file.path(tmp2, "vat_svf.txt"), quiet = TRUE),
  openness_pos = scan(file.path(tmp2, "vat_opns.txt"), quiet = TRUE),
  slope        = scan(file.path(tmp2, "vat_slope.txt"), quiet = TRUE),
  hillshade    = scan(file.path(tmp2, "vat_hs.txt"), quiet = TRUE),
  vat          = scan(file.path(tmp2, "vat_out.txt"), quiet = TRUE),
  nr = 24L, nc = 20L
)
saveRDS(vat_oracle, "tests/testthat/fixtures/vat_oracle.rds", version = 2)
cat(sprintf("Fixture VAT ecrite : %d cellules.\n", length(vat_oracle$vat)))

if (requireNamespace("pkgload", quietly = TRUE)) {
  tmpl <- terra::rast(nrows = 24L, ncols = 20L, xmin = 0, xmax = 20, ymin = 0, ymax = 24)
  mk <- function(v) {
    rr <- terra::rast(tmpl)
    terra::values(rr) <- v
    rr
  }
  stack <- c(mk(vat_oracle$svf), mk(vat_oracle$openness_pos),
             mk(vat_oracle$slope), mk(vat_oracle$hillshade))
  got <- terra::values(blend_rvt(stack, vat_default_layers()))[, 1]
  cat(sprintf("Accord VAT  : max|delta| = %.2e\n", max(abs(got - vat_oracle$vat))))
}

# --- 5. Oracle CVAT : combinaison par defaut du plugin QGIS RVT --------------
# CVAT = 0.5*VAT_general + 0.5*VAT_flat, puis byte_scale(., 0, 1). On reproduit
# le wrapper CVAT de qrvt.py (presets terrain general/flat de
# default_terrains_settings.json) avec les fonctions numpy-pures du PLUGIN
# rvt-qgis (rvt/vis.py : slope_aspect, hillshade, byte_scale, sky_view_factor ;
# rvt/blend_func.py : normalize_image, blend_images, render_images). vis.py tire
# scipy en tete -> on EXTRAIT seulement les fonctions pures (comme la section 1).
# Cloner le plugin :  git clone https://github.com/EarthObservation/rvt-qgis
# et pointer RVT_QGIS_SRC vers sa racine (dossier contenant rvt/).
rvt_qgis <- path.expand(Sys.getenv("RVT_QGIS_SRC", "~/dev/rvt-qgis"))
py_cvat <- sprintf("
import numpy as np, re, sys
root = %s
bf = {}
exec(open(root + '/rvt/blend_func.py').read(), bf)     # numpy + matplotlib : ok
vsrc = open(root + '/rvt/vis.py').read()
vis = {'np': np}
def grab(name):
    m = re.search(r'\\ndef ' + name + r'\\(.*?\\n(?=def |\\Z)', vsrc, re.S)
    return m.group(0)
for fn in ['roll_fill_nans','slope_aspect','hillshade','byte_scale',
           'horizon_shift_vector','sky_view_factor_compute','sky_view_factor']:
    exec(grab(fn), vis)
ny, nx = 40, 32
yy, xx = np.mgrid[0:ny, 0:nx].astype(np.float64)
dem = (100.0 + 0.35*xx - 0.15*yy + 6.0*np.sin(xx/4.0)*np.cos(yy/5.0) + 2.5*np.sin(xx/2.0))
dem[18:23, 12:17] -= 5.0
dem = dem.astype(np.float32); res = 1.0
def vat(dem, res, r_max, noise, svf_rng, opns_rng, slp_max, sun_el):
    d = vis['sky_view_factor'](dem, res, compute_svf=True, compute_opns=True,
                               compute_asvf=False, svf_n_dir=16, svf_r_max=r_max, svf_noise=noise)
    slope = vis['slope_aspect'](dem=dem, resolution_x=res, resolution_y=res, output_units='degree')['slope']
    hs = vis['hillshade'](dem=dem, resolution_x=res, resolution_y=res, sun_azimuth=315, sun_elevation=sun_el)
    layers = [('Sky-View Factor', d['svf'], svf_rng[0], svf_rng[1], 'multiply', 25),
              ('Openness - Positive', d['opns'], opns_rng[0], opns_rng[1], 'overlay', 50),
              ('Slope gradient', slope, 0, slp_max, 'luminosity', 50),
              ('Hillshade', hs, 0, 1, 'normal', 100)]
    rendered = None
    for (v, img, mn, mx, mode, op) in reversed(layers):
        norm = bf['normalize_image'](v, np.float32(np.array(img, copy=True)), mn, mx, 'value')
        if rendered is None: rendered = norm
        else:
            top = bf['blend_images'](mode, norm, rendered)
            rendered = bf['render_images'](top, rendered, op)
    return np.asarray(rendered, dtype=np.float32)
g = vat(dem, res, 10, 0, (0.7,1.0), (68,93), 50, 35)
f = vat(dem, res, 20, 3, (0.9,1.0), (85,93), 15, 15)
cvat = np.float32(0.5*g + 0.5*f)
cvat8 = vis['byte_scale'](np.array(cvat, copy=True), c_min=0, c_max=1)
out = sys.argv[1]
np.savetxt(out + '/cvat_dem.txt', dem.ravel())
np.savetxt(out + '/cvat_float.txt', cvat.ravel())
np.savetxt(out + '/cvat_8bit.txt', np.asarray(cvat8).ravel(), fmt='%d')
", shQuote(paste0("r'", rvt_qgis, "'")))
tmp3 <- tempfile("cvat_oracle_")
dir.create(tmp3)
pyf3 <- file.path(tmp3, "gen_cvat.py")
writeLines(py_cvat, pyf3)
status3 <- system2("python3", c(pyf3, tmp3))
if (status3 != 0) stop("RVT plugin CVAT oracle failed (verifier RVT_QGIS_SRC, numpy+matplotlib)")

cvat_oracle <- list(
  dem   = scan(file.path(tmp3, "cvat_dem.txt"), quiet = TRUE),
  float = scan(file.path(tmp3, "cvat_float.txt"), quiet = TRUE),
  byte  = scan(file.path(tmp3, "cvat_8bit.txt"), quiet = TRUE),
  nr = 40L, nc = 32L, res = 1.0
)
saveRDS(cvat_oracle, "tests/testthat/fixtures/cvat_oracle.rds", version = 2)
cat(sprintf("Fixture CVAT ecrite : %d cellules.\n", length(cvat_oracle$float)))

if (requireNamespace("pkgload", quietly = TRUE)) {
  mnt <- terra::rast(nrows = 40L, ncols = 32L, xmin = 0, xmax = 32, ymin = 0, ymax = 40)
  terra::values(mnt) <- cvat_oracle$dem
  gf <- terra::values(vat_combined(mnt, as_byte = FALSE))[, 1]
  gb <- terra::values(vat_combined(mnt, as_byte = TRUE))[, 1]
  cat(sprintf("Accord CVAT float : max|delta| = %.2e\n", max(abs(gf - cvat_oracle$float))))
  cat(sprintf("Accord CVAT 8bit  : max|delta| = %d\n", as.integer(max(abs(gb - cvat_oracle$byte)))))
}
