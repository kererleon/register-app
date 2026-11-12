//! Teacher photos: found on the school's website (register_core::
//! teacher_photos), downloaded once, made small and kept on the device; and
//! own pictures for the brainrot look.

use std::cell::RefCell;
use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use register_core::model::Teacher;
use register_core::teacher_photos::{self, Photos};
use serde_json::{Value, json};
use slint::Image;

use crate::settings;

/// The photo list is searched again after a week, after three days when no
/// page was found.
const MAX_AGE: i64 = 7 * 24 * 3600;
const MAX_AGE_NOT_FOUND: i64 = 3 * 24 * 3600;

#[derive(Default)]
pub struct Store {
    pub photos: Photos,
    /// The staff page the photos come from.
    pub page: Option<String>,
    /// A staff page entered by hand (per school).
    pub custom_page: Option<String>,
    host: Option<String>,
    /// Photos being downloaded, so they are not fetched twice.
    loading: HashSet<String>,
}

pub static STORE: Mutex<Option<Store>> = Mutex::new(None);

fn photos_dir() -> PathBuf {
    settings::dir().join("teacher_photos")
}

fn cache_path(host: &str) -> PathBuf {
    settings::dir().join(format!("teacher_photos_{host}.json"))
}

fn file_for(url: &str) -> PathBuf {
    photos_dir().join(format!("{:016x}.png", crate::dart_random::string_hash(url) as u64 ^ url.len() as u64 * 0x9E37))
}

fn now() -> i64 {
    chrono::Local::now().timestamp()
}

/// Makes sure the photo list of the school at [register_url] is there:
/// from the cache, or searched on the website. Blocks; call it in the
/// background. Returns whether something new was loaded.
pub fn ensure(register_url: &str) -> bool {
    let Some(host) = url::Url::parse(register_url).ok().and_then(|u| u.host_str().map(str::to_owned)) else {
        return false;
    };
    let custom = settings::custom_staff_page(&host);
    {
        let mut guard = STORE.lock().unwrap();
        let store = guard.get_or_insert_with(Store::default);
        if store.host.as_deref() == Some(host.as_str()) && store.custom_page == custom && !store.photos.is_empty() {
            return false;
        }
    }
    // The cache, if it is fresh and for the same page.
    let cached: Option<Value> = std::fs::read(cache_path(&host)).ok().and_then(|b| serde_json::from_slice(&b).ok());
    if let Some(c) = &cached {
        let photos: Photos = serde_json::from_value(c["photos"].clone()).unwrap_or_default();
        let age = now() - c["time"].as_i64().unwrap_or(0);
        let max = if photos.is_empty() { MAX_AGE_NOT_FOUND } else { MAX_AGE };
        if c["custom"].as_str().map(str::to_owned) == custom && age < max {
            set(&host, custom, c["page"].as_str().map(str::to_owned), photos);
            return true;
        }
    }
    let (found, answered) = match &custom {
        Some(page) => {
            let (photos, answered) = teacher_photos::load_page(page);
            ((!photos.is_empty()).then(|| (page.clone(), photos)), answered)
        }
        None => teacher_photos::find_staff_page(&host),
    };
    // Offline: keep what there was.
    if found.is_none() && !answered {
        return false;
    }
    let (page, photos) = found.map(|(p, ph)| (Some(p), ph)).unwrap_or((None, Photos::new()));
    let _ = std::fs::create_dir_all(settings::dir());
    let _ = std::fs::write(
        cache_path(&host),
        json!({ "time": now(), "page": page, "custom": custom, "photos": photos }).to_string(),
    );
    set(&host, custom, page, photos);
    true
}

fn set(host: &str, custom: Option<String>, page: Option<String>, photos: Photos) {
    let mut guard = STORE.lock().unwrap();
    let store = guard.get_or_insert_with(Store::default);
    store.host = Some(host.to_owned());
    store.custom_page = custom;
    store.page = page;
    store.photos = photos;
}

/// Forgets the photo list of [register_url], so the next [ensure] searches.
pub fn forget(register_url: &str) {
    if let Some(host) = url::Url::parse(register_url).ok().and_then(|u| u.host_str().map(str::to_owned)) {
        let _ = std::fs::remove_file(cache_path(&host));
    }
    if let Some(store) = STORE.lock().unwrap().as_mut() {
        store.photos.clear();
        store.host = None;
    }
}

