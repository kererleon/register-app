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
use slint::{Color, ComponentHandle, ModelRc, SharedString, VecModel};

use crate::format;
use crate::{
    AbsenceItem, AppData, AppWindow, ChartLine, GradeItem, HomeworkDay, HomeworkItem, Lesson, MessageItem, State,
    SubjectItem, WeekDay,
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
fn nick(subject: &str) -> String {
    match subject {
        "Deutsch" => "Deu",
        "Mathematik" => "Mat",
        "Latein" => "Lat",
        "Religion" => "Rel",
        "Englisch" => "Eng",
        "Naturwissenschaften" => "Nat",
        "Geschichte" => "Gesch",
        "Italienisch" => "Ita",
        "Bewegung und Sport" => "Sport",
        "Recht und Wirtschaft" => "Rw",
        "Griechisch" => "Gr",
        "FÜ" => "Fü",
        other => other,
    }
    .to_owned()
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
}

fn parse_time(t: &str) -> Option<NaiveTime> {
    NaiveTime::parse_from_str(t, "%H:%M").ok()
}

/// "1-2" or "3." like the Flutter app.
fn hours_short(h: &CalendarHour) -> String {
    if h.length() > 1 { format!("{}-{}", h.from_hour, h.to_hour) } else { format!("{}.", h.from_hour) }
}

fn lesson(h: &CalendarHour, date: NaiveDate, now: NaiveDateTime, colors: &BTreeMap<String, u32>) -> Lesson {
    let start = parse_time(h.start()).map(|t| date.and_time(t));
    let end = parse_time(h.end()).map(|t| date.and_time(t));
    let notes: Vec<String> = h.homework_exams.iter().map(|e| format!("{}: {}", e.type_name, e.name)).collect();
    Lesson {
        hours: s(hours_short(h)),
        time: s(if h.start().is_empty() { String::new() } else { format!("{}-{}", h.start(), h.end()) }),
        subject: s(&h.subject),
        nick: s(nick(&h.subject)),
        teachers: s(h.teachers.iter().map(|t| t.last_name.clone()).collect::<Vec<_>>().join("\n")),
        rooms: s(h.rooms.join(", ")),
        note: s(notes.join(" · ")),
        color: rgb(colors.get(&h.subject).copied().unwrap_or(0x7C5CFF)),
        span: h.length(),
        first: h.from_hour,
        has_test: h.homework_exams.iter().any(|e| looks_like_test(&e.type_name) || looks_like_test(&e.name)),
        is_now: matches!((start, end), (Some(a), Some(b)) if now >= a && now < b),
        is_past: end.is_some_and(|e| now >= e),
    }
}

/// "HEUTE", "MORGEN", "MO. 16.11."
fn day_word(date: NaiveDate, today: NaiveDate) -> String {
    match (date - today).num_days() {
        0 => "HEUTE".into(),
        1 => "MORGEN".into(),
        _ => format!("{}. {}", wd2(date).to_uppercase(), format::short(date)),
    }
}

fn homework_item(h: &Homework, header: String) -> HomeworkItem {
    let mut title = h.title.clone();
    if let Some(g) = h.grade.as_deref().and_then(|g| register_core::parse::grade_value(Some(g))) {
        title = format!("{title} · {}", grades::format_grade(g));
    }
    HomeworkItem {
        id: h.id as i32,
        kind: s(format::kind_name(h.kind)),
        header: s(header),
        title: s(title),
        subtitle: s(&h.subtitle),
        is_test: h.is_test(),
        is_grade: h.kind == HomeworkKind::Grade,
        checkable: h.checkable,
        checked: h.checked,
        deletable: h.is_reminder(),
    }
}

fn label_caps(h: &Homework) -> String {
    h.label.as_deref().unwrap_or(if h.is_reminder() { "Erinnerung" } else { "" }).to_uppercase()
}

pub fn apply_today(ui: &AppWindow, state: &State) {
    let d = ui.global::<AppData>();
    let data = &state.data;
    let now = Local::now().naive_local();
    let today = now.date();
    let colors = &state.settings.subject_colors;
    d.set_now_header(s(format!("{} · {:02}:{:02}", format::long(today).to_uppercase(), now.hour(), now.minute())));

    let hours: &[CalendarHour] = data.calendar.get(&today).map(|d| d.hours.as_slice()).unwrap_or(&[]);
    d.set_today_lessons(model(hours.iter().map(|h| lesson(h, today, now, colors)).collect()));

    // The current lesson, or what comes next.
    let mut title = String::new();
    let mut detail = String::new();
    let mut running = false;
    for h in hours {
        let (Some(a), Some(b)) = (parse_time(h.start()), parse_time(h.end())) else { continue };
        let (a, b) = (today.and_time(a), today.and_time(b));
        let room = if h.rooms.is_empty() { String::new() } else { format!(" · {}", h.rooms.join(", ")) };
        if now >= a && now < b {
            running = true;
            title = h.subject.clone();
            detail = format!("Läuft gerade · noch {} min{room}", (b - now).num_minutes() + 1);
            break;
        }
        if now < a {
            title = h.subject.clone();
            detail = format!("Beginnt um {}{room}", h.start());
            break;
        }
    }
    if title.is_empty() {
        title = if hours.is_empty() { "Heute kein Unterricht".into() } else { "Für heute geschafft".into() };
    }
    d.set_now_running(running);
    d.set_now_title(s(title));
    d.set_now_detail(s(detail));

    // Due today and tomorrow, then the next tests.
    let mut due = Vec::new();
    for date in [today, today + Duration::days(1)] {
        for h in data.homework_on(date).iter().filter(|h| !h.checked && h.kind != HomeworkKind::Grade) {
            let label = label_caps(h);
            let word = day_word(date, today);
            let header = if label.is_empty() { word } else { format!("{word} · {label}") };
            due.push(homework_item(h, header));
        }
    }
    d.set_due(model(due));
    d.set_tests(model(
        data.upcoming_tests()
            .into_iter()
            .take(6)
            .map(|(date, h)| {
                let header = format!("{} · {}", day_word(date, today), label_caps(h));
                homework_item(h, header)
            })
            .collect(),
    ));
}

fn apply_homework(d: &AppData, state: &State) {
    let today = today();
    let past = state.show_past;
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
        days.push(HomeworkDay {
            date: s(date.format("%d.%m.%Y").to_string()),
            header: s(header),
            title: s(title),
            is_today: date == today,
            items: model(items.iter().map(|h| homework_item(h, label_caps(h))).collect()),
        });
    };
    if past {
        let mut list: Vec<_> = state.data.dashboard.iter().filter(|d| d.date < today && !d.homework.is_empty()).collect();
        list.reverse();
        for day in list {
            add(day.date, &day.homework);
        }
    } else {
        // Today and tomorrow are always shown, to add reminders.
        for date in [today, today + Duration::days(1)] {
            add(date, state.data.homework_on(date));
        }
        for day in state.data.dashboard.iter().filter(|d| d.date > today + Duration::days(1) && !d.homework.is_empty()) {
            add(day.date, &day.homework);
        }
    }
    d.set_show_past(past);
    d.set_homework(model(days));
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
fn chart(subjects: &[Subject], semester: Semester, colors: &BTreeMap<String, u32>) -> (Vec<ChartLine>, String, String) {
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
            if p.len() == 1 {
                let (px, py) = (x(p[0].0), y(p[0].1));
                ChartLine {
                    color,
                    commands: SharedString::new(),
                    dots: s(format!("M {:.1} {py:.1} a 5 2.5 0 1 0 10 0 a 5 2.5 0 1 0 -10 0 Z", px - 5.0)),
                }
            } else {
                let path: Vec<String> = p
                    .iter()
                    .enumerate()
                    .map(|(i, (d, g))| format!("{} {:.1} {:.1}", if i == 0 { "M" } else { "L" }, x(*d), y(*g)))
                    .collect();
                ChartLine { color, commands: s(path.join(" ")), dots: SharedString::new() }
            }
        })
        .collect();
    (lines, short_month(from), short_month(to))
}

