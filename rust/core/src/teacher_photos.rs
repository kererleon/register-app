//! Photos of the teachers from the staff page of the school's website,
//! matched by name (port of the Flutter app's lib/teacher_photos.dart). The
//! page is found from the register's address or entered in the settings.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::sync::LazyLock;
use std::time::Duration;

use regex::Regex;
use url::Url;

use crate::model::Teacher;

/// Staff pages that are known to work, by the register's subdomain.
const KNOWN_STAFF_PAGES: &[(&str, &str)] = &[
    ("fallmerayer", "https://www.fallmerayer.it/schule/personen/"),
    ("tfo-bruneck", "https://www.tfo-bruneck.it/mitarbeiter/"),
];

/// Websites of schools whose address differs from the register subdomain.
/// For all others the website is guessed ("osz-schlanders" -> osz-schlanders.it).
const SCHOOL_WEBSITES: &[(&str, &str)] = &[
    ("cademia", "https://www.cademia.it/de/"),
    ("cusanus-gymnasium", "https://www.cusanus-gymnasium.it/"),
    ("fs-dietenheim", "https://www.fachschule-dietenheim.it/"),
    ("fstisens", "https://www.fachschule-tisens.it/"),
    ("fs-fuerstenburg", "https://www.fachschule-fuerstenburg.it/"),
    ("fs-kortsch", "https://www.fachschule-kortsch.it/"),
    ("fslaimburg", "https://www.fachschule-laimburg.it/de"),
    ("fachschule-neumarkt", "https://www.fachschule-neumarkt.it/"),
    ("fo-brixen", "https://fo-brixen.it/"),
    ("fos-meran", "https://fos-meran.it/"),
    ("franziskanergymnasium", "https://www.franziskanergymnasium.it/"),
    ("sowikunstgym-bruneck", "https://www.sowikunstgymbruneck.it/"),
    ("gymme", "https://www.gymme.it/"),
    ("vogelweide", "https://www.gymnasium.bz.it/"),
    ("gymnasiumbrixen", "https://www.gymnasiumbrixen.it/"),
    ("herzjesu-institut", "https://herzjesu-institut.it/"),
    ("ite-raetia", "https://www.iteraetia.it/"),
    ("kaiserhof", "https://www.kaiserhof.berufsschule.it/de/"),
    ("lbs-schlanders", "https://www.schlanders.berufsschule.it/"),
    ("lbszuegg", "https://www.zuegg.berufsschule.it/de"),
    ("lhfsbruneck", "https://www.lhfs-bruneck.berufsschule.it/de/home"),
    ("mariengarten", "https://www.mariengarten.it/internatsschule/"),
    ("mhg", "https://www.mhgym.it/"),
    ("osz-sterzing", "https://www.oberschulzentrum-sterzing.eu/"),
    ("oflauer", "https://ofl-auer.it/"),
    ("wfoauer", "https://wfo-auer.it/"),
    ("rg-fob", "https://www.campusfagen.com/"),
    ("rgtfo-me", "https://www.rg-me.it/"),
    ("sogym-fotour", "https://www.sogym.bz.it/"),
    ("sz-sand", "https://www.sz-sandintaufers.it/"),
    ("tfobz", "https://www.tfobz.it/"),
    ("ursulinen", "https://www.ursulinen.it/"),
    ("vinzentinum", "https://www.vinzentinum.it/"),
    ("wfobz", "https://www.wfo.bz.it/"),
    ("wfo-bruneck", "https://www.wfo-bruneck.info/"),
    ("wfokafka", "https://www.wfokafka.it/"),
    ("wob", "https://wob.education/"),
    ("bbz", "https://www.bruneck.berufsschule.it/de/"),
];

/// Words in links that lead to a staff page (German and Italian).
const STAFF_WORDS: [&str; 12] = [
    "mitarbeiter", "personen", "lehrpersonen", "lehrer", "kollegium", "personal", "team", "docenti", "insegnanti",
    "personale", "collegio", "staff",
];

