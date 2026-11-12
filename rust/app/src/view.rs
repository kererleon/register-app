//! Turns the state into what the window shows.

use chrono::{Duration, Local, NaiveDate, NaiveTime, Timelike};
use register_core::absences::{self, Level};
use register_core::data::{monday_of, today};
use register_core::grades::{self, Forecast};
use register_core::model::{
    AbsenceGroup, CalendarHour, MissedHour, Grade, Homework, HomeworkKind, Justified, Semester, Teacher, looks_like_test,
};
use slint::{ComponentHandle, ModelRc, SharedString, VecModel};

use crate::format;
use crate::{
    AbsenceItem, AppData, AppWindow, GradeItem, HomeworkDay, HomeworkItem, Lesson, MessageItem, State, SubjectItem,
    TestItem, WeekDay,
};

fn model<T: Clone + 'static>(items: Vec<T>) -> ModelRc<T> {
    ModelRc::new(VecModel::from(items))
}

fn s(text: impl AsRef<str>) -> SharedString {
    text.as_ref().into()
}

pub fn apply(ui: &AppWindow, state: &State) {
    let d = ui.global::<AppData>();
    let data = &state.data;
    let config = data.config.as_ref();
    d.set_full_name(s(config.map(|c| c.full_name.as_str()).unwrap_or("")));
    d.set_school(s(&state.settings.school));
    d.set_fetched(s(match data.fetched_at.and_then(|t| chrono::DateTime::from_timestamp(t, 0)) {
        Some(t) => {
            let t = t.with_timezone(&Local);
            format!("Zuletzt geladen: {} um {:02}:{:02}", format::short(t.date_naive()), t.hour(), t.minute())
        }
        None => "Noch nicht geladen".into(),
    }));
    apply_today(ui, state);
    apply_homework(&d, state);
    apply_grades(&d, state);
    apply_calendar(&d, state);
    apply_absences(&d, state);
    apply_messages(&d, data);
}

fn parse_time(t: &str) -> Option<NaiveTime> {
    NaiveTime::parse_from_str(t, "%H:%M").ok()
}

fn hours_label(h: &CalendarHour) -> String {
    if h.length() > 1 { format!("{}.–{}. Std.", h.from_hour, h.to_hour) } else { format!("{}. Stunde", h.from_hour) }
}

fn lesson(h: &CalendarHour, date: NaiveDate, now: chrono::NaiveDateTime) -> Lesson {
    let start = parse_time(h.start()).map(|t| date.and_time(t));
    let end = parse_time(h.end()).map(|t| date.and_time(t));
    let is_now = matches!((start, end), (Some(a), Some(b)) if now >= a && now < b);
    let is_past = end.is_some_and(|e| now >= e);
    let mut notes: Vec<String> = h.homework_exams.iter().map(|e| format!("{}: {}", e.type_name, e.name)).collect();
    notes.extend(h.lesson_contents.iter().filter(|(_, n)| !n.is_empty()).map(|(t, n)| {
        if t.is_empty() { n.clone() } else { format!("{t}: {n}") }
    }));
    Lesson {
        hours: s(hours_label(h)),
        time: s(if h.start().is_empty() { String::new() } else { format!("{}–{}", h.start(), h.end()) }),
        subject: s(&h.subject),
        teachers: s(h.teachers.iter().map(Teacher::full_name).collect::<Vec<_>>().join(", ")),
        rooms: s(h.rooms.join(", ")),
        note: s(notes.join(" · ")),
        has_test: h.homework_exams.iter().any(|e| looks_like_test(&e.type_name) || looks_like_test(&e.name)),
        is_now,
        is_past,
    }
}

