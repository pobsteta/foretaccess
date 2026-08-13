# BRIEF `nemetonshiny` — le pire cas Overpass est désormais borné

> Réponse au `BRIEF-osm-overpass-unification.md`, §5.3.
> **À traiter dans une session de dev dédiée sur `/home/pascal/dev/nemetonshiny`.**
> **Rien à changer fonctionnellement** : vous appelez déjà le bon point d'entrée.
> Trois vérifications et un nettoyage.

## Ce qui change pour vous, sans que vous touchiez à quoi que ce soit

`foretaccess::acquire_desserte_osm()` garde **exactement** sa signature, son
filtrage (`track`, `unclassified`, `service`) et son cache. Seul le transport
change (ADR-010).

Ce que vous gagnez : **le pire cas est borné**. Avant, une instance Overpass
bridée faisait boucler `osmdata` en backoff de 60 s **sans plafond** — 16
reprises consécutives mesurées lors d'un test d'intégration, soit 16 minutes
d'attente pure, et plus de 10 minutes pour une requête ordinaire un jour de
bride. Désormais aucun appel ne peut dépasser
`timeout × length(serveurs) × (1 + max_reprises)`, soit **18 minutes au pire
absolu** et quelques secondes en nominal.

Ce que vous ne gagnez pas : la rapidité. 18 minutes reste long pour une
interface. **Ce qui change, c'est que l'appel termine** — au lieu de boucler
indéfiniment.

## Les trois vérifications

1. **L'appel est-il asynchrone et annulable ?** La doc de la fonction l'exige
   explicitement. Le pire cas est borné mais reste de l'ordre de la dizaine de
   minutes ; un bouton synchrone reste inacceptable.
2. **`osmdata` peut sortir de votre `DESCRIPTION`.** Vérifié de notre côté : il
   est déclaré (`Suggests`, ligne 25) mais **aucun appel `osmdata::` n'existe
   dans votre `R/`**. Nous l'avons retiré du nôtre pour la même raison. Confirmez
   avant de supprimer — nous n'avons pas inspecté vos `inst/` ni vos vignettes.
3. **Invalidation du cache.** Les sorties gagnent des colonnes de provenance
   (`date_requete`, `instance`, `requete`), et la couverture peut changer à la
   marge si la bissection remplace un tuilage. Vos caches OSM antérieurs sont à
   invalider — et c'est l'occasion de brancher cela sur le mécanisme que nous
   vous avons déjà signalé comme défaillant : `.load_cached_desserte()` ne
   compare aucun paramètre (cf. annexe A de
   `brief-nemetonshiny-couts-desserte-ui.md`).

## Ce à quoi il ne faut PAS toucher

Les **fonds de carte** — `leaflet::addProviderTiles("OpenStreetMap")`,
`maptiles::get_tiles()`. Ce sont des tuiles raster, sans rapport avec l'API
Overpass. Le brief d'origine le dit explicitement, et nous le répétons parce que
c'est le genre de confusion qui coûte une régression visuelle pour rien.

## Ce que vous pouvez exploiter, si vous le souhaitez

`osm_provenance()` rend `instance`, `requete`, `date_requete` et `nb_entites`
d'une réponse. Vos diagnostics de type `comparer_desserte_osm()` deviennent
**datables**, donc citables — deux exécutions à un mois d'écart ne sont plus
indiscernables. C'est disponible, pas obligatoire.
