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

import 'dart:async';

import 'package:dr/data.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/foundation.dart';

/// The register stores wall-clock times as UTC values; this is "now" in the
/// same form.
UtcDateTime wallClockNow() {
  final n = DateTime.now();
  return UtcDateTime(n.year, n.month, n.day, n.hour, n.minute, n.second);
}

UtcDateTime wallClockToday() {
  final n = DateTime.now();
  return UtcDateTime(n.year, n.month, n.day);
}

bool isLessonNow(CalendarHour hour, [UtcDateTime? at]) {
  final now = at ?? wallClockNow();
  return hour.timeSpans.any((s) => !now.isBefore(s.from) && now.isBefore(s.to));
}

/// Changes every minute, for widgets that show the current lesson.
final ValueNotifier<DateTime> minuteTicker = _startTicker();

ValueNotifier<DateTime> _startTicker() {
  final notifier = ValueNotifier(DateTime.now());
  Timer.periodic(const Duration(seconds: 30), (_) {
    final n = DateTime.now();
    if (n.minute != notifier.value.minute) notifier.value = n;
  });
  return notifier;
}
