//! The register's data, as the app uses it.

use chrono::{NaiveDate, NaiveDateTime};
use serde::{Deserialize, Serialize};

/// Read from the register's start page after logging in.
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Config {
    pub user_id: i64,
    pub full_name: String,
    pub image_url: String,
    pub auto_logout_seconds: i64,
    /// 1 or 2 when the server says which semester is current.
    pub current_semester: Option<u8>,
    pub is_student_or_parent: bool,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum HomeworkKind {
    LessonHomework,
    GradeGroup,
    Grade,
    Observation,
    Homework,
    Other,
}

impl HomeworkKind {
    pub fn parse(s: &str) -> Self {
        match s {
            "lessonHomework" => Self::LessonHomework,
            "gradeGroup" => Self::GradeGroup,
            "grade" => Self::Grade,
            "observation" => Self::Observation,
            "homework" => Self::Homework,
            _ => Self::Other,
        }
    }
}

/// An entry on the dashboard: homework, a test, a reminder, a new grade …
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Homework {
    pub id: i64,
    pub kind: HomeworkKind,
    pub title: String,
    pub subtitle: String,
    /// Usually the subject.
    pub label: Option<String>,
    pub warning: bool,
    pub checkable: bool,
    pub checked: bool,
    pub deleteable: bool,
    /// For new grades.
    pub grade: Option<String>,
    pub deadline: Option<NaiveDateTime>,
}

impl Homework {
    /// Whether the entry is a test or an exam. The server's warning flag
    /// only says that an entry is not marked as homework, which some
    /// teachers forget, so the type and the text decide.
    pub fn is_test(&self) -> bool {
        if matches!(self.kind, HomeworkKind::Grade | HomeworkKind::Observation) {
            return false;
        }
        let text = format!("{} {}", self.title, self.subtitle);
        if looks_like_test(&text) {
            return true;
        }
        if matches!(self.kind, HomeworkKind::LessonHomework | HomeworkKind::Homework)
            || looks_like_homework(&text)
        {
            return false;
        }
        self.kind == HomeworkKind::GradeGroup
    }

    /// Own reminders can really be moved and deleted on the server.
    pub fn is_reminder(&self) -> bool {
        self.kind == HomeworkKind::Homework && self.deleteable
    }
}

const TEST_WORDS: [&str; 9] = [
    "test",
    "schularbeit",
    "prüfung",
    "klausur",
    "lernzielkontrolle",
    "verifica",
    "compito in classe",
    "interrogazione",
    "esame",
];
const HOMEWORK_WORDS: [&str; 7] =
    ["hausaufgabe", "hausübung", "compiti", "compito", "esercizi", "esercizio", "homework"];

fn is_word_char(c: char) -> bool {
    c.is_ascii_lowercase() || "äöüàèéìòù".contains(c)
}

/// Whether the text reads like a test (German or Italian). Whole words only,
/// with the endings "s", "arbeit" and "en": "test" must not match "testo".
pub fn looks_like_test(text: &str) -> bool {
    let t = text.to_lowercase();
    for word in TEST_WORDS {
        for (start, _) in t.match_indices(word) {
            if t[..start].chars().next_back().is_some_and(is_word_char) {
                continue;
            }
            let rest = &t[start + word.len()..];
            let after = ["arbeit", "en", "s", ""]
                .iter()
                .find_map(|ending| rest.strip_prefix(ending).filter(|r| !r.starts_with(is_word_char)));
            if after.is_some() {
                return true;
            }
        }
    }
    false
}

pub fn looks_like_homework(text: &str) -> bool {
    let t = text.to_lowercase();
    HOMEWORK_WORDS.iter().any(|w| t.contains(w))
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct DashboardDay {
    pub date: NaiveDate,
    pub homework: Vec<Homework>,
}

/// A grade as hundredths: "8.25" = 825, so averages stay exact.
pub type GradeValue = i32;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Grade {
    pub id: Option<i64>,
    pub value: Option<GradeValue>,
    pub weight_percent: i32,
    pub date: NaiveDate,
    pub cancelled: bool,
    pub kind: String,
    pub name: String,
    pub description: String,
    pub created: String,
    /// Competences rated with 1 to 5 stars.
    #[serde(default)]
    pub competences: Vec<(String, i32)>,
    /// Why a cancelled grade was cancelled (loaded separately).
    #[serde(default)]
    pub cancelled_description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Observation {
    pub date: NaiveDate,
    pub kind: String,
    pub note: String,
    pub cancelled: bool,
    pub created: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, Hash, Default)]
pub enum Semester {
    First,
    Second,
    #[default]
    All,
}

impl Semester {
    pub fn number(self) -> Option<u8> {
        match self {
            Self::First => Some(1),
            Self::Second => Some(2),
            Self::All => None,
        }
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Subject {
    pub id: i64,
    pub name: String,
    /// Basic grades per semester (1, 2).
    pub grades: [Vec<Grade>; 2],
    /// Detailed grades and observations, once loaded.
    pub details: [Option<Vec<Grade>>; 2],
    pub observations: [Option<Vec<Observation>>; 2],
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Teacher {
    pub first_name: String,
    pub last_name: String,
}

impl Teacher {
    pub fn full_name(&self) -> String {
        format!("{} {}", self.first_name, self.last_name).trim().to_owned()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HomeworkExam {
    pub id: i64,
    pub name: String,
    pub type_name: String,
    pub deadline: Option<NaiveDateTime>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalendarHour {
    pub from_hour: i32,
    pub to_hour: i32,
    pub subject: String,
    pub teachers: Vec<Teacher>,
    pub rooms: Vec<String>,
    /// Start and end of every linked lesson, "07:45".
    pub times: Vec<(String, String)>,
    pub homework_exams: Vec<HomeworkExam>,
    pub lesson_contents: Vec<(String, String)>,
}

impl CalendarHour {
    pub fn length(&self) -> i32 {
        self.to_hour - self.from_hour + 1
    }
    pub fn start(&self) -> &str {
        self.times.first().map(|t| t.0.as_str()).unwrap_or("")
    }
    pub fn end(&self) -> &str {
        self.times.last().map(|t| t.1.as_str()).unwrap_or("")
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct CalendarDay {
    pub date: NaiveDate,
    pub hours: Vec<CalendarHour>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum Justified {
    NotYet,
    Justified,
    NotJustified,
    ForSchool,
}

impl Justified {
    /// The register's codes; everything else is "not yet justified".
    pub fn from_code(code: i64) -> Self {
        match code {
            2 => Self::Justified,
            3 => Self::NotJustified,
            4 => Self::ForSchool,
            _ => Self::NotYet,
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            Self::NotYet => "Noch nicht entschuldigt",
            Self::Justified => "Entschuldigt",
            Self::NotJustified => "Nicht entschuldigt",
            Self::ForSchool => "Schulisch",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct MissedHour {
    pub date: NaiveDate,
    pub hour: i32,
    pub minutes: i32,
    pub came_late: i32,
    pub left_early: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AbsenceGroup {
    pub justified: Justified,
    pub reason: Option<String>,
    pub signature: Option<String>,
    /// When the reason was entered.
    #[serde(default)]
    pub reason_time: Option<NaiveDateTime>,
    pub note: Option<String>,
    pub hours: Vec<MissedHour>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct FutureAbsence {
    pub id: i64,
    pub start: NaiveDate,
    pub end: NaiveDate,
    pub start_hour: i32,
    pub end_hour: i32,
    pub justified: Justified,
    pub reason: Option<String>,
    pub note: Option<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct AbsenceStatistic {
    pub counter: Option<i64>,
    pub counter_for_school: Option<i64>,
    pub delayed: Option<i64>,
    pub justified: Option<i64>,
    pub not_justified: Option<i64>,
    /// Share of the lessons held so far, in percent.
    pub percentage: Option<f64>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Absences {
    pub groups: Vec<AbsenceGroup>,
    pub future: Vec<FutureAbsence>,
    pub statistic: AbsenceStatistic,
    pub can_edit: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Notification {
    pub id: i64,
    pub title: String,
    pub subtitle: String,
    pub kind: String,
    pub time_sent: Option<NaiveDateTime>,
    /// The message a notification of the kind "message" is about.
    #[serde(default)]
    pub object_id: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Message {
    pub id: i64,
    pub subject: String,
    /// Plain text.
    pub text: String,
    pub from: String,
    pub recipients: String,
    pub time_sent: Option<NaiveDateTime>,
    pub read: bool,
    #[serde(default)]
    pub attachments: Vec<Attachment>,
}

/// A file sent with a message.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Attachment {
    pub id: i64,
    pub message_id: i64,
    pub original_name: String,
    pub file: String,
}

impl Attachment {
    /// The name the file is kept under on the device.
    pub fn unique_name(&self) -> String {
        let safe: String =
            self.original_name.chars().map(|c| if matches!(c, '/' | '\\' | ':' | '\0') { '_' } else { c }).collect();
        format!("msg_{}_{}_{}", self.message_id, self.id, safe.trim_start_matches('.'))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn recognizes_tests_in_german_and_italian() {
        assert!(looks_like_test("Mathematik Test"));
        assert!(looks_like_test("Schularbeit Nr. 2"));
        assert!(looks_like_test("Tests korrigieren"));
        assert!(looks_like_test("verifica di storia"));
        assert!(!looks_like_test("Leggere il testo"));
        assert!(!looks_like_test("Testosteron"));
        assert!(looks_like_homework("Compito per casa"));
    }
}
