//! Turns the state into what the window shows, with the texts and formats
//! of the Flutter app.

use std::collections::BTreeMap;

use chrono::{Datelike, Duration, Local, NaiveDate, NaiveDateTime, NaiveTime, Timelike};
use register_core::absences::{self, Level};
use register_core::data::{monday_of, today};
use register_core::grades::{self, Forecast};
use register_core::model::{
    AbsenceGroup, CalendarHour, Grade, Homework, HomeworkKind, Justified, MissedHour, Semester, Subject, looks_like_test,
};
use slint::{Color, ComponentHandle, Image, ModelRc, SharedString, VecModel};

use crate::{format, photos, subject_icons};
use crate::{
    AbsenceItem, AppData, AppWindow, AttachmentItem, CertBlock, ColorItem, NickItem, Prefs, CertRow, ChartLine, GradeItem, HomeworkDay, HomeworkItem, Lesson, MessageItem, State,
    CalcGrade, Competence, DetailCard, DetailRow, GradeGroup, SubjectItem, TargetChip, TeacherView, TestItem, WeakSubject, WeekDay,
};

fn model<T: Clone + 'static>(items: Vec<T>) -> ModelRc<T> {
    ModelRc::new(VecModel::from(items))
}

fn s(text: impl AsRef<str>) -> SharedString {
    text.as_ref().into()
}

fn rgb(c: u32) -> Color {
    Color::from_rgb_u8((c >> 16) as u8, (c >> 8) as u8, c as u8)
}

/// The Flutter app's default abbreviations; other subjects keep their name.
/// What the pages need from the settings while they are built.
#[derive(Default)]
struct Look {
    nicks: Vec<(String, String)>,
    tests_red: bool,
    color_borders: bool,
    colors: BTreeMap<String, u32>,
}

thread_local! {
    static LOOK: std::cell::RefCell<Look> = std::cell::RefCell::new(Look::default());
}

/// The short name of [subject], or the subject itself.
fn nick(subject: &str) -> String {
    LOOK.with(|l| {
        l.borrow().nicks.iter().find(|(name, _)| name == subject).map(|(_, n)| n.clone()).unwrap_or_else(|| subject.to_owned())
    })
}

/// "Mo", "Di" … (two letters of the weekday).
fn wd2(date: NaiveDate) -> String {
    format::weekday(date).chars().take(2).collect()
}

pub fn apply(ui: &AppWindow, state: &mut State) {
    // Every subject gets its colour once and keeps it.
    let mut names: Vec<String> = state.data.subjects.iter().map(|s| s.name.clone()).collect();
    names.extend(state.data.calendar.values().flat_map(|d| d.hours.iter().map(|h| h.subject.clone())));
    let before = state.settings.subject_colors.len();
    for name in names {
        state.settings.subject_color(&name);
    }
    if state.settings.subject_colors.len() != before {
        state.settings.save();
    }

    LOOK.with(|l| {
        *l.borrow_mut() = Look {
            nicks: state.settings.nicks.clone(),
            tests_red: state.settings.tests_red,
            color_borders: state.settings.color_borders,
            colors: state.settings.subject_colors.clone(),
        }
    });
    apply_prefs(ui, state);

    let d = ui.global::<AppData>();
    let data = &state.data;
    d.set_full_name(s(data.config.as_ref().map(|c| c.full_name.as_str()).unwrap_or("")));
    d.set_school(s(&state.settings.school));
    d.set_fetched(s(match data.fetched_at.and_then(|t| chrono::DateTime::from_timestamp(t, 0)) {
        Some(t) => {
            let t = t.with_timezone(&Local);
            format!("ZULETZT GELADEN: {} {:02}:{:02}", format::short(t.date_naive()), t.hour(), t.minute())
        }
        None => "NOCH NICHT GELADEN".into(),
    }));
    d.set_tomorrow_date(s((today() + Duration::days(1)).format("%d.%m.%Y").to_string()));
    apply_today(ui, state);
    apply_homework(&d, state);
    apply_grades(&d, state);
    apply_calendar(&d, state);
    apply_absences(&d, state);
    apply_messages(&d, &state.data);
    apply_certificate(&d, &state.data);
}

fn apply_certificate(d: &AppData, data: &register_core::data::Data) {
    use register_core::json::Block;
    let Some(blocks) = &data.certificate else {
        return;
    };
    d.set_certificate(model(
        blocks
            .iter()
            .map(|b| match b {
                Block::Heading(level, t) => CertBlock { kind: 0, level: *level as i32, text: s(t), ..Default::default() },
                Block::Text(t) => CertBlock { kind: 1, text: s(t), ..Default::default() },
                Block::Table { header, rows } => CertBlock {
                    kind: 2,
                    header: *header,
                    rows: model(rows.iter().map(|r| CertRow { cells: model(r.iter().map(s).collect()) }).collect()),
                    ..Default::default()
                },
            })
            .collect(),
    ));
    d.set_certificate_state(1);

}

fn parse_time(t: &str) -> Option<NaiveTime> {
    NaiveTime::parse_from_str(t, "%H:%M").ok()
}

/// "1-2" or "3." like the Flutter app.
fn hours_short(h: &CalendarHour) -> String {
    if h.length() > 1 { format!("{}–{}", h.from_hour, h.to_hour) } else { format!("{}.", h.from_hour) }
}