fn apply_grades(d: &AppData, state: &State) {
    let semester = semester_of(state.semester);
    let tests = state.data.upcoming_tests();
    let colors = &state.settings.subject_colors;
    let subjects: Vec<SubjectItem> = state
        .data
        .subjects
        .iter()
        .map(|subject| {
            let average = grades::average(subject, semester);
            // Details (names, descriptions) once loaded, else the overview.
            let detailed: Vec<&Grade> = match semester {
                Semester::First => subject.details[0].iter().flatten().collect(),
                Semester::Second => subject.details[1].iter().flatten().collect(),
                Semester::All => subject.details.iter().flatten().flatten().collect(),
            };
            let mut list: Vec<&Grade> =
                if detailed.is_empty() { grades::grades_of(subject, semester).collect() } else { detailed };
            if !state.show_cancelled {
                list.retain(|g| !g.cancelled);
            }
            list.sort_by(|a, b| b.date.cmp(&a.date));
            if state.sort_by_type {
                list.sort_by(|a, b| a.kind.cmp(&b.kind));
            }
            let next_test = tests.iter().find(|(_, h)| {
                h.label.as_deref().is_some_and(|l| l.trim().eq_ignore_ascii_case(subject.name.trim()))
            });
            let forecast = match average {
                Some(avg) if avg < 600 => match grades::forecast(subject, semester, grades::PASS_MARK, 100) {
                    Forecast::Needs(g) => {
                        format!("Für eine 6 brauchst du im nächsten Test mindestens {}", grades::format_steps(g))
                    }
                    Forecast::Impossible => "Eine 6 ist mit dem nächsten Test allein nicht mehr erreichbar".into(),
                    Forecast::Safe => String::new(),
                },
                Some(avg) if avg < 1000 => {
                    let target = ((avg as f64 / 100.0).floor() + 1.0).min(10.0);
                    match grades::forecast(subject, semester, target, 100) {
                        Forecast::Needs(g) => {
                            format!("Für Ø {target} brauchst du als Nächstes eine {}", grades::format_steps(g))
                        }
                        _ => String::new(),
                    }
                }
                _ => String::new(),
            };
            SubjectItem {
                id: subject.id as i32,
                name: s(&subject.name),
                average: s(average.map(grades::format_average).unwrap_or_else(|| "–".into())),
                average_value: average.map(|a| a as f32 / 100.0).unwrap_or(0.0),
                color: rgb(colors.get(&subject.name).copied().unwrap_or(0x7C5CFF)),
                test_chip: s(next_test
                    .map(|(date, _)| format!("Test {}. {}", wd2(*date), format::short(*date)))
                    .unwrap_or_default()),
                forecast: s(forecast),
                grades: model(
                    list.iter()
                        .map(|g| GradeItem {
                            value: s(g.value.map(grades::format_grade).unwrap_or_else(|| "–".into())),
                            title: s(if g.name.is_empty() { g.kind.clone() } else { format!("{} · {}", g.name, g.kind) }),
                            detail: s(&g.description),
                            date: s(format::short(g.date)),
                            weight: s(format!("{} %", g.weight_percent)),
                            cancelled: g.cancelled,
                        })
                        .collect(),
                ),
            }
        })
        .collect();
    let overall = grades::overall_average(&state.data.subjects, semester, &[]);
    d.set_semester(state.semester);
    d.set_show_cancelled(state.show_cancelled);
    d.set_sort_by_type(state.sort_by_type);
    d.set_overall(s(overall.map(grades::format_average).unwrap_or_else(|| "–".into())));
    d.set_overall_value(overall.map(|a| a as f32 / 100.0).unwrap_or(0.0));
    d.set_overall_note(s(match overall {
        None => "Noch keine Noten",
        Some(avg) if avg >= 600 => "Alles im grünen Bereich",
        Some(_) => "Unter der Genügend-Grenze",
    }));
    let (lines, from, to) = chart(&state.data.subjects, semester, colors);
    d.set_chart(model(lines));
    d.set_chart_from(s(from));
    d.set_chart_to(s(to));
    d.set_subjects(model(subjects));
}