/// Tried directly when the homepage links to nothing helpful.
const COMMON_PATHS: [&str; 8] =
    ["mitarbeiter/", "personen/", "schule/personen/", "lehrpersonen/", "kollegium/", "team/", "personale/", "docenti/"];

/// Name on the staff page -> photo URL.
pub type Photos = BTreeMap<String, String>;

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .user_agent("Mozilla/5.0 (Register-App)")
        .timeout_global(Some(Duration::from_secs(10)))
        .http_status_as_error(false)
        .build()
        .into()
}

/// An HTML page, or None (not found, not HTML, too big, offline). The bool
/// says whether the website answered at all.
fn fetch(agent: &ureq::Agent, url: &str, answered: &mut bool) -> Option<String> {
    let mut response = agent.get(url).call().ok()?;
    *answered = true;
    if response.status() != 200 {
        return None;
    }
    let html = response
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .is_none_or(|t| t.contains("html"));
    if !html {
        return None;
    }
    // Real staff pages are far smaller; this keeps memory use low.
    response.body_mut().with_config().limit(4 * 1024 * 1024).read_to_string().ok()
}

fn bare_host(host: &str) -> &str {
    host.strip_prefix("www.").unwrap_or(host)
}

fn decode_entities(s: &str) -> String {
    crate::json::decode_entities(s).replace("&#8217;", "’")
}

static LINK: LazyLock<Regex> = LazyLock::new(|| Regex::new(r##"(?is)<a\b[^>]*href="([^"#]+)"[^>]*>(.*?)</a>"##).unwrap());
static TAG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"<[^>]*>").unwrap());
static IMG: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)<img\b[^>]*>").unwrap());
static PHOTO_PATH: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)\.(jpe?g|png|webp)$").unwrap());
static SPACES: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"\s+").unwrap());
static NOT_NAME: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[\d@:/|©]").unwrap());
static NAME_WORD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-ZÄÖÜÀ-Ý][\p{L}'’.-]*$").unwrap());
static FILE_WORD: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[\p{L}'’.-]+$").unwrap());
static SIZE_SUFFIX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"-?\d+x\d+$").unwrap());
static NUMBER_SUFFIX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[-_]+\d*$").unwrap());
static DASHES: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"[-_]+").unwrap());

