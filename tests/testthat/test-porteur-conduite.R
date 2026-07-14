# Balayage radial de conduite du porteur (spec 003 §4.2).

# Distance conduite le long d'un axe depuis le point de desserte central.
dist_le_long <- function(res_conduite, pre, dx, dy, pas = 4) {
  centre <- terra::xyFromCell(pre$mnt, which(!is.na(terra::values(pre$desserte))))
  n <- terra::nrow(pre$mnt)
  cells <- integer(pas)
  for (k in seq_len(pas)) {
    xy <- cbind(centre[1] + dx * k * terra::res(pre$mnt)[1],
                centre[2] + dy * k * terra::res(pre$mnt)[1])
    cells[k] <- terra::cellFromXY(pre$mnt, xy)
  }
  as.numeric(terra::values(res_conduite$distance))[cells]
}

test_that("les seuils de pente sont compares en degres, pas en pourcents (CA-3.1)", {
  # atan(0.30) = 16,70 deg : un seuil exprime en % est converti avant comparaison.
  expect_equal(.pct_en_deg(30), atan(0.30) * 180 / pi)

  # Cote OUEST du plan : la cellule est plus basse que la route, donc le porteur
  # remonte le bois charge -> contrainte de MONTEE (30 %). Un plan a 29 % passe, un
  # plan a 31 % casse. C'est la comparaison au seuil de montee qu'on isole ici.
  ouest <- function(p) {
    pre <- pre_plan(pente = p)
    cd <- conduire(pre, foretaccess_config(), zone_conduite(pre))
    dist_le_long(cd, pre, dx = -1, dy = 0)
  }
  expect_true(all(!is.na(ouest(0.29))))
  expect_true(all(is.na(ouest(0.31))))
})

test_that("le devers depend de l'azimut : nul dans le sens de la pente, max en travers (CA-3.2)", {
  # Plan a 20 %, exposition ouest. Devers max = pente_travers 15 %.
  # Est-ouest = sens de la pente (pas de devers) ; nord-sud = travers (devers = 20 %).
  pre <- pre_plan(pente = 0.20)
  cfg <- foretaccess_config()
  cd <- conduire(pre, cfg, zone_conduite(pre))

  est <- dist_le_long(cd, pre, dx = 1, dy = 0) # montee, sens pente
  nord <- dist_le_long(cd, pre, dx = 0, dy = 1) # travers

  # Sens de la pente : 20 % < seuil montee 30 %, aucun devers -> conduisible.
  expect_true(all(!is.na(est)))
  # En travers : devers 20 % > seuil travers 15 % -> non conduisible.
  expect_true(all(is.na(nord)))
})

test_that("le sens amont/aval distingue montee et descente (CA-3.3)", {
  # Le porteur ramene le bois charge vers la route. Une cellule *plus haute* que la
  # route -> trajet charge en DESCENTE (seuil 40 %) ; plus basse -> MONTEE (seuil 30 %).
  # La descente est le sens PERMISSIF : c'est charge, en descente, que l'engin passe
  # la plus forte pente. Sur un plan montant vers l'est a 35 % : est plus haut
  # (35 < 40, passe), ouest plus bas (35 > 30, casse).
  pre <- pre_plan(pente = 0.35)
  cd <- conduire(pre, foretaccess_config(), zone_conduite(pre))

  est <- dist_le_long(cd, pre, dx = 1, dy = 0) # plus haut : contrainte descente
  ouest <- dist_le_long(cd, pre, dx = -1, dy = 0) # plus bas : contrainte montee

  expect_true(all(!is.na(est)))
  expect_true(all(is.na(ouest)))
})

test_that("l'accumulateur de pente forte plafonne la conduite (CA-3.4)", {
  # Plan a 20 %, sens de la pente (est), donc pas de devers ni de blocage de pente en
  # long (20 % < 30 %). Mais 20 % > seuil travers 15 %, donc chaque pas compte dans
  # l'accumulateur. Avec un plafond court, la conduite s'arrete tot.
  pre <- pre_plan(pente = 0.20, n = 81)
  court <- foretaccess_config(porteur = list(distance_pente_forte_max_m = 30))
  long <- foretaccess_config(porteur = list(distance_pente_forte_max_m = 300))

  cd_court <- conduire(pre, court, zone_conduite(pre))
  cd_long <- conduire(pre, long, zone_conduite(pre))

  atteint <- function(cd) sum(!is.na(terra::values(cd$distance)))
  expect_lt(atteint(cd_court), atteint(cd_long))
})

test_that("la distance retenue est 3D (CA-3.6)", {
  # Plan a 20 %, montee vers l'est. La distance 3D depasse la distance planimetrique
  # du facteur sqrt(1 + 0,2^2) = 1,0198.
  pre <- pre_plan(pente = 0.20)
  cd <- conduire(pre, foretaccess_config(), zone_conduite(pre))

  res <- terra::res(pre$mnt)[1]
  est <- dist_le_long(cd, pre, dx = 1, dy = 0, pas = 3)
  # Premiere cellule a l'est : planimetrique = res, 3D = res * sqrt(1 + 0,2^2).
  expect_equal(est[1], res * sqrt(1 + 0.20^2), tolerance = 1e-6)
})

test_that("les cellules de desserte sont a distance nulle et allouees a elles-memes", {
  pre <- pre_plan(pente = 0.10)
  cd <- conduire(pre, foretaccess_config(), zone_conduite(pre))

  route <- which(!is.na(terra::values(pre$desserte)))
  expect_equal(as.numeric(terra::values(cd$distance))[route], 0)
  expect_equal(as.numeric(terra::values(cd$allocation))[route], route)
})

test_that("une desserte absente leve une erreur ciblee", {
  pre <- pre_plan(pente = 0.10)
  terra::values(pre$desserte) <- NA_real_
  expect_error(conduire(pre, foretaccess_config(), zone_conduite(pre)),
    regexp = "aucune cellule")
})

test_that("les rayons qui sortent tous de la grille arretent le balayage", {
  # Desserte dans un COIN d'une petite grille plate : les rayons pointant hors grille en
  # sortent des le premier pas, ce qui declenche l'arret de sortie de grille. Ceux qui
  # pointent vers l'interieur couvrent leur voisinage.
  mnt <- mnt_plan(pente = 0, n = 11)
  d0 <- sf::st_sf(classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(5, 5), c(10, 5))), crs = 2154))
  pre <- preprocess(mnt = mnt, desserte = d0, foret = foret_pleine(mnt))
  pre$desserte <- desserte_point(mnt, 2.5, 2.5) # coin bas-gauche de la grille 11x11

  cd <- conduire(pre, foretaccess_config(), zone_conduite(pre))
  # Le balayage se termine sans planter, et atteint l'interieur depuis le coin.
  atteint <- sum(!is.na(terra::values(cd$distance)))
  expect_gt(atteint, 20)
})

test_that("un replat n'a pas de devers : la conduite n'y est bornee que par la pente en long", {
  # MNT plat : pente 0, exposition NA. Aucun filtre ne casse, tout est conduisible.
  mnt <- mnt_plan(pente = 0, n = 41)
  d0 <- sf::st_sf(classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(5, 5), c(10, 5))), crs = 2154))
  pre <- preprocess(mnt = mnt, desserte = d0, foret = foret_pleine(mnt))
  pre$desserte <- desserte_point(mnt, 100, 100)

  cd <- conduire(pre, foretaccess_config(), zone_conduite(pre))
  # Sur un plat, la portee n'est bornee que par le rayon (distance_pente_forte_max_m).
  expect_gt(sum(!is.na(terra::values(cd$distance))), 100)
})
