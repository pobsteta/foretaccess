# Composite VAT (spec RVT). La mecanique de fusion (blend_rvt / .rvt_blend_*)
# est testee en math pure (invariants analytiques : multiply, overlay, opacite,
# ecretage). vat_archeo() est teste bout-en-bout (assemblage des 4 canaux +
# fusion) sur un petit MNT, en s'appuyant sur le noyau Rust micro_relief().

test_that(".rvt_normalize : etirement, ecretage et inversion", {
  x <- c(-1, 0, 5, 10, 11)
  n <- foretaccess:::.rvt_normalize(x, 0, 10)
  expect_equal(n, c(0, 0, 0.5, 1, 1))
  # Inversion : 1 - normalise.
  expect_equal(foretaccess:::.rvt_normalize(x, 0, 10, invert = TRUE), 1 - n)
  # NA propage.
  expect_true(is.na(foretaccess:::.rvt_normalize(NA_real_, 0, 10)))
})

test_that(".rvt_blend_pair : modes de fusion sur niveaux de gris (formules RVT)", {
  top <- c(0.2, 0.8)
  bg <- c(0.3, 0.7) # de part et d'autre de 0.5 pour les branches overlay/soft_light
  expect_equal(foretaccess:::.rvt_blend_pair(top, bg, "normal"), top)
  expect_equal(foretaccess:::.rvt_blend_pair(top, bg, "luminosity"), top)
  expect_equal(foretaccess:::.rvt_blend_pair(top, bg, "multiply"), top * bg)
  expect_equal(foretaccess:::.rvt_blend_pair(top, bg, "screen"), 1 - (1 - top) * (1 - bg))
  # Overlay : branche sur bg (> 0.5). bg=0.3 -> 2*bg*top ; bg=0.7 -> 1-(1-2*(bg-0.5))*(1-top).
  expect_equal(
    foretaccess:::.rvt_blend_pair(top, bg, "overlay"),
    c(2 * 0.3 * 0.2, 1 - (1 - 2 * (0.7 - 0.5)) * (1 - 0.8))
  )
  # Soft light : branche sur top (< 0.5). top=0.2 -> quadratique ; top=0.8 -> racine.
  expect_equal(
    foretaccess:::.rvt_blend_pair(top, bg, "soft_light"),
    c(
      2 * 0.3 * 0.2 + 0.3^2 * (1 - 2 * 0.2),
      2 * 0.7 * (1 - 0.8) + sqrt(0.7) * (2 * 0.8 - 1)
    )
  )
  expect_error(foretaccess:::.rvt_blend_pair(top, bg, "bidon"), "inconnu")
})

test_that(".rvt_blend_stack : overlay neutralise l'opacite (quirk RVT), pas multiply", {
  m <- cbind(rep(0.9, 3), rep(0.4, 3))
  base <- list(min = 0, max = 1, invert = FALSE, mode = "normal", opacity = 1)
  # Overlay a 50 % == overlay a 100 % (background mute en place chez RVT).
  ov50 <- list(min = 0, max = 1, invert = FALSE, mode = "overlay", opacity = 0.5)
  ov100 <- list(min = 0, max = 1, invert = FALSE, mode = "overlay", opacity = 1)
  r50 <- foretaccess:::.rvt_blend_stack(m, list(ov50, base))
  r100 <- foretaccess:::.rvt_blend_stack(m, list(ov100, base))
  expect_equal(r50, r100)
  # Multiply, lui, DOIT doser : 25 % != 100 %.
  mu25 <- list(min = 0, max = 1, invert = FALSE, mode = "multiply", opacity = 0.25)
  mu100 <- list(min = 0, max = 1, invert = FALSE, mode = "multiply", opacity = 1)
  expect_false(isTRUE(all.equal(
    foretaccess:::.rvt_blend_stack(m, list(mu25, base)),
    foretaccess:::.rvt_blend_stack(m, list(mu100, base))
  )))
})