fn lesson(h: &CalendarHour, date: NaiveDate, now: NaiveDateTime, colors: &BTreeMap<String, u32>) -> Lesson {
    let start = parse_time(h.start()).map(|t| date.and_time(t));
    let end = parse_time(h.end()).map(|t| date.and_time(t));
    let notes: Vec<String> = h.homework_exams.iter().map(|e| format!("{}: {}", e.type_name, e.name)).collect();
    Lesson {
        hours: s(hours_short(h)),
        time: s(if h.start().is_empty() { String::new() } else { format!("{}–{}", h.start(), h.end()) }),
        subject: s(&h.subject),
        nick: s(nick(&h.subject)),
        teachers: s(h.teachers.iter().map(|t| t.last_name.clone()).collect::<Vec<_>>().join("\n")),
        teacher_width: h.teachers.iter().map(|t| t.last_name.chars().count()).max().unwrap_or(0) as i32,
        rooms: s(h.rooms.join("\n")),
        note: s(notes.join(" · ")),
        color: rgb(colors.get(&h.subject).copied().unwrap_or(0x7C5CFF)),
        span: h.length(),
        first: h.from_hour,
        index: 0,
        pattern: Image::default(),
        photo: Image::default(),
        has_photo: false,
        selected: false,
        has_test: h.homework_exams.iter().any(|e| looks_like_test(&e.type_name) || looks_like_test(&e.name)),
        is_now: matches!((start, end), (Some(a), Some(b)) if now >= a && now < b),
        is_past: end.is_some_and(|e| now >= e),
    }
}

fn homework_item(h: &Homework, header: String) -> HomeworkItem {
    let mut title = h.title.clone();
    if let Some(g) = h.grade.as_deref().and_then(|g| register_core::parse::grade_value(Some(g))) {
        title = format!("{title} · {}", grades::format_grade(g));
    }
    let test = h.is_test();
    // _accent: the stripe on the entry's edge.
    let (accent, tint) = LOOK.with(|l| {
        let l = l.borrow();
        let subject = h.label.as_ref().and_then(|label| l.colors.get(label)).filter(|_| l.color_borders);
        if test && l.tests_red {
            (1, Color::default())
        } else if let Some(&c) = subject {
            (3, rgb(c))
        } else if h.kind == HomeworkKind::Grade || h.checked {
            (2, Color::default())
        } else {
            (0, Color::default())
        }
    });
    HomeworkItem {
        id: h.id as i32,
        kind: s(format::kind_name(h.kind)),
        urgent: false,
        header: s(header),
        title: s(title),
        subtitle: s(&h.subtitle),
        is_test: test,
        is_grade: h.kind == HomeworkKind::Grade,
        checkable: h.checkable,
        checked: h.checked,
        deletable: h.is_reminder(),
        type_icon: if test {
            1
        } else {
            match h.kind {
                HomeworkKind::Grade => 2,
                HomeworkKind::Observation => 3,
                HomeworkKind::GradeGroup => 4,
                HomeworkKind::Homework => 5,
                _ => 0,
            }
        },
        accent,
        tint,
        badge: SharedString::new(),
        moved_to: SharedString::new(),
        day_date: SharedString::new(),
        index: 0,
    }
}


/// "Fr. 13.11." (EE dd.MM.)
pub fn day_short(date: NaiveDate) -> String {
    format!("{}. {}", wd2(date), format::short(date))
}

/// The tests of the next 30 days, as on the today page.
pub fn tests_soon(data: &register_core::data::Data, today: NaiveDate) -> Vec<(NaiveDate, &Homework)> {
    data.upcoming_tests().into_iter().filter(|(d, _)| (*d - today).num_days() <= 30).collect()
}

