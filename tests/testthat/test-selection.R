# Selection multicritere des lignes cable (Lot 5) : la table candidate (5a,
# potentiel_cable$lignes) et selectionner_lignes (5b). On teste la table sur MNT
# synthetique, puis le scoring/greedy sur des tables construites a la main
# (oracle analytique).

# --- 5a : table des lignes candidates ------------------------------------

pre_cable_vol <- function(vol = 150) {
  mnt <- mnt_plan(pente = 0.2, n = 25, res = 5)
  d0 <- sf::st_sf(classe = "route",
    geometry = sf::st_sfc(sf::st_linestring(rbind(c(5, 5), c(10, 5))), crs = 2154))
  pre <- preprocess(mnt = mnt, desserte = d0, foret = foret_pleine(mnt))
  pre$desserte <- desserte_point(mnt, 105, 62.5)
  vr <- terra::rast(mnt)
  terra::values(vr) <- vol
  pre$volume <- vr
  pre
}

config_court <- function() {
  foretaccess_config(cable = list(longueur_max_m = 60, longueur_min_m = 20))
}

test_that("potentiel_cable emet une table de lignes candidates coherente", {
  ca <- potentiel_cable(pre_cable_vol(), config_court())
  lg <- ca$lignes

  expect_s3_class(lg, "data.frame")
  expect_setequal(
    names(lg),
    c("depart", "azimut", "longueur_m", "surface_ha", "sens", "supports", "volume_m3", "ipc")
  )
  expect_gt(nrow(lg), 0)
  expect_true(all(lg$surface_ha > 0))
  expect_true(all(lg$longueur_m >= 20 & lg$longueur_m <= 60))
  expect_true(all(!is.na(lg$ipc))) # volume fourni -> IPC calcule
  expect_equal(lg$ipc, lg$volume_m3 / lg$longueur_m) # IPC = volume / longueur
})

test_that("sans volume, les colonnes volume/IPC sont NA", {
  pre <- pre_cable_vol()
  pre$volume <- NULL
  ca <- potentiel_cable(pre, config_court())
  expect_true(all(is.na(ca$lignes$volume_m3)))
  expect_true(all(is.na(ca$lignes$ipc)))
})

# --- 5b : selection sur tables construites (oracle analytique) ------------

# Fabrique un objet foretaccess_cable minimal a partir d'une table de lignes et
# d'un gabarit raster (25x25, res 5, CRS 2154), sans relancer le scan.
cable_factice <- function(lignes, config = foretaccess_config()) {
  g <- terra::rast(nrows = 25, ncols = 25, xmin = 0, xmax = 125, ymin = 0, ymax = 125,
    crs = "EPSG:2154")
  terra::values(g) <- 3L
  structure(list(accessibilite = g, lignes = lignes, config = config),
    class = "foretaccess_cable")
}

ligne_row <- function(depart, azimut, longueur_m, surface_ha, sens = 0L,
                      supports = 0L, volume_m3 = NA_real_, ipc = NA_real_) {
  data.frame(depart = depart, azimut = azimut, longueur_m = longueur_m,
    surface_ha = surface_ha, sens = sens, supports = supports,
    volume_m3 = volume_m3, ipc = ipc)
}

test_that("le filtrage par limites ecarte les lignes hors bornes", {
  lignes <- rbind(
    ligne_row(313, 90, 40, 0.5), # gardee
    ligne_row(313, 90, 10, 0.5), # longueur < min
    ligne_row(313, 90, 40, 0.01) # surface < min
  )
  cfg <- foretaccess_config(cable = list(selection = list(
    poids = list(surface = 1, supports = 0, longueur = 0, volume = 0, ipc = 0),
    limites = list(surface_min = 0.1, supports_max = Inf, longueur_min = 20,
      longueur_max = Inf, volume_min = 0, ipc_min = 0),
    sens_prefere = 0, contribution_min = 0.6
  )))
  sel <- selectionner_lignes(cable_factice(lignes, cfg))
  # Seule la premiere ligne satisfait toutes les limites.
  expect_equal(nrow(sel$lignes), 1)
  expect_equal(sel$lignes$longueur_m, 40)
})

test_that("a poids surface seul, la plus grande surface est retenue en premier", {
  # Deux lignes qui se recouvrent (meme depart/azimut) : une seule retenue,
  # celle de plus grande surface (mieux classee).
  lignes <- rbind(
    ligne_row(313, 90, 40, 0.2),
    ligne_row(313, 90, 40, 0.8)
  )
  sel <- selectionner_lignes(cable_factice(lignes))
  expect_equal(nrow(sel$lignes), 1)
  expect_equal(sel$lignes$surface_ha, 0.8)
})

test_that("deux lignes non recouvrantes sont toutes deux retenues", {
  # Departs et azimuts opposes -> emprises disjointes.
  lignes <- rbind(
    ligne_row(313, 90, 40, 0.5), # vers l'est
    ligne_row(313, 270, 40, 0.5) # vers l'ouest
  )
  sel <- selectionner_lignes(cable_factice(lignes))
  expect_equal(nrow(sel$lignes), 2)
})

test_that("la sortie sf est valide (CRS, LINESTRING) et la couverture coherente", {
  lignes <- ligne_row(313, 90, 40, 0.5)
  sel <- selectionner_lignes(cable_factice(lignes))

  expect_s3_class(sel$lignes, "sf")
  expect_false(is.na(sf::st_crs(sel$lignes)$epsg))
  expect_equal(as.character(sf::st_geometry_type(sel$lignes)), "LINESTRING")
  expect_s4_class(sel$couverture, "SpatRaster")
  # La couverture ne marque que des cellules (0/1) et il y en a.
  vals <- terra::values(sel$couverture)
  expect_setequal(unique(vals), c(0L, 1L))
  expect_gt(sum(vals), 0)
})

test_that("le criteres volume/IPC sont neutralises sans donnee de volume", {
  # Volume tout NA : la selection tourne sur les criteres geometriques.
  lignes <- rbind(
    ligne_row(313, 90, 40, 0.8),
    ligne_row(313, 270, 40, 0.2)
  )
  cfg <- foretaccess_config(cable = list(selection = list(
    poids = list(surface = 1, supports = 0, longueur = 0, volume = 5, ipc = 5),
    limites = list(surface_min = 0, supports_max = Inf, longueur_min = 0,
      longueur_max = Inf, volume_min = 100, ipc_min = 100),
    sens_prefere = 0, contribution_min = 0.6
  )))
  # limites volume/ipc a 100 ecarteraient tout SI le volume comptait ; comme il
  # est absent, elles sont ignorees et les deux lignes disjointes passent.
  sel <- selectionner_lignes(cable_factice(lignes, cfg))
  expect_equal(nrow(sel$lignes), 2)
})
