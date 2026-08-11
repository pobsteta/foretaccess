# BRIEF `nemetonshiny` — exposer les deux décisions de coût que le cœur ne peut pas trancher

> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/nemetonshiny`**
> (un repo = une session). Repo concerné : `pobsteta/nemetonshiny`.
> Amont : `foretaccess`, branche `feat/cout-terrassement` (poussée).
> Fait suite à `BRIEF-dessertR-classement-osm-et-cout-terrassement.md` §5, qui annonçait le coût
> de terrassement « disponible, non activé ». Il l'est toujours — et c'est le sujet.
> **Rien d'urgent** : la chaîne actuelle est correcte, ce brief ajoute un choix.

## 1. Pourquoi ce brief

Le cœur a instrumenté deux façons de tarifer la pente et les a comparées sur DABO
(`specs/029-cout-terrassement.md` §7). Le banc établit que **le choix a des conséquences fortes,
pas qu'il a une bonne réponse** :

| | barème | terrassement |
|---|---:|---:|
| coût médian (domaine commun) | 45,0 €/m | 46,4 €/m |
| coût **moyen** | 64,6 €/m | **99,0 €/m** |
| routes créées / longueur | 37 / 6 931 m | 40 / 7 550 m |
| **recouvrement des deux tracés** | — | **44,1 %** |

Moins de la moitié du réseau est commune, pour des agrégats qui se ressemblent. Personne n'a jugé
lequel des deux jeux de tracés est le plus plausible sur le terrain — c'est un avis de
gestionnaire, pas une propriété du modèle. **D'où la décision : ne pas trancher dans le cœur, et
rendre le choix à l'utilisateur.**

## 2. Ce qu'il faut exposer — trois entrées, pas une

`surface_cout_construction()` prend désormais :

```r
surface_cout_construction(pre, cfg,
                          methode_pente = c("bareme", "terrassement"),
                          largeur_m     = 4,
                          pente_max_pct = NULL)
