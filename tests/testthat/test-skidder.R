
test_that("le reseau public n'est ni une destination de debardage ni un chemin", {
  # Trouve par confrontation a l'oracle Sylvaccess (jeu ColduPre) : le reseau
  # public est le point de chargement du CAMION, pas une place de depot, et pour
  # le skidder une BARRIERE. Sylvaccess l'exclut des sources et de la zone
  # roulable (`from_rast[Res_pub==1]=0`, `zone_rast[Res_pub==1]=0`). Le compter
  # comme une route rendait accessibles des cellules qui ne le sont pas, et
  # faisait rouler le skidder le long de la route publique au tarif obstacle.
  d <- toy_desserte()
  d_pub <- d
  d_pub$classe <- "reseau_public"

  pre_route <- preprocess(mnt = toy_mnt(), desserte = d, foret = toy_foret())
  pre_pub <- preprocess(mnt = toy_mnt(), desserte = d_pub, foret = toy_foret())

  # Meme geometrie, mais requalifiee en reseau public : plus aucune livraison
  # possible, donc le skidder n'a plus de point de depart.
  expect_gt(length(.cellules_livraison(pre_route)), 0)
  expect_length(.cellules_livraison(pre_pub), 0)
  expect_error(skidder(pre_pub), "Aucune cellule de desserte")

  # Et le reseau public sort de la zone roulable, meme sous le seuil de pente.
  z <- terra::values(zone_roulage(pre_pub, foretaccess_config()))
  pub <- terra::values(pre_pub$reseau_public_mask) == 1
  expect_true(all(z[pub] == 0))
})
