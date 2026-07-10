# Normalisation des entrées (chemin ou objet)

Le prétraitement accepte chaque entrée soit comme **chemin de fichier**,
soit comme **objet déjà chargé** (`SpatRaster` pour les rasters, `sf`
pour les vecteurs). Ces helpers internes uniformisent l'accès, pour
rester testable et découplé de l'I/O (ADR-004).