test_that("blend_rvt colle a l'oracle RVT_py (VAT - Archaeological)", {
  o <- readRDS(test_path("fixtures", "vat_oracle.rds"))
  tmpl <- terra::rast(
    nrows = o$nr, ncols = o$nc, xmin = 0, xmax = o$nc, ymin = 0, ymax = o$nr,
    crs = "EPSG:2154"
  )
  mk <- function(v) {
    rr <- terra::rast(tmpl)
    terra::values(rr) <- v
    rr
  }
  # Pile HAUT -> BAS du preset : svf, openness+, slope, hillshade.
  stack <- c(mk(o$svf), mk(o$openness_pos), mk(o$slope), mk(o$hillshade))
  got <- terra::values(blend_rvt(stack, vat_default_layers()))[, 1]
  # Tolerance large devant l'ecart mesure (~1.6e-7, purement float32 de RVT).
  expect_equal(got, o$vat, tolerance = 1e-5)
})

test_that("vat_default_layers : epingle au preset blender_VAT.json", {
  l <- vat_default_layers()
  expect_equal(names(l), c("svf", "openness_pos", "slope", "hillshade"))
  expect_equal(unname(vapply(l, function(s) s$mode, "")),
    c("multiply", "overlay", "luminosity", "normal"))
  expect_equal(unname(vapply(l, function(s) s$opacity, 0)), c(0.25, 0.50, 0.50, 1.00))
  expect_true(l$slope$invert) # pente : echelle inversee (RVT normalize_image)
  expect_false(l$openness_pos$invert)
})

test_that(".rvt_blend_stack : le fond est le canal du bas, l'opacite dose", {
  # Deux canaux constants. Bas = 0.4 (fond), haut = 0.9, mode normal, opacite 0.5.
  # res = 0.5 * 0.9 + 0.5 * 0.4 = 0.65.
  m <- cbind(rep(0.9, 3), rep(0.4, 3))
  specs <- list(
    list(min = 0, max = 1, invert = FALSE, mode = "normal", opacity = 0.5),
    list(min = 0, max = 1, invert = FALSE, mode = "normal", opacity = 1)
  )
  expect_equal(foretaccess:::.rvt_blend_stack(m, specs), rep(0.65, 3))
})

test_that("blend_rvt : exige autant de specs que de couches, sort dans [0,1]", {
  r <- terra::rast(nrows = 8, ncols = 8, xmin = 0, xmax = 8, ymin = 0, ymax = 8)
  s <- c(r, r)
  terra::values(s) <- cbind(runif(64), runif(64))
  specs <- vat_default_layers()[1:2]
  out <- blend_rvt(s, specs)
  expect_s4_class(out, "SpatRaster")
  expect_equal(names(out), "vat")
  v <- terra::values(out)[, 1]
  expect_true(all(v >= 0 & v <= 1))
  # Nombre de specs != nombre de couches -> erreur.
  expect_error(blend_rvt(s, specs[1]), "autant")
  expect_error(blend_rvt(matrix(1, 3, 3), specs), "SpatRaster")
})

test_that("vat_archeo : assemble les 4 canaux en un composite [0,1]", {
  mnt <- terra::rast(
    nrows = 24, ncols = 24, xmin = 0, xmax = 24, ymin = 0, ymax = 24,
    crs = "EPSG:2154"
  )
  # Un versant incline + une depression centrale pour reveiller les canaux.
  terra::values(mnt) <- 100 + terra::rowFromCell(mnt, 1:576) * 0.3
  mnt[12, 12] <- 95
  vat <- vat_archeo(mnt, radius_m = 5)
  expect_s4_class(vat, "SpatRaster")
  expect_equal(names(vat), "vat")
  expect_equal(as.vector(terra::ext(vat)), as.vector(terra::ext(mnt)))
  v <- terra::values(vat)[, 1]
  expect_true(all(v >= 0 & v <= 1, na.rm = TRUE))
})

test_that("vat_archeo : sous-ensemble de canaux et canal inconnu rejete", {
  mnt <- terra::rast(
    nrows = 16, ncols = 16, xmin = 0, xmax = 16, ymin = 0, ymax = 16,
    crs = "EPSG:2154"
  )
  terra::values(mnt) <- 100 + terra::colFromCell(mnt, 1:256) * 0.4
  # Deux canaux seulement (svf multiply sur base hillshade).
  ls <- vat_default_layers()[c("svf", "hillshade")]
  vat <- vat_archeo(mnt, radius_m = 4, layers = ls)
  expect_equal(names(vat), "vat")
  # Canal hors liste -> erreur.
  mauvais <- list(list(name = "srlm", min = 0, max = 1, invert = FALSE, mode = "normal", opacity = 1))
  expect_error(vat_archeo(mnt, layers = mauvais), "inconnu")
})