pub fn apply_today(ui: &AppWindow, state: &State) {
    let d = ui.global::<AppData>();
    let data = &state.data;
    let now = Local::now().naive_local();
    let today = now.date();
    let colors = &state.settings.subject_colors;
    d.set_now_header(s(format!("{} · {:02}:{:02}", format::long(today).to_uppercase(), now.hour(), now.minute())));
    d.set_day_number((today - NaiveDate::from_ymd_opt(2026, 1, 1).unwrap()).num_days() as i32);

    let day = data.calendar.get(&today);
    let hours: &[CalendarHour] = day.map(|d| d.hours.as_slice()).unwrap_or(&[]);
    d.set_today_lessons(model(
        hours
            .iter()
            .map(|h| {
                let mut l = lesson(h, today, now, colors);
                l.rooms = s(h.rooms.join(", "));
                l
            })
            .collect(),
    ));

    // What the "now" card says (_NowCard).
    let times = |h: &CalendarHour| {
        Some((today.and_time(parse_time(h.start())?), today.and_time(parse_time(h.end())?)))
    };
    let current = hours.iter().find(|h| times(h).is_some_and(|(a, b)| now >= a && now < b));
    let next = hours.iter().find(|h| times(h).is_some_and(|(a, _)| a > now));
    let over = hours.last().and_then(times).is_some_and(|(_, b)| now >= b);
    let (state_no, subject, minutes, rooms, next_time) = if day.is_none() {
        (0, String::new(), 0, String::new(), String::new())
    } else if hours.is_empty() {
        (1, String::new(), 0, String::new(), String::new())
    } else if let Some(h) = current {
        let (_, b) = times(h).unwrap();
        (2, nick(&h.subject), (b - now).num_minutes(), h.rooms.join(", "), String::new())
    } else if let Some(h) = next {
        let (a, _) = times(h).unwrap();
        (3, nick(&h.subject), (a - now).num_minutes(), String::new(), h.start().to_owned())
    } else if over {
        (4, String::new(), 0, String::new(), String::new())
    } else {
        (5, String::new(), 0, String::new(), String::new())
    };
    d.set_now_state(state_no);
    d.set_now_subject(s(subject));
    d.set_now_minutes(minutes as i32);
    d.set_now_rooms(s(rooms));
    d.set_next_time(s(next_time));

    // Due today and tomorrow (_TaskRow).
    let mut due = Vec::new();
    for (date, when) in [(today, "HEUTE"), (today + Duration::days(1), "MORGEN")] {
        for h in data.homework_on(date).iter().filter(|h| !matches!(h.kind, HomeworkKind::Grade | HomeworkKind::Observation)) {
            let header = match &h.label {
                Some(l) => format!("{when} · {}", l.to_uppercase()),
                None => when.to_owned(),
            };
            let mut item = homework_item(h, header);
            item.urgent = date == today;
            due.push(item);
        }
    }
    d.set_due(model(due));

    // Tests with countdown and what is needed (_TestCountdown, TestTargets).
    let semester = semester_of(state.semester);
    let tests: Vec<TestItem> = tests_soon(data, today)
        .into_iter()
        .enumerate()
        .map(|(i, (date, h))| {
            let subject = h.label.as_deref().and_then(|l| {
                data.subjects.iter().find(|s| s.name.trim().eq_ignore_ascii_case(l.trim()))
            });
            let average = subject.and_then(|s| grades::average(s, semester));
            let targets: Vec<TargetChip> = match (subject, average) {
                (Some(subject), Some(_)) => [6.0, 7.0, 8.0]
                    .into_iter()
                    .map(|target| {
                        let (kind, needed) = match grades::forecast(subject, semester, target, 100) {
                            Forecast::Safe => (0, 0.0),
                            Forecast::Impossible => (1, 0.0),
                            Forecast::Needs(g) => (2, g),
                        };
                        TargetChip {
                            target: target as i32,
                            kind,
                            needed: s(if kind == 2 { grades::format_steps(needed) } else { String::new() }),
                            needed_value: needed as f32,
                        }
                    })
                    .collect(),
                _ => Vec::new(),
            };
            TestItem {
                index: i as i32,
                days: (date - today).num_days() as i32,
                header: s(match &h.label {
                    Some(l) => format!("{} · {}", day_short(date), l).to_uppercase(),
                    None => day_short(date).to_uppercase(),
                }),
                title: s(&h.title),
                subtitle: s(&h.subtitle),
                average_now: s(average.map(|a| grades::format_steps(a as f64 / 100.0)).unwrap_or_default()),
                targets: model(targets),
                date_long: s(format!("{}, {}", format::weekday(date), format::day_month(date))),
            }
        })
        .collect();
    d.set_tests(model(tests));

    // Subjects below 6, lowest first.
    let mut weak: Vec<(String, f64)> = data
        .subjects
        .iter()
        .filter_map(|s| Some((s.name.clone(), grades::average(s, semester)? as f64 / 100.0)))
        .filter(|(_, avg)| *avg < grades::PASS_MARK)
        .collect();
    weak.sort_by(|a, b| a.1.total_cmp(&b.1));
    d.set_weak(model(
        weak.into_iter()
            .map(|(name, avg)| WeakSubject { name: s(name), value: avg as f32, label: s(grades::format_steps(avg)) })
            .collect(),
    ));
}

/// The days for [sessions] study sessions before the test: the days right
/// before it, from today on and without Sundays (studyDays).
pub fn study_days(test: NaiveDate, today: NaiveDate, sessions: usize) -> Vec<NaiveDate> {
    let mut result = Vec::new();
    let mut day = test - Duration::days(1);
    while result.len() < sessions && day >= today {
        if day.weekday() != chrono::Weekday::Sun {
            result.push(day);
        }
        day -= Duration::days(1);
    }
    result.reverse();
    result
}

fn apply_homework(d: &AppData, state: &State) {
    let today = today();
    let past = state.show_past;
    let data = &state.data;
    let mut days: Vec<HomeworkDay> = Vec::new();
    let mut add = |date: NaiveDate, items: &[Homework]| {
        let title = match (date - today).num_days() {
            0 => "Heute".to_owned(),
            1 => "Morgen".to_owned(),
            -1 => "Gestern".to_owned(),
            _ => format!("{}, {}", format::weekday(date), format::short(date)),
        };
        let header = if date == today {
            format!("HEUTE · {}", date.format("%d.%m"))
        } else {
            format!("{}. · {}", wd2(date).to_uppercase(), date.format("%d.%m.%Y"))
        };
        let key_date = date.format("%d.%m.%Y").to_string();
        let items: Vec<HomeworkItem> = items
            .iter()
            .enumerate()
            .map(|(i, h)| {
                let key = register_core::data::homework_key(h);
                let mut item = homework_item(h, h.label.as_deref().unwrap_or("").to_uppercase());
                item.day_date = s(&key_date);
                item.index = i as i32;
                if state.settings.mark_new && data.unseen.contains(&key) {
                    item.badge = s(if data.previous.contains_key(&key) { "geändert" } else { "neu" });
                }
                if let Some(m) = data.moved.get(&key) {
                    item.moved_to = s(day_short(m.to));
                }
                item
            })
            .collect();
        days.push(HomeworkDay {
            date: s(key_date),
            header: s(header),
            title: s(title),
            is_today: date == today,
            items: model(items),
        });
    };
    if past {
        let mut list: Vec<_> = data.dashboard.iter().filter(|d| d.date < today && !d.homework.is_empty()).collect();
        list.reverse();
        for day in list {
            add(day.date, &day.homework);
        }
    } else {
        // Every day from today to the last entry, so reminders can be added
        // to any of them.
        let last = data.dashboard.iter().map(|d| d.date).max().unwrap_or(today).max(today + Duration::days(1));
        let mut date = today;
        while date <= last {
            add(date, data.homework_on(date));
            date += Duration::days(1);
        }
    }
    d.set_show_past(past);
    d.set_homework(model(days));
}

