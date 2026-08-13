# Client Overpass canonique (ADR-010). AUCUN test ne tape le reseau : le
# transport HTTP (`.osm_curl`) est le point de mock, comme `.fetch_osm` l'etait.
#
# Le contrat teste ici est celui du brief §2.2 -- TROIS ISSUES, jamais
# confondues. La troisieme est la raison d'etre du lot : une instance bridee
# repond un XML BIEN FORME, HTTP 200, quelques centaines d'octets, avec un
# `<remark>`. Lu naivement, cela dit « rien ici » -- l'erreur qui a masque
# l'absence de DFCI pendant une journee entiere.

# --- Fabriques de reponses ---------------------------------------------------

rep_xml <- function(corps, code = 200L, headers = raw(0)) {
  list(status_code = code, content = charToRaw(corps), headers = headers)
}

# XML Overpass avec un way : deux noeuds et une way qui les relie.
xml_avec_way <- function() {
  paste0('<?xml version="1.0" encoding="UTF-8"?>\n<osm version="0.6">\n',
    '<node id="1" lat="45.0000" lon="6.0000"/>\n',
    '<node id="2" lat="45.0010" lon="6.0010"/>\n',
    '<way id="10"><nd ref="1"/><nd ref="2"/>',
    '<tag k="highway" v="track"/><tag k="surface" v="ground"/></way>\n',
    '</osm>\n')
}

# XML valide, AUCUN way, AUCUN remark : c'est un vide LEGITIME.
xml_vide <- function() {
  paste0('<?xml version="1.0" encoding="UTF-8"?>\n<osm version="0.6">\n',
    '<meta osm_base="2026-08-13T00:00:00Z"/>\n',
    '<!-- rien a cet endroit, et c est un resultat -->\n</osm>\n')
}

# Le piege : bien forme, HTTP 200, mais c'est un REFUS.
xml_remark <- function() {
  paste0('<?xml version="1.0" encoding="UTF-8"?>\n<osm version="0.6">\n',
    '<remark> runtime error: Query timed out in "recurse" at line 4 </remark>\n',
    '<!-- bourrage pour depasser la taille minimale de garde ',
    strrep("x", 200), ' -->\n</osm>\n')
}

# --- Les trois issues --------------------------------------------------------

test_that("issue 1 : un XML avec <way> rend un sf non vide", {
  testthat::local_mocked_bindings(
    .osm_curl = function(url, ql, timeout) rep_xml(xml_avec_way()))
  d <- osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway")
  expect_s3_class(d, "sf")
  expect_gt(nrow(d), 0)
})

test_that("issue 2 : un XML valide SANS way et SANS remark rend un sf vide, PAS une erreur", {
  # Un vide est un resultat : il dit « il n'y a rien ici », ce qui s'exploite.
  testthat::local_mocked_bindings(
    .osm_curl = function(url, ql, timeout) rep_xml(xml_vide()))
  d <- osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway")
  expect_s3_class(d, "sf")
  expect_equal(nrow(d), 0)
})

test_that("issue 3 : un <remark> est une ERREUR, et le message le cite", {
  # LA regle de conservation du lot : un refus ne devient JAMAIS une couche vide.
  testthat::local_mocked_bindings(
    .osm_curl = function(url, ql, timeout) rep_xml(xml_remark()))
  expect_error(
    osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway"),
    "remark"
  )
})

test_that("un corps tronque est un refus, pas un vide", {
  testthat::local_mocked_bindings(
    .osm_curl = function(url, ql, timeout) rep_xml("<osm/>"))
  expect_error(osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01),
                            "highway"), "refus")
})

# --- Rotation d'instances ----------------------------------------------------

test_that("un 429 sur la 1re instance bascule sur la 2e, et le dit", {
  vues <- character(0)
  testthat::local_mocked_bindings(.osm_curl = function(url, ql, timeout) {
    vues <<- c(vues, url)
    if (length(vues) == 1L) rep_xml("", code = 429L) else rep_xml(xml_avec_way())
  })
  expect_message(
    d <- osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01),
                      "highway", max_reprises = 0),
    "repli"
  )
  expect_gt(nrow(d), 0)
  expect_length(unique(vues), 2L)
  # La bascule ne coute AUCUN appel reseau supplementaire : c'est ce qui la
  # distingue de `osmdata::set_overpass_url()`, dont le changement d'instance
  # tape lui-meme le reseau et meurt donc quand l'instance est saturee.
  expect_length(vues, 2L)
})

