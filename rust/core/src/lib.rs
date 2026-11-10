//! Register: the core of the app without its user interface. Talks to the
//! Digitales Register, reads its answers and prepares them (averages,
//! absences over the school year, tests …).

pub mod absences;
pub mod client;
pub mod data;
pub mod demo;
pub mod grades;
pub mod json;
pub mod model;
pub mod parse;
pub mod schools;
