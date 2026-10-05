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
import 'package:dr/grade_forecast.dart';
import 'package:dr/lesson_time.dart';
import 'package:dr/ui/absence_meter.dart';
import 'package:dr/ui/holo.dart';
import 'package:dr/ui/theme.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

/// Everything the "Heute" page shows, taken from the app state.
class TodayData {
  final UtcDateTime today;
  final List<CalendarHour> lessons;
  final bool lessonsLoaded;
  final List<Homework> dueToday;
  final List<Homework> dueTomorrow;
  final List<UpcomingTest> tests;

  /// The subject of each test, for the grade it needs.
  final Map<UpcomingTest, Subject> testSubjects;
  final Semester semester;
  final double? absencePercent;
  final List<(Subject, double)> weakSubjects;
  final BuiltMapLike subjectNicks;

  const TodayData({
    required this.today,
    required this.lessons,
    required this.lessonsLoaded,
    required this.dueToday,
    required this.dueTomorrow,
    required this.tests,
    required this.testSubjects,
    required this.semester,
    required this.absencePercent,
    required this.weakSubjects,
    required this.subjectNicks,
  });

  static bool isTest(Homework hw) => isTestEntry(hw);

  factory TodayData.from(AppState state) {
    final today = wallClockToday();
    final tomorrow = today.add(const Duration(days: 1));
    final days = state.dashboardState.allDays ?? const <Day>[];
    List<Homework> dueOn(UtcDateTime date) => [
          for (final day in days)
            if (day.date == date)
              for (final hw in day.homework)
                if (hw.type != HomeworkType.grade &&
                    hw.type != HomeworkType.observation)
                  hw,
        ];
    final tests = <UpcomingTest>[
      for (final day in days)
        if (!day.date.isBefore(today) &&
            day.date.difference(today).inDays <= 30)
          for (final hw in day.homework)
            if (isTest(hw)) UpcomingTest(hw, day.date),
    ]..sort((a, b) => a.date.compareTo(b.date));
    final calendarDay = state.calendarState.days[today];
    final semester = state.gradesState.semester;
    final weak = <(Subject, double)>[
      for (final subject in state.gradesState.subjects)
        if (subject.average(semester) case final avg?)
          if (avg / 100 < passMark) (subject, avg / 100),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return TodayData(
      today: today,
      lessons: calendarDay?.hours.toList() ?? const [],
      lessonsLoaded: calendarDay != null,
      dueToday: dueOn(today),
      dueTomorrow: dueOn(tomorrow),
      tests: tests,
      testSubjects: {
        for (final test in tests)
          if (subjectForLabel(
            state.gradesState.subjects,
            test.homework.label,
          )
              case final subject?)
            test: subject,
      },
      semester: semester,
      absencePercent: parseAbsencePercentage(
        state.absencesState.statistic?.percentage,
      ),
      weakSubjects: weak,
      subjectNicks: BuiltMapLike(state.settingsState.subjectNicks.toMap()),
    );
  }
}

/// A plain map wrapper so [TodayData] does not depend on built_collection.
class BuiltMapLike {
  final Map<String, String> map;
  const BuiltMapLike(this.map);
  String nick(String subject) => map[subject.toLowerCase()] ?? subject;
}

typedef CreateStudyPlanCallback = void Function(
    UpcomingTest test, List<UtcDateTime> days);

class TodayPage extends StatelessWidget {
  final TodayData data;
  final CreateStudyPlanCallback onCreateStudyPlan;
  final VoidCallback onShowGrades;
  final VoidCallback onShowAbsences;
  final VoidCallback onShowCalendar;
  final bool noInternet;

