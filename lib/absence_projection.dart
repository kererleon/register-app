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

// The register only knows the share of the lessons held so far. This
// projects the absences onto the whole school year: lessons still to come
// are counted from the school calendar of South Tyrol and the timetable.

import 'dart:math';

import 'package:built_collection/built_collection.dart';

import 'package:dr/data.dart';
import 'package:dr/ui/absence_meter.dart';
import 'package:dr/utc_date_time.dart';

/// Absences measured against the whole school year.
typedef AbsenceProjection = ({
  /// Missed lessons so far (from the register's share, so not whole).
  double missed,

  /// Lessons of the whole year (held so far plus still to come).
  int totalLessons,

  /// Lessons that may still be missed until the end of the year.
  int stillAllowed,

  /// Missed lessons as share of the whole year.
  double yearPercent,

  /// Last day of lessons.
  DateTime end,
});

class _SchoolYear {
  final DateTime start;
  final DateTime end;

  /// Days without lessons (both ends included).
  final List<(DateTime, DateTime)> free;

  const _SchoolYear(this.start, this.end, this.free);

  bool isFree(DateTime day) =>
      free.any((f) => !day.isBefore(f.$1) && !day.isAfter(f.$2));
}

/// School calendars decided by the provincial government. Schools may
/// shift a few days of their own, so the result is an estimate.
final _years = [
  _SchoolYear(DateTime(2026, 9, 7), DateTime(2027, 6, 16), [
    (DateTime(2026, 10, 31), DateTime(2026, 11, 8)), // Allerheiligen
    (DateTime(2026, 12, 8), DateTime(2026, 12, 8)), // Maria Empfängnis
    (DateTime(2026, 12, 24), DateTime(2027, 1, 6)), // Weihnachten
    (DateTime(2027, 2, 6), DateTime(2027, 2, 14)), // Fasching
    (DateTime(2027, 3, 25), DateTime(2027, 3, 30)), // Ostern
    (DateTime(2027, 5, 1), DateTime(2027, 5, 1)), // Tag der Arbeit
    (DateTime(2027, 5, 17), DateTime(2027, 5, 17)), // Pfingstmontag
    (DateTime(2027, 6, 2), DateTime(2027, 6, 2)), // Tag der Republik
  ]),
];

/// The calendar for the school year around [day]; for years not listed a
/// typical one (early September to mid June, Christmas off).
_SchoolYear _schoolYearOf(DateTime day) {
  for (final year in _years) {
    if (!day.isBefore(year.start.subtract(const Duration(days: 30))) &&
        !day.isAfter(year.end.add(const Duration(days: 60)))) {
      return year;
    }
  }
  final first = day.month >= 8 ? day.year : day.year - 1;
  return _SchoolYear(DateTime(first, 9, 6), DateTime(first + 1, 6, 15), [
    (DateTime(first, 11, 1), DateTime(first, 11, 1)),
    (DateTime(first, 12, 8), DateTime(first, 12, 8)),
    (DateTime(first, 12, 24), DateTime(first + 1, 1, 6)),
  ]);
}

/// Lessons per weekday (1 = Monday), from the most recent day of each
/// weekday that had lessons. Days without lessons (holidays) are skipped.
Map<int, int> lessonsPerWeekday(Iterable<CalendarDay> days) {
  final latest = <int, CalendarDay>{};
  for (final day in days) {
    if (day.hours.isEmpty) continue;
    final weekday = day.date.weekday;
    final known = latest[weekday];
    if (known == null || day.date.isAfter(known.date)) latest[weekday] = day;
  }
  return {
    for (final MapEntry(:key, :value) in latest.entries)
      key: value.hours.fold(0, (sum, hour) => sum + hour.length),
  };
}

int _lessonsBetween(
  _SchoolYear year,
  DateTime from,
  DateTime to,
  Map<int, int> perWeekday,
) {
  var lessons = 0;
  for (var day = from;
      !day.isAfter(to);
      day = DateTime(day.year, day.month, day.day + 1)) {
    if (day.isBefore(year.start) || day.isAfter(year.end)) continue;
    if (year.isFree(day)) continue;
    lessons += perWeekday[day.weekday] ?? 0;
  }
  return lessons;
}

// The last result: the pages ask on every state change, but the inputs
// rarely change.
(AbsenceStatistic, Object, DateTime, AbsenceProjection?)? _last;

/// Projects [stat] onto the whole school year. Null without a timetable.
/// [days] is the calendar's map of days; it is only compared by identity.
AbsenceProjection? projectAbsences(
  AbsenceStatistic stat,
  BuiltMap<UtcDateTime, CalendarDay> days,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  if (_last case (final s, final d, final t, final result)
      when identical(s, stat) && identical(d, days) && t == today) {
    return result;
  }
  final result = _project(stat, days.values, today);
  _last = (stat, days, today, result);
  return result;
}

AbsenceProjection? _project(
  AbsenceStatistic stat,
  Iterable<CalendarDay> days,
  DateTime today,
) {
  final perWeekday = lessonsPerWeekday(days);
  if (perWeekday.isEmpty) return null;
  final year = _schoolYearOf(today);
  // The register gives no number of missed lessons (its counters count
  // absences, not lessons), only their share of the lessons held so far.
  // So the lessons held are counted from the calendar and the missed ones
  // follow from the share.
  final percent = parseAbsencePercentage(stat.percentage) ?? 0;
  final heldSoFar = _lessonsBetween(
    year,
    year.start,
    today.subtract(const Duration(days: 1)),
    perWeekday,
  );
  final missed = heldSoFar * percent / 100;
  final remaining = _lessonsBetween(year, today, year.end, perWeekday);
  final total = heldSoFar + remaining;
  if (total <= 0) return null;
  final allowed = (total * absenceLimitPercent / 100).floor();
  return (
    missed: missed,
    totalLessons: total,
    stillAllowed: max(0, (allowed - missed).floor()),
    yearPercent: missed * 100 / total,
    end: year.end,
  );
}
