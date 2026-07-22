# Enumeration du domaine ACCESSFOR (IGN) et verification de la correspondance
# avec classes_debardage(). Documentaire / reproductible -- PAS execute en CI
# (appels reseau WFS). Sous-tend `accessfor_correspondance()` (R/accessfor.R) et
# la resolution du sec. 3 du brief nemeton (specs/brief-foretaccess-accessfor.md,
# cote nemeton) : elucider `class=2`, les classes >= 7, et la table de
# correspondance -- AVANT tout chiffre.
#
#   Rscript data-raw/accessfor.R
#
# Resultat verifie le 2026-07-22 (departement 48, Chastel-Nouvel).

.libPaths(c(.libPaths(), "~/R/x86_64-pc-linux-gnu-library/4.6"))
suppressPackageStartupMessages({
  library(httr2)
})

WFS <- "https://data.geopf.fr/wfs/ows"
DEP <- "48" # Lozere (Chastel-Nouvel)

# Un GetFeature WFS 2.0 filtre par departement et par classe. `hits_only` ne
# renvoie que le compte (numberMatched) ; sinon la 1re feature (pour le libelle).
accessfor_get <- function(couche, classe, hits_only = TRUE) {
  cql <- sprintf("dep='%s' AND class=%d", DEP, classe)
  req <- request(WFS) |>
    req_url_query(
      SERVICE = "WFS", VERSION = "2.0.0", REQUEST = "GetFeature",
      TYPENAMES = paste0("IGNF_ACCESSIBILITE-PHYSIQUE-FORETS-:", couche),
      CQL_FILTER = cql,
      RESULTTYPE = if (hits_only) "hits" else "results",
      COUNT = if (hits_only) NULL else "1"
    )
  resp <- req_perform(req) |> resp_body_string()
  if (hits_only) {
    as.integer(sub('.*numberMatched="([0-9]+)".*', "\\1", resp))
  } else {
    lab <- sub(".*<[^>]*:cat>([^<]*)</[^>]*:cat>.*", "\\1", resp)
    if (identical(lab, resp)) NA_character_ else lab
  }
}

# --- Enumeration : combien de features par classe, et leur libelle -----------
for (couche in c("acces_skidder", "acces_porteur")) {
  cat("\n== ", couche, " (dep ", DEP, ") ==\n", sep = "")
  for (cl in 1:9) {
    n <- accessfor_get(couche, cl, hits_only = TRUE)
    lab <- if (!is.na(n) && n > 0) accessfor_get(couche, cl, hits_only = FALSE) else ""
    cat(sprintf("  class=%d | n=%7s | %s\n", cl, format(n), lab))
  }
}

# Attendu (verifie 2026-07-22), IDENTIQUE skidder et porteur :
#   1 Inaccessible
#   2 Zone non exploitable (pente trop elevee)      <- notre `inexploitable`
#   3 Accessible - debardage 1 : 0 - 250 m          <- bande 1
#   4 Accessible - debardage 2 : 250 - 500 m        <- bande 2
#   5 Accessible - debardage 3 : 500 - 1000 m       <- bande 3
#   6 Accessible - debardage 4 : 1000 - 1500 m      <- bande 4
#   7 Accessible - debardage 5 : 1500 - 2000 m      <- bande 5
#   8 Accessible - debardage 6 : > 2000 m           <- bande 6 (ouverte)
#   9 (inexistant)
#
# => domaine TERME POUR TERME celui de classes_debardage() (defauts Sylvaccess).
# L'echantillon national du brief (dep 01/08/09, 200 features) etait trompeur :
# il manquait les classes 2, 7 et 8. Cf. accessfor_correspondance().

# --- Coherence de la table encodee vs le domaine observe ---------------------
if (requireNamespace("foretaccess", quietly = TRUE)) {
  co <- foretaccess::accessfor_correspondance()
  stopifnot(
    identical(sort(co$accessfor_class[!is.na(co$accessfor_class)]), 1:8),
    identical(co$accessfor_class[co$fa_classe == "inexploitable"], 2L)
  )
  cat("\naccessfor_correspondance() : coherente avec le domaine WFS observe.\n")
  print(co)
}