```

### 2.1 Méthode de tarification — `methode_pente`

`radioButtons`, défaut **barème**.

- **Barème** (défaut) — quatre classes de pente, échelle en vigueur. Discontinue : 65 €/m d'écart
  entre 34,9 % et 35,1 %. Aveugle à la largeur de plateforme.
- **Terrassement** — volumes de déblai / remblai chiffrés au m³. Continu, et **le seul des deux
  qui tienne compte de la largeur** : le volume croît comme son carré.

Libellé d'aide suggéré : « Le terrassement chiffre un volume de terre ; le barème applique une
grille par classe de pente. Les deux donnent des coûts médians comparables mais **des tracés
différents à plus de la moitié**. »

### 2.2 Largeur de plateforme — `largeur_m`

`numericInput`, défaut 4 m, plage 2,5–6.

**Elle n'a d'effet qu'avec le terrassement** — le griser en mode barème serait honnête. Elle doit
venir de la largeur visée par le gestionnaire, pas d'une constante : c'est précisément ce que le
barème ne sait pas représenter.

### 2.3 Pente maximale constructible — `pente_max_pct`

`numericInput`, défaut **60 %**.

**C'est l'entrée à ne pas oublier, et l'ordre compte** : sans elle, choisir « terrassement »
décidait *aussi* du plafond, en silence. Le barème s'arrête à 60 % par sa dernière classe ; le
terrassement va jusqu'à la pente du talus de déblai (100 %) et ouvrait ainsi **5,02 % du massif
DABO** — 67 632 cellules entre 60 et 100 % de pente — sans que personne l'ait demandé.

Le cœur reprend maintenant par défaut le plafond implicite du barème, de sorte que changer de
méthode ne change **que la tarification**. Passer le plafond au-dessus de 60 % est une décision
distincte, qui doit se voir.

Libellé d'aide suggéré : « Au-delà de ce seuil, aucune route n'est tracée. L'augmenter ouvre du
terrain que le barème refusait : le coût y est très élevé mais **fini**, donc dissuasif et non
interdit — dans un corridor sans alternative, le solveur le prendra. »

## 3. Ce qu'il ne faut pas faire

- **Ne pas basculer le défaut** sur « terrassement ». Le calage des prix au m³ n'est pas un relevé
  de devis : il est obtenu par inversion d'un plafond de subvention (spec 029, §Prix). Tant qu'un
  gestionnaire n'a pas fourni de barème réel, le terrassement est un modèle mieux formé, pas un
  modèle mieux calé.
- **Ne pas exposer `pente_max_pct` sans son avertissement.** Un `numericInput` nu invite à monter
  le chiffre pour « avoir plus de solutions ».
- **Ne pas comparer deux runs sur leurs totaux.** C'est le piège que le banc a documenté : longueur
  à 9 % près, trois routes d'écart, et 44 % de géométrie commune. Si l'app affiche un comparatif,
  qu'il porte sur la géométrie.

## 4. Invalidation du cache

Les trois entrées changent le résultat. Elles doivent entrer dans la clé du cache desserte, au même
titre que `skidding_m` et le moteur — sinon un changement de méthode rendra le réseau précédent
sans recalcul. Le mécanisme d'invalidation ajouté pour `pondere_cout` (`meta$pondere_cout`) est le
bon endroit.

## 5. Ce que le cœur fournit, et ce qu'il ne fournit pas

**Fourni** : les trois arguments, testés ; le plafond appliqué aux deux méthodes ; la garantie que
la géométrie garde le dernier mot — au-delà du talus de déblai, aucun plafond ne rend une cellule
constructible.

**Non fourni** : un barème de prix au m³ digne de ce nom, et un avis sur lequel des deux jeux de
tracés est le meilleur. Le second ne viendra pas du cœur — il viendra du terrain, ou pas.

---

## Annexe A — le §4 ne suffit pas : le cache ne compare rien

> Ajoutée par la session cœur du 2026-08-11, après lecture de
> `nemetonshiny/R/service_desserte.R` et `R/mod_desserte.R` (lecture seule).
> **Code non exécuté** : il n'a pas pu être testé dans l'app depuis cette session.

Le §4 dit que « le mécanisme d'invalidation ajouté pour `pondere_cout`
(`meta$pondere_cout`) est le bon endroit ». Ce mécanisme ne fait pas ce que la phrase suggère.

```r
.load_cached_desserte <- function(project_path) {   # <- un seul argument
  ...
  if (!isTRUE(meta$pondere_cout)) next               # <- gate a sens unique
  return(list(..., skidding_m = meta$skidding_m %||% NA_real_, ...))
}
```

Il ne **compare** aucun paramètre : il rejette les caches antérieurs à `pondere_cout = TRUE`, et
sert tout le reste tel quel. `skidding_m` est *rapporté* depuis `meta`, jamais confronté à la
valeur demandée.

**Conséquence, déjà vraie aujourd'hui** : changer `skidding_m` puis rouvrir l'onglet sert le
réseau précédent, calculé à l'ancienne distance. Le badge affichera d'ailleurs l'ancienne valeur —
donc rien ne trahit l'écart. Ajouter `methode_pente`, `largeur_m` et `pente_max_pct` à `meta`
n'y changerait rien tant que la fonction ne prend pas les paramètres demandés en entrée.

### A.1 Le correctif de fond

```r
# `.load_cached_desserte()` : comparer, pas seulement rapporter.
# Tout parametre qui change le RESULTAT doit invalider. `pondere_cout` reste un
# gate a part : c'est une rupture de compatibilite, pas un reglage.
.load_cached_desserte <- function(project_path, params = NULL) {
  ...
    if (!isTRUE(meta$pondere_cout)) next
    if (!is.null(params) && !.desserte_params_identiques(meta, params)) next
  ...
}

