//! Turns the register's responses into the app's data.

use chrono::{NaiveDate, NaiveDateTime};
use serde_json::Value;

use crate::json::{boolean, date, decode_entities, float, int, list, string, strip_html, text};
use crate::model::*;

fn date_time(v: &Value) -> Option<NaiveDateTime> {
    let s = v.as_str()?;
    NaiveDateTime::parse_from_str(s.get(..19)?, "%Y-%m-%d %H:%M:%S").ok()
}

// --- Start page (config) ---

fn after<'a>(source: &'a str, marker: &str) -> Option<&'a str> {
    source.find(marker).map(|i| &source[i + marker.len()..])
}

/// Reads the user's data from the register's start page (HTML).
pub fn config(source: &str) -> Option<Config> {
    let user_id = after(source, "currentUserId=")?
        .split(';')
        .next()?
        .trim()
        .parse()
        .ok()?;
    let auto_logout_seconds = after(source, "auto_logout_seconds: ")
        .and_then(|s| s.split(',').next())
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(300);
    let picture = after(source, "navigationProfilePicture").unwrap_or("").trim();
    let full_name = picture
        .find('>')
        .and_then(|start| picture[start + 1..].split('<').next())
        .map(|s| decode_entities(s.trim()))
        .unwrap_or_default();
    let image_url = after(picture, "src=\"")
        .and_then(|s| s.split('"').next())
        .unwrap_or("")
        .trim()
        .to_owned();
    let current_semester = if source.contains("semesterWechsel=1") {
        Some(2)
    } else if source.contains("semesterWechsel=2") {
        Some(1)
    } else {
        None
    };
    Some(Config {
        user_id,
        full_name,
        image_url,
        auto_logout_seconds,
        current_semester,
        is_student_or_parent: !source.contains("var isStudentOrParent=0;"),
    })
}

// --- Dashboard ---

fn homework(item: &Value) -> Homework {
    Homework {
        id: int(&item["id"]).unwrap_or(0),
        kind: HomeworkKind::parse(item["type"].as_str().unwrap_or("")),
        title: text(&item["title"]),
        subtitle: text(&item["subtitle"]),
        label: string(&item["label"]).map(|s| decode_entities(&s)).filter(|s| !s.is_empty()),
        warning: item["homework"] == Value::from(0),
        checkable: boolean(&item["checkable"]).unwrap_or(false),
        checked: boolean(&item["checked"]).unwrap_or(false),
        deleteable: boolean(&item["deleteable"]).unwrap_or(false),
        grade: string(&item["grade"]).filter(|g| !g.is_empty()),
        deadline: date_time(&item["deadline"]),
    }
}

pub fn dashboard(data: &Value) -> Vec<DashboardDay> {
    let mut days: Vec<DashboardDay> = list(data)
        .iter()
        .filter_map(|day| {
            let date = date(&day["date"])?;
            let mut items: Vec<Homework> = Vec::new();
            for item in list(&day["items"]) {
                let hw = homework(item);
                // The server sometimes lists an entry twice.
                if !items.iter().any(|h| h.id == hw.id && h.kind == hw.kind) {
                    items.push(hw);
                }
            }
            Some(DashboardDay { date, homework: items })
        })
        .collect();
    days.sort_by_key(|d| d.date);
    days
}

// --- Grades ---

/// "8.25" -> 825; "", "0" and missing -> no grade.
pub fn grade_value(s: Option<&str>) -> Option<GradeValue> {
    let s = s?.trim();
    if s.is_empty() || s == "0" {
        return None;
    }
    let mut parts = s.split('.');
    let main: i32 = parts.next()?.parse().ok()?;
    let decimals: i32 = parts.next().map(|d| d.parse().ok()).unwrap_or(Some(0))?;
    Some(main * 100 + decimals)
}

fn grade(g: &Value) -> Option<Grade> {
    Some(Grade {
        id: int(&g["id"]),
        value: grade_value(g["grade"].as_str()),
        weight_percent: int(&g["weight"]).unwrap_or(100) as i32,
        date: date(&g["date"])?,
        cancelled: int(&g["cancelled"]).unwrap_or(0) != 0,
        kind: text(if g["typeName"].is_null() { &g["type"] } else { &g["typeName"] }),
        name: text(&g["name"]),
        description: text(&g["description"]),
        created: text(&g["created"]),
    })
}

/// Updates [subjects] with the overview of one semester (index 0 or 1).
pub fn subjects(data: &Value, semester: usize, subjects: &mut Vec<Subject>) {
    let mut seen = Vec::new();
    for entry in list(&data["subjects"]) {
        let Some(id) = int(&entry["subject"]["id"]) else { continue };
        seen.push(id);
        let grades: Vec<Grade> = list(&entry["grades"]).iter().filter_map(grade).collect();
        match subjects.iter_mut().find(|s| s.id == id) {
            Some(subject) => subject.grades[semester] = grades,
            None => {
                let mut subject = Subject {
                    id,
                    name: text(&entry["subject"]["name"]),
                    ..Default::default()
                };
                subject.grades[semester] = grades;
                subjects.push(subject);
            }
        }
    }
    // Subjects that disappeared are no longer attended (new school year).
    subjects.retain(|s| seen.contains(&s.id));
    // In the register's order, as the Flutter app shows them.
    subjects.sort_by_key(|s| seen.iter().position(|id| *id == s.id));
}

