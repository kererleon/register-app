//! Averages and the grade forecast, calculated like the original app.

use crate::model::{Grade, GradeValue, Semester, Subject};

/// Lowest and highest grade the Digitales Register gives.
pub const MIN_GRADE: f64 = 1.0;
pub const MAX_GRADE: f64 = 10.0;
/// The pass mark in South Tyrol.
pub const PASS_MARK: f64 = 6.0;

/// The basic grades of [semester] (both semesters for [Semester::All]).
pub fn grades_of(subject: &Subject, semester: Semester) -> impl Iterator<Item = &Grade> {
    let (a, b) = match semester {
        Semester::First => (&subject.grades[0][..], &[][..]),
        Semester::Second => (&subject.grades[1][..], &[][..]),
        Semester::All => (&subject.grades[0][..], &subject.grades[1][..]),
    };
    a.iter().chain(b.iter())
}

/// Weighted average in hundredths, rounded like the original app.
pub fn average(subject: &Subject, semester: Semester) -> Option<GradeValue> {
    let (mut sum, mut n) = (0i64, 0i64);
    for g in grades_of(subject, semester) {
        let Some(value) = g.value else { continue };
        if g.cancelled {
            continue;
        }
        sum += value as i64 * g.weight_percent as i64;
        n += g.weight_percent as i64;
    }
    (n > 0).then(|| (sum as f64 / n as f64).round() as GradeValue)
}

/// The average of the subject averages, without the [ignored] subjects.
pub fn overall_average(subjects: &[Subject], semester: Semester, ignored: &[String]) -> Option<GradeValue> {
    let averages: Vec<GradeValue> = subjects
        .iter()
        .filter(|s| !ignored.iter().any(|i| i.eq_ignore_ascii_case(&s.name)))
        .filter_map(|s| average(s, semester))
        .collect();
    if averages.is_empty() {
        return None;
    }
    let sum: i64 = averages.iter().map(|&a| a as i64).sum();
    Some((sum as f64 / averages.len() as f64).round() as GradeValue)
}

/// 825 -> "8,25", 800 -> "8".
pub fn format_average(value: GradeValue) -> String {
    let main = value / 100;
    let rest = value % 100;
    if rest == 0 {
        main.to_string()
    } else if rest % 10 == 0 {
        format!("{main},{}", rest / 10)
    } else {
        format!("{main},{rest:02}")
    }
}

/// A single grade like the register writes it: 8, 8+, 8/9, 9-.
pub fn format_grade(value: GradeValue) -> String {
    let main = value / 100;
    match value % 100 {
        0 => main.to_string(),
        25 => format!("{main}+"),
        50 => format!("{main}/{}", main + 1),
        75 => format!("{}-", main + 1),
        _ => format_average(value),
    }
}