fn homework_item(h: &Homework) -> HomeworkItem {
    let is_grade = h.kind == HomeworkKind::Grade;
    let mut title = h.title.clone();
    if let Some(g) = h.grade.as_deref().and_then(|g| register_core::parse::grade_value(Some(g))) {
        title = format!("{title} · {}", grades::format_grade(g));
    }
    HomeworkItem {
        id: h.id as i32,
        kind: s(format::kind_name(h.kind)),
        title: s(title),
        subtitle: s(&h.subtitle),
        label: s(h.label.as_deref().unwrap_or("")),
        is_test: h.is_test(),
        is_grade,
        checkable: h.checkable,
        checked: h.checked,
    }
}

pub fn apply_today(ui: &AppWindow, state: &State) {
    let d = ui.global::<AppData>();
    let data = &state.data;
    let now = Local::now().naive_local();
    let today = now.date();
    let hour = now.hour();
    let first = data
        .config
        .as_ref()
        .map(|c| c.full_name.split_whitespace().next().unwrap_or("").to_owned())
        .unwrap_or_default();
    let greeting = match hour {
        5..=10 => "Guten Morgen",
        11..=17 => "Hallo",
        _ => "Guten Abend",
    };
    d.set_greeting(s(if first.is_empty() { greeting.to_owned() } else { format!("{greeting}, {first}") }));
    d.set_today_title(s(format::long(today)));

    let lessons: Vec<Lesson> = data
        .calendar
        .get(&today)
        .map(|day| day.hours.iter().map(|h| lesson(h, today, now)).collect())
        .unwrap_or_default();
    // The current lesson, how much of it is over, and what comes next.
    let mut now_subject = String::new();
    let mut now_detail = String::new();
    let mut progress = 0.0f32;
    let mut next = String::new();
    if let Some(day) = data.calendar.get(&today) {
        for (i, h) in day.hours.iter().enumerate() {
            let (Some(a), Some(b)) = (parse_time(h.start()), parse_time(h.end())) else { continue };
            let (a, b) = (today.and_time(a), today.and_time(b));
            if now >= a && now < b {
                let left = (b - now).num_minutes();
                now_subject = h.subject.clone();
                now_detail = format!(
                    "{} · noch {left} Min.{}",
                    hours_label(h),
                    if h.rooms.is_empty() { String::new() } else { format!(" · {}", h.rooms.join(", ")) }
                );
                progress = ((now - a).num_seconds() as f32 / (b - a).num_seconds().max(1) as f32).clamp(0.0, 1.0);
                if let Some(n) = day.hours.get(i + 1) {
                    next = format!("{} um {}", n.subject, n.start());
                }
                break;
            }
        }
    }
    d.set_now_subject(s(now_subject));
    d.set_now_detail(s(now_detail));
    d.set_now_progress(progress);
    d.set_next_subject(s(next));
    d.set_today_lessons(model(lessons));

    let tomorrow = today + Duration::days(1);
    d.set_due_tomorrow(model(data.homework_on(tomorrow).iter().filter(|h| !h.checked).map(homework_item).collect()));
    d.set_tests(model(
        data.upcoming_tests()
            .into_iter()
            .take(5)
            .map(|(date, h)| TestItem {
                title: s(&h.title),
                subject: s(h.label.as_deref().unwrap_or("")),
                when: s(format!("{} · {}", format::long(date), format::relative(date, today))),
                days: (date - today).num_days() as i32,
            })
            .collect(),
    ));
}

fn apply_homework(d: &AppData, state: &State) {
    let today = today();
    let days: Vec<HomeworkDay> = state
        .data
        .dashboard
        .iter()
        .filter(|day| state.show_past || day.date >= today)
        .filter(|day| !day.homework.is_empty())
        .map(|day| HomeworkDay {
            title: s(format::long(day.date).to_uppercase()),
            relative: s(format::relative(day.date, today)),
            is_today: day.date == today,
            items: model(day.homework.iter().map(homework_item).collect()),
        })
        .collect();
    d.set_show_past(state.show_past);
    d.set_homework(model(days));
}

fn semester_of(index: i32) -> Semester {
    match index {
        0 => Semester::First,
        1 => Semester::Second,
        _ => Semester::All,
    }
}

