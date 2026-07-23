# Oracle de non-regression RVT_py pour le noyau Rust rvt_svf_opns() (spec 021,
# J3). Documentaire / reproductible -- PAS execute en CI (dependance Python).
# Regenere la fixture tests/testthat/fixtures/rvt_oracle.rds : un petit MNT
# synthetique + les SVF / openness (+/-) calcules par RVT_py, contre lesquels le
# crate est valide pixel a pixel (test-micro-relief.R). Ecart mesure au portage :
# ~2e-6 (SVF), ~2e-4 deg (openness) -- purement le float32 interne de RVT.
#
#   Rscript data-raw/oracle_rvt.R
#
# Prerequis : python3 + numpy, et le source RVT_py (Apache 2.0) :
#   git clone https://github.com/EarthObservation/RVT_py
# On n'importe PAS rvt.vis en entier (il tire scipy) : seules horizon_shift_vector,
# sky_view_factor_compute et sky_view_factor (numpy pur) sont extraites dans un
# module autonome. TRANSLITTERE au mot pres dans src/rust/src/rvt/mod.rs.

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