  const TodayPage({
    super.key,
    required this.data,
    required this.onCreateStudyPlan,
    required this.onShowGrades,
    required this.onShowAbsences,
    required this.onShowCalendar,
    required this.noInternet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: ResponsiveAppBar(title: Text(br("Heute", "Heute, no cap 💀"))),
      body: ValueListenableBuilder(
        valueListenable: minuteTicker,
        builder: (context, _, __) => ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            _NowCard(data: data, onShowCalendar: onShowCalendar),
            if (data.dueToday.isNotEmpty || data.dueTomorrow.isNotEmpty) ...[
              SectionLabel(br("Fällig", "Fällig 😬")),
              for (final hw in data.dueToday)
                _TaskRow(homework: hw, when: "Heute", urgent: true),
              for (final hw in data.dueTomorrow)
                _TaskRow(homework: hw, when: "Morgen"),
            ],
            SectionLabel(br("Tests & Schularbeiten", "Boss-Fights ⚔️")),
            if (data.tests.isEmpty)
              HoloPanel(
                child: Text(
                  "Keine Tests in den nächsten 30 Tagen eingetragen.",
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            for (final test in data.tests)
              _TestCountdown(
                test: test,
                subject: data.testSubjects[test],
                semester: data.semester,
                today: data.today,
                noInternet: noInternet,
                onCreateStudyPlan: onCreateStudyPlan,
              ),
            if (data.weakSubjects.isNotEmpty) ...[
              SectionLabel(br("Achtung bei den Noten", "Ohio-Zone 🌽")),
              for (final (subject, avg) in data.weakSubjects)
                HoloPanel(
                  accent: AppColors.danger,
                  onTap: onShowGrades,
                  child: Row(
                    children: [
                      NeonRing(
                        value: avg,
                        label: formatGradeSteps(avg),
                        size: 44,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(subject.name,
                                style: theme.textTheme.titleMedium),
                            Text(
                              "Unter 6 – unter Noten siehst du, was du im nächsten Test brauchst.",
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
            ],
            if (data.absencePercent != null) ...[
              SectionLabel(br("Fehlstunden", "Skip-Statistik 🛌")),
              HoloPanel(
                onTap: onShowAbsences,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${data.absencePercent!.toStringAsFixed(1).replaceAll(".", ",")} % der Unterrichtszeit",
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    AbsenceMeter(percent: data.absencePercent!),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _time(UtcDateTime t) => DateFormat("HH:mm").format(t);

String _lessonTimes(CalendarHour hour) {
  if (hour.timeSpans.isEmpty) return "";
  return "${_time(hour.timeSpans.first.from)}–${_time(hour.timeSpans.last.to)}";
}

class _NowCard extends StatelessWidget {
  final TodayData data;
  final VoidCallback onShowCalendar;
  const _NowCard({required this.data, required this.onShowCalendar});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = wallClockNow();
    final lessons = data.lessons;
    final current = lessons.where((h) => isLessonNow(h, now)).firstOrNull;
    final next = lessons
        .where((h) =>
            h.timeSpans.isNotEmpty && h.timeSpans.first.from.isAfter(now))
        .firstOrNull;
    final over = lessons.isNotEmpty &&
        lessons.last.timeSpans.isNotEmpty &&
        !now.isBefore(lessons.last.timeSpans.last.to);

    String headline;
    String detail;
    if (!data.lessonsLoaded) {
      headline = "Stundenplan wird geladen";
      detail = "Sobald die Woche geladen ist, siehst du hier deine Stunden.";
    } else if (lessons.isEmpty) {
      headline = br("Heute frei", "Heute frei, W 🏖️");
      detail = "Kein Unterricht eingetragen.";
    } else if (current != null) {
      final left = current.timeSpans.last.to.difference(now).inMinutes;
      headline = data.subjectNicks.nick(current.subject);
      detail = "${br("Läuft gerade", "Lock in 🔒")} · noch $left min"
          "${current.rooms.isEmpty ? "" : " · ${current.rooms.join(", ")}"}";
    } else if (next != null) {
      final inMin = next.timeSpans.first.from.difference(now).inMinutes;
      headline = "Gleich: ${data.subjectNicks.nick(next.subject)}";
      detail = inMin < 60
          ? "Beginnt in $inMin min"
          : "Beginnt um ${_time(next.timeSpans.first.from)}";
    } else if (over) {
      headline = br("Schulschluss", "Schulschluss 🗿");
      detail =
          br("Für heute geschafft.", "Sigma grindset ✔️ Für heute geschafft.");
    } else {
      headline = "Heute";
      detail = "";
    }

    return GlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HudLabel(
                "${DateFormat("EEEE, d. MMMM", "de").format(data.today)} · ${DateFormat("HH:mm").format(DateTime.now())}",
              ),
              const Spacer(),
              if (current != null)
                StatusPill(label: "Jetzt", color: AppColors.cyan),
            ],
          ),
          const SizedBox(height: 8),
          GradientText(headline, style: theme.textTheme.headlineMedium),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(detail, style: theme.textTheme.bodyMedium),
          ],
          if (lessons.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final hour in lessons)
              _LessonLine(
                hour: hour,
                nick: data.subjectNicks.nick(hour.subject),
                isNow: hour == current,
                isPast: hour.timeSpans.isNotEmpty &&
                    !now.isBefore(hour.timeSpans.last.to),
              ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onShowCalendar,
              icon: const Icon(Icons.calendar_month_outlined, size: 18),
              label: const Text("Kalender"),
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonLine extends StatelessWidget {
  final CalendarHour hour;
  final String nick;
  final bool isNow;
  final bool isPast;

  const _LessonLine({
    required this.hour,
    required this.nick,
    required this.isNow,
    required this.isPast,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isNow ? AppColors.cyan : theme.colorScheme.onSurface;
    return Opacity(
      opacity: isPast ? 0.45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isNow ? AppColors.cyan.withValues(alpha: 0.14) : null,
          borderRadius: BorderRadius.circular(10),
          border: isNow
              ? Border.all(color: AppColors.cyan.withValues(alpha: 0.6))
              : null,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Text(
                hour.fromHour == hour.toHour
                    ? "${hour.fromHour}."
                    : "${hour.fromHour}–${hour.toHour}",
                style: mono(theme.textTheme.bodySmall, weight: FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 92,
              child: Text(
                _lessonTimes(hour),
                style: mono(
                  theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
            Expanded(
              child: Text(
                nick,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: isNow ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hour.warning)
              Icon(Icons.bolt_rounded, size: 16, color: AppColors.danger),
            if (hour.rooms.isNotEmpty)
              Text(
                hour.rooms.join(", "),
                style: mono(theme.textTheme.labelSmall),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Homework homework;
  final String when;
  final bool urgent;
  const _TaskRow(
      {required this.homework, required this.when, this.urgent = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HoloPanel(
      accent: TodayData.isTest(homework)
          ? AppColors.danger
          : urgent
              ? AppColors.warning
              : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HudLabel(
                  [when, if (homework.label != null) homework.label!]
                      .join(" · "),
                ),
                const SizedBox(height: 4),
                Text(homework.title, style: theme.textTheme.titleMedium),
                if (homework.subtitle.isNotEmpty)
                  Text(
                    homework.subtitle,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (homework.checked)
            Icon(Icons.check_circle_rounded, color: AppColors.success),
        ],
      ),
    );
  }
}

class _TestCountdown extends StatelessWidget {
  final UpcomingTest test;
  final Subject? subject;
  final Semester semester;
  final UtcDateTime today;
  final bool noInternet;
  final CreateStudyPlanCallback onCreateStudyPlan;

  const _TestCountdown({
    required this.test,
    required this.subject,
    required this.semester,
    required this.today,
    required this.noInternet,
    required this.onCreateStudyPlan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = test.date.difference(today).inDays;
    final countdown = switch (days) {
      0 => "Heute",
      1 => "Morgen",
      _ => "in $days Tagen",
    };
    final color = days <= 1
        ? AppColors.danger
        : days <= 4
            ? AppColors.warning
            : AppColors.cyan;
    return HoloPanel(
      accent: color,
      highlighted: days <= 1,
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Column(
              children: [
                Text(
                  days <= 1 ? "!" : "$days",
                  style: mono(
                    theme.textTheme.headlineMedium?.copyWith(color: color),
                    weight: FontWeight.w700,
                  ),
                ),
                HudLabel(days <= 1 ? countdown : "Tage", color: color),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HudLabel(
                  "${DateFormat("EE dd.MM.", "de").format(test.date)}"
                  "${test.homework.label != null ? " · ${test.homework.label}" : ""}",
                ),
                const SizedBox(height: 4),
                Text(test.homework.title, style: theme.textTheme.titleMedium),
                if (test.homework.subtitle.isNotEmpty)
                  Text(
                    test.homework.subtitle,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subject != null && subject!.average(semester) != null) ...[
                  const SizedBox(height: 8),
                  TestTargets(subject: subject!, semester: semester),
                ],
              ],
            ),
          ),
          if (days >= 2)
            IconButton(
              tooltip: "Lernplan erstellen",
              icon: const Icon(Icons.auto_awesome_rounded),
              color: AppColors.violet,
              onPressed:
                  noInternet ? null : () => _showStudyPlanDialog(context),
            ),
        ],
      ),
    );
  }

  Future<void> _showStudyPlanDialog(BuildContext context) async {
    final maxSessions = test.date.difference(today).inDays.clamp(1, 5);
    var sessions = maxSessions.clamp(1, 3);
    final days = await showDialog<List<UtcDateTime>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final plan = studyDays(test.date, today, sessions);
          return AlertDialog(
            title: const Text("Lernplan erstellen"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Für „${test.homework.title}“ am ${DateFormat("EEEE, d. MMMM", "de").format(test.date)}. "
                  "Die Lerntage werden als Erinnerungen im Register eingetragen.",
                ),
                const SizedBox(height: 16),
                const HudLabel("Lerneinheiten"),
                Slider(
                  value: sessions.toDouble(),
                  min: 1,
                  max: maxSessions.toDouble(),
                  divisions: maxSessions > 1 ? maxSessions - 1 : null,
                  label: "$sessions",
                  onChanged: maxSessions > 1
                      ? (v) => setState(() => sessions = v.round())
                      : null,
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final d in plan)
                      Chip(
                        avatar: const Icon(Icons.menu_book_rounded, size: 16),
                        label: Text(DateFormat("EE dd.MM.", "de").format(d)),
                      ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Abbrechen"),
              ),
              FilledButton(
                onPressed:
                    plan.isEmpty ? null : () => Navigator.pop(context, plan),
                child: Text("${plan.length} Erinnerungen eintragen"),
              ),
            ],
          );
        },
      ),
    );
    if (days != null && days.isNotEmpty) onCreateStudyPlan(test, days);
  }
}

/// The [sessions] days right before [testDate], from today on and without
/// Sundays.
List<UtcDateTime> studyDays(
    UtcDateTime testDate, UtcDateTime today, int sessions) {
  final result = <UtcDateTime>[];
  var day = testDate.subtract(const Duration(days: 1));
  while (result.length < sessions && !day.isBefore(today)) {
    if (day.weekday != DateTime.sunday) result.add(day);
    day = day.subtract(const Duration(days: 1));
  }
  return result.reversed.toList();
}

/// What a test needs for an average of 6, 7 and 8, as compact chips.
class TestTargets extends StatelessWidget {
  final Subject subject;
  final Semester semester;
  const TestTargets({super.key, required this.subject, required this.semester});

  @override
  Widget build(BuildContext context) {
    final current = subject.average(semester)! / 100;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        HudLabel("Ø jetzt ${formatGradeSteps(current)} · brauchst"),
        for (final target in const [6.0, 7.0, 8.0])
          _TargetChip(
            target: target,
            forecast: forecastNextGrade(subject, semester, target: target),
          ),
      ],
    );
  }
}

class _TargetChip extends StatelessWidget {
  final double target;
  final Forecast forecast;
  const _TargetChip({required this.target, required this.forecast});

  @override
  Widget build(BuildContext context) {
    final needed = roundUpToQuarter(forecast.required);
    final (text, color) = switch (forecast.kind) {
      ForecastKind.safe => (br("sicher", "safe 🗿"), AppColors.success),
      ForecastKind.impossible => (br("unmöglich", "L 💀"), AppColors.danger),
      ForecastKind.reachable => (formatGradeSteps(needed), gradeColor(needed)),
    };
    return StatusPill(
      label: "Ø${target.toStringAsFixed(0)} → $text",
      color: color,
    );
  }
}