fn apply_grades(d: &AppData, state: &State) {
    let semester = semester_of(state.semester);
    let today = today();
    let tests = state.data.upcoming_tests();
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
            list.sort_by(|a, b| b.date.cmp(&a.date));
            let count = list.iter().filter(|g| g.value.is_some() && !g.cancelled).count();
            let next_test = tests.iter().find(|(_, h)| {
                h.label.as_deref().is_some_and(|l| l.trim().eq_ignore_ascii_case(subject.name.trim()))
            });
            let forecast = match (average, next_test) {
                (Some(avg), Some(_)) if avg < 600 => match grades::forecast(subject, semester, grades::PASS_MARK, 100) {
                    Forecast::Needs(g) => format!("Für eine 6 brauchst du im nächsten Test mindestens {}", grades::format_steps(g)),
                    Forecast::Impossible => "Eine 6 ist mit dem nächsten Test allein nicht mehr erreichbar".into(),
                    Forecast::Safe => String::new(),
                },
                (Some(avg), _) => {
                    let target = ((avg as f64 / 100.0).floor() + 1.0).min(10.0);
                    match grades::forecast(subject, semester, target, 100) {
                        Forecast::Needs(g) if avg < 1000 => {
                            format!("Für Ø {} brauchst du als Nächstes eine {}", target, grades::format_steps(g))
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
                count: count as i32,
                forecast: s(forecast),
                next_test: s(next_test
                    .map(|(date, h)| format!("Test {}: {}", format::relative(*date, today), h.title))
                    .unwrap_or_default()),
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
    d.set_semester(state.semester);
    d.set_overall(s(grades::overall_average(&state.data.subjects, semester, &[])
        .map(grades::format_average)
        .unwrap_or_else(|| "–".into())));
    d.set_subjects(model(subjects));
}

fn apply_calendar(d: &AppData, state: &State) {
    let now = Local::now().naive_local();
    let today = now.date();
    let monday = monday_of(today) + Duration::weeks(state.week_offset);
    let mut days = Vec::new();
    for i in 0..6 {
        let date = monday + Duration::days(i);
        let lessons: Vec<Lesson> = state
            .data
            .calendar
            .get(&date)
            .map(|day| day.hours.iter().map(|h| lesson(h, date, now)).collect())
            .unwrap_or_default();
        // Saturday only when there are lessons.
        if i == 5 && lessons.is_empty() {
            continue;
        }
        days.push(WeekDay {
            title: s(format::weekday(date).to_uppercase()),
            date: s(format::day_month(date)),
            is_today: date == today,
            lessons: model(lessons),
        });
    }
    let sunday = monday + Duration::days(6);
    d.set_week_title(s(match state.week_offset {
        0 => format!("Diese Woche · {} – {}", format::short(monday), format::short(sunday)),
        1 => format!("Nächste Woche · {} – {}", format::short(monday), format::short(sunday)),
        -1 => format!("Letzte Woche · {} – {}", format::short(monday), format::short(sunday)),
        _ => format!("{} – {}", format::short(monday), format::short(sunday)),
    }));
    d.set_week(model(days));
}

fn level_number(level: Level) -> i32 {
    match level {
        Level::Green => 0,
        Level::Yellow => 1,
        Level::Red | Level::Over => 2,
    }
}

fn apply_absences(d: &AppData, state: &State) {
    let a = &state.data.absences;
    let stat = &a.statistic;
    d.set_absence_can_edit(a.can_edit && !state.client.as_ref().is_some_and(|c| c.is_demo()));
    let tomorrow = today() + Duration::days(1);
    d.set_tomorrow_date(s(tomorrow.format("%d.%m.%Y").to_string()));
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
            let end = format!("{}. {}", p.end.format("%-d"), format::month(chrono::Datelike::month(&p.end)));
            d.set_year_allowed(s(if p.still_allowed == 0 {
                "Keine Fehlstunde mehr übrig".to_owned()
            } else {
                format!("Noch ~{} {} fehlen bis Schulende ({end}) erlaubt", p.still_allowed, if p.still_allowed == 1 { "Stunde" } else { "Stunden" })
            }));
            let missed = if p.missed > 0.0 && p.missed < 1.0 { 1 } else { p.missed.round() as i64 };
            d.set_year_detail(s(format!(
                "Aufs ganze Schuljahr: {} (~{missed} von ~{} Stunden)",
                format::percent(p.year_percent),
                p.total_lessons
            )));
        }
        None => {
            d.set_year_allowed(SharedString::new());
            d.set_year_detail(SharedString::new());
        }
    }
    let count = |label: &str, v: Option<i64>| v.map(|v| format!("{v} {label}"));
    d.set_absence_counts(s([
        count("Absenzen", stat.counter),
        count("entschuldigt", stat.justified),
        count("nicht entschuldigt", stat.not_justified),
        count("Verspätungen", stat.delayed),
    ]
    .into_iter()
    .flatten()
    .collect::<Vec<_>>()
    .join(" · ")));

    let status_level = |j: Justified| match j {
        Justified::Justified | Justified::ForSchool => 0,
        Justified::NotYet => 1,
        Justified::NotJustified => 2,
    };
    let mut groups: Vec<&AbsenceGroup> = a.groups.iter().collect();
    groups.sort_by(|x, y| {
        let first = |g: &AbsenceGroup| g.hours.iter().map(|h| h.date).min();
        first(y).cmp(&first(x))
    });
    d.set_absences(model(
        groups
            .into_iter()
            .map(|g| {
                let dates: Vec<NaiveDate> = g.hours.iter().map(|h| h.date).collect();
                let (from, to) = (dates.iter().min().copied(), dates.iter().max().copied());
                let title = match (from, to) {
                    (Some(f), Some(t)) if f != t => format!("{} – {}", format::short(f), format::long(t)),
                    (Some(f), _) => format::long(f),
                    _ => String::new(),
                };
                let mut sorted: Vec<&MissedHour> = g.hours.iter().collect();
                sorted.sort_by_key(|h| (h.date, h.hour));
                let hours: Vec<String> = sorted
                    .into_iter()
                    .map(|h| {
                        if h.came_late > 0 {
                            format!("{}. Std. ({} Min. zu spät)", h.hour, h.came_late)
                        } else if h.left_early > 0 {
                            format!("{}. Std. ({} Min. früher weg)", h.hour, h.left_early)
                        } else {
                            format!("{}. Std.", h.hour)
                        }
                    })
                    .collect();
                let mut detail = hours.join(", ");
                if let Some(r) = &g.reason {
                    detail = format!("{detail}\n{r}");
                }
                AbsenceItem {
                    title: s(title),
                    detail: s(detail),
                    status: s(g.justified.label()),
                    level: status_level(g.justified),
                }
            })
            .collect(),
    ));
    d.set_future_absences(model(
        a.future
            .iter()
            .map(|f| AbsenceItem {
                title: s(if f.start == f.end {
                    format::long(f.start)
                } else {
                    format!("{} – {}", format::short(f.start), format::long(f.end))
                }),
                detail: s(format!(
                    "{}.–{}. Stunde{}",
                    f.start_hour,
                    f.end_hour,
                    f.reason.as_deref().map(|r| format!(" · {r}")).unwrap_or_default()
                )),
                status: s(f.justified.label()),
                level: status_level(f.justified),
            })
            .collect(),
    ));
}

fn date_time(t: Option<chrono::NaiveDateTime>) -> String {
    t.map(|t| format!("{} {:02}:{:02}", format::short(t.date()), t.hour(), t.minute())).unwrap_or_default()
}

fn apply_messages(d: &AppData, data: &register_core::data::Data) {
    d.set_messages(model(
        data.messages
            .iter()
            .map(|m| MessageItem {
                id: m.id as i32,
                subject: s(&m.subject),
                from: s(&m.from),
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