fn apply_calendar(d: &AppData, state: &State) {
    let now = Local::now().naive_local();
    let today = now.date();
    let colors = &state.settings.subject_colors;
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
        days.push(WeekDay {
            weekday: s(wd2(date).to_uppercase()),
            date: s(date.format("%d.%m").to_string()),
            is_today: date == today,
            lessons: model(list.into_iter().map(|h| lesson(h, date, now, colors)).collect()),
        });
    }
    let friday = monday + Duration::days(4);
    d.set_week_title(s(format!("{} - {}", monday.format("%d.%m.%y"), friday.format("%d.%m.%y"))));
    d.set_week_hours(hours);
    d.set_week(model(days));
}

/// "Mi. 14.10.2026"
fn day_long(date: NaiveDate) -> String {
    format!("{}. {}.{}.{}", wd2(date), date.day(), date.month(), date.year())
}

fn level_number(level: Level) -> i32 {
    match level {
        Level::Green => 0,
        Level::Yellow => 1,
        Level::Red | Level::Over => 2,
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

fn date_time(t: Option<NaiveDateTime>) -> String {
    t.map(|t| format!("{} {:02}:{:02}", t.date().format("%d.%m.%Y"), t.hour(), t.minute())).unwrap_or_default()
}

fn apply_messages(d: &AppData, data: &register_core::data::Data) {
    d.set_messages(model(
        data.messages
            .iter()
            .map(|m| MessageItem {
                id: m.id as i32,
                subject: s(&m.subject),
                from: s(m.from.to_uppercase()),
                date: s(date_time(m.time_sent)),
                text: s(&m.text),
                unread: !m.read,
            })
            .collect(),
    ));
    d.set_notifications(model(
        data.notifications
            .iter()
            .map(|n| MessageItem {
                id: n.id as i32,
                subject: s(&n.title),
                from: SharedString::new(),
                date: s(date_time(n.time_sent)),
                text: s(&n.subtitle),
                unread: true,
            })
            .collect(),
    ));
    d.set_unread((data.messages.iter().filter(|m| !m.read).count() + data.notifications.len()) as i32);
}
