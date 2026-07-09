# Interface de stockage vectoriel (StorageBackend)

ForêtAccess écrit ses sorties vectorielles derrière une interface
commune, avec deux implémentations interchangeables : **GeoPackage**
([`storage_gpkg()`](https://pobsteta.github.io/foretaccess/reference/storage_gpkg.md))
et **PostGIS**
([`storage_postgis()`](https://pobsteta.github.io/foretaccess/reference/storage_postgis.md)).
Conformément à l'ADR-002, **aucun backend n'est le défaut** : il est
choisi explicitement à chaque usage. Les rasters ne passent pas par
cette interface (GeoTIFF/COG sur disque).

## Details

Contrat commun (méthodes S3) :

- [`sb_write_layer()`](https://pobsteta.github.io/foretaccess/reference/sb_write_layer.md)
  : écrit une couche (idempotent : remplace si elle existe) ;

- [`sb_read_layer()`](https://pobsteta.github.io/foretaccess/reference/sb_read_layer.md)
  : relit une couche ;

- [`sb_list_layers()`](https://pobsteta.github.io/foretaccess/reference/sb_list_layers.md)
  : liste les couches disponibles.