/// Details of an entry for the info dialog.
pub fn homework_info(data: &register_core::data::Data, h: &Homework, date: NaiveDate) -> String {
    let key = register_core::data::homework_key(h);
    let mut lines = Vec::new();
    let kind = match h.kind {
        HomeworkKind::LessonHomework => "Hausaufgabe aus dem Unterricht",
        HomeworkKind::GradeGroup => if h.is_test() { "Test / Schularbeit" } else { "Prüfung oder Abgabe" },
        HomeworkKind::Grade => "Note",
        HomeworkKind::Observation => "Beobachtung",
        HomeworkKind::Homework => "Eigene Erinnerung",
        HomeworkKind::Other => "Eintrag",
    };
    lines.push(format!("{kind} für {}", format::long(date)));
    if let Some(label) = &h.label {
        lines.push(format!("Fach: {label}"));
    }
    if let Some(deadline) = h.deadline {
        lines.push(format!("Fällig: {} um {:02}:{:02}", deadline.date().format("%d.%m.%Y"), deadline.hour(), deadline.minute()));
    }
    let stamp = |t: i64| {
        chrono::DateTime::from_timestamp(t, 0)
            .map(|t| t.with_timezone(&Local).format("%d.%m.%Y, %H:%M").to_string())
            .unwrap_or_default()
    };
    if let Some(&t) = data.first_seen.get(&key) {
        lines.push(format!("Zuerst gesehen: {}", stamp(t)));
    }
    if let Some(p) = data.previous.get(&key) {
        lines.push(format!("Geändert: {}", stamp(p.changed_at)));
        lines.push(format!("Vorher: {}{}", p.title, if p.subtitle.is_empty() { String::new() } else { format!(" – {}", p.subtitle) }));
    }
    if let Some(m) = data.moved.get(&key) {
        lines.push(format!("Verschoben auf {}", format::long(m.to)));
    }
    lines.join("\n")
}

fn semester_of(index: i32) -> Semester {
    match index {
        0 => Semester::First,
        1 => Semester::Second,
        _ => Semester::All,
    }
}

const MONTHS_SHORT: [&str; 12] =
    ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez."];

fn short_month(date: NaiveDate) -> String {
    format!("{}. {}", date.day(), MONTHS_SHORT[date.month0() as usize])
}

/// One line per subject through its grades (grade 10 at the top, 3 at the
/// bottom), in a 1000 × 100 box.
fn chart(
    subjects: &[Subject],
    semester: Semester,
    colors: &BTreeMap<String, u32>,
    thick: &BTreeMap<String, i32>,
) -> (Vec<ChartLine>, String, String) {
    let points: Vec<(&Subject, Vec<(NaiveDate, f64)>)> = subjects
        .iter()
        .map(|s| {
            let mut p: Vec<(NaiveDate, f64)> = grades::grades_of(s, semester)
                .filter(|g| !g.cancelled)
                .filter_map(|g| Some((g.date, g.value? as f64 / 100.0)))
                .collect();
            p.sort_by_key(|p| p.0);
            (s, p)
        })
        .filter(|(_, p)| !p.is_empty())
        .collect();
    let dates: Vec<NaiveDate> = points.iter().flat_map(|(_, p)| p.iter().map(|p| p.0)).collect();
    let (Some(&from), Some(&to)) = (dates.iter().min(), dates.iter().max()) else {
        return (Vec::new(), String::new(), String::new());
    };
    let span = (to - from).num_days().max(1) as f64;
    let x = |d: NaiveDate| (d - from).num_days() as f64 / span * 980.0 + 10.0;
    let y = |g: f64| (10.0 - g.clamp(3.0, 10.0)) / 7.0 * 100.0;
    let lines = points
        .into_iter()
        .map(|(subject, p)| {
            let color = rgb(colors.get(&subject.name).copied().unwrap_or(0x7C5CFF));
            let thick = thick.get(&subject.name).copied().unwrap_or(2);
            let (commands, dots) = if p.len() == 1 {
                let (px, py) = (x(p[0].0), y(p[0].1));
                (String::new(), format!("M {:.1} {py:.1} a 5 2.5 0 1 0 10 0 a 5 2.5 0 1 0 -10 0 Z", px - 5.0))
            } else {
                let path: Vec<String> = p
                    .iter()
                    .enumerate()
                    .map(|(i, (d, g))| format!("{} {:.1} {:.1}", if i == 0 { "M" } else { "L" }, x(*d), y(*g)))
                    .collect();
                (path.join(" "), String::new())
            };
            ChartLine { name: s(&subject.name), thick, color, commands: s(commands), dots: s(dots) }
        })
        .collect();
    (lines, short_month(from), short_month(to))
}

fn grade_item(g: &Grade) -> GradeItem {
    GradeItem {
        value: s(g.value.map(grades::format_grade).unwrap_or_default()),
        value_num: g.value.map(|v| v as f32 / 100.0).unwrap_or(0.0),
        name: s(if g.name.is_empty() { g.kind.clone() } else { g.name.clone() }),
        description: s(&g.description),
        line: s(format!("{}: {} - {}%", g.date.format("%d.%m.%y"), g.kind, g.weight_percent)),
        created: s(&g.created),
        cancelled_reason: s(g.cancelled_description.as_deref().unwrap_or("")),
        cancelled: g.cancelled,
        observation: false,
        competences: model(
            g.competences.iter().map(|(name, stars)| Competence { name: s(name), stars: *stars }).collect(),
        ),
    }
}

