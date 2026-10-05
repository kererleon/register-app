import 'dart:convert';

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/data.dart';
import 'package:dr/serializers.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

String _encode(Object state) => json.encode(serializers.serialize(state));

void main() {
  test('the app state can be turned into JSON in another isolate', () async {
    final state = AppState(
      (b) => b
        ..dashboardState.allDays = ListBuilder([
          Day(
            (d) => d
              ..date = UtcDateTime(2026, 10, 5)
              ..homework = ListBuilder([
                Homework(
                  (h) => h
                    ..id = 1
                    ..title = "Hausaufgabe"
                    ..subtitle = "S. 45"
                    ..type = HomeworkType.lessonHomework
                    ..firstSeen = UtcDateTime(2026, 10, 1)
                    ..deleted = false
                    ..isNew = false
                    ..isChanged = false
                    ..warning = false
                    ..checkable = true
                    ..checked = false
                    ..deleteable = false,
                ),
              ]),
          ),
        ]),
    );
    final inIsolate = await compute(_encode, state);
    expect(inIsolate, _encode(state));
    expect(inIsolate, contains("S. 45"));
  });
}