/// The details of one subject. The register sends them as a JSON string.
pub fn subject_detail(data: &Value) -> (Vec<Grade>, Vec<Observation>) {
    let parsed;
    let data = match data {
        Value::String(s) => {
            parsed = serde_json::from_str(s).unwrap_or(Value::Null);
            &parsed
        }
        other => other,
    };
    let grades = list(&data["grades"]).iter().filter_map(grade).collect();
    let observations = list(&data["observations"])
        .iter()
        .filter_map(|o| {
            Some(Observation {
                date: date(&o["date"])?,
                kind: text(&o["typeName"]),
                note: text(&o["note"]),
                cancelled: int(&o["cancelled"]).unwrap_or(0) != 0,
                created: text(&o["created"]),
            })
        })
        .collect();
    (grades, observations)
}

// --- Calendar ---

fn time(object: &Value) -> Option<String> {
    let h = int(&object["h"])?;
    let m = int(&object["m"])?;
    Some(format!("{h:02}:{m:02}"))
}

fn calendar_hour(entry: &Value) -> Option<CalendarHour> {
    let lesson = &entry["lesson"];
    let mut times = Vec::new();
    for linked in std::iter::once(lesson).chain(list(&lesson["linkedHours"])) {
        if let (Some(from), Some(to)) =
            (time(&linked["timeStartObject"]), time(&linked["timeEndObject"]))
        {
            times.push((from, to));
        }
    }
    Some(CalendarHour {
        from_hour: int(&lesson["hour"])? as i32,
        to_hour: int(&lesson["toHour"]).or_else(|| int(&lesson["hour"]))? as i32,
        subject: text(&lesson["subject"]["name"]),
        teachers: list(&lesson["teachers"])
            .iter()
            .map(|t| Teacher { first_name: text(&t["firstName"]), last_name: text(&t["lastName"]) })
            .collect(),
        rooms: list(&lesson["rooms"]).iter().map(|r| text(&r["name"])).collect(),
        times,
        homework_exams: list(&lesson["homeworkExams"])
            .iter()
            .map(|e| HomeworkExam {
                id: int(&e["id"]).unwrap_or(0),
                name: text(&e["name"]),
                type_name: text(&e["typeName"]),
                deadline: date_time(&e["deadline"]),
            })
            .collect(),
        lesson_contents: list(&lesson["lessonContents"])
            .iter()
            .map(|c| (text(&c["typeName"]), text(&c["name"])))
            .collect(),
    })
}

/// A week of the timetable: date -> { "1" -> { "1" -> { hour -> entry } } }.
pub fn calendar(data: &Value) -> Vec<CalendarDay> {
    let Some(week) = data.as_object() else { return Vec::new() };
    let mut days: Vec<CalendarDay> = week
        .iter()
        .filter_map(|(key, day)| {
            let date = NaiveDate::parse_from_str(key, "%Y-%m-%d").ok()?;
            let entries = day
                .as_object()
                .and_then(|d| d.values().next())
                .and_then(|d| d.as_object())
                .and_then(|d| d.values().next())
                .and_then(|d| d.as_object());
            let mut hours: Vec<CalendarHour> = entries
                .into_iter()
                .flat_map(|e| e.values())
                .filter(|e| !e.is_null() && int(&e["isLesson"]) != Some(0))
                .filter_map(calendar_hour)
                .collect();
            hours.sort_by_key(|h| h.from_hour);
            Some(CalendarDay { date, hours })
        })
        .collect();
    days.sort_by_key(|d| d.date);
    days
}

// --- Absences ---

fn non_empty(v: &Value) -> Option<String> {
    string(v).map(|s| decode_entities(&s)).filter(|s| !s.trim().is_empty())
}