# Egalite sur les seuls champs qui changent le trace. Un cache SANS le champ
# (anterieur a son introduction) est traite comme divergent : on ne peut pas
# affirmer qu'il a ete calcule avec la valeur demandee.
.desserte_params_identiques <- function(meta, params) {
  for (nm in names(params)) {
    a <- meta[[nm]]; b <- params[[nm]]
    if (is.null(a)) return(FALSE)
    if (is.character(b) || is.character(a)) {
      if (!identical(as.character(a), as.character(b))) return(FALSE)
    } else if (!isTRUE(all.equal(as.numeric(a), as.numeric(b)))) {
      return(FALSE)
    }
  }
  TRUE
}
```

Aux deux appels (`mod_desserte.R:402` et `:439`), passer les valeurs **courantes des entrées** :

```r
params <- list(skidding_m    = input$dess_skidding,
               methode_pente = input$dess_methode_pente,
               largeur_m     = input$dess_largeur,
               pente_max_pct = input$dess_pente_max)
cached <- .load_cached_desserte(project_path, params)
```

`skidding_m` figure dans la liste : le défaut d'invalidation existe déjà pour lui, et le corriger
au passage coûte une ligne.

### A.2 Passe-plat dans `run_desserte()`

```r
run_desserte <- function(aoi_path, engine, cache_dir, buffer_m = 0,
                         skidding_m    = DESSERTE_SKIDDING_DEFAULT_M,
                         methode_pente = "bareme",
                         largeur_m     = 4,
                         pente_max_pct = 60) {
  ...
  cout <- tryCatch(
    foretaccess::surface_cout_construction(pre,
      methode_pente = methode_pente,
      largeur_m     = largeur_m,
      pente_max_pct = pente_max_pct),
    error = function(e) structure(list(msg = conditionMessage(e)), class = "acc_err"))
```

et dans le `meta` persisté, à côté de `skidding_m` et `pondere_cout` :

```r
  methode_pente = methode_pente,
  largeur_m     = largeur_m,
  pente_max_pct = pente_max_pct,
```

**Attention au défaut de `pente_max_pct`.** Le cœur accepte `NULL` et reprend alors le plafond
implicite du barème. Écrire `NULL` dans `meta` rendrait la comparaison A.1 ambiguë — `NULL` n'est
pas comparable et le cache serait invalidé à chaque fois. Poser `60` explicitement côté app est
plus simple, au prix d'un couplage : si le barème du cœur change sa dernière classe, la valeur
codée ici ne suivra pas. Le commentaire doit le dire.

### A.3 Les trois entrées

```r
shiny::radioButtons(ns("dess_methode_pente"), i18n$t("dess_methode_pente"),
  choices = c("bareme", "terrassement"), selected = "bareme", inline = TRUE),
shiny::helpText(i18n$t("dess_methode_pente_help")),

shiny::numericInput(ns("dess_largeur"), i18n$t("dess_largeur"),
                    value = 4, min = 2.5, max = 6, step = 0.5),

shiny::numericInput(ns("dess_pente_max"), i18n$t("dess_pente_max"),
                    value = 60, min = 0, max = 100, step = 5),
shiny::helpText(i18n$t("dess_pente_max_help"))
```

Le grisage de la largeur en mode barème (§2.2) — elle n'a d'effet qu'avec le terrassement :

```r
shiny::observeEvent(input$dess_methode_pente, {
  shinyjs::toggleState("dess_largeur",
                       condition = identical(input$dess_methode_pente, "terrassement"))
}, ignoreInit = FALSE)
```

Si `shinyjs` n'est pas déjà chargé dans le module, une `conditionalPanel` sur
`input.dess_methode_pente == 'terrassement'` évite la dépendance.

### A.4 Ce que cette annexe ne couvre pas

Les clés i18n (`dess_methode_pente`, `dess_largeur`, `dess_pente_max`, et les deux `_help`)
restent à écrire dans vos fichiers de traduction, avec les libellés d'aide du §2 — en particulier
l'avertissement du §2.3, que le brief demande explicitement de ne pas omettre.

Rien de tout ceci n'a été exécuté : c'est une proposition lue sur votre code, pas une livraison
testée.
