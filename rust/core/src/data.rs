//! All of a student's data, loaded in parallel and kept on the device so that
//! the app shows something right away on the next start.

use std::collections::BTreeMap;
use std::path::Path;

use chrono::{Datelike, Duration, Local, NaiveDate};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::client::{Client, Error};
use crate::model::*;
use crate::parse;

/// An entry of a teacher moved to another day: shown there as a reminder.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Moved {
    pub to: NaiveDate,
    pub reminder_id: i64,
}

/// What an entry looked like before the register changed it.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct PreviousVersion {
    pub title: String,
    pub subtitle: String,
    pub changed_at: i64,
}

/// Identifies an entry across reloads ("gradeGroup:1338").
pub fn homework_key(h: &Homework) -> String {
    format!("{:?}:{}", h.kind, h.id)
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq)]
pub struct Data {
    pub config: Option<Config>,
    pub dashboard: Vec<DashboardDay>,
    pub subjects: Vec<Subject>,
    pub calendar: BTreeMap<NaiveDate, CalendarDay>,
    pub absences: Absences,
    pub notifications: Vec<Notification>,
    pub messages: Vec<Message>,
    /// When the data was last loaded completely, as a Unix time.
    pub fetched_at: Option<i64>,
    /// Entries moved to another day, by [homework_key].
    #[serde(default)]
    pub moved: BTreeMap<String, Moved>,
    /// When each entry was seen first, by [homework_key].
    #[serde(default)]
    pub first_seen: BTreeMap<String, i64>,
    /// Earlier versions of changed entries.
    #[serde(default)]
    pub previous: BTreeMap<String, PreviousVersion>,
    /// New or changed entries the user has not looked at yet.
    #[serde(default)]
    pub unseen: std::collections::BTreeSet<String>,
}

/// Which parts failed to load, with the first error.
#[derive(Debug, Default)]
pub struct RefreshReport {
    pub failed: Vec<&'static str>,
    pub error: Option<Error>,
}

pub fn monday_of(day: NaiveDate) -> NaiveDate {
    day - Duration::days(day.weekday().num_days_from_monday() as i64)
}

pub fn today() -> NaiveDate {
    Local::now().date_naive()
}

impl Data {
    pub fn load(path: &Path) -> Option<Data> {
        let bytes = std::fs::read(path).ok()?;
        serde_json::from_slice(&bytes).ok()
    }

    /// Written to a temporary file first, so a crash never leaves half a file.
    pub fn save(&self, path: &Path) -> std::io::Result<()> {
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        let tmp = path.with_extension("tmp");
        std::fs::write(&tmp, serde_json::to_vec(self)?)?;
        std::fs::rename(tmp, path)
    }

