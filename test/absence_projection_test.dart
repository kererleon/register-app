import 'package:built_collection/built_collection.dart';
import 'package:dr/absence_projection.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence_meter.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A week (Mon 19.10.2026 to Fri) with 6 lessons a day, 5 on Friday.
BuiltMap<UtcDateTime, CalendarDay> _week() {
  CalendarDay day(int dayOfMonth, int lessons) {
    final date = UtcDateTime(2026, 10, dayOfMonth);
    return CalendarDay(
      (b) => b
        ..date = date
        ..hours.addAll([
          for (var h = 1; h <= lessons; h++)
            CalendarHour(
              (b) => b
                ..fromHour = h
                ..toHour = h
                ..subject = "Mathematik",
            ),
        ]),
    );
  }

  return BuiltMap({
    for (final (d, n) in [(19, 6), (20, 6), (21, 6), (22, 6), (23, 5)])
      UtcDateTime(2026, 10, d): day(d, n),
  });
}

AbsenceStatistic _stat(int missed, String percent) => AbsenceStatistic(
      (b) => b
        ..counterForSchool = missed
        ..percentage = percent,
    );

void main() {
  test('lessons per weekday come from the timetable', () {
    expect(lessonsPerWeekday(_week().values), {1: 6, 2: 6, 3: 6, 4: 6, 5: 5});
  });

  test('absences are projected onto the rest of the school year', () {
    // Until 21.10. 186 lessons were held (from 7.9., holidays excluded) and
    // 835 are left; both checked by hand. 0.7 % of 186 = 1.3 missed.
    final p =
        projectAbsences(_stat(0, "0.7"), _week(), DateTime(2026, 10, 21))!;
    expect(p.totalLessons, 186 + 835);
    expect(p.missed, closeTo(1.302, 0.001));
    expect(p.stillAllowed, (1021 * 0.25 - 1.302).floor());
    expect(p.yearPercent, closeTo(0.13, 0.01));
    expect(p.end, DateTime(2027, 6, 16));
  });

  test('without absences all of the quarter is left', () {
    final p = projectAbsences(_stat(0, "0"), _week(), DateTime(2026, 10, 21))!;
    expect(p.totalLessons, 186 + 835);
    expect(p.stillAllowed, 255);
    expect(p.yearPercent, 0);
  });

  test('over the limit nothing is left', () {
    final p =
        projectAbsences(_stat(400, "40"), _week(), DateTime(2027, 6, 14))!;
    expect(p.stillAllowed, 0);
  });

  test('without a timetable there is no projection', () {
    expect(
      projectAbsences(_stat(5, "2"), BuiltMap(), DateTime(2026, 10, 21)),
      isNull,
    );
  });

  testWidgets('the outlook fits on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final p =
        projectAbsences(_stat(30, "10"), _week(), DateTime(2026, 10, 21))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AbsenceYearOutlook(projection: p),
          ),
        ),
      ),
    );
    expect(find.textContaining("Stunden"), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