/// 7.5 -> "7½" (quarter steps, as the register uses them).
pub fn format_steps(grade: f64) -> String {
    let base = grade.floor();
    let rest = grade - base;
    if rest < 0.125 {
        format!("{base}")
    } else if rest < 0.375 {
        format!("{base}+")
    } else if rest < 0.625 {
        format!("{base}½")
    } else {
        format!("{}-", base + 1.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum Forecast {
    /// Reached even with the worst grade.
    Safe,
    /// Reachable with this grade (rounded up to a quarter).
    Needs(f64),
    /// Even a 10 is not enough.
    Impossible,
}

/// Which grade the next test (weight in percent) needs so that the subject's
/// average reaches [target].
pub fn forecast(subject: &Subject, semester: Semester, target: f64, weight_percent: i32) -> Forecast {
    let (mut sum, mut weight) = (0.0, 0i64);
    for g in grades_of(subject, semester) {
        let Some(value) = g.value else { continue };
        if g.cancelled {
            continue;
        }
        sum += value as f64 / 100.0 * g.weight_percent as f64;
        weight += g.weight_percent as i64;
    }
    let w = weight_percent as f64;
    let required = (target * (weight as f64 + w) - sum) / w;
    if required <= MIN_GRADE {
        Forecast::Safe
    } else if required > MAX_GRADE {
        Forecast::Impossible
    } else {
        Forecast::Needs((required * 4.0).ceil() / 4.0)
    }
}

/// A grade as typed into the grade calculator (tryParseFormattedGrade):
/// "8", "8,25", "8.5", "8+", "9-", "7/8" or "7-8".
pub fn parse_input(text: &str) -> Option<GradeValue> {
    let t = text.trim();
    let in_range = |g: i32| (0..=1000).contains(&g).then_some(g);
    let digits = |s: &str| !s.is_empty() && s.chars().all(|c| c.is_ascii_digit());
    // 8, 8,25, 8.5
    if let Some((major, minor)) = t.split_once([',', '.']).or(Some((t, ""))) {
        if digits(major) && (minor.is_empty() && !t.contains([',', '.']) || digits(minor) && minor.len() <= 2) {
            let major: i32 = major.parse().ok()?;
            let mut minor: i32 = if minor.is_empty() { 0 } else { minor.parse().ok()? };
            if t.split_once([',', '.']).is_some_and(|(_, m)| m.len() == 1) {
                minor *= 10;
            }
            return in_range(major * 100 + minor);
        }
    }
    // 9-, 8+
    if let Some(n) = t.strip_suffix('-').filter(|n| digits(n)) {
        return in_range(n.parse::<i32>().ok()? * 100 - 25);
    }
    if let Some(n) = t.strip_suffix('+').filter(|n| digits(n)) {
        return in_range(n.parse::<i32>().ok()? * 100 + 25);
    }
    // 7/8, 7-8
    if let Some((a, b)) = t.split_once(['/', '-']).filter(|(a, b)| digits(a) && digits(b)) {
        let (a, b): (i32, i32) = (a.parse().ok()?, b.parse().ok()?);
        return (b == a + 1).then(|| in_range(a * 100 + 50)).flatten();
    }
    None
}

/// The calculator's average: integer division like the Flutter app, "/"
/// without grades.
pub fn calculator_average(grades: &[(GradeValue, i32)]) -> String {
    let weights: i64 = grades.iter().map(|g| g.1 as i64).sum();
    if weights == 0 {
        return "/".into();
    }
    let sum: i64 = grades.iter().map(|g| g.0 as i64 * g.1 as i64).sum();
    format_average((sum / weights) as GradeValue)
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::NaiveDate;

    fn g(value: i32, weight: i32) -> Grade {
        Grade {
            id: None,
            value: Some(value),
            weight_percent: weight,
            date: NaiveDate::from_ymd_opt(2026, 10, 1).unwrap(),
            cancelled: false,
            kind: String::new(),
            name: String::new(),
            description: String::new(),
            created: String::new(),
            competences: Vec::new(),
            cancelled_description: None,
        }
    }

    fn subject(grades: Vec<Grade>) -> Subject {
        Subject { id: 1, name: "Mathematik".into(), grades: [grades, vec![]], ..Default::default() }
    }

    #[test]
    fn weighted_average() {
        let s = subject(vec![g(800, 100), g(600, 50)]);
        // (800*100 + 600*50) / 150 = 733.3
        assert_eq!(average(&s, Semester::First), Some(733));
        assert_eq!(average(&s, Semester::Second), None);
        assert_eq!(format_average(733), "7,33");
        assert_eq!(format_average(750), "7,5");
    }

    #[test]
    fn cancelled_grades_do_not_count() {
        let mut cancelled = g(200, 100);
        cancelled.cancelled = true;
        assert_eq!(average(&subject(vec![g(900, 100), cancelled]), Semester::All), Some(900));
    }

    #[test]
    fn grade_formats() {
        assert_eq!(format_grade(825), "8+");
        assert_eq!(format_grade(850), "8/9");
        assert_eq!(format_grade(875), "9-");
        assert_eq!(format_steps(7.5), "7½");
    }

    #[test]
    fn forecasts() {
        let s = subject(vec![g(500, 100)]);
        // (6 * 200 - 500) / 100 = 7
        assert_eq!(forecast(&s, Semester::First, 6.0, 100), Forecast::Needs(7.0));
        assert_eq!(forecast(&s, Semester::First, 4.0, 100), Forecast::Needs(3.0));
        assert_eq!(forecast(&s, Semester::First, 2.5, 100), Forecast::Safe);
        assert_eq!(forecast(&subject(vec![g(200, 100)]), Semester::First, 8.0, 100), Forecast::Impossible);
    }

    #[test]
    fn calculator_inputs() {
        assert_eq!(parse_input("8"), Some(800));
        assert_eq!(parse_input("8,25"), Some(825));
        assert_eq!(parse_input("8.5"), Some(850));
        assert_eq!(parse_input("8+"), Some(825));
        assert_eq!(parse_input("9-"), Some(875));
        assert_eq!(parse_input("7/8"), Some(750));
        assert_eq!(parse_input("7-8"), Some(750));
        assert_eq!(parse_input("7/9"), None);
        assert_eq!(parse_input("11"), None);
        assert_eq!(parse_input("abc"), None);
        assert_eq!(calculator_average(&[(800, 100), (650, 50)]), "7,5");
        assert_eq!(calculator_average(&[]), "/");
    }
}
