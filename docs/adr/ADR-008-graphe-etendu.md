# ADR-008 — Graphe étendu à voisinage disque pour le tracé de desserte

- **Statut** : proposé — en attente de validation
- **Date** : 2026-07-16
- **Décideurs** : Pascal Obstetar
- **Sources** : lecture du code source **SylvaRoad** (S. Dupire / ONF, GPL v3) et **Forest Road
  Designer** (PANOimagen / Gob. La Rioja, GPL v3) ; **Chung & Sessions 2007** (*Improved road
  network design models…*, Can. J. For. Res.) ; comparaison avec **ForestRoadNetwork** (Klemet).

## Contexte

Le service least-cost existant (`propager_cout`/`.dijkstra`, Lot 2) opère en **8-connexité** :
huit voisins, huit directions. C'est suffisant pour l'**accessibilité/débardage** (déplacement
isotrope d'un engin), mais insuffisant pour **tracer une route** :

- la 8-connexité produit des **zigzags à 45°** (une droite en biais devient un escalier) ;
- elle ne permet ni **rayon de braquage** ni **pente en long** réalistes ;
- elle interdit les **virages doux** et la maîtrise des **épingles**.

Les deux outils de référence du tracé de desserte (SylvaRoad, FRD) et le modèle académique de
la famille (Chung & Sessions) convergent tous vers un **graphe à voisinage élargi** :

- Chung & Sessions : jusqu'à **48 liens / 16 directions** par cellule, plus MST/Steiner ;
- SylvaRoad / FRD : voisinage **disque paramétrable** (`D_neighborhood`), ~30-50 directions,
  angles dédupliqués, avec pénalités quadratiques de direction/pente et rayon de courbure.

## Décision

Pour la **conception de desserte** (Lots 15-18), adopter un **graphe étendu à voisinage disque
paramétrable**, distinct du service 8-connexe de l'accessibilité :

- nœud = **cellule** ; arêtes = tous les voisins dans le disque de rayon `D_neighborhood`,
  **dédupliqués par azimut** (une arête par direction distincte) ;
- filtrage amont des arêtes hors `[pente_long_min, pente_long_max]` (**contrainte dure**) ;
- coût de transition **anisotrope** : distance + pénalités quadratiques de changement de
  direction et de pente + gestion d'épingle (rayon `Radius`) + rayon de courbure minimal ;
- heuristique A\* = **distance-de-coût pré-calculée depuis la cible** (Dijkstra inverse).

Le service 8-connexe (Lot 2) **reste** pour l'accessibilité : il en est le cas dégénéré. Les
deux coexistent ; on ne casse rien.

## Conséquences

- Le solveur de tracé devient un **point chaud** : ~30-50 voisins par cellule dépilée, rappelé
  N fois par le réseau (Lot 16). → **portage Rust** (déclenche le réserve d'ADR-001), avec
  `rayon` au Lot 16/18 (tracés indépendants).
- Frontière R↔Rust : R passe coût/MNT/waypoints/paramètres en tableaux `f64`/`i32` ; Rust rend
  la suite d'indices du tracé + coût + faisabilité. Aucune logique SIG dans le crate (cohérent
  avec ADR-001/004).
- Mémoire : le voisinage disque multiplie le nombre d'arêtes ; la déduplication angulaire (FRD)
  le borne. `D_neighborhood` documenté avec ses effets.
- Non-régression : SylvaRoad (`meisenthal2`) et FRD servent d'oracles (ADR-006).

## Alternatives écartées

- **Rester en 8-connexité** (réutiliser `.dijkstra` tel quel) : zigzags, pas de rayon ni de
  pente en long → inadapté au tracé de route. Écarté.
- **16 directions fixes (Chung & Sessions strict)** : plus simple, mais moins général que le
  disque paramétrable de SylvaRoad/FRD ; on perd le réglage fin du lissage. Écarté au profit du
  disque, qui **contient** le cas 16 directions.
- **Graphe d'états (cellule, direction)** : théoriquement plus riche (mémoire de la direction
  dans le nœud), mais ×16 nœuds pour un gain marginal ici — les pénalités de direction sur
  arêtes suffisent (approche SylvaRoad/FRD, validée par leurs résultats). Reporté si besoin.
- **Tout R** : trop lent pour le point chaud à l'échelle massif. Écarté (portage Rust).
