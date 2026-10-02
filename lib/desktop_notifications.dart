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
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How often the dashboard is reloaded while the app is open, so that new
/// entries are noticed.
const refreshInterval = Duration(minutes: 15);

const _seenKey = "notifiedEntries";
const _seenServerKey = "notifiedServerNotifications";
const _lessonsKey = "knownLessonTeachers";

const _darwin = DarwinNotificationDetails(
  presentAlert: true,
  presentBanner: true,
  presentList: true,
  presentSound: true,
);
const _details = NotificationDetails(macOS: _darwin, iOS: _darwin);

Future<void> _show(int id, String title, String body) async {
  if (!await _ensureInitialized()) return;
  await _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: _details,
  );
}

const _maxRemembered = 500;

final _plugin = FlutterLocalNotificationsPlugin();
bool _initialized = false;

bool get desktopNotificationsSupported => Platform.isMacOS || Platform.isIOS;

Future<bool> _ensureInitialized() async {
  if (!desktopNotificationsSupported) return false;
  if (_initialized) return true;
  try {
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(macOS: darwin, iOS: darwin),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  } on Exception catch (e) {
    log("Notifications not available", error: e);
  }
  return _initialized;
}

/// A key that changes whenever an entry is added or changed.
String _entryKey(Homework hw) =>
    "${homeworkMoveKey(hw)}@${hw.firstSeen.millisecondsSinceEpoch}";

String _describe(Homework hw) {
  final kind = switch (hw.type) {
    HomeworkType.grade => "Neue Note",
    HomeworkType.gradeGroup => "Neuer Test",
    HomeworkType.observation => "Neue Beobachtung",
    _ => isTestEntry(hw) ? "Neuer Test" : "Neue Aufgabe",
  };
  final changed = hw.isChanged && !hw.isNew;
  return [
    changed
        ? kind
            .replaceFirst("Neue", "Geänderte")
            .replaceFirst("Neuer", "Geänderter")
        : kind,
    if (hw.label != null) hw.label!,
  ].join(" · ");
}

/// Shows a notification for every entry on the dashboard that is new or
/// changed and has not been announced yet.
Future<void> notifyNewEntries(AppState state) async {
  if (!desktopNotificationsSupported) return;
  final days = state.dashboardState.allDays;
  if (days == null) return;
  final candidates = [
    for (final day in days)
      for (final hw in day.homework)
        if (hw.isNew || hw.isChanged) hw,
  ];
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList(_seenKey);
  final seen = {...?stored};
  final fresh =
      candidates.where((hw) => !seen.contains(_entryKey(hw))).toList();
  seen.addAll(fresh.map(_entryKey));
  final list = seen.toList();
  await prefs.setStringList(
    _seenKey,
    list.length > _maxRemembered
        ? list.sublist(list.length - _maxRemembered)
        : list,
  );
  // On the very first run everything counts as seen, to avoid a flood of
  // notifications about old entries.
  // Ask for permission right away, not only when the first entry arrives.
  if (!await _ensureInitialized()) return;
  if (stored == null || fresh.isEmpty) return;

  const details = _details;
  if (fresh.length <= 3) {
    for (final hw in fresh) {
      await _plugin.show(
        id: _entryKey(hw).hashCode,
        title: _describe(hw),
        body: [
          if (hw.type == HomeworkType.grade && hw.gradeFormatted != null)
            hw.gradeFormatted!,
          hw.title,
          if (hw.subtitle.isNotEmpty) hw.subtitle,
        ].join(" – "),
        notificationDetails: details,
      );
    }
  } else {
    await _plugin.show(
      id: 0,
      title: "${fresh.length} neue Einträge im Register",
      body: fresh.take(4).map(_describe).join("\n"),
      notificationDetails: details,
    );
  }
}

/// Announces notifications of the register that were not announced yet.
Future<void> notifyServerNotifications(AppState state) async {
  if (!desktopNotificationsSupported) return;
  final notifications = state.notificationState.notifications;
  if (notifications == null) return;
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList(_seenServerKey);
  final seen = {...?stored};
  final fresh = notifications.where((n) => !seen.contains("${n.id}")).toList();
  seen.addAll(fresh.map((n) => "${n.id}"));
  final list = seen.toList();
  await prefs.setStringList(
    _seenServerKey,
    list.length > _maxRemembered
        ? list.sublist(list.length - _maxRemembered)
        : list,
  );
  if (stored == null || fresh.isEmpty) return;
  for (final n in fresh.take(3)) {
    await _show(
      "server-${n.id}".hashCode,
      n.title,
      n.subTitle ?? "Neue Benachrichtigung im Register",
    );
  }
  if (fresh.length > 3) {
    await _show(1, "${fresh.length} neue Benachrichtigungen",
        "Öffne Register, um sie zu sehen.");
  }
}

String _teacherNames(CalendarHour hour) =>
    hour.teachers.map((t) => "${t.firstName} ${t.lastName}").join(", ");

/// Remembers who teaches each lesson and announces when that changes, e.g.
/// because of a substitution ("Supplenz"). Only lessons from today on count.
Future<void> notifySubstitutions(
  AppState state,
  Iterable<UtcDateTime> dates,
) async {
  if (!desktopNotificationsSupported) return;
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_lessonsKey);
  final known = raw == null
      ? <String, String>{}
      : Map<String, String>.from(jsonDecode(raw) as Map);
  final today = UtcDateTime.now().stripTime();
  final changes = <String>[];
  for (final date in dates) {
    final day = state.calendarState.days[date];
    if (day == null || date.isBefore(today)) continue;
    final dayLabel = DateFormat("EE dd.MM.", "de").format(date);
    for (final hour in day.hours) {
      final key = "${DateFormat("yyyy-MM-dd").format(date)}|${hour.fromHour}";
      final now = "${hour.subject}|${_teacherNames(hour)}";
      final before = known[key];
      known[key] = now;
      if (before == null || before == now) continue;
      final parts = before.split("|");
      final oldSubject = parts.first;
      final oldTeachers = parts.length > 1 ? parts[1] : "";
      if (oldTeachers == _teacherNames(hour) && oldSubject == hour.subject) {
        continue;
      }
      changes.add(
        "$dayLabel, ${hour.fromHour}. Stunde: "
        "${oldSubject == hour.subject ? hour.subject : "$oldSubject → ${hour.subject}"} "
        "– jetzt ${_teacherNames(hour).isEmpty ? "ohne Lehrperson" : _teacherNames(hour)}"
        "${oldTeachers.isEmpty ? "" : " statt $oldTeachers"}",
      );
    }
  }
  // Forget lessons that are over.
  known.removeWhere((key, _) {
    final date = UtcDateTime.tryParse(key.split("|").first);
    return date == null ||
        date.isBefore(today.subtract(const Duration(days: 7)));
  });
  await prefs.setString(_lessonsKey, jsonEncode(known));
  for (final change in changes.take(4)) {
    await _show(change.hashCode, "Supplenz / Lehrerwechsel", change);
  }
  if (changes.length > 4) {
    await _show(2, "${changes.length} Änderungen im Stundenplan",
        "Öffne den Kalender in Register.");
  }
}
