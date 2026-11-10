//! Demo mode: example data compiled into the app ("demo-user-6540" at the
//! Vinzentinum). Dates are moved so that the data always looks current.

use chrono::{Datelike, Duration, Local, NaiveDate};
use serde_json::Value;

use crate::model::Config;

pub fn config() -> Config {
    Config {
        user_id: 0,
        full_name: "Demo User".into(),
        image_url: String::new(),
        auto_logout_seconds: 300,
        current_semester: Some(1),
        is_student_or_parent: true,
    }
}

const DASHBOARD: &str = include_str!("../../demo/api_student_dashboard_dashboard.json");
const SUBJECTS: &str = include_str!("../../demo/api_student_all_subjects.json");
const ABSENCES: &str = include_str!("../../demo/api_student_dashboard_absences.json");
const CALENDAR: &str = include_str!("../../demo/api_calendar_student.json");
/// The Monday of the stored calendar week.
const CALENDAR_MONDAY: (i32, u32, u32) = (2026, 11, 9);
/// The first day of the stored dashboard.
const DASHBOARD_FIRST: (i32, u32, u32) = (2022, 10, 19);

fn subject_detail(id: i64) -> &'static str {
    match id {
        5 => include_str!("../../demo/api_student_subject_detail_5.json"),
        6 => include_str!("../../demo/api_student_subject_detail_6.json"),
        7 => include_str!("../../demo/api_student_subject_detail_7.json"),
        8 => include_str!("../../demo/api_student_subject_detail_8.json"),
        10 => include_str!("../../demo/api_student_subject_detail_10.json"),
        13 => include_str!("../../demo/api_student_subject_detail_13.json"),
        14 => include_str!("../../demo/api_student_subject_detail_14.json"),
        17 => include_str!("../../demo/api_student_subject_detail_17.json"),
        19 => include_str!("../../demo/api_student_subject_detail_19.json"),
        20 => include_str!("../../demo/api_student_subject_detail_20.json"),
        21 => include_str!("../../demo/api_student_subject_detail_21.json"),
        22 => include_str!("../../demo/api_student_subject_detail_22.json"),
        24 => include_str!("../../demo/api_student_subject_detail_24.json"),
        29 => include_str!("../../demo/api_student_subject_detail_29.json"),
        103 => include_str!("../../demo/api_student_subject_detail_103.json"),
        106 => include_str!("../../demo/api_student_subject_detail_106.json"),
        _ => "{\"grades\":[],\"observations\":[]}",
    }
}

fn ymd((y, m, d): (i32, u32, u32)) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, d).unwrap()
}

/// Moves every date ("2022-10-19…") in [value] by [by] days.
fn shift(value: &mut Value, by: Duration) {
    match value {
        Value::String(s) => {
            if let Some(date) = s.get(..10).and_then(|d| NaiveDate::parse_from_str(d, "%Y-%m-%d").ok()) {
                *s = format!("{}{}", (date + by).format("%Y-%m-%d"), &s[10..]);
            }
        }
        Value::Array(items) => items.iter_mut().for_each(|v| shift(v, by)),
        Value::Object(map) => {
            let entries: Vec<(String, Value)> = std::mem::take(map).into_iter().collect();
            for (key, mut v) in entries {
                shift(&mut v, by);
                let key = match NaiveDate::parse_from_str(&key, "%Y-%m-%d") {
                    Ok(date) => (date + by).format("%Y-%m-%d").to_string(),
                    Err(_) => key,
                };
                map.insert(key, v);
            }
        }
        _ => {}
    }
}

fn parse(s: &str) -> Value {
    serde_json::from_str(s).unwrap_or(Value::Null)
}

fn this_monday() -> NaiveDate {
    let today = Local::now().date_naive();
    today - Duration::days(today.weekday().num_days_from_monday() as i64)
}

pub fn response(path: &str, args: &Value) -> Value {
    match path {
        "api/student/dashboard/dashboard" => {
            let mut v = parse(DASHBOARD);
            // The entries start a week ago.
            let by = this_monday() - Duration::days(7) - ymd(DASHBOARD_FIRST);
            shift(&mut v, by);
            v
        }
        "api/student/all_subjects" => parse(SUBJECTS),
        "api/student/subject_detail" => {
            Value::String(subject_detail(args["subjectId"].as_i64().unwrap_or(0)).to_owned())
        }
        "api/student/dashboard/absences" => parse(ABSENCES),
        "api/calendar/student" => {
            let start = args["startDate"]
                .as_str()
                .and_then(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
                .unwrap_or_else(this_monday);
            let mut v = parse(CALENDAR);
            shift(&mut v, start - ymd(CALENDAR_MONDAY));
            v
        }
        "api/notification/unread" | "api/message/getMyMessages" => Value::Array(Vec::new()),
        _ => serde_json::json!({ "success": true }),
    }
}
