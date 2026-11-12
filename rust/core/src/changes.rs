//! What is new since the last load: new grades, entries, messages and
//! timetable changes (substitutions, cancelled lessons). The app announces
//! them as notifications.

use std::collections::HashSet;

use chrono::NaiveDate;

use crate::data::Data;
use crate::grades;
use crate::model::{CalendarHour, Teacher};

#[derive(Debug, Clone, PartialEq)]
pub struct Change {
    pub title: String,
    pub body: String,
}

fn change(title: impl Into<String>, body: impl Into<String>) -> Change {
    Change { title: title.into(), body: body.into() }
}

fn teachers(h: &CalendarHour) -> String {
    h.teachers.iter().map(Teacher::full_name).collect::<Vec<_>>().join(", ")
}

/// The changes from [old] to [new], from [today] on for the timetable.
/// Nothing on the very first load, so a new installation stays quiet.
pub fn between(old: &Data, new: &Data, today: NaiveDate) -> Vec<Change> {
    if old.fetched_at.is_none() {
        return Vec::new();
    }
    let mut out = Vec::new();

    // Grades: compared by everything that identifies them.
    for subject in &new.subjects {
        let before: HashSet<_> = old
            .subjects
            .iter()
            .filter(|s| s.id == subject.id)
            .flat_map(|s| s.grades.iter().flatten())
            .map(|g| (g.date, g.value, g.kind.clone(), g.weight_percent))
            .collect();
        for g in subject.grades.iter().flatten() {
            if g.cancelled || before.contains(&(g.date, g.value, g.kind.clone(), g.weight_percent)) {
                continue;
            }
            let value = g.value.map(grades::format_grade).unwrap_or_default();
            out.push(change(format!("Neue Note in {}", subject.name), format!("{value} · {}", g.kind)));
        }
    }

    // Homework, tests and reminders (grades and observations are above).
    let known: HashSet<_> = old.dashboard.iter().flat_map(|d| &d.homework).map(|h| (h.kind, h.id)).collect();
    for day in &new.dashboard {
        for h in &day.homework {
            use crate::model::HomeworkKind::*;
            if known.contains(&(h.kind, h.id)) || matches!(h.kind, Grade | Observation) || h.is_reminder() {
                continue;
            }
            let what = if h.is_test() { "Neuer Test" } else { "Neue Aufgabe" };
            let label = h.label.as_deref().map(|l| format!("{l}: ")).unwrap_or_default();
            out.push(change(format!("{what} am {}", day.date.format("%d.%m.")), format!("{label}{}", h.title)));
        }
    }

    // Messages and notifications from the register.
    let known: HashSet<i64> = old.messages.iter().map(|m| m.id).collect();
    for m in new.messages.iter().filter(|m| !m.read && !known.contains(&m.id)) {
        out.push(change(format!("Mitteilung von {}", m.from), m.subject.clone()));
    }
    let known: HashSet<i64> = old.notifications.iter().map(|n| n.id).collect();
    for n in new.notifications.iter().filter(|n| !known.contains(&n.id)) {
        out.push(change(n.title.clone(), n.subtitle.clone()));
    }

    // Timetable: only days both loads know, from today on.
    for (date, day) in new.calendar.range(today..) {
        let Some(before) = old.calendar.get(date) else { continue };
        let when = date.format("%d.%m.");
        for was in &before.hours {
            let now = day.hours.iter().find(|h| h.from_hour <= was.from_hour && h.to_hour >= was.from_hour);
            match now {
                None => {
                    // A day without any lessons is a holiday or not loaded.
                    if !day.hours.is_empty() {
                        out.push(change(
                            format!("Stunde entfällt am {when}"),
                            format!("{}. Stunde {}", was.from_hour, was.subject),
                        ));
                    }
                }
                Some(now) if now.subject != was.subject => out.push(change(
                    format!("Stundenänderung am {when}"),
                    format!("{}. Stunde: {} statt {}", was.from_hour, now.subject, was.subject),
                )),
                Some(now) if teachers(now) != teachers(was) && !now.teachers.is_empty() => out.push(change(
                    format!("Supplenz am {when}"),
                    format!("{}. Stunde {}: {}", was.from_hour, now.subject, teachers(now)),
                )),
                Some(now) if now.rooms != was.rooms && !now.rooms.is_empty() => out.push(change(
                    format!("Raumänderung am {when}"),
                    format!("{}. Stunde {}: {}", was.from_hour, now.subject, now.rooms.join(", ")),
                )),
                _ => {}
            }
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::client::Client;

    fn demo() -> Data {
        let client = Client::new("https://vinzentinum.digitalesregister.it", "demo-user-6540", "x");
        client.login(None).unwrap();
        let mut data = Data::default();
        data.refresh(&client);
        data
    }

    #[test]
    fn first_load_is_quiet_and_nothing_new_is_quiet() {
        let data = demo();
        assert!(between(&Data::default(), &data, crate::data::today()).is_empty());
        assert!(between(&data, &data, crate::data::today()).is_empty());
    }

    #[test]
    fn substitutions_cancelled_lessons_and_new_grades_are_found() {
        let old = demo();
        let mut new = old.clone();
        let (&date, _) = new.calendar.iter().next().unwrap();
        let day = new.calendar.get_mut(&date).unwrap();
        day.hours[0].teachers = vec![Teacher { first_name: "Vertretung".into(), last_name: "Muster".into() }];
        let removed = day.hours.remove(1);
        let mut grade = new.subjects[0].grades[0].first().cloned().unwrap_or_else(|| new.subjects[1].grades[0][0].clone());
        grade.value = Some(675);
        grade.kind = "Schularbeit".into();
        new.subjects[0].grades[0].push(grade);

        let changes = between(&old, &new, date);
        let titles: Vec<&str> = changes.iter().map(|c| c.title.as_str()).collect();
        assert!(titles.iter().any(|t| t.starts_with("Supplenz")), "{changes:?}");
        assert!(
            changes.iter().any(|c| c.title.starts_with("Stunde entfällt") && c.body.contains(&removed.subject)),
            "{changes:?}"
        );
        assert!(changes.iter().any(|c| c.title.starts_with("Neue Note") && c.body.starts_with("7-")), "{changes:?}");
    }
}
