//! German texts for dates and the like.

use chrono::{Datelike, NaiveDate};
use register_core::model::HomeworkKind;

const WEEKDAYS: [&str; 7] = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];
const MONTHS: [&str; 12] = [
    "Jänner", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November",
    "Dezember",
];

pub fn weekday(date: NaiveDate) -> &'static str {
    WEEKDAYS[date.weekday().num_days_from_monday() as usize]
}

/// "21. Oktober"
pub fn day_month(date: NaiveDate) -> String {
    format!("{}. {}", date.day(), MONTHS[date.month0() as usize])
}

/// "21.10."
pub fn short(date: NaiveDate) -> String {
    format!("{:02}.{:02}.", date.day(), date.month())
}

/// "Mittwoch, 21. Oktober"
pub fn long(date: NaiveDate) -> String {
    format!("{}, {}", weekday(date), day_month(date))
}

/// The name the register uses for the type (for toggling entries).
pub fn kind_name(kind: HomeworkKind) -> &'static str {
    match kind {
        HomeworkKind::LessonHomework => "lessonHomework",
        HomeworkKind::GradeGroup => "gradeGroup",
        HomeworkKind::Grade => "grade",
        HomeworkKind::Observation => "observation",
        HomeworkKind::Homework => "homework",
        HomeworkKind::Other => "other",
    }
}

pub fn percent(value: f64) -> String {
    format!("{value:.1} %").replace('.', ",")
}

pub fn month(m: u32) -> &'static str {
    MONTHS[(m as usize).saturating_sub(1) % 12]
}

/// "13.11.2026", "13.11.26" or "13.11." (this school year).
pub fn parse_date(text: &str, today: NaiveDate) -> Option<NaiveDate> {
    let parts: Vec<&str> = text.trim().trim_end_matches('.').split('.').map(str::trim).collect();
    let day: u32 = parts.first()?.parse().ok()?;
    let month: u32 = parts.get(1)?.parse().ok()?;
    let year = match parts.get(2).filter(|y| !y.is_empty()) {
        Some(y) => {
            let y: i32 = y.parse().ok()?;
            if y < 100 { 2000 + y } else { y }
        }
        // Without a year: the next such date from today on.
        None => {
            let this = NaiveDate::from_ymd_opt(today.year(), month, day)?;
            if this < today { today.year() + 1 } else { today.year() }
        }
    };
    NaiveDate::from_ymd_opt(year, month, day)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dates() {
        let today = NaiveDate::from_ymd_opt(2026, 11, 12).unwrap();
        assert_eq!(parse_date("13.11.2026", today), NaiveDate::from_ymd_opt(2026, 11, 13));
        assert_eq!(parse_date("13.11.", today), NaiveDate::from_ymd_opt(2026, 11, 13));
        assert_eq!(parse_date("8.1.", today), NaiveDate::from_ymd_opt(2027, 1, 8));
        assert_eq!(parse_date("31.02.2027", today), None);
    }
}
