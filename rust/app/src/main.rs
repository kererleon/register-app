// Register – Rust version. The program itself is in lib.rs, so that Android
// can start it as a library.

#![cfg_attr(all(not(debug_assertions), target_os = "windows"), windows_subsystem = "windows")]

fn main() -> Result<(), slint::PlatformError> {
    register::run()
}
