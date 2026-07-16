//! Distance-de-cout inverse depuis la cible : l'heuristique `h` de l'A* (15b).
//!
//! Portage de `calcul_distance_de_cout` de SylvaRoad. Depuis la cellule cible, on
//! propage une **distance geometrique** (8-connexite, pas = resolution ou
//! `resolution * sqrt(2)` en diagonale) sur la **zone franchissable** (`zone == 1`).
//! Le cout d'un pas ne depend pas de la cellule (cout unitaire = distance) : la
//! valeur obtenue est donc une **borne inferieure** du cout reel restant, ce qui
//! rend `h` admissible et l'A* optimal (spec 015 §4.2, CA-15.8).
//!
//! SylvaRoad propage par vagues successives (algorithme correcteur d'etiquettes) ;
//! on emploie un Dijkstra a tas binaire, qui donne les **memes** distances (plus
//! court chemin exact) sans revisites inutiles.

use std::cmp::Ordering;
use std::collections::BinaryHeap;

/// Etat de la file de priorite : distance cumulee croissante (tas-min via `Ord`
/// inverse). `f64` n'etant pas `Ord`, on compare par `total_cmp`.
struct State {
    dist: f64,
    idx: usize,
}

impl PartialEq for State {
    fn eq(&self, other: &Self) -> bool {
        self.dist == other.dist
    }
}
impl Eq for State {}
impl PartialOrd for State {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for State {
    fn cmp(&self, other: &Self) -> Ordering {
        // Tas-min : la plus petite distance en tete (ordre inverse), depart des
        // egalites stable par indice pour un resultat deterministe (CA-15.9).
        other
            .dist
            .total_cmp(&self.dist)
            .then_with(|| other.idx.cmp(&self.idx))
    }
}

/// Distance-de-cout depuis `(y_end, x_end)` sur la grille `nr x nc` (aplatie
/// ligne par ligne). `zone[i] == 1` = cellule franchissable. Renvoie une grille
/// `f64` : `0` a la cible, la distance cumulee ailleurs, et `NaN` pour les
/// cellules non atteintes ou au-dela de `max_distance` (sentinelle `-9999` de
/// SylvaRoad, rendue en `NaN` pour la couche SIG).
pub fn dist_to_end(
    zone: &[i32],
    nr: usize,
    nc: usize,
    csize: f64,
    y_end: usize,
    x_end: usize,
    max_distance: f64,
) -> Vec<f64> {
    let n = nr * nc;
    let mut out = vec![f64::NAN; n];
    if y_end >= nr || x_end >= nc {
        return out;
    }

    // 8 voisins et leur pas planimetrique.
    let offsets: [(i32, i32); 8] = [
        (-1, -1),
        (-1, 0),
        (-1, 1),
        (0, -1),
        (0, 1),
        (1, -1),
        (1, 0),
        (1, 1),
    ];
    let step: [f64; 8] = offsets.map(|(dr, dc)| ((dr * dr + dc * dc) as f64).sqrt() * csize);

    let start = y_end * nc + x_end;
    let mut best = vec![f64::INFINITY; n];
    best[start] = 0.0;
    let mut heap = BinaryHeap::new();
    heap.push(State {
        dist: 0.0,
        idx: start,
    });

    while let Some(State { dist, idx }) = heap.pop() {
        if dist > best[idx] {
            continue; // entree perimee
        }
        let y = (idx / nc) as i32;
        let x = (idx % nc) as i32;
        for k in 0..8 {
            let (dr, dc) = offsets[k];
            let y1 = y + dr;
            let x1 = x + dc;
            if y1 < 0 || y1 >= nr as i32 || x1 < 0 || x1 >= nc as i32 {
                continue;
            }
            let j = (y1 as usize) * nc + (x1 as usize);
            if zone[j] != 1 {
                continue; // hors zone franchissable
            }
            let nd = dist + step[k];
            if nd > max_distance {
                continue;
            }
            if nd < best[j] {
                best[j] = nd;
                heap.push(State { dist: nd, idx: j });
            }
        }
    }

    for i in 0..n {
        if best[i].is_finite() {
            out[i] = best[i];
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn end_is_zero_and_reaches_all() {
        // Zone 3x3 toute franchissable, cible au centre.
        let zone = vec![1; 9];
        let d = dist_to_end(&zone, 3, 3, 10.0, 1, 1, 1e9);
        assert_eq!(d[4], 0.0); // centre
        assert!((d[1] - 10.0).abs() < 1e-9); // dessus (orthogonal)
        assert!((d[0] - (10.0 * 2f64.sqrt())).abs() < 1e-9); // coin (diagonale)
    }

    #[test]
    fn obstacle_column_blocks_and_detours() {
        // Colonne du milieu infranchissable : la cible (gauche) n'atteint pas la
        // colonne de droite (mur complet vertical dans une grille 3x3).
        let mut zone = vec![1; 9];
        zone[1] = 0;
        zone[4] = 0;
        zone[7] = 0;
        let d = dist_to_end(&zone, 3, 3, 10.0, 1, 0, 1e9);
        assert_eq!(d[3], 0.0);
        assert!(d[5].is_nan()); // droite, coupee par le mur
        assert!(d[2].is_nan());
    }

    #[test]
    fn max_distance_caps() {
        let zone = vec![1; 25];
        let d = dist_to_end(&zone, 5, 5, 10.0, 0, 0, 15.0);
        // Coin oppose (>15 m) non atteint.
        assert!(d[24].is_nan());
        assert!(d[1].is_finite());
    }

    #[test]
    fn deterministic() {
        let zone = vec![1; 16];
        let a = dist_to_end(&zone, 4, 4, 5.0, 2, 2, 1e9);
        let b = dist_to_end(&zone, 4, 4, 5.0, 2, 2, 1e9);
        assert_eq!(a, b);
    }
}
