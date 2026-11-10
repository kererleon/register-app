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

/// "heute", "morgen", "in 3 Tagen", "vor 2 Tagen"
pub fn relative(date: NaiveDate, today: NaiveDate) -> String {
    match (date - today).num_days() {
        0 => "heute".into(),
        1 => "morgen".into(),
        -1 => "gestern".into(),
        n if n > 1 => format!("in {n} Tagen"),
        n => format!("vor {} Tagen", -n),
    }
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
