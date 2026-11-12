//! The decorations of the brainrot and israel backgrounds, placed with the
//! same formulas and the same random numbers (Dart's `Random(7)` and
//! `Random(9)`) as the Flutter app's `_AuroraPainter`.

use std::f64::consts::PI;

use slint::{ModelRc, SharedString, VecModel};

use crate::dart_random::DartRandom;
use crate::DecoItem;

pub struct Decoration {
    pub stripes: String,
    pub items: Vec<DecoItem>,
    pub flag_height: f32,
    pub flag_star: String,
}

const BRAINROT_EMOJIS: [&str; 10] = ["💀", "🗿", "🔥", "🤑", "🧠", "💯", "🫠", "😭", "🚀", "🌽"];
const ISRAEL_EMOJIS: [&str; 12] = ["🇮🇱", "🥙", "🧆", "🫓", "🌊", "☀️", "🐪", "🍊", "🏖️", "🇮🇱", "💙", "🔥"];
const ISRAEL_MEMES: [&str; 12] = [
    "YALLA BALAGAN 🤯",
    "SABABA ACHI 😎",
    "HUMMUS > ALLES 🥙",
    "TACHLES. 6 REICHT.",
    "MA NISHMA? 👀",
    "KAPARA ALECHA 💙",
    "BESEDER? BESEDER.",
    "YALLA BYE ✌️",
    "ACHI, LERN MAL 📚",
    "SHAKSHUKA TIME 🍳",
    "SHALOM, TEST 👋",
    "OY VEY, MATHE 😵",
];

/// Two triangles (a star of David) around (cx, cy).
fn star_path(cx: f64, cy: f64, r: f64) -> String {
    let mut out = String::new();
    for start in [-PI / 2.0, PI / 2.0] {
        for i in 0..3 {
            let a = start + i as f64 * 2.0 * PI / 3.0;
            let (x, y) = (cx + a.cos() * r, cy + a.sin() * r);
            out.push_str(&format!("{} {x:.2} {y:.2} ", if i == 0 { "M" } else { "L" }));
        }
        out.push_str("Z ");
    }
    out
}

fn item(kind: i32, text: &str, x: f64, y: f64, size: f64, rotation_rad: f64, opacity: f32, path: String) -> DecoItem {
    DecoItem {
        kind,
        text: SharedString::from(text),
        x: x as f32,
        y: y as f32,
        size: size as f32,
        rotation: (rotation_rad * 180.0 / PI) as f32,
        opacity,
        path: path.into(),
    }
}

/// Style 1 (brainrot) or 2 (israel); nothing for the others.
pub fn decorate(style: i32, dark: bool, w: f64, h: f64) -> Decoration {
    let mut d = Decoration { stripes: String::new(), items: Vec::new(), flag_height: 0.0, flag_star: String::new() };
    if w <= 0.0 || h <= 0.0 {
        return d;
    }
    match style {
        1 => {
            // Diagonal stripes every 64 px.
            let mut x = -h;
            while x < w {
                d.stripes.push_str(&format!("M {x:.1} {h:.1} L {:.1} 0 ", x + h));
                x += 64.0;
            }
            let mut r = DartRandom::new(7);
            let count = (w * h / 26000.0).clamp(12.0, 80.0).round() as i32;
            for _ in 0..count {
                let emoji = BRAINROT_EMOJIS[r.next_int(BRAINROT_EMOJIS.len() as i64) as usize];
                let size = 22.0 + r.next_double() * 26.0;
                let (x, y) = (r.next_double() * w, r.next_double() * h);
                let rot = (r.next_double() - 0.5) * 0.8;
                d.items.push(item(0, emoji, x, y, size, rot, if dark { 0.16 } else { 0.3 }, String::new()));
            }
        }
        2 => {
            let flag = 170f64.min(120f64.max(h * 0.2));
            d.flag_height = flag as f32;
            d.flag_star = star_path(w / 2.0, flag / 2.0, flag * 0.2);
            let mut r = DartRandom::new(9);
            let area = (h - flag - 20.0).max(1.0);
            let count = (w * area / 26000.0).clamp(10.0, 70.0).round() as i32;
            for i in 0..count {
                let (x, y) = (r.next_double() * w, flag + r.next_double() * area);
                if i % 3 == 0 {
                    let radius = 8.0 + r.next_double() * 8.0;
                    let path = star_path(radius, radius, radius);
                    d.items.push(item(1, "", x - radius, y - radius, radius, 0.0, if dark { 0.22 } else { 0.16 }, path));
                } else {
                    let emoji = ISRAEL_EMOJIS[r.next_int(ISRAEL_EMOJIS.len() as i64) as usize];
                    let size = 20.0 + r.next_double() * 14.0;
                    let rot = (r.next_double() - 0.5) * 0.6;
                    d.items.push(item(0, emoji, x, y, size, rot, if dark { 0.22 } else { 0.4 }, String::new()));
                }
            }
            let stickers = (w * area / 90000.0).clamp(3.0, 14.0).round() as i64;
            for i in 0..stickers {
                let text = ISRAEL_MEMES[((i * 5 + r.next_int(12)) % 12) as usize];
                let size = 13.0 + r.next_double() * 5.0;
                // The box as Flutter measures it (Rubik Black, padding 10/6).
                let box_w = text.chars().count() as f64 * size * 0.68 + 20.0;
                let box_h = size * 1.2 + 12.0;
                let x = r.next_double() * (w - box_w).max(1.0);
                let y = flag + 10.0 + r.next_double() * (area - box_h - 20.0).max(1.0);
                let rot = (r.next_double() - 0.5) * 0.35;
                d.items.push(item(2, text, x, y, size, rot, 1.0, String::new()));
            }
        }
        _ => {}
    }
    d
}

pub fn model(items: Vec<DecoItem>) -> ModelRc<DecoItem> {
    ModelRc::new(VecModel::from(items))
}
