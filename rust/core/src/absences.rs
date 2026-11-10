//! Absences over the whole school year. The register only knows the share
//! of the lessons held so far; the lessons still to come are counted from
//! the school calendar of South Tyrol and the timetable.

use std::collections::HashMap;

use chrono::{Datelike, Duration, NaiveDate};

use crate::model::{AbsenceStatistic, CalendarDay};

/// Students who miss more than a quarter of the lessons can not be admitted
/// to the end-of-year assessment (except for documented reasons).
pub const LIMIT_PERCENT: f64 = 25.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Level {
    Green,
    Yellow,
    Red,
    Over,
}

pub fn level(percent: f64) -> Level {
    if percent < 10.0 {
        Level::Green
    } else if percent < 18.0 {
        Level::Yellow
    } else if percent < LIMIT_PERCENT {
        Level::Red
    } else {
        Level::Over
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Projection {
    /// Missed lessons so far (from the register's share, so not whole).
    pub missed: f64,
    /// Lessons of the whole year (held so far plus still to come).
    pub total_lessons: i64,
    /// Lessons that may still be missed until the end of the year.
    pub still_allowed: i64,
    /// Missed lessons as share of the whole year.
    pub year_percent: f64,
    /// Last day of lessons.
    pub end: NaiveDate,
}

struct SchoolYear {
    start: NaiveDate,
    end: NaiveDate,
    /// Days without lessons (both ends included).
    free: Vec<(NaiveDate, NaiveDate)>,
}

impl SchoolYear {
    fn is_free(&self, day: NaiveDate) -> bool {
        self.free.iter().any(|&(from, to)| day >= from && day <= to)
    }
}

fn d(y: i32, m: u32, day: u32) -> NaiveDate {
    NaiveDate::from_ymd_opt(y, m, day).unwrap()
}

/// School calendars decided by the provincial government. Schools may shift
/// a few days of their own, so the result is an estimate.
fn school_year_of(day: NaiveDate) -> SchoolYear {
    let known = SchoolYear {
        start: d(2026, 9, 7),
        end: d(2027, 6, 16),
        free: vec![
            (d(2026, 10, 31), d(2026, 11, 8)), // Allerheiligen
            (d(2026, 12, 8), d(2026, 12, 8)),  // Maria Empfängnis
            (d(2026, 12, 24), d(2027, 1, 6)),  // Weihnachten
            (d(2027, 2, 6), d(2027, 2, 14)),   // Fasching
            (d(2027, 3, 25), d(2027, 3, 30)),  // Ostern
            (d(2027, 5, 1), d(2027, 5, 1)),    // Tag der Arbeit
            (d(2027, 5, 17), d(2027, 5, 17)),  // Pfingstmontag
            (d(2027, 6, 2), d(2027, 6, 2)),    // Tag der Republik
        ],
    };
    if day >= known.start - Duration::days(30) && day <= known.end + Duration::days(60) {
        return known;
    }
    // A typical year: early September to mid June, Christmas off.
    let first = if day.month() >= 8 { day.year() } else { day.year() - 1 };
    SchoolYear {
        start: d(first, 9, 6),
        end: d(first + 1, 6, 15),
        free: vec![
            (d(first, 11, 1), d(first, 11, 1)),
            (d(first, 12, 8), d(first, 12, 8)),
            (d(first, 12, 24), d(first + 1, 1, 6)),
        ],
    }
}

/// Lessons per weekday (0 = Monday), from the most recent day of each
/// weekday that had lessons. Days without lessons (holidays) are skipped.
pub fn lessons_per_weekday<'a>(days: impl IntoIterator<Item = &'a CalendarDay>) -> HashMap<u32, i64> {
    let mut latest: HashMap<u32, &CalendarDay> = HashMap::new();
    for day in days {
        if day.hours.is_empty() {
            continue;
        }
        let weekday = day.date.weekday().num_days_from_monday();
        if latest.get(&weekday).is_none_or(|known| day.date > known.date) {
            latest.insert(weekday, day);
        }
    }
    latest
        .into_iter()
        .map(|(weekday, day)| (weekday, day.hours.iter().map(|h| h.length() as i64).sum()))
        .collect()
}

fn lessons_between(year: &SchoolYear, from: NaiveDate, to: NaiveDate, per_weekday: &HashMap<u32, i64>) -> i64 {
    let (from, to) = (from.max(year.start), to.min(year.end));
    from.iter_days()
        .take_while(|&day| day <= to)
        .filter(|&day| !year.is_free(day))
        .map(|day| per_weekday.get(&day.weekday().num_days_from_monday()).copied().unwrap_or(0))
        .sum()
}

/// Projects [stat] onto the whole school year. None without a timetable.
pub fn project<'a>(
    stat: &AbsenceStatistic,
    days: impl IntoIterator<Item = &'a CalendarDay>,
    today: NaiveDate,
) -> Option<Projection> {
    let per_weekday = lessons_per_weekday(days);
    if per_weekday.is_empty() {
        return None;
    }
    let year = school_year_of(today);
    // The register gives no number of missed lessons (its counters count
    // absences, not lessons), only their share of the lessons held so far.
    let percent = stat.percentage.unwrap_or(0.0);
    let held = lessons_between(&year, year.start, today - Duration::days(1), &per_weekday);
    let missed = held as f64 * percent / 100.0;
    let remaining = lessons_between(&year, today, year.end, &per_weekday);
    let total = held + remaining;
    if total <= 0 {
        return None;
    }
    let allowed = (total as f64 * LIMIT_PERCENT / 100.0).floor();
    Some(Projection {
        missed,
        total_lessons: total,
        still_allowed: ((allowed - missed).floor() as i64).max(0),
        year_percent: missed * 100.0 / total as f64,
        end: year.end,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::CalendarHour;

    /// A week (Mon 19.10.2026 to Fri) with 6 lessons a day, 5 on Friday —
    /// the same case as the Flutter app's test.
    fn week() -> Vec<CalendarDay> {
        [(19, 6), (20, 6), (21, 6), (22, 6), (23, 5)]
            .into_iter()
            .map(|(day, n)| CalendarDay {
                date: d(2026, 10, day),
                hours: (1..=n)
                    .map(|h| CalendarHour {
                        from_hour: h,
                        to_hour: h,
                        subject: "Mathematik".into(),
                        teachers: vec![],
                        rooms: vec![],
                        times: vec![],
                        homework_exams: vec![],
                        lesson_contents: vec![],
                    })
                    .collect(),
            })
            .collect()
    }

    fn stat(percent: f64) -> AbsenceStatistic {
        AbsenceStatistic { percentage: Some(percent), ..Default::default() }
    }

    #[test]
    fn projected_like_the_flutter_app() {
        // Until 21.10. 186 lessons were held and 835 are left.
        let p = project(&stat(0.7), &week(), d(2026, 10, 21)).unwrap();
        assert_eq!(p.total_lessons, 186 + 835);
        assert!((p.missed - 1.302).abs() < 0.001);
        assert_eq!(p.still_allowed, (1021.0f64 * 0.25 - 1.302).floor() as i64);
        assert!((p.year_percent - 0.13).abs() < 0.01);
        assert_eq!(p.end, d(2027, 6, 16));
    }

    #[test]
    fn without_absences_all_of_the_quarter_is_left() {
        let p = project(&stat(0.0), &week(), d(2026, 10, 21)).unwrap();
        assert_eq!(p.still_allowed, 255);
    }

    #[test]
    fn over_the_limit_nothing_is_left() {
        assert_eq!(project(&stat(40.0), &week(), d(2027, 6, 14)).unwrap().still_allowed, 0);
    }

    #[test]
    fn without_a_timetable_there_is_no_projection() {
        assert!(project(&stat(2.0), &[], d(2026, 10, 21)).is_none());
    }
}
