//! The faint pattern of subject icons behind the calendar tiles
//! (SubjectIconPattern), drawn like the Flutter app: 30 px cells, every
//! other row shifted, each icon slightly turned by `Random(subject.hashCode)`.

use std::cell::RefCell;
use std::collections::HashMap;

use slint::Image;

use crate::dart_random::{DartRandom, string_hash};
use crate::subject_icon_data::{FALLBACK_ICONS, SUBJECT_ICONS, icon_markup};

/// Large enough for the tallest tile; tiles show the top left part.
const WIDTH: f64 = 320.0;
const HEIGHT: f64 = 420.0;

fn icons_for(subject: &str) -> &'static [&'static str] {
    let name = subject.to_lowercase();
    SUBJECT_ICONS
        .iter()
        .find(|(keys, _)| keys.iter().any(|k| name.contains(k)))
        .map(|(_, icons)| *icons)
        .unwrap_or(FALLBACK_ICONS)
}

fn pattern_svg(subject: &str, rgb: u32) -> String {
    let icons = icons_for(subject);
    let mut random = DartRandom::new(string_hash(subject));
    let mut svg = format!(
        r##"<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}"><g fill="#{rgb:06x}" fill-opacity="0.22">"##
    );
    let cell = 30.0;
    let mut i = 0;
    let mut y = 4.0;
    while y < HEIGHT {
        let offset = if ((y / cell).floor() as i64) % 2 == 1 { cell / 2.0 } else { 0.0 };
        let mut x = 2.0 - offset;
        while x < WIDTH {
            let icon = icons[i % icons.len()];
            i += 1;
            let degrees = (random.next_double() - 0.5) * 0.6 * 180.0 / std::f64::consts::PI;
            svg.push_str(&format!(
                r#"<g transform="translate({:.1} {:.1}) rotate({degrees:.2}) translate(-8 -8) scale(0.5833)">{}</g>"#,
                x + 8.0,
                y + 8.0,
                icon_markup(icon)
            ));
            x += cell;
        }
        y += cell;
    }
    svg.push_str("</g></svg>");
    svg
}

thread_local! {
    static CACHE: RefCell<HashMap<(String, u32), Image>> = RefCell::new(HashMap::new());
}

/// The pattern for [subject] in its colour; made once, then reused.
pub fn pattern(subject: &str, rgb: u32) -> Image {
    CACHE.with(|cache| {
        cache
            .borrow_mut()
            .entry((subject.to_owned(), rgb))
            .or_insert_with(|| Image::load_from_svg_data(pattern_svg(subject, rgb).as_bytes()).unwrap_or_default())
            .clone()
    })
}