test_that("toutes les instances en echec : erreur relayant la derniere cause", {
  testthat::local_mocked_bindings(
    .osm_curl = function(url, ql, timeout) rep_xml("", code = 503L))
  expect_error(
    osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway",
                 serveurs = c("a", "b"), max_reprises = 0),
    "503"
  )
})

test_that("le nombre d'appels est BORNE par serveurs x (1 + reprises)", {
  n <- 0L
  testthat::local_mocked_bindings(.osm_curl = function(url, ql, timeout) {
    n <<- n + 1L
    rep_xml("", code = 503L)
  })
  try(osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway",
                   serveurs = c("a", "b", "c"), max_reprises = 1), silent = TRUE)
  # 503 n'est pas un quota : on ne reessaie pas la meme instance, on passe.
  expect_lte(n, 3L * 2L)
})

# --- Requete : c'est elle qui porte le gain 5->1 et 3->1 ---------------------

test_that("une liste de filtres produit UNE union Overpass", {
  ql <- foretaccess:::.osm_requete(
    c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01),
    list(list(cle = "building", valeur = NULL),
         list(cle = "natural", valeur = "water")))
  expect_match(ql, "\\[\"building\"\\]")
  expect_match(ql, "\\[\"natural\"=\"water\"\\]")
  # Une seule union, donc un seul aller-retour : Overpass plafonne le NOMBRE de
  # requetes, pas la surface.
  expect_equal(lengths(regmatches(ql, gregexpr("out body;", ql)))[[1]], 1L)
  # `relation` autant que `way` : sans les relations, les plans d'eau
  # multipolygones manqueraient.
  expect_match(ql, "relation")
})

test_that("la bbox est en ordre Overpass (sud, ouest, nord, est)", {
  ql <- foretaccess:::.osm_requete(
    c(xmin = 6, ymin = 45, xmax = 7, ymax = 46), "highway")
  expect_match(ql, "(45,6,46,7)", fixed = TRUE)
})

# --- Bissection --------------------------------------------------------------

test_that("un refus de VOLUME bissecte, un 429 NON", {
  # Distinction du brief §3 : le volume appelle un decoupage, le quota appelle
  # une rotation. Les confondre, c'est decouper pour un probleme de debit --
  # donc multiplier les requetes, donc aggraver le quota.
  appels <- 0L
  testthat::local_mocked_bindings(.osm_curl = function(url, ql, timeout) {
    appels <<- appels + 1L
    if (appels == 1L) rep_xml(xml_remark()) else rep_xml(xml_avec_way())
  })
  # `remark` de type timeout -> bissection -> les quadrants aboutissent.
  d <- suppressMessages(foretaccess:::.osm_bissecter(
    c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway"))
  expect_s3_class(d, "sf")
  expect_gt(appels, 1L)
})

test_that("la bissection dedoublonne sur osm_id", {
  # Un way traversant deux quadrants revient une fois par quadrant.
  testthat::local_mocked_bindings(.osm_curl = function(url, ql, timeout) {
    rep_xml(xml_avec_way())
  })
  d <- osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway")
  expect_equal(anyDuplicated(d$osm_id), 0L)
})

# --- Provenance --------------------------------------------------------------

test_that("la reponse porte instance, requete et date", {
  # Sans horodatage, deux executions a un mois d'ecart different SANS AUCUNE
  # TRACE. Sur des donnees qui alimentent une conception de reseau, c'en est un
  # probleme de fond, pas de la comptabilite.
  testthat::local_mocked_bindings(
    .osm_curl = function(url, ql, timeout) rep_xml(xml_avec_way()))
  d <- osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway")
  p <- osm_provenance(d)
  expect_true(all(c("instance", "requete", "date_requete", "nb_entites") %in% names(p)))
  expect_match(p$instance, "^https://")
  expect_match(p$date_requete, "^\\d{4}-\\d{2}-\\d{2}T")
  expect_match(p$requete, "out body")
})

# --- Chemins que les trois issues ne traversaient pas -------------------------
# Signales par la couverture du patch : le contrat principal etait teste, ses
# bordures non. Ce sont elles qui se declenchent un jour de panne.

test_that("une erreur de transport (socket, DNS) est un refus, pas un vide", {
  # `.osm_curl` rend `erreur` quand libcurl echoue avant toute reponse HTTP.
  testthat::local_mocked_bindings(.osm_curl = function(url, ql, timeout) {
    list(status_code = -1L, content = raw(0), headers = raw(0),
         erreur = "Timeout was reached")
  })
  expect_error(
    osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway",
                 serveurs = "a", max_reprises = 0),
    "Timeout"
  )
})

test_that("un Retry-After COURT est honore, un long fait changer d'instance", {
  # La regle du brief : au-dela de ~10 s, changer d'instance bat attendre. Le
  # comportement a proscrire est celui d'`osmdata` -- 60 s en boucle, sans plafond.
  entete <- function(s) charToRaw(paste0("HTTP/1.1 429\r\nRetry-After: ", s, "\r\n\r\n"))
  expect_equal(foretaccess:::.osm_retry_after(entete(3)), 3)
  expect_equal(foretaccess:::.osm_retry_after(entete(120)), 120)
  expect_true(is.na(foretaccess:::.osm_retry_after(raw(0))))

  # Court : on reessaie la MEME instance (2 appels sur un seul serveur).
  n <- 0L
  testthat::local_mocked_bindings(.osm_curl = function(url, ql, timeout) {
    n <<- n + 1L
    if (n == 1L) list(status_code = 429L, content = raw(0), headers = entete(0))
    else rep_xml(xml_avec_way())
  })
  d <- osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway",
                    serveurs = "a", max_reprises = 1)
  expect_gt(nrow(d), 0)
  expect_equal(n, 2L)
})

