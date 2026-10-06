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
const _android = AndroidNotificationDetails(
  "register_updates",
  "Neuigkeiten aus dem Register",
  channelDescription:
      "Neue Noten, Aufgaben, Mitteilungen und Änderungen im Stundenplan",
  importance: Importance.high,
  priority: Priority.high,
);
const _details = NotificationDetails(
  macOS: _darwin,
  iOS: _darwin,
  android: _android,
  windows: WindowsNotificationDetails(),
);

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

bool get desktopNotificationsSupported =>
    Platform.isMacOS || Platform.isIOS || Platform.isAndroid || Platform.isWindows;

Future<bool> _ensureInitialized() async {
  if (!desktopNotificationsSupported) return false;
  if (_initialized) return true;
  try {
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(
        macOS: darwin,
        iOS: darwin,
        android: AndroidInitializationSettings("@mipmap/launcher_icon"),
        windows: WindowsInitializationSettings(
          appName: "Register",
          appUserModelId: "kererleon.Register",
          guid: "6f3c2a91-4d7e-4b8a-9c15-2e8f0d6a7b34",
        ),
      ),
    );
    _initialized = true;
    // ignore: avoid_catches_without_on_clauses
  } catch (e) {
    // Also errors: without a platform plugin (e.g. in tests) this throws one.
    log("Notifications not available", error: e);
    return false;
  }
  // Asking for permission needs a visible app; in the background it fails,
  // which must not stop the notifications themselves.
  try {
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  } on Object catch (e) {
    log("Could not ask for notification permission", error: e);
  }
  return true;
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

const _usualKey = "usualTeachers";
const _notifiedLessonKey = "notifiedLessonChanges";

Map<String, String> _readMap(SharedPreferences prefs, String key) {
  final raw = prefs.getString(key);
  return raw == null ? {} : Map<String, String>.from(jsonDecode(raw) as Map);
}

/// Who usually teaches a subject: the teacher seen in most of its lessons,
/// once there are enough lessons to tell.
String? _usualTeacher(Map<String, dynamic> counts) {
  if (counts.isEmpty) return null;
  final total = counts.values.fold<int>(0, (a, b) => a + (b as int));
  final top = counts.entries.reduce((a, b) => (a.value as int) >= (b.value as int) ? a : b);
  if (total < 3 || (top.value as int) / total < 0.6) return null;
  return top.key;
}