fn observation_item(o: &register_core::model::Observation) -> GradeItem {
    GradeItem {
        value: SharedString::new(),
        value_num: 0.0,
        name: s(&o.kind),
        description: SharedString::new(),
        line: s(format!(
            "{}{}",
            o.date.format("%d.%m.%y"),
            if o.note.is_empty() { String::new() } else { format!(": {}", o.note) }
        )),
        created: s(&o.created),
        cancelled_reason: SharedString::new(),
        cancelled: o.cancelled,
        observation: true,
        competences: model(Vec::new()),
    }
}

/// The semester's detail entries of [subject], or None before they are
/// loaded: grades and observations, newest first.
fn detail_entries(subject: &Subject, semester: Semester) -> Option<Vec<(NaiveDate, String, GradeItem, bool)>> {
    let semesters: &[usize] = match semester {
        Semester::First => &[0],
        Semester::Second => &[1],
        Semester::All => &[0, 1],
    };
    let mut entries = Vec::new();
    let mut any = false;
    for &i in semesters {
        if let (Some(grades), Some(observations)) = (&subject.details[i], &subject.observations[i]) {
            any = true;
            entries.extend(grades.iter().map(|g| (g.date, g.kind.clone(), grade_item(g), g.cancelled)));
            entries.extend(observations.iter().map(|o| (o.date, "Beobachtung".to_owned(), observation_item(o), o.cancelled)));
        }
    }
    entries.sort_by(|a, b| b.0.cmp(&a.0));
    any.then_some(entries)
}

fn apply_grades(d: &AppData, state: &State) {
    let semester = semester_of(state.semester);
    let today = today();
    let tests = state.data.upcoming_tests();
    let ignored = &state.settings.ignored_subjects;
    let is_ignored = |name: &str| ignored.iter().any(|i| i.eq_ignore_ascii_case(name));
    let subjects: Vec<SubjectItem> = state
        .data
        .subjects
        .iter()
        .map(|subject| {
            let average = grades::average(subject, semester);
            let next_test = tests
                .iter()
                .find(|(_, h)| h.label.as_deref().is_some_and(|l| l.trim().eq_ignore_ascii_case(subject.name.trim())));
            let entries = detail_entries(subject, semester);
            let loaded = entries.is_some();
            let entries: Vec<_> = entries.unwrap_or_default().into_iter().filter(|e| state.show_cancelled || !e.3).collect();
            let groups: Vec<GradeGroup> = if state.sort_by_type {
                let mut types: Vec<String> = Vec::new();
                for e in &entries {
                    if !types.contains(&e.1) {
                        types.push(e.1.clone());
                    }
                }
                types
                    .into_iter()
                    .map(|t| GradeGroup {
                        title: s(t.to_uppercase()),
                        entries: model(entries.iter().filter(|e| e.1 == t).map(|e| e.2.clone()).collect()),
                    })
                    .collect()
            } else {
                vec![GradeGroup { title: SharedString::new(), entries: model(entries.into_iter().map(|e| e.2).collect()) }]
            };
            SubjectItem {
                id: subject.id as i32,
                name: s(&subject.name),
                average: s(average.map(grades::format_average).unwrap_or_else(|| "/".into())),
                average_value: average.map(|a| a as f32 / 100.0).unwrap_or(0.0),
                ignored: is_ignored(&subject.name),
                test_chip: s(next_test.map(|(date, _)| format!("Test {}", day_short(*date))).unwrap_or_default()),
                next_test: s(next_test
                    .map(|(date, h)| format!("Nächster Test: {} am {}, {}", h.title, format::weekday(*date), format::day_month(*date)))
                    .unwrap_or_default()),
                loaded,
                groups: model(groups),
            }
        })
        .collect();
    let _ = today;
    let overall = grades::overall_average(&state.data.subjects, semester, ignored);
    d.set_semester(state.semester);
    d.set_show_cancelled(state.show_cancelled);
    d.set_sort_by_type(state.sort_by_type);
    d.set_overall(s(overall.map(grades::format_average).unwrap_or_else(|| "/".into())));
    d.set_overall_value(overall.map(|a| a as f32 / 100.0).unwrap_or(0.0));
    d.set_ignored_note(s(if state.data.subjects.iter().any(|s| is_ignored(&s.name)) {
        "* Du hast dieses Fach aus dem Notendurchschnitt ausgeschlossen"
    } else {
        ""
    }));
    let (lines, from, to) =
        chart(&state.data.subjects, semester, &state.settings.subject_colors, &state.settings.subject_thick);
    d.set_chart(model(lines));
    d.set_chart_from(s(from));
    d.set_chart_to(s(to));
    d.set_subjects(model(subjects));
    apply_calculator(d, state);
}

/// The grade calculator's list and average.
pub fn apply_calculator(d: &AppData, state: &State) {
    d.set_calc_grades(model(
        state
            .calc
            .iter()
            .map(|(g, w, desc)| CalcGrade {
                grade: s(grades::format_grade(*g)),
                weight: s(w.to_string()),
                description: s(desc.as_deref().unwrap_or("")),
            })
            .collect(),
    ));
    let pairs: Vec<(i32, i32)> = state.calc.iter().map(|(g, w, _)| (*g, *w)).collect();
    d.set_calc_average(s(grades::calculator_average(&pairs)));
    d.set_calc_subjects(model(state.data.subjects.iter().map(|s| s.name.as_str().into()).collect()));
}

