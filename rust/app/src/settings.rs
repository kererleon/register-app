//! Settings in a small file; the login in the system's secure store
//! (Keychain on macOS, Credential Manager on Windows).

use std::path::PathBuf;
use std::sync::OnceLock;

use serde_json::{Value, json};

#[cfg_attr(any(target_os = "android", target_os = "ios"), allow(dead_code))]
const SERVICE: &str = "Register-Rust";
#[cfg_attr(any(target_os = "android", target_os = "ios"), allow(dead_code))]
const ACCOUNT: &str = "login";

static DIR: OnceLock<PathBuf> = OnceLock::new();

/// Android gives the app its own private folder.
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
pub fn set_dir(dir: PathBuf) {
    let _ = DIR.set(dir);
}

pub fn dir() -> PathBuf {
    DIR.get_or_init(|| {
        // iOS: the app's own folder, encrypted while the iPhone is locked.
        #[cfg(target_os = "ios")]
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join("Library/Application Support");
        }
        directories::ProjectDirs::from("com", "webandgrow", "Register-Rust")
            .map(|d| d.data_dir().to_path_buf())
            .unwrap_or_else(|| std::env::temp_dir().join("register-rust"))
    })
    .clone()
}

pub struct Settings {
    pub dark: bool,
    /// The accent of the clean look, as 0xAARRGGBB.
    pub accent: u32,
    pub school: String,
}

impl Settings {
    fn path() -> PathBuf {
        dir().join("settings.json")
    }

    pub fn load() -> Settings {
        let v: Value = std::fs::read(Self::path())
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
            .unwrap_or(Value::Null);
        Settings {
            dark: v["dark"].as_bool().unwrap_or(true),
            accent: v["accent"].as_u64().map(|a| a as u32).unwrap_or(0xff5b6cff),
            school: v["school"].as_str().unwrap_or_default().to_owned(),
        }
    }

    pub fn save(&self) {
        let v = json!({ "dark": self.dark, "accent": self.accent, "school": self.school });
        let _ = std::fs::create_dir_all(dir());
        let _ = std::fs::write(Self::path(), v.to_string());
    }
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn entry() -> Option<keyring::Entry> {
    keyring::Entry::new(SERVICE, ACCOUNT).ok()
}

/// Android and iOS: the app's own folder, which only the app can read.
#[cfg(any(target_os = "android", target_os = "ios"))]
fn login_file() -> PathBuf {
    dir().join("login.json")
}

fn write_secret(secret: &str) {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if let Some(e) = entry() {
        let _ = e.set_password(secret);
    }
    #[cfg(any(target_os = "android", target_os = "ios"))]
    {
        let _ = std::fs::create_dir_all(dir());
        let _ = std::fs::write(login_file(), secret);
    }
}

fn read_secret() -> Option<String> {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    return entry()?.get_password().ok();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    return std::fs::read_to_string(login_file()).ok();
}

pub fn store_login(url: &str, user: &str, pass: &str) {
    write_secret(&json!({ "url": url, "user": user, "pass": pass }).to_string());
}

pub fn load_login() -> Option<(String, String, String)> {
    let v: Value = serde_json::from_str(&read_secret()?).ok()?;
    Some((
        v["url"].as_str()?.to_owned(),
        v["user"].as_str()?.to_owned(),
        v["pass"].as_str()?.to_owned(),
    ))
}

pub fn forget_login() {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    if let Some(e) = entry() {
        let _ = e.delete_credential();
    }
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let _ = std::fs::remove_file(login_file());
}