/// Remembers every lesson and announces changes from today on: substitutions
/// ("Supplenz"), a teacher other than the usual one, cancelled lessons, room
/// changes and new lessons.
Future<void> notifySubstitutions(
  AppState state,
  Iterable<UtcDateTime> dates,
) async {
  if (!desktopNotificationsSupported) return;
  final prefs = await SharedPreferences.getInstance();
  final known = _readMap(prefs, _lessonsKey);
  final firstRun = known.isEmpty;
  final rawUsual = prefs.getString(_usualKey);
  final usual = rawUsual == null
      ? <String, Map<String, dynamic>>{}
      : (jsonDecode(rawUsual) as Map).map(
          (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
        );
  final notified = {...?prefs.getStringList(_notifiedLessonKey)};
  final today = UtcDateTime.now().stripTime();
  final changes = <(String, String, String)>[]; // (id, title, text)

  for (final date in dates) {
    final day = state.calendarState.days[date];
    if (day == null) continue;
    final dateKey = DateFormat("yyyy-MM-dd").format(date);
    final dayLabel = DateFormat("EE dd.MM.", "de").format(date);
    final upcoming = !date.isBefore(today);
    final present = <String>{};
    for (final hour in day.hours) {
      final key = "$dateKey|${hour.fromHour}";
      present.add(key);
      final teachers = _teacherNames(hour);
      final rooms = hour.rooms.join(", ");
      final now = "${hour.subject}|$teachers|$rooms";
      final before = known[key];
      known[key] = now;
      final where = "$dayLabel, ${hour.fromHour}. Stunde";

      if (before == null) {
        // Learn who usually teaches the subject.
        final counts = usual.putIfAbsent(hour.subject, () => {});
        for (final t in hour.teachers) {
          final name = "${t.firstName} ${t.lastName}";
          counts[name] = ((counts[name] as int?) ?? 0) + 1;
        }
        if (!upcoming || firstRun) continue;
        final regular = _usualTeacher(usual[hour.subject]!);
        if (regular != null &&
            hour.teachers.isNotEmpty &&
            !teachers.contains(regular)) {
          changes.add((
            "$key@sub@$teachers",
            "Supplenz: ${hour.subject}",
            "$where – $teachers statt $regular",
          ));
        }
        continue;
      }
      if (!upcoming || before == now) continue;
      final old = before.split("|");
      final oldSubject = old[0];
      final oldTeachers = old.length > 1 ? old[1] : "";
      final oldRooms = old.length > 2 ? old[2] : "";
      if (oldSubject != hour.subject) {
        changes.add((
          "$key@subject@$now",
          "Stundenplan geändert",
          "$where: ${hour.subject} statt $oldSubject"
              "${teachers.isEmpty ? "" : " ($teachers)"}",
        ));
      } else if (oldTeachers != teachers) {
        changes.add((
          "$key@teacher@$now",
          "Supplenz: ${hour.subject}",
          "$where – ${teachers.isEmpty ? "ohne Lehrperson" : teachers}"
              "${oldTeachers.isEmpty ? "" : " statt $oldTeachers"}",
        ));
      } else if (oldRooms != rooms && rooms.isNotEmpty) {
        changes.add((
          "$key@room@$now",
          "Raumänderung: ${hour.subject}",
          "$where – jetzt in $rooms${oldRooms.isEmpty ? "" : " statt $oldRooms"}",
        ));
      }
    }
    // Lessons that were there before and are gone now: cancelled.
    final gone = known.keys
        .where((k) => k.startsWith("$dateKey|") && !present.contains(k))
        .toList();
    for (final key in gone) {
      final old = known.remove(key)!.split("|");
      if (!upcoming || firstRun) continue;
      final hourNo = key.split("|")[1];
      changes.add((
        "$key@gone",
        "Stunde entfällt: ${old[0]}",
        "$dayLabel, $hourNo. Stunde${old.length > 1 && old[1].isNotEmpty ? " (${old[1]})" : ""}",
      ));
    }
  }

  // Forget lessons that are long over.
  known.removeWhere((key, _) {
    final date = UtcDateTime.tryParse(key.split("|").first);
    return date == null ||
        date.isBefore(today.subtract(const Duration(days: 7)));
  });
  final fresh = changes.where((c) => !notified.contains(c.$1)).toList();
  notified.addAll(fresh.map((c) => c.$1));
  final notifiedList = notified.toList();
  await prefs.setString(_lessonsKey, jsonEncode(known));
  await prefs.setString(_usualKey, jsonEncode(usual));
  await prefs.setStringList(
    _notifiedLessonKey,
    notifiedList.length > _maxRemembered
        ? notifiedList.sublist(notifiedList.length - _maxRemembered)
        : notifiedList,
  );
  for (final (id, title, text) in fresh.take(4)) {
    await _show(id.hashCode, title, text);
  }
  if (fresh.length > 4) {
    await _show(
      2,
      "${fresh.length} Änderungen im Stundenplan",
      "Öffne den Kalender in Register.",
    );
  }
}

const _seenMessagesKey = "notifiedMessages";

/// Announces messages ("Mitteilungen") that are unread and not announced yet.
Future<void> notifyNewMessages(AppState state) async {
  if (!desktopNotificationsSupported) return;
  final messages = state.messagesState.messages;
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getStringList(_seenMessagesKey);
  final seen = {...?stored};
  final fresh =
      messages.where((m) => m.isNew && !seen.contains("${m.id}")).toList();
  seen.addAll(messages.map((m) => "${m.id}"));
  final list = seen.toList();
  await prefs.setStringList(
    _seenMessagesKey,
    list.length > _maxRemembered
        ? list.sublist(list.length - _maxRemembered)
        : list,
  );
  if (stored == null || fresh.isEmpty) return;
  for (final m in fresh.take(3)) {
    await _show("message-${m.id}".hashCode, "Neue Mitteilung: ${m.subject}",
        "Von ${m.fromName}");
  }
  if (fresh.length > 3) {
    await _show(3, "${fresh.length} neue Mitteilungen", "Öffne Register, um sie zu lesen.");
  }
}
