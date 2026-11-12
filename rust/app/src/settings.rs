//! Settings in a small file; the login in the system's secure store
//! (Keychain on macOS, Credential Manager on Windows).

use std::collections::BTreeMap;
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
    /// 0 Holo, 1 Brainrot, 2 Israel, 3 Clean, 4 Liquid Glass.
    pub style: i32,
    pub dark: bool,
    /// The accent of the clean look, as 0xAARRGGBB.
    pub accent: u32,
    pub school: String,
    /// Each subject keeps the colour it got first (0xRRGGBB).
    pub subject_colors: BTreeMap<String, u32>,
    /// Teacher photos in the calendar.
    pub show_photos: bool,
    /// Own pictures of teachers (brainrot), by teacher key.
    pub own_images: BTreeMap<String, String>,
    /// Staff pages entered by hand, by register host.
    pub staff_pages: BTreeMap<String, String>,
}

/// The staff page entered by hand for the school at [host].
pub fn custom_staff_page(host: &str) -> Option<String> {
    Settings::load().staff_pages.get(host).cloned()
}

/// Material's primary colours without the ones that look alike, as the
/// Flutter app assigns them; the look-alikes come last.
const SUBJECT_COLORS: [u32; 18] = [
    0xF44336, 0xE91E63, 0x9C27B0, 0x673AB7, 0x3F51B5, 0x2196F3, 0x009688, 0x4CAF50, 0x8BC34A, 0xFFEB3B,
    0xFF9800, 0xFF5722, 0x795548, 0x607D8B, 0xCDDC39, 0x03A9F4, 0x00BCD4, 0xFFC107,
];

impl Settings {
    /// The colour of [subject]; new subjects get the next free one.
    pub fn subject_color(&mut self, subject: &str) -> u32 {
        if let Some(&c) = self.subject_colors.get(subject) {
            return c;
        }
        let used: Vec<u32> = self.subject_colors.values().copied().collect();
        let c = SUBJECT_COLORS
            .iter()
            .copied()
            .find(|c| !used.contains(c))
            .unwrap_or(SUBJECT_COLORS[self.subject_colors.len() % SUBJECT_COLORS.len()]);
        self.subject_colors.insert(subject.to_owned(), c);
        c
    }
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
            style: v["style"].as_i64().unwrap_or(0) as i32,
            dark: v["dark"].as_bool().unwrap_or(true),
            accent: v["accent"].as_u64().map(|a| a as u32).unwrap_or(0xff2563eb),
            school: v["school"].as_str().unwrap_or_default().to_owned(),
            show_photos: v["showPhotos"].as_bool().unwrap_or(true),
            own_images: v["ownImages"]
                .as_object()
                .map(|m| m.iter().filter_map(|(k, p)| Some((k.clone(), p.as_str()?.to_owned()))).collect())
                .unwrap_or_default(),
            staff_pages: v["staffPages"]
                .as_object()
                .map(|m| m.iter().filter_map(|(k, p)| Some((k.clone(), p.as_str()?.to_owned()))).collect())
                .unwrap_or_default(),
            subject_colors: v["subjectColors"]
                .as_object()
                .map(|m| m.iter().filter_map(|(k, c)| Some((k.clone(), c.as_u64()? as u32))).collect())
                .unwrap_or_default(),
        }
    }

    pub fn save(&self) {
        let v = json!({
            "style": self.style,
            "dark": self.dark,
            "accent": self.accent,
            "school": self.school,
            "subjectColors": self.subject_colors,
            "showPhotos": self.show_photos,
            "ownImages": self.own_images,
            "staffPages": self.staff_pages,
        });
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