pub fn page() -> Option<String> {
    STORE.lock().unwrap().as_ref().and_then(|s| s.page.clone())
}

/// The photo URL of [teacher] on the staff page.
pub fn url_for(teacher: &Teacher) -> Option<String> {
    let guard = STORE.lock().unwrap();
    teacher_photos::photo_for(&guard.as_ref()?.photos, teacher)
}

/// Downloads the photos of [teachers] that are not on the device yet.
/// Blocks; returns whether any arrived.
pub fn download(teachers: &[Teacher]) -> bool {
    let urls: Vec<String> = {
        let mut guard = STORE.lock().unwrap();
        let Some(store) = guard.as_mut() else { return false };
        let urls: Vec<String> = teachers
            .iter()
            .filter_map(|t| teacher_photos::photo_for(&store.photos, t))
            .filter(|u| !file_for(u).exists() && !store.loading.contains(u))
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        store.loading.extend(urls.iter().cloned());
        urls
    };
    if urls.is_empty() {
        return false;
    }
    let _ = std::fs::create_dir_all(photos_dir());
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .user_agent("Mozilla/5.0 (Register-App)")
        .timeout_global(Some(Duration::from_secs(15)))
        .build()
        .into();
    let mut any = false;
    for url in &urls {
        let bytes = agent
            .get(url)
            .call()
            .ok()
            .and_then(|mut r| r.body_mut().with_config().limit(8 * 1024 * 1024).read_to_vec().ok());
        if let Some(bytes) = bytes
            && let Ok(img) = image::load_from_memory(&bytes)
        {
            // Photos are shown small: 200 px is plenty and saves memory.
            let small = img.thumbnail(200, 200);
            if small.save_with_format(file_for(url), image::ImageFormat::Png).is_ok() {
                any = true;
            }
        }
    }
    if let Some(store) = STORE.lock().unwrap().as_mut() {
        for u in &urls {
            store.loading.remove(u);
        }
    }
    any
}

thread_local! {
    static IMAGES: RefCell<HashMap<PathBuf, Image>> = RefCell::new(HashMap::new());
}

fn load(path: &Path) -> Option<Image> {
    if !path.exists() {
        return None;
    }
    IMAGES.with(|images| {
        let mut images = images.borrow_mut();
        if let Some(i) = images.get(path) {
            return Some(i.clone());
        }
        let image = Image::load_from_path(path).ok()?;
        images.insert(path.to_owned(), image.clone());
        Some(image)
    })
}

/// The picture of [teacher]: an own one in the brainrot look, else the
/// downloaded photo (UI thread).
pub fn image_for(teacher: &Teacher, own: &BTreeMap<String, String>, brainrot: bool) -> Option<Image> {
    if brainrot && let Some(path) = own.get(&teacher_photos::teacher_key(teacher)) {
        if let Some(i) = load(Path::new(path)) {
            return Some(i);
        }
    }
    load(&file_for(&url_for(teacher)?))
}

/// Lets the user choose an own picture for [teacher]; copied into the app's
/// folder. Returns the new path.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
pub fn pick_own(teacher: &Teacher) -> Option<String> {
    let file = rfd::FileDialog::new()
        .set_title(format!("Bild für {}", teacher.full_name()))
        .add_filter("Bilder", &["jpg", "jpeg", "png", "webp", "heic", "gif"])
        .pick_file()?;
    let img = image::open(&file).ok()?;
    let dir = settings::dir().join("teacher_images");
    std::fs::create_dir_all(&dir).ok()?;
    // A new name each time, so the picture cache shows the new one.
    let path = dir.join(format!("{}_{}.png", teacher_photos::teacher_key(teacher), now()));
    img.thumbnail(1400, 1400).save_with_format(&path, image::ImageFormat::Png).ok()?;
    Some(path.to_string_lossy().into_owned())
}

#[cfg(any(target_os = "android", target_os = "ios"))]
pub fn pick_own(_teacher: &Teacher) -> Option<String> {
    None
}
