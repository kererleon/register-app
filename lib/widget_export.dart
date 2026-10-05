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

import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Talks to the native side of the macOS app, which stores the data for the
/// desktop widget and asks WidgetKit to redraw it.
const _channel = MethodChannel("register/widget");

/// Fallback colors for subjects without a color chosen in the settings.
const _palette = [
  0xFF7C5CFF,
  0xFF22D3EE,
  0xFF2DD4A3,
  0xFFF5B544,
  0xFFFF5C7A,
  0xFF60A5FA,
  0xFFC084FC,
  0xFFF472B6,
];

bool get widgetSupported => Platform.isMacOS;

String _hm(DateTime t) => DateFormat("HH:mm").format(t);

int _colorFor(SettingsState settings, String subject) =>
    settings.subjectThemes[subject]?.color ??
    _palette[subject.hashCode.abs() % _palette.length];

/// Sends the current week, upcoming tasks and grade averages to the desktop
/// widgets.
Future<void> exportWeekForWidget(AppState state) async {
  if (!widgetSupported) return;
  final monday = toMonday(UtcDateTime.now());
  final today = UtcDateTime.now().stripTime();
  final settings = state.settingsState;
  final days = <Map<String, Object?>>[];
  for (var i = 0; i < 5; i++) {
    final date = monday.add(Duration(days: i));
    final day = state.calendarState.days[date];
    days.add({
      "date": DateFormat("yyyy-MM-dd").format(date),
      "weekday": DateFormat("E", "de").format(date),
      "loaded": day != null,
      "lessons": [
        if (day != null)
          for (final hour in day.hours)
            {
              "from": hour.fromHour,
              "to": hour.toHour,
              "subject": hour.subject,
              "short": settings.subjectNicks[hour.subject.toLowerCase()] ??
                  hour.subject,
              "room": hour.rooms.isEmpty ? null : hour.rooms.join(", "),
              "test": hour.warning,
              "color": _colorFor(settings, hour.subject),
              "start": hour.timeSpans.isEmpty
                  ? null
                  : _hm(hour.timeSpans.first.from),
              "end":
                  hour.timeSpans.isEmpty ? null : _hm(hour.timeSpans.last.to),
            },
      ],
    });
  }

  final tasks = <Map<String, Object?>>[
    for (final day in state.dashboardState.allDays ?? const <Day>[])
      if (!day.date.isBefore(today) && day.date.difference(today).inDays <= 14)
        for (final hw in day.homework)
          if (hw.type != HomeworkType.grade &&
              hw.type != HomeworkType.observation)
            {
              "date": DateFormat("yyyy-MM-dd").format(day.date),
              "label": hw.label,
              "title": hw.title,
              "subtitle": hw.subtitle,
              "test": isTestEntry(hw),
              "done": hw.checked,
              "color": hw.label == null ? null : _colorFor(settings, hw.label!),
            },
  ]..sort((a, b) => (a["date"]! as String).compareTo(b["date"]! as String));

  final semester = state.gradesState.semester;
  final grades = <Map<String, Object?>>[
    for (final subject in state.gradesState.subjects)
      if (subject.average(semester) case final avg?)
        {
          "subject": subject.name,
          "short":
              settings.subjectNicks[subject.name.toLowerCase()] ?? subject.name,
          "average": avg / 100,
          "color": _colorFor(settings, subject.name),
        },
  ]..sort(
      (a, b) => (a["average"]! as double).compareTo(b["average"]! as double));
  final counted = grades.where((g) => !settings.ignoreForGradesAverage
      .any((i) => i.toLowerCase() == (g["subject"]! as String).toLowerCase()));
  final overall = counted.isEmpty
      ? null
      : counted.map((g) => g["average"]! as double).reduce((a, b) => a + b) /
          counted.length;

  final json = jsonEncode({
    "updated": DateTime.now().toIso8601String(),
    "monday": DateFormat("yyyy-MM-dd").format(monday),
    "days": days,
    "tasks": tasks,
    "grades": grades,
    "overall": overall,
    "semester": semester.name,
  });
  try {
    await _channel.invokeMethod<void>("saveWeek", json);
  } on PlatformException catch (e) {
    log("Could not update the desktop widget", error: e);
  } on MissingPluginException {
    // The native side is not available, e.g. in tests.
  }
}
