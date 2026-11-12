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
    /// Line thickness of each subject in the grade chart (0 hides it).
    pub subject_thick: BTreeMap<String, i32>,
    /// Subjects left out of the overall average.
    pub ignored_subjects: Vec<String>,
    /// "Angemeldet bleiben": the login is kept on the device.
    pub remember: bool,
    /// "Daten lokal speichern".
    pub save_data: bool,
    pub delete_on_logout: bool,
    /// 0 follows the device, 1 light, 2 dark.
    pub theme_mode: i32,
    /// Homework framed in the subject's colour / lessons filled with it.
    pub color_borders: bool,
    pub calendar_color: bool,
    pub tests_red: bool,
    pub mark_new: bool,
    pub dedupe: bool,
    pub ask_delete: bool,
    pub show_diagram: bool,
    pub show_average: bool,
    /// Short names of subjects, in the order the user sees them.
    pub nicks: Vec<(String, String)>,
    pub nick_bar: bool,
    /// An own background picture and how much it is toned down.
    pub background: Option<String>,
    pub background_dim: f32,
}

/// The short names the app starts with.
const DEFAULT_NICKS: [(&str, &str); 12] = [
    ("Deutsch", "Deu"),
    ("Mathematik", "Mat"),
    ("Latein", "Lat"),
    ("Religion", "Rel"),
    ("Englisch", "Eng"),
    ("Naturwissenschaften", "Nat"),
    ("Geschichte", "Gesch"),
    ("Italienisch", "Ita"),
    ("Bewegung und Sport", "Sport"),
    ("Recht und Wirtschaft", "Rw"),
    ("Griechisch", "Gr"),
    ("FÜ", "Fü"),
];

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
            subject_thick: v["subjectThick"]
                .as_object()
                .map(|m| m.iter().filter_map(|(k, t)| Some((k.clone(), t.as_i64()? as i32))).collect())
                .unwrap_or_default(),
            ignored_subjects: v["ignoredSubjects"]
                .as_array()
                .map(|a| a.iter().filter_map(|x| x.as_str().map(str::to_owned)).collect())
                .unwrap_or_default(),
            remember: v["remember"].as_bool().unwrap_or(true),
            save_data: v["saveData"].as_bool().unwrap_or(true),
            delete_on_logout: v["deleteOnLogout"].as_bool().unwrap_or(false),
            theme_mode: v["themeMode"]
                .as_i64()
                .map(|m| m as i32)
                .unwrap_or(if v["dark"].as_bool().unwrap_or(true) { 2 } else { 1 }),
            color_borders: v["colorBorders"].as_bool().unwrap_or(false),
            calendar_color: v["calendarColor"].as_bool().unwrap_or(false),
            tests_red: v["testsRed"].as_bool().unwrap_or(true),
            mark_new: v["markNew"].as_bool().unwrap_or(true),
            dedupe: v["dedupe"].as_bool().unwrap_or(true),
            ask_delete: v["askDelete"].as_bool().unwrap_or(false),
            show_diagram: v["showDiagram"].as_bool().unwrap_or(true),
            show_average: v["showAverage"].as_bool().unwrap_or(true),
            nicks: v["nicks"]
                .as_array()
                .map(|a| {
                    a.iter().filter_map(|e| Some((e[0].as_str()?.to_owned(), e[1].as_str()?.to_owned()))).collect()
                })
                .unwrap_or_else(|| DEFAULT_NICKS.iter().map(|(a, b)| (a.to_string(), b.to_string())).collect()),
            nick_bar: v["nickBar"].as_bool().unwrap_or(true),
            background: v["background"].as_str().map(str::to_owned).filter(|p| std::path::Path::new(p).exists()),
            background_dim: v["backgroundDim"].as_f64().unwrap_or(0.6) as f32,
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
            "subjectThick": self.subject_thick,
            "ignoredSubjects": self.ignored_subjects,
            "remember": self.remember,
            "saveData": self.save_data,
            "deleteOnLogout": self.delete_on_logout,
            "themeMode": self.theme_mode,
            "colorBorders": self.color_borders,
            "calendarColor": self.calendar_color,
            "testsRed": self.tests_red,
            "markNew": self.mark_new,
            "dedupe": self.dedupe,
            "askDelete": self.ask_delete,
            "showDiagram": self.show_diagram,
            "showAverage": self.show_average,
            "nicks": self.nicks,
            "nickBar": self.nick_bar,
            "background": self.background,
            "backgroundDim": self.background_dim,
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