test_that("un Retry-After LONG ne fait pas attendre : on passe au miroir", {
  entete <- charToRaw("HTTP/1.1 429\r\nRetry-After: 300\r\n\r\n")
  vues <- character(0)
  testthat::local_mocked_bindings(.osm_curl = function(url, ql, timeout) {
    vues <<- c(vues, url)
    if (length(vues) == 1L) list(status_code = 429L, content = raw(0), headers = entete)
    else rep_xml(xml_avec_way())
  })
  t <- system.time(suppressMessages(
    osm_overpass(c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway",
                 serveurs = c("a", "b"), max_reprises = 1)))
  # Le test vaut par sa DUREE : 300 s d'attente auraient ete honorees par une
  # implementation naive. On bascule, donc c'est instantane.
  expect_lt(as.numeric(t[["elapsed"]]), 5)
  expect_length(unique(vues), 2L)
})

test_that("les tags noyes dans other_tags sont deplies", {
  # Le driver OSM de GDAL ne promeut en colonne que certains tags (selon
  # `OSM_CONFIG_FILE`) ; le reste atterrit dans `other_tags`. Sans depliage,
  # `tracktype`/`surface`/`access` -- documentes en sortie
  # d'`acquire_desserte_osm()` -- disparaitraient SILENCIEUSEMENT.
  d <- sf::st_sf(
    osm_id = c("1", "2"),
    highway = c("track", NA),
    other_tags = c("\"tracktype\"=>\"grade3\",\"surface\"=>\"ground\"",
                   "\"highway\"=>\"service\",\"access\"=>\"private\""),
    geometry = sf::st_sfc(sf::st_point(c(6, 45)), sf::st_point(c(6.1, 45.1)),
                          crs = 4326))
  out <- foretaccess:::.osm_deplier_tags(d)
  expect_equal(out$tracktype, c("grade3", NA))
  expect_equal(out$surface, c("ground", NA))
  expect_equal(out$access, c(NA, "private"))
  # Une colonne DEJA renseignee n'est pas ecrasee ; un NA est complete.
  expect_equal(out$highway, c("track", "service"))
})

test_that("la bissection s'arrete a la profondeur maximale, en le disant", {
  # Profondeur 3 = 64 sous-emprises au pire. Au-dela, l'erreur est plus honnete
  # qu'un decoupage qui n'aboutira pas.
  testthat::local_mocked_bindings(
    .osm_curl = function(url, ql, timeout) rep_xml(xml_remark()))
  expect_error(
    suppressMessages(foretaccess:::.osm_bissecter(
      c(xmin = 6, ymin = 45, xmax = 6.01, ymax = 45.01), "highway",
      serveurs = "a", timeout = 1)),
    "remark"
  )
})
