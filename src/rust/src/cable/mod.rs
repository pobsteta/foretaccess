//! Noyau cable (CableHelp) : mecanique de la catenaire elastique.
//!
//! Ce module porte la mecanique de travee de Sylvaccess v3.6 (GPL v3) : la
//! catenaire elastique (`catenaire`) et sa resolution par Newton-Raphson
//! (`newton`). La frontiere R<->Rust reste minimale et typee (ADR-001) : R
//! passe des scalaires `f64`, le crate resout, R oriente et agrege.

pub mod catenaire;
pub mod newton;
pub mod faisabilite;
pub mod supports;
pub mod optpyl;
pub mod ligne;
pub mod scan;
