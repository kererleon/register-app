//! Lenient readers for the register's JSON. The server is not consistent:
//! numbers arrive as strings, booleans as 0/1, and fields may be missing.

use chrono::NaiveDate;
use serde_json::Value;

pub fn int(v: &Value) -> Option<i64> {
    match v {
        Value::Number(n) => n.as_i64().or_else(|| n.as_f64().map(|f| f as i64)),
        Value::String(s) => s.trim().parse().ok(),
        Value::Bool(b) => Some(*b as i64),
        _ => None,
    }
}

pub fn float(v: &Value) -> Option<f64> {
    match v {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.trim().replace(',', ".").parse().ok(),
        _ => None,
    }
}

pub fn string(v: &Value) -> Option<String> {
    match v {
        Value::String(s) => Some(s.clone()),
        Value::Number(n) => Some(n.to_string()),
        _ => None,
    }
}

pub fn boolean(v: &Value) -> Option<bool> {
    match v {
        Value::Bool(b) => Some(*b),
        Value::Number(n) => n.as_i64().map(|i| i != 0),
        Value::String(s) => match s.as_str() {
            "1" | "true" => Some(true),
            "0" | "false" => Some(false),
            _ => None,
        },
        _ => None,
    }
}

/// "2026-10-21" or "2026-10-21 07:45:00".
pub fn date(v: &Value) -> Option<NaiveDate> {
    let s = v.as_str()?;
    NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d").ok()
}

pub fn list(v: &Value) -> &[Value] {
    v.as_array().map(Vec::as_slice).unwrap_or(&[])
}

/// Text from the register with the most common HTML entities decoded.
pub fn text(v: &Value) -> String {
    string(v).map(|s| decode_entities(&s)).unwrap_or_default()
}

pub fn decode_entities(s: &str) -> String {
    if !s.contains('&') {
        return s.to_owned();
    }
    s.replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&#039;", "'")
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .replace("&auml;", "ä")
        .replace("&ouml;", "ö")
        .replace("&uuml;", "ü")
        .replace("&Auml;", "Ä")
        .replace("&Ouml;", "Ö")
        .replace("&Uuml;", "Ü")
        .replace("&szlig;", "ß")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
}

/// HTML (message texts, self declarations) as plain text.
pub fn strip_html(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut in_tag = false;
    let mut tag = String::new();
    for c in s.chars() {
        match c {
            '<' => {
                in_tag = true;
                tag.clear();
            }
            '>' if in_tag => {
                in_tag = false;
                let t = tag.trim_start_matches('/').to_ascii_lowercase();
                if t.starts_with("br") || t.starts_with('p') || t.starts_with("div") || t.starts_with("li") {
                    out.push('\n');
                }
            }
            _ if in_tag => tag.push(c),
            _ => out.push(c),
        }
    }
    let decoded = decode_entities(&out);
    // Collapse blank lines.
    let mut result = String::with_capacity(decoded.len());
    let mut blank = 0;
    for line in decoded.lines() {
        let line = line.trim();
        if line.is_empty() {
            blank += 1;
            if blank > 1 || result.is_empty() {
                continue;
            }
        } else {
            blank = 0;
        }
        result.push_str(line);
        result.push('\n');
    }
    result.trim_end().to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn lenient_numbers_and_flags() {
        assert_eq!(int(&json!("12")), Some(12));
        assert_eq!(int(&json!(3.0)), Some(3));
        assert_eq!(float(&json!("0,7")), Some(0.7));
        assert_eq!(boolean(&json!(1)), Some(true));
        assert_eq!(date(&json!("2026-10-21 07:45:00")), NaiveDate::from_ymd_opt(2026, 10, 21));
    }

    #[test]
    fn html_to_text() {
        assert_eq!(strip_html("<p>Erkl&auml;rung</p><p>zwei<br>drei</p>"), "Erklärung\n\nzwei\ndrei");
    }
}