pub fn absences(data: &Value) -> Absences {
    let stats = &data["statistics"];
    let groups = list(&data["absences"])
        .iter()
        .map(|g| AbsenceGroup {
            justified: Justified::from_code(int(&g["justified"]).unwrap_or(1)),
            reason: non_empty(&g["reason"]),
            signature: non_empty(&g["reason_signature"]),
            reason_time: date_time(&g["reason_timestamp"]),
            note: non_empty(&g["note"]),
            hours: list(&g["group"])
                .iter()
                .filter_map(|a| {
                    Some(MissedHour {
                        date: date(&a["date"])?,
                        hour: int(&a["hour"]).unwrap_or(0) as i32,
                        minutes: int(&a["minutes"]).unwrap_or(0) as i32,
                        came_late: int(&a["minutes_begin"]).unwrap_or(0) as i32,
                        left_early: int(&a["minutes_end"]).unwrap_or(0) as i32,
                    })
                })
                .collect(),
        })
        .collect();
    let future = list(&data["futureAbsences"])
        .iter()
        .filter_map(|a| {
            Some(FutureAbsence {
                id: int(&a["id"]).unwrap_or(0),
                start: date(&a["startDate"])?,
                end: date(&a["endDate"])?,
                start_hour: int(&a["startTime"]).unwrap_or(1) as i32,
                end_hour: int(&a["endTime"]).unwrap_or(1) as i32,
                justified: Justified::from_code(int(&a["justified"]).unwrap_or(1)),
                reason: non_empty(&a["reason"]),
                note: non_empty(&a["note"]),
            })
        })
        .collect();
    Absences {
        groups,
        future,
        statistic: AbsenceStatistic {
            counter: int(&stats["counter"]),
            counter_for_school: int(&stats["counterForSchool"]),
            delayed: int(&stats["delayed"]),
            justified: int(&stats["justified"]),
            not_justified: int(&stats["notJustified"]),
            percentage: float(&stats["percentage"]),
        },
        can_edit: boolean(&data["canEdit"]).unwrap_or(false),
    }
}

// --- Notifications and messages ---

pub fn notifications(data: &Value) -> Vec<Notification> {
    list(data)
        .iter()
        .map(|n| Notification {
            id: int(&n["id"]).unwrap_or(0),
            title: text(&n["title"]),
            subtitle: text(&n["subTitle"]),
            kind: text(&n["type"]),
            time_sent: date_time(&n["timeSent"]),
        })
        .collect()
}

pub fn messages(data: &Value) -> Vec<Message> {
    let mut messages: Vec<Message> = list(data)
        .iter()
        .map(|m| Message {
            id: int(&m["id"]).unwrap_or(0),
            subject: text(&m["subject"]),
            text: strip_html(&string(&m["text"]).unwrap_or_default()),
            from: text(&m["fromName"]),
            recipients: text(&m["recipientString"]),
            time_sent: date_time(&m["timeSent"]),
            read: !m["timeRead"].is_null(),
        })
        .collect();
    messages.sort_by(|a, b| b.time_sent.cmp(&a.time_sent));
    messages
}

#[cfg(test)]
mod tests {
    use super::*;

    fn demo(name: &str) -> Value {
        let path = format!("{}/../demo/{name}.json", env!("CARGO_MANIFEST_DIR"));
        serde_json::from_str(&std::fs::read_to_string(path).unwrap()).unwrap()
    }

    #[test]
    fn grade_values() {
        assert_eq!(grade_value(Some("9.00")), Some(900));
        assert_eq!(grade_value(Some("8.25")), Some(825));
        assert_eq!(grade_value(Some("7")), Some(700));
        assert_eq!(grade_value(Some("0")), None);
        assert_eq!(grade_value(Some("")), None);
    }

    #[test]
    fn demo_dashboard() {
        let days = dashboard(&demo("api_student_dashboard_dashboard"));
        assert!(!days.is_empty());
        let all: Vec<_> = days.iter().flat_map(|d| &d.homework).collect();
        assert_eq!(all.len(), 28);
        assert!(all.iter().all(|h| !h.title.is_empty()));
    }

    #[test]
    fn demo_grades() {
        let mut list = Vec::new();
        subjects(&demo("api_student_all_subjects"), 0, &mut list);
        assert_eq!(list.len(), 16);
        let sport = list.iter().find(|s| s.name == "Bewegung und Sport").unwrap();
        assert_eq!(sport.grades[0][0].value, Some(900));
        let (grades, observations) = subject_detail(&demo("api_student_subject_detail_17"));
        assert_eq!(grades[0].name, "Ausdauertest");
        assert_eq!(observations[0].kind, "Plus");
    }

    #[test]
    fn demo_calendar() {
        let days = calendar(&demo("api_calendar_student"));
        assert!(days.len() >= 5);
        let monday = &days[0];
        assert!(!monday.hours.is_empty());
        let first = &monday.hours[0];
        assert_eq!(first.subject, "Englisch");
        assert_eq!(first.start(), "07:45");
        assert_eq!(first.teachers[0].last_name, "Mitterrutzner");
    }

    #[test]
    fn demo_absences() {
        let a = absences(&demo("api_student_dashboard_absences"));
        assert_eq!(a.statistic.percentage, Some(1.2));
        assert_eq!(a.groups[0].justified, Justified::NotYet);
        assert_eq!(a.groups[0].hours.len(), 3);
        assert!(a.can_edit);
    }

    #[test]
    fn start_page_config() {
        let html = r#"<script>var currentUserId=6619; var x={auto_logout_seconds: 300, y:1}</script>
            <img id="navigationProfilePicture" src="/v2/pic.png">Max Muster</span>"#;
        let c = config(html).unwrap();
        assert_eq!(c.user_id, 6619);
        assert_eq!(c.auto_logout_seconds, 300);
        assert_eq!(c.full_name, "Max Muster");
        assert_eq!(c.image_url, "/v2/pic.png");
        assert!(c.is_student_or_parent);
    }
}
