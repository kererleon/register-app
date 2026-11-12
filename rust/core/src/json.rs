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

/// A piece of an HTML page that the app can show without a browser.
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum Block {
    Heading(u8, String),
    Text(String),
    /// Rows of cells; the first row is a header when it was made of <th>.
    Table { header: bool, rows: Vec<Vec<String>> },
}

/// Turns HTML (e.g. the certificate) into headings, paragraphs and tables.
pub fn html_blocks(html: &str) -> Vec<Block> {
    let mut blocks: Vec<Block> = Vec::new();
    let mut text = String::new();
    let mut heading: Option<u8> = None;
    let mut table: Option<(bool, Vec<Vec<String>>)> = None;
    let mut cell: Option<String> = None;
    let mut skip = 0u32; // inside <script> or <style>
    let flush = |text: &mut String, blocks: &mut Vec<Block>, heading: Option<u8>| {
        let t = decode_entities(text.split_whitespace().collect::<Vec<_>>().join(" ").trim());
        if !t.is_empty() {
            blocks.push(match heading {
                Some(level) => Block::Heading(level, t),
                None => Block::Text(t),
            });
        }
        text.clear();
    };
    let mut rest = html;
    while !rest.is_empty() {
        let Some(start) = rest.find('<') else {
            if skip == 0 {
                match &mut cell {
                    Some(c) => c.push_str(rest),
                    None => text.push_str(rest),
                }
            }
            break;
        };
        let (before, after) = rest.split_at(start);
        if skip == 0 {
            match &mut cell {
                Some(c) => c.push_str(before),
                None => text.push_str(before),
            }
        }
        let Some(end) = after.find('>') else { break };
        let tag = after[1..end].trim();
        rest = &after[end + 1..];
        let closing = tag.starts_with('/');
        let name: String = tag
            .trim_start_matches('/')
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect::<String>()
            .to_ascii_lowercase();
        match name.as_str() {
            "script" | "style" => skip = if closing { skip.saturating_sub(1) } else { skip + 1 },
            "h1" | "h2" | "h3" | "h4" | "h5" | "h6" if cell.is_none() => {
                flush(&mut text, &mut blocks, heading);
                heading = if closing { None } else { name[1..].parse().ok() };
            }
            "br" | "p" | "div" | "li" | "ul" | "ol" | "hr" => match &mut cell {
                Some(c) => c.push('\n'),
                None => flush(&mut text, &mut blocks, heading),
            },
            "table" if !closing => {
                flush(&mut text, &mut blocks, heading);
                table = Some((false, Vec::new()));
            }
            "table" => {
                if let Some((header, rows)) = table.take() {
                    let rows: Vec<Vec<String>> = rows.into_iter().filter(|r| r.iter().any(|c| !c.is_empty())).collect();
                    if !rows.is_empty() {
                        blocks.push(Block::Table { header, rows });
                    }
                }
            }
            "tr" if !closing => {
                if let Some((_, rows)) = &mut table {
                    rows.push(Vec::new());
                }
            }
            "td" | "th" if !closing => {
                cell = Some(String::new());
                if name == "th"
                    && let Some((header, rows)) = &mut table
                    && rows.len() <= 1
                {
                    *header = true;
                }
            }
            "td" | "th" => {
                if let (Some(c), Some((_, rows))) = (cell.take(), &mut table) {
                    let c = decode_entities(
                        &c.lines().map(|l| l.split_whitespace().collect::<Vec<_>>().join(" ")).collect::<Vec<_>>().join("\n"),
                    )
                    .trim()
                    .to_owned();
                    if let Some(row) = rows.last_mut() {
                        row.push(c);
                    } else {
                        rows.push(vec![c]);
                    }
                }
            }
            _ => {}
        }
    }
    flush(&mut text, &mut blocks, heading);
    blocks
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

    #[test]
    fn certificate_html() {
        let html = r#"<div class="student-subject-list"><div><h2 class="h2">Zeugnis Mustermann Max</h2>Zeugnis noch nicht verfügbar</div></div>"#;
        assert_eq!(
            html_blocks(html),
            vec![Block::Heading(2, "Zeugnis Mustermann Max".into()), Block::Text("Zeugnis noch nicht verfügbar".into())]
        );
        let table = "<table><tr><th>Fach</th><th>Note</th></tr><tr><td>Deutsch</td><td>8</td></tr></table>";
        assert_eq!(
            html_blocks(table),
            vec![Block::Table { header: true, rows: vec![vec!["Fach".into(), "Note".into()], vec!["Deutsch".into(), "8".into()]] }]
        );
    }
}