fn apply_calendar(d: &AppData, state: &State) {
    let now = Local::now().naive_local();
    let today = now.date();
    let colors = &state.settings.subject_colors;
    let brainrot = state.settings.style == 1;
    let monday = monday_of(today) + Duration::weeks(state.week_offset);
    let mut days = Vec::new();
    let mut hours = 6;
    for i in 0..6 {
        let date = monday + Duration::days(i);
        let list: Vec<&CalendarHour> =
            state.data.calendar.get(&date).map(|d| d.hours.iter().collect()).unwrap_or_default();
        // Saturday only when there are lessons.
        if i == 5 && list.is_empty() {
            continue;
        }
        hours = hours.max(list.iter().map(|h| h.to_hour).max().unwrap_or(0));
        let lessons: Vec<Lesson> = list
            .into_iter()
            .enumerate()
            .map(|(n, h)| {
                let mut l = lesson(h, date, now, colors);
                l.index = n as i32;
                l.selected = state.detail.is_some_and(|(dd, nn)| dd == date && nn == n);
                if brainrot {
                    if state.settings.show_photos
                        && let Some(photo) = h.teachers.first().and_then(|t| photos::image_for(t, &state.settings.own_images, true))
                    {
                        l.photo = photo;
                        l.has_photo = true;
                    }
                } else {
                    l.pattern = subject_icons::pattern(&h.subject, colors.get(&h.subject).copied().unwrap_or(0x7C5CFF));
                }
                l
            })
            .collect();
        days.push(WeekDay {
            weekday: s(wd2(date).to_uppercase()),
            date: s(date.format("%d.%m").to_string()),
            is_today: date == today,
            lessons: model(lessons),
        });
    }
    let friday = monday + Duration::days(4);
    d.set_week_title(s(format!("{} - {}", monday.format("%d.%m.%y"), friday.format("%d.%m.%y"))));
    d.set_week_hours(hours);
    d.set_week(model(days));
    apply_detail(d, state);
}

const MONTHS_ABBR: [&str; 12] = ["Jan.", "Feb.", "März", "Apr.", "Mai", "Juni", "Juli", "Aug.", "Sep.", "Okt.", "Nov.", "Dez."];

/// The lessons of the chosen day in detail (CalendarCard).
fn apply_detail(d: &AppData, state: &State) {
    let Some((date, selected)) = state.detail else {
        d.set_detail_open(false);
        return;
    };
    d.set_detail_open(true);
    d.set_detail_title(s(format!("{}., {}. {}", wd2(date), date.day(), MONTHS_ABBR[date.month0() as usize])));
    let colors = &state.settings.subject_colors;
    let brainrot = state.settings.style == 1;
    let hours: &[CalendarHour] = state.data.calendar.get(&date).map(|d| d.hours.as_slice()).unwrap_or(&[]);
    let cards: Vec<DetailCard> = hours
        .iter()
        .enumerate()
        .map(|(n, h)| {
            let teachers: Vec<TeacherView> = h
                .teachers
                .iter()
                .map(|t| {
                    let photo =
                        if state.settings.show_photos { photos::image_for(t, &state.settings.own_images, brainrot) } else { None };
                    TeacherView {
                        name: s(t.full_name()),
                        initial: s(t.last_name.chars().next().map(|c| c.to_string()).unwrap_or_else(|| "?".into())),
                        has_photo: photo.is_some(),
                        photo: photo.unwrap_or_default(),
                        custom: brainrot
                            && state.settings.own_images.contains_key(&register_core::teacher_photos::teacher_key(t)),
                    }
                })
                .collect();
            let mut rows = Vec::new();
            if !h.teachers.is_empty() {
                rows.push(DetailRow {
                    icon: if h.teachers.len() == 1 { 1 } else { 2 },
                    title: s(if h.teachers.len() == 1 { "LEHRER*IN" } else { "LEHRER*INNEN" }),
                    content: s(h.teachers.iter().map(|t| t.full_name()).collect::<Vec<_>>().join(", ")),
                });
            }
            if !h.rooms.is_empty() {
                rows.push(DetailRow { icon: 3, title: s("RÄUME"), content: s(h.rooms.join(", ")) });
            }
            for (kind, name) in &h.lesson_contents {
                rows.push(DetailRow { icon: 4, title: s(kind.to_uppercase()), content: s(name) });
            }
            for e in &h.homework_exams {
                let test = looks_like_test(&e.type_name) || looks_like_test(&e.name);
                rows.push(DetailRow { icon: if test { 5 } else { 6 }, title: s(e.type_name.to_uppercase()), content: s(&e.name) });
            }
            DetailCard {
                subject: s(&h.subject),
                letter: s(h.subject.chars().next().map(|c| c.to_uppercase().to_string()).unwrap_or_else(|| "?".into())),
                color: rgb(colors.get(&h.subject).copied().unwrap_or(0x7C5CFF)),
                hours: s(if h.from_hour == h.to_hour {
                    format!("{}. STUNDE", h.from_hour)
                } else {
                    format!("{}. – {}. STUNDE", h.from_hour, h.to_hour)
                }),
                times: s(h.times.iter().map(|(a, b)| format!("{a} – {b}")).collect::<Vec<_>>().join(", ")),
                teachers: model(teachers),
                rows: model(rows),
                selected: n == selected,
            }
        })
        .collect();
    d.set_detail_selected(selected as i32);
    d.set_detail_cards(model(cards));
}

/// "Mi. 14.10.2026"
fn day_long(date: NaiveDate) -> String {
    format!("{}. {}.{}.{}", wd2(date), date.day(), date.month(), date.year())
}

fn level_number(level: Level) -> i32 {
    match level {
        Level::Green => 0,
        Level::Yellow => 1,
        Level::Red => 2,
        Level::Over => 3,
    }
}

fn justified(j: Justified) -> (i32, &'static str) {
    match j {
        Justified::Justified => (0, "Entschuldigt"),
        Justified::NotYet => (1, "Offen"),
        Justified::NotJustified => (2, "Nicht entschuldigt"),
        Justified::ForSchool => (3, "Im Auftrag der Schule"),
    }
}

