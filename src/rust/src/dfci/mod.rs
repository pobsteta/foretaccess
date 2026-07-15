//! Noyau DFCI : balayage radial de la zone defendable par les pompiers.
//!
//! Porte la mecanique de `debusq_dfci` de Sylvaccess v3.6 (GPL v3) : depuis
//! chaque pixel du reseau DFCI, un lancer de rayons 360 deg / 1 deg deroule une
//! **lance** qui epouse le relief (`Lcum += sqrt(dh^2 + ddist^2)`), plafonnee a
//! `dfci_lmax`, arretee par la pente, un obstacle ou le bord. Pas de Dijkstra
//! pondere (le chemin `calc_dist_dfci` est desactive chez Sylvaccess). La
//! frontiere R<->Rust reste minimale et typee (ADR-001) : R rasterise sources,
//! pente et obstacles, le crate balaie, R assemble les sorties SIG.

pub mod scan;