    /// Loads everything; the parts are fetched at the same time.
    pub fn refresh(&mut self, client: &Client) -> RefreshReport {
        let monday = monday_of(today());
        let semester = self.config.as_ref().and_then(|c| c.current_semester);
        let (dashboard, absences, notifications, messages, weeks, grades) = std::thread::scope(|s| {
            let dashboard = s.spawn(|| client.send("api/student/dashboard/dashboard", json!({ "viewFuture": true })));
            let absences = s.spawn(|| client.send("api/student/dashboard/absences", json!({})));
            let notifications = s.spawn(|| client.send("api/notification/unread", json!({})));
            let messages = s.spawn(|| client.send("api/message/getMyMessages", json!({})));
            let weeks = s.spawn(|| {
                [monday, monday + Duration::days(7)]
                    .map(|m| client.send("api/calendar/student", json!({ "startDate": m.format("%Y-%m-%d").to_string() })))
            });
            // The server answers for the semester chosen before, so the two
            // semesters are loaded one after the other.
            let grades = s.spawn(|| load_grades(client, semester));
            (
                dashboard.join().unwrap(),
                absences.join().unwrap(),
                notifications.join().unwrap(),
                messages.join().unwrap(),
                weeks.join().unwrap(),
                grades.join().unwrap(),
            )
        });

        let mut report = RefreshReport::default();
        let fail = |part: &'static str, e: Error, report: &mut RefreshReport| {
            report.failed.push(part);
            report.error.get_or_insert(e);
        };
        match dashboard {
            Ok(v) => {
                let new = parse::dashboard(&v);
                self.track_changes(&new);
                self.dashboard = new;
            }
            Err(e) => fail("Hausaufgaben", e, &mut report),
        }
        match absences {
            Ok(v) => self.absences = parse::absences(&v),
            Err(e) => fail("Absenzen", e, &mut report),
        }
        match notifications {
            Ok(v) => self.notifications = parse::notifications(&v),
            Err(e) => fail("Benachrichtigungen", e, &mut report),
        }
        match messages {
            Ok(v) => self.messages = parse::messages(&v),
            Err(e) => fail("Mitteilungen", e, &mut report),
        }
        for week in weeks {
            match week {
                Ok(v) => {
                    for day in parse::calendar(&v) {
                        self.calendar.insert(day.date, day);
                    }
                }
                Err(e) => fail("Kalender", e, &mut report),
            }
        }
        // Keep the timetable of the last months only.
        let keep_from = monday - Duration::days(120);
        self.calendar.retain(|date, _| *date >= keep_from);
        match grades {
            Ok(semesters) => {
                for (index, v) in semesters.into_iter().enumerate() {
                    if let Some(v) = v {
                        parse::subjects(&v, index, &mut self.subjects);
                    }
                }
            }
            Err(e) => fail("Noten", e, &mut report),
        }
        self.config = client.config().or(self.config.take());
        if report.failed.is_empty() {
            self.fetched_at = Some(Local::now().timestamp());
        }
        report
    }

    /// The timetable of the week starting at [monday], from the server.
    pub fn load_week(&mut self, client: &Client, monday: NaiveDate) -> Result<(), Error> {
        let v = client.send("api/calendar/student", json!({ "startDate": monday.format("%Y-%m-%d").to_string() }))?;
        for day in parse::calendar(&v) {
            self.calendar.insert(day.date, day);
        }
        Ok(())
    }

    /// Grades and observations of one subject in detail.
    pub fn load_subject_details(&mut self, client: &Client, subject_id: i64, semester: usize) -> Result<(), Error> {
        let user = self.config.as_ref().map(|c| c.user_id).unwrap_or(0);
        client.select_semester(semester as u8 + 1)?;
        let v = client.send("api/student/subject_detail", json!({ "studentId": user, "subjectId": subject_id }))?;
        let (grades, observations) = parse::subject_detail(&v);
        if let Some(subject) = self.subjects.iter_mut().find(|s| s.id == subject_id) {
            subject.details[semester] = Some(grades);
            subject.observations[semester] = Some(observations);
        }
        Ok(())
    }

    /// Reports an absence in advance (e.g. a doctor's appointment).
    #[allow(clippy::too_many_arguments)]
    pub fn add_future_absence(
        &mut self,
        client: &Client,
        start: NaiveDate,
        end: NaiveDate,
        start_hour: i32,
        end_hour: i32,
        reason: &str,
        signature: &str,
    ) -> Result<(), Error> {
        client.send(
            "api/student/dashboard/absence_future",
            json!({ "futureAbsence": {
                "startDate": start.format("%Y-%m-%d").to_string(),
                "endDate": end.format("%Y-%m-%d").to_string(),
                "startTime": start_hour,
                "endTime": end_hour,
                "reason": reason,
                "reason_signature": signature,
            }}),
        )?;
        self.reload_absences(client)
    }

    /// Deletes the [index]th reported absence. The server wants back the
    /// complete entry it sent, so it is fetched again.
    pub fn remove_future_absence(&mut self, client: &Client, index: usize) -> Result<(), Error> {
        let raw = client.send("api/student/dashboard/absences", json!({}))?;
        let entry = raw["futureAbsences"]
            .get(index)
            .cloned()
            .ok_or_else(|| Error::Server("Diese Abwesenheit gibt es nicht mehr".into()))?;
        client.send("api/student/dashboard/remove_absence_future", json!({ "futureAbsence": entry }))?;
        self.reload_absences(client)
    }

    fn reload_absences(&mut self, client: &Client) -> Result<(), Error> {
        self.absences = parse::absences(&client.send("api/student/dashboard/absences", json!({}))?);
        Ok(())
    }

    /// Adds an own reminder for [date].
    pub fn add_reminder(&mut self, client: &Client, date: NaiveDate, text: &str) -> Result<(), Error> {
        client.send(
            "api/student/dashboard/save_reminder",
            json!({ "date": date.format("%Y-%m-%d").to_string(), "text": text }),
        )?;
        self.reload_dashboard(client)
    }

    /// Deletes an own reminder.
    pub fn delete_reminder(&mut self, client: &Client, id: i64) -> Result<(), Error> {
        let result = client.send("api/student/dashboard/delete_reminder", json!({ "id": id }))?;
        if result["success"] == false {
            return Err(Error::Server("Die Erinnerung konnte nicht gelöscht werden".into()));
        }
        self.reload_dashboard(client)
    }

    fn reload_dashboard(&mut self, client: &Client) -> Result<(), Error> {
        let new = parse::dashboard(&client.send("api/student/dashboard/dashboard", json!({ "viewFuture": true }))?);
        self.track_changes(&new);
        self.dashboard = new;
        Ok(())
    }

    /// Marks entries that are new or changed since the last load (not on
    /// the very first load) and remembers when each was seen first.
    fn track_changes(&mut self, new: &[DashboardDay]) {
        let now = Local::now().timestamp();
        let first_load = self.dashboard.is_empty();
        let old: std::collections::HashMap<String, &Homework> =
            self.dashboard.iter().flat_map(|d| &d.homework).map(|h| (homework_key(h), h)).collect();
        for h in new.iter().flat_map(|d| &d.homework) {
            let key = homework_key(h);
            self.first_seen.entry(key.clone()).or_insert(now);
            match old.get(&key) {
                None if !first_load => {
                    self.unseen.insert(key);
                }
                Some(before) if before.title != h.title || before.subtitle != h.subtitle => {
                    self.previous.insert(
                        key.clone(),
                        PreviousVersion { title: before.title.clone(), subtitle: before.subtitle.clone(), changed_at: now },
                    );
                    self.unseen.insert(key);
                }
                _ => {}
            }
        }
    }

    /// Moves an entry to another day. Own reminders really move; entries of
    /// teachers can not be changed, so a reminder on the new day shows the
    /// move everywhere, including the website.
    pub fn move_homework(&mut self, client: &Client, h: &Homework, from: NaiveDate, to: NaiveDate) -> Result<(), Error> {
        let key = homework_key(h);
        let own = h.is_reminder();
        let text = if own {
            h.subtitle.clone()
        } else {
            let mut parts: Vec<&str> = Vec::new();
            if let Some(l) = &h.label {
                parts.push(l);
            }
            parts.push(&h.title);
            if !h.subtitle.is_empty() {
                parts.push(&h.subtitle);
            }
            const WD: [&str; 7] = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"];
            format!(
                "Verschoben: {} (eigentlich {}. {})",
                parts.join(" – "),
                WD[from.weekday().num_days_from_monday() as usize],
                from.format("%d.%m.")
            )
        };
        let created = client.send(
            "api/student/dashboard/save_reminder",
            json!({ "date": to.format("%Y-%m-%d").to_string(), "text": text }),
        )?;
        let created_id = crate::json::int(&created["id"])
            .ok_or_else(|| Error::Server("Die Aufgabe konnte nicht verschoben werden".into()))?;
        // Remove what the new reminder replaces: the reminder itself, or the
        // reminder of an earlier move of the same entry.
        let replaced = if own { Some(h.id) } else { self.moved.get(&key).map(|m| m.reminder_id) };
        if let Some(id) = replaced {
            client.send("api/student/dashboard/delete_reminder", json!({ "id": id }))?;
        }
        if !own {
            self.moved.insert(key, Moved { to, reminder_id: created_id });
        }
        self.reload_dashboard(client)
    }

    /// Undoes a move: deletes the reminder on the new day.
    pub fn reset_move(&mut self, client: &Client, h: &Homework) -> Result<(), Error> {
        if let Some(m) = self.moved.remove(&homework_key(h)) {
            client.send("api/student/dashboard/delete_reminder", json!({ "id": m.reminder_id }))?;
        }
        self.reload_dashboard(client)
    }

    /// Upcoming tests (today and later), soonest first.
    pub fn upcoming_tests(&self) -> Vec<(NaiveDate, &Homework)> {
        let today = today();
        self.dashboard
            .iter()
            .filter(|d| d.date >= today)
            .flat_map(|d| d.homework.iter().filter(|h| h.is_test()).map(move |h| (d.date, h)))
            .collect()
    }

    pub fn homework_on(&self, date: NaiveDate) -> &[Homework] {
        self.dashboard.iter().find(|d| d.date == date).map(|d| d.homework.as_slice()).unwrap_or(&[])
    }
}

