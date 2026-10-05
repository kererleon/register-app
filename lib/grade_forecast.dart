// Copyright (C) 2026 kererleon
//
// This file is part of digitales_register.
//
// digitales_register is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// digitales_register is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with digitales_register.  If not, see <http://www.gnu.org/licenses/>.

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';

/// Lowest and highest grade the Digitales Register gives.
const minGrade = 1.0;
const maxGrade = 10.0;

/// The pass mark in South Tyrol.
const passMark = 6.0;

enum ForecastKind {
  /// The target is already reached even with the worst grade.
  safe,

  /// The target can be reached with [Forecast.required].
  reachable,

  /// Even a 10 is not enough.
  impossible,
}

class Forecast {
  final ForecastKind kind;

  /// The grade needed in the next test, on the 1–10 scale.
  final double required;

  const Forecast(this.kind, this.required);
}

/// Weighted sum and total weight of all grades that count, with grades on the
/// 1–10 scale.
(double, int) _weightedGrades(Subject subject, Semester semester) {
  var sum = 0.0;
  var weight = 0;
  for (final grade in subject.basicGrades(semester) ?? const <GradeAll>[]) {
    if (grade.cancelled || grade.grade == null) continue;
    sum += grade.grade! / 100 * grade.weightPercentage;
    weight += grade.weightPercentage;
  }
  return (sum, weight);
}

/// Which grade the next test with [weightPercentage] must have so that the
/// subject's average reaches [target].
Forecast forecastNextGrade(
  Subject subject,
  Semester semester, {
  required double target,
  int weightPercentage = 100,
}) {
  final (sum, weight) = _weightedGrades(subject, semester);
  final required =
      (target * (weight + weightPercentage) - sum) / weightPercentage;
  if (required <= minGrade) return Forecast(ForecastKind.safe, required);
  if (required > maxGrade) return Forecast(ForecastKind.impossible, required);
  return Forecast(ForecastKind.reachable, required);
}

/// Rounds up to the next grade step the register uses (quarters), so that the
/// shown grade is really enough.
double roundUpToQuarter(double grade) => (grade * 4).ceil() / 4;

/// Formats a grade like the register: 7, 7+, 7½, 8-.
String formatGradeSteps(double grade) {
  final base = grade.floor();
  final rest = grade - base;
  if (rest < 0.125) return "$base";
  if (rest < 0.375) return "$base+";
  if (rest < 0.625) return "$base½";
  return "${base + 1}-";
}

String _normalize(String name) => name.trim().toLowerCase();

/// The subject a dashboard entry belongs to, matched by its label.
Subject? subjectForLabel(Iterable<Subject> subjects, String? label) {
  if (label == null) return null;
  final wanted = _normalize(label);
  for (final subject in subjects) {
    if (_normalize(subject.name) == wanted) return subject;
  }
  return null;
}

/// An upcoming test from the dashboard.
class UpcomingTest {
  final Homework homework;
  final UtcDateTime date;
  const UpcomingTest(this.homework, this.date);

  @override
  bool operator ==(Object other) =>
      other is UpcomingTest && other.homework == homework && other.date == date;

  @override
  int get hashCode => Object.hash(homework, date);
}

/// The next test of every subject that has one, keyed by the lower-case
/// subject name.
Map<String, UpcomingTest> nextTestsBySubject(AppState state) {
  final today = UtcDateTime.now().stripTime();
  final result = <String, UpcomingTest>{};
  final days = (state.dashboardState.allDays ?? const <Day>[]).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  for (final day in days) {
    if (day.date.isBefore(today)) continue;
    for (final hw in day.homework) {
      if (!isTestEntry(hw) || hw.label == null) continue;
      result.putIfAbsent(
          _normalize(hw.label!), () => UpcomingTest(hw, day.date));
    }
  }
  return result;
}

/// The next test of [subject], if one is entered.
UpcomingTest? nextTestFor(Map<String, UpcomingTest> tests, Subject subject) =>
    tests[_normalize(subject.name)];
