# Faisabilite d'une travee de cable (Lot 4b) : check_droite (pre-filtre) et
# check_Hlinemin (balayage complet de la charge, garde au sol). Portes en Rust,
# valides depuis R sur la meme solution manufacturee qu'en 4a : on choisit
# (Tho, Tvo) au milieu, on en deduit la geometrie (D, H) qui annule f_x, f_z ;
# le balayage s'amorce alors exactement, et la faisabilite depend du profil sol.

g <- 9.80665

params_cable <- function() {
  lo <- 200
  ao <- 0.25 * pi * 18^2
  list(
    lo = lo,
    q1 = 1.85,
    w = 1.85 * g * lo,
    f_o = g * (2500 + 400),
    eao = 160000 * ao,
    q = 0.9, # masses lineaires traction/retour (kg/m)
    tmax = 35000 * g / 2
  )
}

# Geometrie manufacturee : (Tho, Tvo) au milieu -> (D, H) exacts, et cote du
# support haut `zup` telle que le point bas du cable soit a 20 m au-dessus de 0.
cas_manufacture <- function() {
  p <- params_cable()
  tho <- 60000
  tvo <- 25000
  s_mid <- p$lo * 0.5
  f_mid <- 0.5 * (s_mid * p$q + (p$lo - s_mid) * p$q) * g + p$f_o
  d <- cable_calcul_xs(tho, tvo, p$lo, p$eao, p$w, f_mid, s_mid, p$lo)
  h_alt <- cable_calcul_zs(tho, tvo, p$lo, p$eao, p$w, f_mid, s_mid, p$lo)
  drop_mid <- cable_calcul_zs(tho, tvo, p$lo, p$eao, p$w, f_mid, s_mid, s_mid)
  zup <- 20 + drop_mid
  c(p, list(tho = tho, tvo = tvo, d = d, h_alt = h_alt, zup = zup, z_mid = 20))
}

test_that("une travee degagee est faisable, garde minimale positive et bornee", {
  c <- cas_manufacture()
  alts <- rep(0, 1000) # sol plat a 0, echantillonne au demi-metre
  hmin <- cable_check_hlinemin(alts, c$h_alt, c$d, c$lo, 1, c$tho, c$tvo, 0, c$zup,
    c$f_o, c$tmax, 3.5, 50, c$q1, c$q, c$q, 5, c$eao)

  expect_gt(hmin, 0) # faisable
  # Garde minimale sous la garde du point bas (z_mid - hline_min = 16,5 m).
  expect_lt(hmin, c$z_mid - 3.5 + 0.1)
  expect_gt(hmin, 5)
})

test_that("un sol trop haut passe sous le cable : travee infaisable (-1)", {
  c <- cas_manufacture()
  alts <- rep(25, 1000) # sol releve au-dessus du cable (20 m)
  hmin <- cable_check_hlinemin(alts, c$h_alt, c$d, c$lo, 1, c$tho, c$tvo, 0, c$zup,
    c$f_o, c$tmax, 3.5, 50, c$q1, c$q, c$q, 5, c$eao)
  expect_equal(hmin, -1)
})

test_that("un cable trop haut au-dessus du sol depasse hline_max : infaisable (-1)", {
  c <- cas_manufacture()
  alts <- rep(-100, 1000) # sol tres bas -> garde > hline_max (50)
  hmin <- cable_check_hlinemin(alts, c$h_alt, c$d, c$lo, 1, c$tho, c$tvo, 0, c$zup,
    c$f_o, c$tmax, 3.5, 50, c$q1, c$q, c$q, 5, c$eao)
  expect_equal(hmin, -1)
})

# check_droite est un pre-filtre geometrique : travee plate (h_alt = 0),
# garde = zup - terrain partout.
test_that("check_droite ecarte une corde trop basse (< hline_min)", {
  p <- params_cable()
  n <- 220
  line_x <- (0:(n - 1)) * 0.5
  line_z <- rep(9, n) # terrain a 1 m sous le support a 10 m
  ok <- cable_check_droite(1, 0, 100, 0, 10, line_x, line_z, 3.5, 50, p$tmax,
    p$q1, p$q, p$q, p$f_o, 0L, as.integer(n - 1))
  expect_equal(ok, 0)
})

test_that("check_droite accepte un profil degage (dans les gardes)", {
  p <- params_cable()
  n <- 220
  line_x <- (0:(n - 1)) * 0.5
  line_z <- rep(0, n) # terrain a 0, support a 20 m -> garde ~20 m
  ok <- cable_check_droite(1, 0, 100, 0, 20, line_x, line_z, 3.5, 50, p$tmax,
    p$q1, p$q, p$q, p$f_o, 0L, as.integer(n - 1))
  expect_equal(ok, 1)
})