fn attr(tag: &str, name: &str) -> Option<String> {
    let re = Regex::new(&format!(r#"(?i)\s{name}\s*=\s*["']([^"']*)["']"#)).ok()?;
    re.captures(tag).map(|c| c[1].to_owned())
}

/// Links on [html] that lead to a staff page of the same website, best first.
fn staff_links(html: &str, base: &Url) -> Vec<String> {
    let mut scored: HashMap<String, usize> = HashMap::new();
    let mut order: Vec<String> = Vec::new();
    for m in LINK.captures_iter(html) {
        let Ok(url) = base.join(&decode_entities(m[1].trim())) else { continue };
        if !url.scheme().starts_with("http")
            || bare_host(url.host_str().unwrap_or("")) != bare_host(base.host_str().unwrap_or(""))
        {
            continue;
        }
        let text = format!("{} {}", url.path(), TAG.replace_all(&m[2], " ")).to_lowercase();
        let score = STAFF_WORDS.iter().filter(|w| text.contains(*w)).count();
        if score == 0 {
            continue;
        }
        let mut clean = url.clone();
        clean.set_query(None);
        clean.set_fragment(None);
        let key = clean.to_string();
        if !scored.contains_key(&key) {
            order.push(key.clone());
        }
        *scored.entry(key).or_default() += score;
    }
    order.sort_by(|a, b| scored[b].cmp(&scored[a]));
    order
}

fn looks_like_name(text: &str, from_file: bool) -> bool {
    let len = text.chars().count();
    if !(4..=60).contains(&len) || NOT_NAME.is_match(text) {
        return false;
    }
    let words: Vec<&str> = text.split(' ').filter(|w| !w.is_empty()).collect();
    if !(2..=5).contains(&words.len()) {
        return false;
    }
    const PARTICLES: [&str; 8] = ["von", "van", "der", "de", "di", "da", "del", "dal"];
    words.iter().all(|w| {
        PARTICLES.contains(&w.to_lowercase().as_str())
            || NAME_WORD.is_match(w)
            || (from_file && FILE_WORD.is_match(w))
    })
}

/// Reads "name -> photo URL" from a staff page. Every photo is paired with
/// the first text after it that looks like a name, or else its alt text or
/// file name. Images used many times (placeholders) and icons are skipped.
pub fn parse_staff_page(html: &str, page_url: &str) -> Photos {
    let Ok(base) = Url::parse(page_url) else { return Photos::new() };
    struct Photo {
        start: usize,
        end: usize,
        url: String,
        alt: String,
    }
    let mut photos: Vec<Photo> = Vec::new();
    let mut uses: HashMap<String, usize> = HashMap::new();
    for m in IMG.find_iter(html) {
        let tag = m.as_str();
        let src = ["data-src", "data-lazy-src", "data-original", "src"]
            .iter()
            .filter_map(|a| attr(tag, a))
            .find(|s| !s.is_empty() && !s.starts_with("data:"));
        let Some(src) = src else { continue };
        let Ok(url) = base.join(&decode_entities(src.trim())) else { continue };
        if !PHOTO_PATH.is_match(url.path()) {
            continue;
        }
        let address = url.to_string();
        *uses.entry(address.clone()).or_default() += 1;
        photos.push(Photo {
            start: m.start(),
            end: m.end(),
            url: address,
            alt: decode_entities(&attr(tag, "alt").unwrap_or_default()).trim().to_owned(),
        });
    }
    let mut result = Photos::new();
    for (i, photo) in photos.iter().enumerate() {
        if uses[&photo.url] > 2 {
            continue; // a placeholder
        }
        let next = photos.get(i + 1).map(|p| p.start).unwrap_or(html.len());
        let mut stop = next.clamp(photo.end, photo.end + 3000).min(html.len());
        while !html.is_char_boundary(stop) {
            stop -= 1;
        }
        let between = &html[photo.end..stop];
        let name = TAG
            .split(between)
            .map(|t| SPACES.replace_all(&decode_entities(t), " ").trim().to_owned())
            .find(|t| looks_like_name(t, false));
        if let Some(name) = name {
            result.insert(name, photo.url.clone());
        } else if looks_like_name(&photo.alt, false) {
            result.insert(photo.alt.clone(), photo.url.clone());
        } else {
            let last = photo.url.rsplit('/').next().unwrap_or("");
            let decoded = url::form_urlencoded::parse(last.as_bytes())
                .map(|(k, v)| if v.is_empty() { k.into_owned() } else { format!("{k}={v}") })
                .collect::<String>();
            let file = PHOTO_PATH.replace(&decoded, "");
            let file = SIZE_SUFFIX.replace(&file, "");
            let file = NUMBER_SUFFIX.replace(&file, "");
            let file = DASHES.replace_all(&file, " ").trim().to_owned();
            if looks_like_name(&file, true) {
                result.insert(file, photo.url.clone());
            }
        }
    }
    result
}

/// Searches the school's website for its staff page: the homepage comes from
/// a list or is guessed from the register's subdomain, then links that sound
/// like a staff page are tried. Returns the page with the most photos, and
/// whether any website answered (if not, the device was offline).
pub fn find_staff_page(register_host: &str) -> (Option<(String, Photos)>, bool) {
    let agent = agent();
    let mut answered = false;
    let school = register_host.split('.').next().unwrap_or("").to_lowercase();
    if let Some((_, known)) = KNOWN_STAFF_PAGES.iter().find(|(s, _)| *s == school) {
        if let Some(html) = fetch(&agent, known, &mut answered) {
            let photos = parse_staff_page(&html, known);
            if !photos.is_empty() {
                return (Some((known.to_string(), photos)), true);
            }
        }
    }
    let mut homes: Vec<String> = Vec::new();
    if let Some((_, website)) = SCHOOL_WEBSITES.iter().find(|(s, _)| *s == school) {
        homes.push(website.to_string());
    }
    homes.push(format!("https://www.{school}.it/"));
    homes.push(format!("https://{school}.it/"));
    if school.contains('-') {
        homes.push(format!("https://www.{}.it/", school.replace('-', "")));
    }
    let mut seen = HashSet::new();
    for home in homes.into_iter().filter(|h| seen.insert(h.clone())) {
        let Ok(home_url) = Url::parse(&home) else { continue };
        let Some(html) = fetch(&agent, &home, &mut answered) else { continue };
        let mut candidates = staff_links(&html, &home_url);
        for path in COMMON_PATHS {
            if let Ok(u) = home_url.join(path) {
                let u = u.to_string();
                if !candidates.contains(&u) {
                    candidates.push(u);
                }
            }
        }
        let mut best: Option<(String, Photos)> = None;
        // A handful of pages at most, so the search stays light.
        for candidate in candidates.into_iter().take(12) {
            let Some(page) = fetch(&agent, &candidate, &mut answered) else { continue };
            let photos = parse_staff_page(&page, &candidate);
            if photos.len() > best.as_ref().map(|b| b.1.len()).unwrap_or(0) {
                best = Some((candidate, photos));
            }
            if best.as_ref().is_some_and(|b| b.1.len() >= 20) {
                break;
            }
        }
        if let Some(best) = best.filter(|b| b.1.len() >= 3) {
            return (Some(best), true);
        }
    }
    (None, answered)
}

/// The photos from a page entered by hand.
pub fn load_page(url: &str) -> (Photos, bool) {
    let mut answered = false;
    let photos = fetch(&agent(), url, &mut answered).map(|h| parse_staff_page(&h, url)).unwrap_or_default();
    (photos, answered)
}

const PLAIN: [(&str, &str); 14] = [
    ("ä", "a"), ("ö", "o"), ("ü", "u"), ("ß", "ss"), ("à", "a"), ("á", "a"), ("è", "e"), ("é", "e"), ("ì", "i"),
    ("í", "i"), ("ò", "o"), ("ó", "o"), ("ù", "u"), ("ú", "u"),
];

/// Lower-case name parts without accents and initials like "M.".
pub fn name_parts(name: &str) -> Vec<String> {
    let mut n = name.to_lowercase();
    for (k, v) in PLAIN {
        n = n.replace(k, v);
    }
    let mut parts: Vec<String> = n
        .split(|c: char| !c.is_ascii_lowercase())
        .filter(|p| p.len() > 1)
        .map(str::to_owned)
        .collect();
    parts.sort();
    parts.dedup();
    parts
}

/// Like [name_parts], but "oe" and "ö" are the same, as in file names.
fn match_parts(name: &str) -> HashSet<String> {
    name_parts(name).into_iter().map(|p| p.replace("ae", "a").replace("oe", "o").replace("ue", "u")).collect()
}

/// The photo of [teacher], matched by last and first name; names on the
/// page come in either order. Without a matching first name only a unique
/// last name counts, and another first name means another person.
pub fn photo_for(photos: &Photos, teacher: &Teacher) -> Option<String> {
    let last = match_parts(&teacher.last_name);
    let first = match_parts(&teacher.first_name);
    if last.is_empty() {
        return None;
    }
    let mut only_last = None;
    let mut count = 0;
    for (name, url) in photos {
        let parts = match_parts(name);
        if !last.is_subset(&parts) {
            continue;
        }
        if !first.is_empty() && first.iter().any(|f| parts.contains(f)) {
            return Some(url.clone());
        }
        if !first.is_empty() && parts.difference(&last).next().is_some() {
            continue;
        }
        only_last = Some(url.clone());
        count += 1;
    }
    if count == 1 { only_last } else { None }
}

/// The key for own pictures of a teacher.
pub fn teacher_key(teacher: &Teacher) -> String {
    format!("{}_{}", name_parts(&teacher.last_name).join("-"), name_parts(&teacher.first_name).join("-"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(first: &str, last: &str) -> Teacher {
        Teacher { first_name: first.into(), last_name: last.into() }
    }

    #[test]
    fn fallmerayer_layout() {
        let html = r#"<ul class="plist-container"><li class="plist-item"><figure><img src="../../wp-content/uploads/2020/09/Augschoell-Josef-357x500.jpg" alt=""></figure><figcaption><p>Josef Augschöll</p></figcaption></li><li class="plist-item"><figure><img src="../../wp-content/uploads/2026/10/person-belchr.webp" alt=""></figure><figcaption><p>Belloni M. Cristina</p></figcaption></li></ul>"#;
        let photos = parse_staff_page(html, "https://www.fallmerayer.it/schule/personen/");
        assert_eq!(photos.len(), 2);
        assert_eq!(
            photos["Josef Augschöll"],
            "https://www.fallmerayer.it/wp-content/uploads/2020/09/Augschoell-Josef-357x500.jpg"
        );
        assert!(photo_for(&photos, &t("Josef", "Augschöll")).is_some());
        assert!(photo_for(&photos, &t("Cristina", "Belloni")).unwrap().contains("person-belchr"));
        assert!(photo_for(&photos, &t("Anna", "Müller")).is_none());
    }

    #[test]
    fn lazy_loading_placeholders_and_relatives() {
        let card = |img: &str, name: &str| format!(
            r#"<div class="employe-box"><a href="{img}"><img data-src="{img}" src="data:image/svg+xml;base64,AA" class="lazyload"></a><a href="mailto:x@schule.suedtirol.it"><img data-src="/wp-content/uploads/mailicon.svg" alt="social"></a><h5> {name}</h5></div>"#
        );
        let block = "/wp-content/uploads/2024/10/Block.png";
        let html = [
            card("/wp-content/uploads/2024/09/Kaser-Silvia.jpg", "Kaser Silvia"),
            card(block, "Vizedirektor"),
            card("/wp-content/uploads/2023/10/Egger_Philipp.jpg", "Egger Philipp Christoph"),
            card(block, "Lehrerkollegium"),
            r#"<div class="employe-box"><h5> Abfalterer Annemarie</h5></div>"#.to_owned(),
            card(block, "Sekretariat"),
            card("/wp-content/uploads/2023/10/Abfalterer_Siegfried-1.jpg", "Abfalterer Siegfried"),
        ]
        .join("\n");
        let photos = parse_staff_page(&html, "https://www.tfo-bruneck.it/mitarbeiter/");
        let mut names: Vec<&str> = photos.keys().map(String::as_str).collect();
        names.sort();
        assert_eq!(names, ["Abfalterer Siegfried", "Egger Philipp Christoph", "Kaser Silvia"]);
        assert!(photo_for(&photos, &t("Annemarie", "Abfalterer")).is_none());
        assert!(photo_for(&photos, &t("Siegfried", "Abfalterer")).unwrap().contains("Siegfried"));
    }

    #[test]
    fn names_from_file_names() {
        let photos = parse_staff_page(r#"<img src="/bilder/Augschoell-Josef-357x500.jpg">"#, "https://schule.example/team/");
        assert!(photo_for(&photos, &t("Josef", "Augschöll")).is_some());
    }
}

#[cfg(test)]
mod live {
    /// Asks the real school websites: `cargo test -- --ignored live`.
    #[test]
    #[ignore]
    fn live_staff_pages() {
        for host in ["fallmerayer.digitalesregister.it", "tfo-bruneck.digitalesregister.it", "gymme.digitalesregister.it"] {
            let (found, answered) = super::find_staff_page(host);
            let (page, photos) = found.expect(host);
            println!("{host}: {} Fotos auf {page} (Antwort: {answered})", photos.len());
            assert!(photos.len() >= 3);
        }
    }
}
