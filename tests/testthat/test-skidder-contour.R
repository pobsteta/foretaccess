# Treuillage depuis le contour de la zone roulee (skid_debusq_contour de Sylvaccess).
#
# L'engin entre en foret, s'arrete au bord du terrain roulable, et treuille DEPUIS
# LA. Une cellule peut donc etre desservie bien au-dela de la portee du treuil
# mesuree depuis la route.

# Plateau plat a l'ouest (roulable), versant a 45 % vers l'est (non roulable, mais
# treuillable : 45 % < pente_abattage_max_pct). La rupture est a x = 125 m.
mnt_plateau_versant <- function(n = 60, res = 5, rupture = 125, pente = 0.45) {
  r <- terra::rast(
    nrows = n, ncols = n, xmin = 0, xmax = n * res, ymin = 0, ymax = n * res,
    crs = "EPSG:2154"
  )
  x <- terra::xyFromCell(r, seq_len(terra::ncell(r)))[, "x"]
  terra::values(r) <- 100 - pente * pmax(0, x - rupture)
  names(r) <- "altitude"
  r
}

pre_plateau <- function() {
  mnt <- mnt_plateau_versant()
  em <- terra::ext(mnt)
  coins <- cbind(
    c(em$xmin, em$xmax, em$xmax, em$xmin, em$xmin),
    c(em$ymin, em$ymin, em$ymax, em$ymax, em$ymin)
  )
  foret <- sf::st_sf(
    geometry = sf::st_sfc(sf::st_polygon(list(coins)), crs = 2154)
  )
  # Une seule route, nord-sud, sur le plateau, a 100 m a l'ouest de la rupture.
  desserte <- sf::st_sf(
    classe = "route",
    geometry = sf::st_sfc(
      sf::st_linestring(cbind(c(25, 25), c(em$ymin, em$ymax))),
      crs = 2154
    )
  )
  preprocess(mnt = mnt, desserte = desserte, foret = foret)
}

test_that("le skidder treuille depuis le bord de la zone roulee, pas seulement depuis la route", {
  pre <- pre_plateau()
  sk <- skidder(pre)

  cl <- terra::levels(sk$accessibilite)[[1]]
  code <- function(nom) cl[[1]][cl[[2]] == nom]

  acc <- as.numeric(terra::values(sk$accessibilite))
  d_tr <- as.numeric(terra::values(sk$distance_treuillage))
  d_fo <- as.numeric(terra::values(sk$distance_trainage_foret))

  # Cellule a x = 197,5 m : 172,5 m a l'est de la route, bien au-dela de la portee
  # du treuil (100 m aval au maximum), et sur un versant a 45 % ou l'engin ne roule
  # pas. Elle n'est atteignable qu'en treuillant depuis le bord du plateau.
  loin <- terra::cellFromRowCol(sk$accessibilite, 30, 40)
  expect_gt(terra::xFromCell(sk$accessibilite, loin) - 25, 170)

  expect_equal(acc[loin], code("accessible"))
  expect_gt(d_tr[loin], 0)
  # Elle herite du trainage de la rampe : le skidder a d'abord roule jusqu'au bord.
  expect_gt(d_fo[loin], 50)
  # Total coherent : trainage + treuil couvrent la distance a la route.
  expect_gt(as.numeric(terra::values(sk$distance_debardage))[loin], 170)
})

test_that("la rampe de contour reste allouee a une cellule de desserte", {
  pre <- pre_plateau()
  sk <- skidder(pre)

  desserte_cel <- which(!is.na(terra::values(pre$desserte)))
  alloc <- as.numeric(terra::values(sk$allocation))
  loin <- terra::cellFromRowCol(sk$accessibilite, 30, 40)

  # L'allocation d'une cellule treuillee depuis le contour n'est pas la rampe :
  # c'est la desserte a laquelle la rampe est elle-meme rattachee.
  expect_true(alloc[loin] %in% desserte_cel)
})