fn hour_range(mut hours: Vec<i32>) -> String {
    hours.sort();
    hours.dedup();
    match (hours.first(), hours.last()) {
        (Some(a), Some(b)) if a == b => format!("{a}. h"),
        (Some(a), Some(b)) if (b - a + 1) as usize == hours.len() => format!("{a}.–{b}. h"),
        _ => hours.iter().map(|h| format!("{h}.")).collect::<Vec<_>>().join(", ") + " h",
    }
}

fn apply_absences(d: &AppData, state: &State) {
    let a = &state.data.absences;
    let stat = &a.statistic;
    d.set_absence_can_edit(a.can_edit && !state.client.as_ref().is_some_and(|c| c.is_demo()));
    match stat.percentage {
        Some(p) => {
            let level = absences::level(p);
            d.set_absence_percent(s(format::percent(p)));
            d.set_absence_fraction((p / absences::LIMIT_PERCENT) as f32);
            d.set_absence_level(level_number(level));
            d.set_absence_label(s(match level {
                Level::Green => "Im grünen Bereich",
                Level::Yellow => "Aufpassen",
                Level::Red => "Kritisch",
                Level::Over => "Über der Grenze",
            }));
            d.set_absence_left(s(if p >= absences::LIMIT_PERCENT {
                "GRENZE 25 % ÜBERSCHRITTEN".to_owned()
            } else {
                format!("NOCH {} BIS 25 %", format::percent(absences::LIMIT_PERCENT - p))
            }));
        }
        None => {
            d.set_absence_percent(SharedString::new());
            d.set_absence_left(SharedString::new());
        }
    }
    match absences::project(stat, state.data.calendar.values(), today()) {
        Some(p) => {
            let end = format!("{}. {}", p.end.day(), format::month(p.end.month()));
            d.set_year_left(p.still_allowed as i32);
            if p.still_allowed == 0 {
                d.set_year_allowed(s("Keine Fehlstunde mehr übrig"));
                d.set_year_allowed_rest(SharedString::new());
            } else {
                let unit = if p.still_allowed == 1 { "Stunde" } else { "Stunden" };
                d.set_year_allowed(s(format!("Noch ~{} {unit}", p.still_allowed)));
                d.set_year_allowed_rest(s(format!("fehlen bis Schulende ({end}) erlaubt")));
            }
            let missed = if p.missed > 0.0 && p.missed < 1.0 { 1 } else { p.missed.round() as i64 };
            d.set_year_detail(s(format!(
                "Aufs ganze Schuljahr: {} (~{missed} von ~{} Stunden)",
                format::percent(p.year_percent),
                p.total_lessons
            )));
        }
        None => {
            d.set_year_allowed(SharedString::new());
            d.set_year_allowed_rest(SharedString::new());
            d.set_year_detail(SharedString::new());
        }
    }
    let n = |v: Option<i64>| s(v.map(|v| v.to_string()).unwrap_or_else(|| "–".into()));
    d.set_count_absences(n(stat.counter));
    d.set_count_justified(n(stat.justified));
    d.set_count_not_justified(n(stat.not_justified));
    d.set_count_delayed(n(stat.delayed));

    let mut groups: Vec<&AbsenceGroup> = a.groups.iter().collect();
    let first = |g: &AbsenceGroup| g.hours.iter().map(|h| h.date).min();
    groups.sort_by(|x, y| first(y).cmp(&first(x)));
    d.set_absences(model(
        groups
            .into_iter()
            .map(|g| {
                let (level, status) = justified(g.justified);
                let mut hours: Vec<&MissedHour> = g.hours.iter().collect();
                hours.sort_by_key(|h| (h.date, h.hour));
                let (from, to) = (hours.first().map(|h| h.date), hours.last().map(|h| h.date));
                let title = match (from, to) {
                    (Some(f), Some(t)) if f != t => format!("{} – {}", day_long(f), day_long(t)),
                    (Some(f), _) => format!("{}, {}", day_long(f), hour_range(hours.iter().map(|h| h.hour).collect())),
                    _ => String::new(),
                };
                let late: Vec<String> = hours
                    .iter()
                    .filter(|h| h.came_late > 0 || h.left_early > 0)
                    .map(|h| {
                        if h.came_late > 0 {
                            format!("{} Min. zu spät", h.came_late)
                        } else {
                            format!("{} Min. früher gegangen", h.left_early)
                        }
                    })
                    .collect();
                let count = hours.len();
                let subtitle = if late.is_empty() {
                    format!("{count} {}", if count == 1 { "Schulstunde" } else { "Schulstunden" })
                } else {
                    late.join(", ")
                };
                let stamp = |t: NaiveDateTime| format!("{}, {:02}:{:02}", t.date().format("%d.%m.%Y"), t.hour(), t.minute());
                let footer = match (g.reason_time, g.signature.as_deref()) {
                    (Some(t), Some(sig)) => format!("{} · {sig}", stamp(t)),
                    (Some(t), None) => stamp(t),
                    (None, Some(sig)) => sig.to_owned(),
                    (None, None) => String::new(),
                };
                AbsenceItem {
                    index: -1,
                    title: s(title),
                    subtitle: s(subtitle),
                    reason: s(g.reason.as_deref().unwrap_or("")),
                    footer: s(footer),
                    status: s(status),
                    level,
                }
            })
            .collect(),
    ));
    d.set_future_absences(model(
        a.future
            .iter()
            .enumerate()
            .map(|(i, f)| {
                let (level, status) = justified(f.justified);
                let hours = if f.start_hour == f.end_hour {
                    format!("{}. Stunde", f.start_hour)
                } else {
                    format!("{}.–{}. Stunde", f.start_hour, f.end_hour)
                };
                AbsenceItem {
                    index: i as i32,
                    title: s(if f.start == f.end {
                        format!("{}, {hours}", day_long(f.start))
                    } else {
                        format!("{} – {}, {hours}", day_long(f.start), day_long(f.end))
                    }),
                    subtitle: s("Im Voraus gemeldet"),
                    reason: s(f.reason.as_deref().or(f.note.as_deref()).unwrap_or("")),
                    footer: SharedString::new(),
                    status: s(status),
                    level,
                }
            })
            .collect(),
    ));
}

