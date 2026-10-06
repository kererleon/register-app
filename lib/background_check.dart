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

// Checks the register for news while the app is closed (Android: about every
// 15 minutes; iPhone: whenever iOS allows a background refresh).
//
// It loads the state the app saved, feeds the new data through the app's own
// reducers and then uses the same notification logic as the open app, so
// nothing is announced twice.

import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:ui';

import 'package:built_redux/built_redux.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/desktop.dart';
import 'package:dr/desktop_notifications.dart';
import 'package:dr/middleware/middleware.dart'
    show escapeKey, getStorageKey;
import 'package:dr/reducer/reducer.dart';
import 'package:dr/serializers.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';

const backgroundTaskId = "com.webandgrow.register.check";

bool get backgroundChecksSupported => Platform.isAndroid || Platform.isIOS;

/// Registers the periodic background check. Safe to call on every start.
Future<void> registerBackgroundChecks() async {
  if (!backgroundChecksSupported) return;
  try {
    await Workmanager().initialize(backgroundDispatcher);
    await Workmanager().registerPeriodicTask(
      backgroundTaskId,
      backgroundTaskId,
      // Android's minimum; iOS decides by itself how often it really runs.
      frequency: const Duration(minutes: 15),
      // Saves battery: no checks without internet or on a low battery.
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      // "update" keeps the schedule but applies changed constraints.
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } on Object catch (e) {
    log("Could not register background checks", error: e);
  }
}

@pragma("vm:entry-point")
void backgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await runBackgroundCheck();
    } on Object catch (e) {
      log("Background check failed", error: e);
    }
    // Always "done": a failed check is simply repeated next time.
    return true;
  });
}

/// One check: log in, fetch, compare with the saved state, notify, save.
Future<void> runBackgroundCheck() async {
  // At night nobody needs a notification; skip the network work entirely.
  final hour = DateTime.now().hour;
  if (hour >= 22 || hour < 6) return;
  await initializeDateFormatting("de");
  final storage = getFlutterSecureStorage();
  final loginRaw = await storage.read(key: "login");
  if (loginRaw == null) return; // "Stay logged in" is off.
  final login = json.decode(loginRaw) as Map;
  final user = login["user"] as String?;
  final pass = login["pass"] as String?;
  final url = login["url"] as String?;
  if (user == null || pass == null || url == null) return;
  if (user.startsWith("demo-")) return;

  final base = "$url/v2/";
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20).inMilliseconds,
      receiveTimeout: const Duration(seconds: 30).inMilliseconds,
    ),
  )..interceptors.add(CookieManager(CookieJar()));
  final loginResponse = getMap(
    (await dio.post<dynamic>("${base}api/auth/login",
            data: {"username": user, "password": pass}))
        .data,
  );
  if (!(getBool(loginResponse?["loggedIn"]) ?? false)) return;

  Future<dynamic> send(String path, [Map<String, Object?>? args]) async =>
      (await dio.post<dynamic>(base + path, data: args ?? {})).data;

  // The state the app saved; the reducers compare new data against it.
  final stateKey = escapeKey(getStorageKey(user, "${base}api/auth/login"));
  final savedRaw = await storage.read(key: stateKey);
  AppState initial = AppState();
  var savedFullState = false;
  if (savedRaw != null) {
    final saved = serializers.deserialize(json.decode(savedRaw) as Object);
    if (saved is AppState) {
      initial = saved;
      savedFullState = true;
    } else if (saved is SettingsState) {
      initial = initial.rebuild((b) => b..settingsState.replace(saved));
    }
  }
  final store = Store<AppState, AppStateBuilder, AppActions>(
    appReducerBuilder.build(),
    initial,
    AppActions(),
  );
  final actions = store.actions;

  final days = await send(
    "api/student/dashboard/dashboard",
    {"viewFuture": true},
  );
  if (days is List && savedFullState) {
    await actions.dashboardActions.loaded(
      DaysLoadedPayload(
        (b) => b
          ..data = days
          ..future = true
          ..markNewOrChangedEntries =
              store.state.settingsState.dashboardMarkNewOrChangedEntries
          ..deduplicateEntries =
              store.state.settingsState.dashboardDeduplicateEntries,
      ),
    );
    await notifyNewEntries(store.state);
  }

  final notifications = await send("api/notification/unread");
  if (notifications is List) {
    await actions.notificationsActions.loaded(notifications);
    await notifyServerNotifications(store.state);
  }

  final messages = await send("api/message/getMyMessages");
  if (messages is List) {
    await actions.messagesActions.loaded(messages);
    await notifyNewMessages(store.state);
  }

  final monday = toMonday(UtcDateTime.now());
  for (final week in [monday, monday.add(const Duration(days: 7))]) {
    final data = await send(
      "api/calendar/student",
      {"startDate": DateFormat("yyyy-MM-dd").format(week)},
    );
    if (data is Map<String, dynamic>) {
      await actions.calendarActions.loaded(data);
      await notifySubstitutions(store.state, data.keys.map(UtcDateTime.parse));
    }
  }

  // Save the updated state, so the open app does not report the same news
  // again (only if the user lets the app save data).
  if (savedFullState) {
    await storage.write(
      key: stateKey,
      value: json.encode(serializers.serialize(store.state)),
    );
  }
}
