import 'dart:convert';

import 'package:built_redux/built_redux.dart';
import 'package:dr/actions/app_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/demo.dart';
import 'package:dr/desktop_notifications.dart';
import 'package:dr/reducer/reducer.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _week(UtcDateTime monday) => Map<String, dynamic>.from(
      getDemoResponse("api/calendar/student", {
        "startDate": DateFormat("yyyy-MM-dd").format(monday),
      }) as Map,
    );

Future<AppState> _load(Map<String, dynamic> week) async {
  final store = Store<AppState, AppStateBuilder, AppActions>(
    appReducerBuilder.build(),
    AppState(),
    AppActions(),
  );
  await store.actions.calendarActions.loaded(week);
  return store.state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting("de"));

  test('teacher changes, room changes and cancelled lessons are noticed',
      () async {
    SharedPreferences.setMockInitialValues({});
    // Next week, so that every lesson lies in the future.
    final monday = toMonday(UtcDateTime.now()).add(const Duration(days: 7));
    final week = _week(monday);
    final dates = week.keys.map(UtcDateTime.parse).toList();

    // First look: everything is just remembered.
    await notifySubstitutions(await _load(week), dates);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList("notifiedLessonChanges") ?? [], isEmpty);

    // Change the first lesson of the first day: other teacher.
    final changed = jsonDecode(jsonEncode(week)) as Map<String, dynamic>;
    final firstDay = changed[changed.keys.first] as Map;
    // day -> "1" -> "1" -> hour -> entry
    final hour = firstDay.values.first as Map;
    final slot = hour.values.first as Map;
    final lesson = (slot.values.first as Map)["lesson"] as Map;
    (lesson["teachers"] as List)[0] = {
      "firstName": "Vertretung",
      "lastName": "Muster",
    };
    // Remove the lessons of the second day: cancelled.
    final secondKey = changed.keys.elementAt(1);
    changed[secondKey] = <String, dynamic>{
      "1": {"1": <String, dynamic>{}},
    };

    await notifySubstitutions(await _load(changed), dates);
    final notified = prefs.getStringList("notifiedLessonChanges")!;
    expect(notified.any((n) => n.contains("@teacher@")), isTrue,
        reason: notified.join("\n"));
    expect(notified.any((n) => n.endsWith("@gone")), isTrue,
        reason: notified.join("\n"));

    // Seeing the same state again announces nothing new.
    final count = notified.length;
    await notifySubstitutions(await _load(changed), dates);
    expect(prefs.getStringList("notifiedLessonChanges")!.length, count);
  });
}
