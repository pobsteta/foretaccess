# Package index

## All functions

- [`agreger_zones()`](https://pobsteta.github.io/foretaccess/reference/agreger_zones.md)
  : Agrégation zonale des surfaces et volumes (Lot 8)

- [`cable_calcul_xs()`](https://pobsteta.github.io/foretaccess/reference/cable_calcul_xs.md)
  :

  Position horizontale du câble à l'abscisse curviligne `s`.

- [`cable_calcul_zs()`](https://pobsteta.github.io/foretaccess/reference/cable_calcul_zs.md)
  :

  Position verticale (chute depuis le support haut) à l'abscisse
  curviligne `s` : c'est elle qui fournit la garde au sol du câble.

- [`cable_check_droite()`](https://pobsteta.github.io/foretaccess/reference/cable_check_droite.md)
  :

  Pré-filtre géométrique : le câble est approximé par la corde entre
  supports moins une flèche analytique. Renvoie 1 si le profil
  `(line_x, line_z)` reste dans les gardes entre les indices `pg+1` et
  `pd-1`, 0 sinon. Sans supports intermédiaires (Lot 4b).

- [`cable_check_hlinemin()`](https://pobsteta.github.io/foretaccess/reference/cable_check_hlinemin.md)
  :

  Faisabilité complète d'une travée : la charge balaie la longueur, on
  résout les tensions à chaque position et on mesure la garde au sol.
  Renvoie la garde minimale rencontrée (m), ou `-1` si la travée est
  infaisable (garde hors `[hline_min, hline_max]` ou tension au-delà de
  `tmax + 1000`). Sans supports intermédiaires (Lot 4b).

- [`cable_f_x()`](https://pobsteta.github.io/foretaccess/reference/cable_f_x.md)
  :

  Equation horizontale de la caténaire élastique `f_x(Th, Tv)`, nulle à
  la solution.

- [`cable_f_z()`](https://pobsteta.github.io/foretaccess/reference/cable_f_z.md)
  :

  Equation verticale de la caténaire élastique `f_z(Th, Tv)`, nulle à la
  solution.

- [`cable_find_lomin()`](https://pobsteta.github.io/foretaccess/reference/cable_find_lomin.md)
  :

  Cherche la longueur à vide minimale `Lo` telle que la tension du
  câble, la charge au milieu, atteigne `tmax`, puis vérifie la garde au
  sol sur toute la travée. Renvoie un vecteur
  `c(faisable, Lo, Th, Tv, Tcalc, F)` ; `faisable` vaut 1 ou 0. Sans
  supports intermédiaires (Lot 4c).

- [`cable_find_thtv_tmax()`](https://pobsteta.github.io/foretaccess/reference/cable_find_thtv_tmax.md)
  :

  Amorçage `(Th, Tv, faisable)` par recherche sur grille sous la tension
  admissible. Renvoie un vecteur de longueur 3 ; `faisable` vaut 1 si
  `sqrt(Th^2 + Tv^2) <= tmax`, 0 sinon.

- [`cable_newton_thtv()`](https://pobsteta.github.io/foretaccess/reference/cable_newton_thtv.md)
  :

  Résout `f_x = f_z = 0` (tensions `Th, Tv` au support haut) par
  Newton-Raphson à Jacobien analytique, repli sur grille. Renvoie un
  vecteur `c(Th, Tv)`.

- [`cable_test_span()`](https://pobsteta.github.io/foretaccess/reference/cable_test_span.md)
  :

  Teste un segment de câble entre les points `pg` et `posi` du profil,
  portant des supports de hauteurs `hg` et `hd` : pré-filtre, pente dans
  `[slope_min, slope_max]`, contrainte d'angle au support intermédiaire
  (`angle_intsup`) vis-à-vis du segment précédent (`slope_prev`, `-9999`
  si aucun), puis `find_lomin`. Renvoie un vecteur
  `c(faisable, D, H, diag, slope, fact, Xup, Zup, Lo, Th, Tv, Tcalc, F)`.

- [`cablehelp_version()`](https://pobsteta.github.io/foretaccess/reference/cablehelp_version.md)
  :

  Version de la crate Rust `cablehelp` (noyau câble).

- [`calculer_terrain()`](https://pobsteta.github.io/foretaccess/reference/calculer_terrain.md)
  : Pente et exposition depuis un MNT

- [`camion_dfci()`](https://pobsteta.github.io/foretaccess/reference/camion_dfci.md)
  : Moteur camion DFCI — zone défendable (beta)

- [`certifier_propagation()`](https://pobsteta.github.io/foretaccess/reference/certifier_propagation.md)
  : Certificat d'exactitude d'une propagation sur une fenêtre

- [`chemin_optimal()`](https://pobsteta.github.io/foretaccess/reference/chemin_optimal.md)
  : Trajet optimal d'une cellule vers sa source

- [`coefficients_bascule()`](https://pobsteta.github.io/foretaccess/reference/coefficients_bascule.md)
  : Coefficients de la loi de bascule

- [`compare_to_oracle()`](https://pobsteta.github.io/foretaccess/reference/compare_to_oracle.md)
  : Compare une sortie à un oracle de non-régression

- [`conduire()`](https://pobsteta.github.io/foretaccess/reference/conduire.md)
  : Balayage radial de conduite du porteur

- [`decouper_emprise()`](https://pobsteta.github.io/foretaccess/reference/decouper_emprise.md)
  : Découper une emprise en tuiles avec halo

- [`distance_treuillage_max()`](https://pobsteta.github.io/foretaccess/reference/distance_treuillage_max.md)
  : Distance maximale de treuillage admissible

- [`fenetre_tuile()`](https://pobsteta.github.io/foretaccess/reference/fenetre_tuile.md)
  : Emprise d'une tuile

- [`foretaccess_config()`](https://pobsteta.github.io/foretaccess/reference/foretaccess_config.md)
  : Configuration métier de ForêtAccess (défauts Sylvaccess v3.6)

- [`lire_rasters()`](https://pobsteta.github.io/foretaccess/reference/lire_rasters.md)
  : Relit un prétraitement écrit sur disque

- [`ponderation_pente()`](https://pobsteta.github.io/foretaccess/reference/ponderation_pente.md)
  : Pondération de pente (facteur d'allongement 3D)

- [`porteur()`](https://pobsteta.github.io/foretaccess/reference/porteur.md)
  : Moteur d'accessibilité porteur (forwarder)

- [`potentiel_cable()`](https://pobsteta.github.io/foretaccess/reference/potentiel_cable.md)
  : Potentiel d'accessibilite par cable-mat (Lot 4d)

- [`preprocess()`](https://pobsteta.github.io/foretaccess/reference/preprocess.md)
  : Prétraitement commun aux moteurs d'accessibilité

- [`propager_cout()`](https://pobsteta.github.io/foretaccess/reference/propager_cout.md)
  : Propagation de coût cumulé depuis des sources (service partagé)

- [`read_config()`](https://pobsteta.github.io/foretaccess/reference/read_config.md)
  : Lit une configuration depuis un fichier YAML

- [`recapituler()`](https://pobsteta.github.io/foretaccess/reference/recapituler.md)
  : Tableau récapitulatif surfaces / volumes par classe

- [`sb_ensure_schema()`](https://pobsteta.github.io/foretaccess/reference/sb_ensure_schema.md)
  : Crée le schéma PostgreSQL du backend s'il n'existe pas

- [`sb_list_layers()`](https://pobsteta.github.io/foretaccess/reference/sb_list_layers.md)
  : Liste les couches disponibles

- [`sb_read_layer()`](https://pobsteta.github.io/foretaccess/reference/sb_read_layer.md)
  : Relit une couche vectorielle

- [`sb_write_layer()`](https://pobsteta.github.io/foretaccess/reference/sb_write_layer.md)
  : Écrit une couche vectorielle

- [`sb_write_layer(`*`<foretaccess_storage_postgis>`*`)`](https://pobsteta.github.io/foretaccess/reference/sb_write_layer.foretaccess_storage_postgis.md)
  : Écrit une couche en PostGIS (idempotent, index spatial)

- [`selectionner_lignes()`](https://pobsteta.github.io/foretaccess/reference/selectionner_lignes.md)
  : Selection multicritere des lignes cable (Lot 5)

- [`skidder()`](https://pobsteta.github.io/foretaccess/reference/skidder.md)
  : Moteur d'accessibilité skidder (débusqueur)

- [`storage`](https://pobsteta.github.io/foretaccess/reference/storage.md)
  : Interface de stockage vectoriel (StorageBackend)

- [`storage_gpkg()`](https://pobsteta.github.io/foretaccess/reference/storage_gpkg.md)
  : Backend de stockage GeoPackage

- [`storage_postgis()`](https://pobsteta.github.io/foretaccess/reference/storage_postgis.md)
  : Backend de stockage PostGIS

- [`surface_cout_skidder()`](https://pobsteta.github.io/foretaccess/reference/surface_cout_skidder.md)
  : Surface de coût du skidder (pondération de pente)

- [`terrain_roulable()`](https://pobsteta.github.io/foretaccess/reference/terrain_roulable.md)
  : Terrain roulable, indépendamment de la forêt

- [`traiter_par_tuiles()`](https://pobsteta.github.io/foretaccess/reference/traiter_par_tuiles.md)
  : Traiter une emprise par tuiles

- [`treuiller()`](https://pobsteta.github.io/foretaccess/reference/treuiller.md)
  : Distance de treuillage depuis la desserte (balayage radial)

- [`validate_config()`](https://pobsteta.github.io/foretaccess/reference/validate_config.md)
  : Valide un objet de configuration ForêtAccess

- [`valider_entrees()`](https://pobsteta.github.io/foretaccess/reference/valider_entrees.md)
  : Validation des entrées du prétraitement

- [`write_config()`](https://pobsteta.github.io/foretaccess/reference/write_config.md)
  : Écrit une configuration au format YAML

- [`zone_roulable_connectee()`](https://pobsteta.github.io/foretaccess/reference/zone_roulable_connectee.md)
  : Zone effectivement roulable, connectée à la desserte

- [`zone_roulage()`](https://pobsteta.github.io/foretaccess/reference/zone_roulage.md)
  : Zone de roulage du skidder

- [`zone_treuillable()`](https://pobsteta.github.io/foretaccess/reference/zone_treuillable.md)
  : Zone treuillable