/// "vor 3 Stunden" (formatTimeAgo).
pub fn time_ago(timestamp: i64) -> String {
    let diff = (Local::now().timestamp() - timestamp).max(0);
    let (n, one, many) = if diff >= 86400 {
        (diff / 86400, "Tag", "Tagen")
    } else if diff >= 3600 {
        (diff / 3600, "Stunde", "Stunden")
    } else if diff >= 60 {
        (diff / 60, "Minute", "Minuten")
    } else {
        (diff, "Sekunde", "Sekunden")
    };
    format!("vor {n} {}", if n == 1 { one } else { many })
}

const WEEKDAYS: [&str; 7] = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"];
const MONTHS: [&str; 12] = [
    "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November",
    "Dezember",
];

pub fn message_item(m: &register_core::model::Message, downloading: Option<i64>) -> MessageItem {
    let t = m.time_sent;
    MessageItem {
        id: m.id as i32,
        subject: s(&m.subject),
        from: s(&m.from),
        glyph: s(m.from.chars().next().map(|c| c.to_uppercase().to_string()).unwrap_or_else(|| "?".into())),
        // dd.MM.yy · HH:mm · sender
        date: s(format!("{} · {}", t.map(|t| t.format("%d.%m.%y · %H:%M").to_string()).unwrap_or_default(), m.from)
            .to_uppercase()),
        // EEEE, d. MMMM yyyy, HH:mm
        sent: s(t
            .map(|t| {
                format!(
                    "{}, {}. {} {}, {:02}:{:02}",
                    WEEKDAYS[t.weekday().num_days_from_monday() as usize],
                    t.day(),
                    MONTHS[t.month0() as usize],
                    t.year(),
                    t.hour(),
                    t.minute()
                )
            })
            .unwrap_or_default()),
        recipients: s(&m.recipients),
        text: s(&m.text),
        unread: !m.read,
        attachments: model(
            m.attachments
                .iter()
                .map(|a| AttachmentItem { id: a.id as i32, name: s(&a.original_name), downloading: downloading == Some(a.id) })
                .collect(),
        ),
        is_message: false,
        object_id: -1,
    }
}

pub fn unread_count(data: &register_core::data::Data) -> i32 {
    (data.messages.iter().filter(|m| !m.read).count() + data.notifications.len()) as i32
}

fn apply_messages(d: &AppData, data: &register_core::data::Data) {
    d.set_messages(model(data.messages.iter().map(|m| message_item(m, None)).collect()));
    d.set_notifications(model(
        data.notifications
            .iter()
            .map(|n| MessageItem {
                id: n.id as i32,
                subject: s(&n.title),
                // d.M.yy H:mm
                date: s(n
                    .time_sent
                    .map(|t| format!("{}.{}.{:02} {}:{:02}", t.day(), t.month(), t.year() % 100, t.hour(), t.minute()))
                    .unwrap_or_default()),
                text: s(&n.subtitle),
                unread: true,
                is_message: n.kind == "message" && n.object_id.is_some(),
                object_id: n.object_id.unwrap_or(-1) as i32,
                ..Default::default()
            })
            .collect(),
    ));
    d.set_unread(unread_count(data));
}

/// The lists of the settings page.
fn apply_prefs(ui: &AppWindow, state: &State) {
    let p = ui.global::<Prefs>();
    let st = &state.settings;
    let subjects: Vec<String> = {
        let mut names: Vec<String> = state.data.subjects.iter().map(|s| s.name.clone()).collect();
        for name in state.data.calendar.values().flat_map(|d| d.hours.iter().map(|h| &h.subject)) {
            if !names.contains(name) {
                names.push(name.clone());
            }
        }
        names
    };
    p.set_ignored(model(st.ignored_subjects.iter().map(s).collect()));
    p.set_ignorable(model(
        state.data.subjects.iter().map(|x| &x.name).filter(|n| !st.ignored_subjects.contains(n)).map(s).collect(),
    ));
    p.set_nicks(model(st.nicks.iter().map(|(a, b)| NickItem { subject: s(a), nick: s(b) }).collect()));
    p.set_nickable(model(subjects.iter().filter(|n| !st.nicks.iter().any(|(a, _)| a == *n)).map(s).collect()));
    p.set_subject_colors(model(st.subject_colors.iter().map(|(n, c)| ColorItem { name: s(n), color: rgb(*c) }).collect()));
    let host = state
        .client
        .as_ref()
        .and_then(|c| url::Url::parse(c.url()).ok())
        .and_then(|u| u.host_str().map(str::to_owned));
    p.set_custom_staff_page(s(host.and_then(|h| st.staff_pages.get(&h).cloned()).unwrap_or_default()));
    p.set_staff_page(s(photos::page().unwrap_or_default()));
    p.set_demo(state.client.as_ref().is_some_and(|c| c.is_demo()));
    // Chosen at the login, too.
    p.set_remember(st.remember);
}