/// Both semesters' subject overviews (index 0 and 1).
fn load_grades(client: &Client, current: Option<u8>) -> Result<[Option<serde_json::Value>; 2], Error> {
    let user = client.config().map(|c| c.user_id).unwrap_or(0);
    let mut result = [None, None];
    for semester in [1u8, 2] {
        client.select_semester(semester)?;
        result[semester as usize - 1] = Some(client.send("api/student/all_subjects", json!({ "studentId": user }))?);
    }
    // Leave the server on the current semester, as the web page does.
    if let Some(current) = current {
        client.select_semester(current)?;
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn demo_refresh_loads_everything_and_round_trips() {
        let client = Client::new("https://vinzentinum.digitalesregister.it", "demo-user-6540", "x");
        client.login(None).unwrap();
        let mut data = Data::default();
        let report = data.refresh(&client);
        assert!(report.failed.is_empty(), "{:?}", report);
        assert!(!data.dashboard.is_empty());
        assert_eq!(data.subjects.len(), 16);
        assert!(data.calendar.len() >= 10, "two weeks of timetable");
        assert!(data.absences.statistic.percentage.is_some());

        let path = std::env::temp_dir().join(format!("register-test-{}.json", std::process::id()));
        data.save(&path).unwrap();
        assert_eq!(Data::load(&path), Some(data));
        std::fs::remove_file(path).ok();
    }
}
