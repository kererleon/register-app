// Copyright (C) 2021 Michael Debertol
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

import 'package:built_collection/built_collection.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/calendar_week_container.dart';
import 'package:dr/data.dart';
import 'package:dr/lesson_time.dart';
import 'package:dr/main.dart';
import 'package:dr/teacher_photos.dart';
import 'package:dr/ui/holo.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/subject_icons.dart';
import 'package:dr/ui/theme.dart';
import 'package:dr/utc_date_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

const holidayIconSize = 65.0;

class CalendarWeek extends StatelessWidget {
  final CalendarWeekViewModel vm;

  const CalendarWeek({
    super.key,
    required this.vm,
  });

  @override
  Widget build(BuildContext context) {
    final latestHour =
        vm.days.fold<int>(0, (a, b) => a < b.toHour ? b.toHour : a);
    return vm.days.isEmpty
        ? vm.noInternet
            ? const NoInternet()
            : const Center(
                child: CircularProgressIndicator(),
              )
        : LastFetchedOverlay(
            lastFetched: vm.days.first.lastFetched,
            noInternet: vm.noInternet,
            child: Column(
              children: <Widget>[
                Expanded(
                  child: Row(
                    children: vm.days
                        .map(
                          (d) => Expanded(
                            child: CalendarDayWidget(
                              calendarDay: d,
                              max: latestHour,
                              subjectNicks: vm.subjectNicks,
                              isSelected: vm.selection?.date == d.date,
                              selectedHour: vm.selection?.date == d.date
                                  ? vm.selection?.hour
                                  : null,
                              colorBackground: vm.colorBackground,
                              subjectThemes: vm.subjectThemes,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ),
          );
  }
}

class _HoursChunk extends StatelessWidget {
  final BuiltMap<String, String> subjectNicks;
  final List<CalendarHour> hours;
  final CalendarDay day;
  final int? selectedHour;
  final bool isSelected;
  final bool colorBackground;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  const _HoursChunk({
    required this.subjectNicks,
    required this.hours,
    required this.day,
    required this.selectedHour,
    required this.isSelected,
    required this.colorBackground,
    required this.subjectThemes,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 3),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: dark ? 0.7 : 0.88),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.8)
              : scheme.outlineVariant,
        ),
        boxShadow: [
          if (isSelected)
            BoxShadow(
              color: AppColors.violet.withValues(alpha: 0.35),
              blurRadius: 18,
              spreadRadius: -6,
            ),
        ],
      ),
      child: Column(
        children: List.generate(
          hours.length * 2 - 1,
          (n) {
            if (n.isOdd) return const Divider(height: 0);
            final hour = hours[n ~/ 2];
            final subjectColor = subjectThemes[hour.subject] != null
                ? Color(subjectThemes[hour.subject]!.color)
                : scheme.primary;
            return HourWidget(
              hour: hour,
              subjectNicks: subjectNicks,
              day: day,
              isSelected: selectedHour == hour.fromHour,
              accent: subjectColor,
              backgroundColor: colorBackground
                  ? subjectColor.withValues(alpha: 0.22)
                  : Colors.transparent,
              selectedBackgroundColor: colorBackground
                  ? subjectColor.withValues(alpha: 0.45)
                  : AppColors.violet.withValues(alpha: 0.22),
            );
          },
        ),
      ),
    );
  }
}

class CalendarDayWidget extends StatelessWidget {
  final int max;
  final CalendarDay calendarDay;
  final BuiltMap<String, String> subjectNicks;
  final bool isSelected;
  final int? selectedHour;
  final bool colorBackground;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  const CalendarDayWidget({
    super.key,
    required this.max,
    required this.calendarDay,
    required this.subjectNicks,
    required this.isSelected,
    required this.selectedHour,
    required this.colorBackground,
    required this.subjectThemes,
  });
  @override
  Widget build(BuildContext context) {
    final chunks = <List<CalendarHour>>[];
    for (final hour in calendarDay.hours) {
      if (chunks.isEmpty) {
        chunks.add([hour]);
      } else {
        final last = chunks.last;
        if (last.last.toHour + 1 < hour.fromHour) {
          chunks.add([hour]);
        } else {
          last.add(hour);
        }
      }
    }
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = calendarDay.date.year == now.year &&
        calendarDay.date.month == now.month &&
        calendarDay.date.day == now.day;
    return Column(
      children: <Widget>[
        Container(
          margin: const EdgeInsets.fromLTRB(3, 6, 3, 4),
          padding: const EdgeInsets.symmetric(vertical: 5),
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: isToday ? AppColors.accentGradient : null,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              if (isToday)
                BoxShadow(
                  color: AppColors.violet.withValues(alpha: 0.45),
                  blurRadius: 14,
                  spreadRadius: -4,
                ),
            ],
          ),
          child: Column(
            children: [
              HudLabel(
                DateFormat("E", "de").format(calendarDay.date),
                color: isToday ? Colors.white : null,
              ),
              Text(
                DateFormat("dd.MM", "de").format(calendarDay.date),
                style: mono(
                  theme.textTheme.bodySmall?.copyWith(
                    color: isToday ? Colors.white : theme.colorScheme.onSurface,
                  ),
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (chunks.isNotEmpty) ...[
          for (var i = 0; i < chunks.length; i++) ...[
            Expanded(
              flex: chunks[i].first.fromHour -
                  (i == 0 ? 0 : chunks[i - 1].last.toHour) -
                  1,
              child: Container(),
            ),
            Expanded(
              flex: chunks[i].last.toHour - chunks[i].first.fromHour + 1,
              child: _HoursChunk(
                hours: chunks[i],
                subjectNicks: subjectNicks,
                day: calendarDay,
                selectedHour: selectedHour,
                isSelected: isSelected,
                colorBackground: colorBackground,
                subjectThemes: subjectThemes,
              ),
            )
          ],
          Expanded(
            flex: max - calendarDay.toHour,
            child: Container(),
          )
        ] else
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 32, bottom: 4),
                  child: SizedBox(
                    height: 75,
                    width: 75,
                    child: findHolidayIconForSeason(
                      calendarDay.date,
                      Theme.of(context).iconTheme.color!,
                      holidayIconSize,
                    ),
                  ),
                ),
                Text(
                  "Frei",
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class HourWidget extends StatelessWidget {
  final CalendarHour hour;
  final CalendarDay day;
  final BuiltMap<String, String> subjectNicks;
  final bool isSelected;
  final Color backgroundColor;
  final Color selectedBackgroundColor;
  final Color accent;

  const HourWidget({
    required this.accent,
    super.key,
    required this.hour,
    required this.subjectNicks,
    required this.day,
    required this.isSelected,
    required this.backgroundColor,
    required this.selectedBackgroundColor,
  });
  @override
  Widget build(BuildContext context) {
    return Flexible(
      flex: hour.length,
      child: ValueListenableBuilder(
        valueListenable: minuteTicker,
        builder: (context, _, __) => _buildTile(context, isLessonNow(hour)),
      ),
    );
  }

  Widget _buildTile(BuildContext context, bool isNow) {
    return ClipRect(
      child: _TeacherPhotoBackground(
        hour: hour,
        accent: accent,
        child: _tileContent(context, isNow),
      ),
    );
  }

  Widget _tileContent(BuildContext context, bool isNow) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () {
          actions.calendarActions.select(
            CalendarSelection((b) => b
              ..date = day.date
              ..hour = hour.fromHour),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: hour.warning
                    ? AppColors.danger
                    : isNow
                        ? AppColors.cyan
                        : accent,
                width: hour.warning || isNow ? 4 : 3,
              ),
            ),
            color: isSelected
                ? selectedBackgroundColor
                : isNow
                    ? AppColors.cyan.withValues(alpha: 0.2)
                    : backgroundColor,
          ),
          child: Center(
            // Short lessons have little room: shrink the labels instead
            // of letting them overflow.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isNow) HudLabel("Jetzt", color: AppColors.cyan),
                    Text(
                      subjectNicks[hour.subject.toLowerCase()] ?? hour.subject,
                      maxLines: 1,
                      softWrap: false,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (hour.teachers.isNotEmpty)
                      const SizedBox(
                        height: 5,
                      ),
                    for (final teacher in hour.teachers)
                      Text(
                        teacher.lastName,
                        maxLines: 1,
                        softWrap: false,
                        style: mono(
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                    if (hour.rooms.isNotEmpty)
                      const SizedBox(
                        height: 5,
                      ),
                    for (final room in hour.rooms)
                      Text(
                        room,
                        maxLines: 1,
                        softWrap: false,
                        style: mono(
                          Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _dateIsNear(UtcDateTime date1, UtcDateTime date2) {
  return date1.difference(date2).inDays.abs() <= 3;
}

Widget findHolidayIconForSeason(UtcDateTime date, Color color, double size) {
  // Weekends
  if (date.weekday >= 6) {
    return Icon(
      Icons.weekend,
      color: color,
      size: size,
    );
  }
  final month = date.month;
  final day = date.day;
  // Summer
  if (month >= 6 && month <= 9) {
    return Icon(
      Icons.beach_access,
      size: size,
      color: color,
    );
  }
  // Christmas
  if (month == 12 && day >= 22 || month == 1 && day <= 10) {
    return Icon(
      Icons.ac_unit_rounded,
      size: size,
      color: color,
    );
  }
  // Halloween
  if (month == 10 && day >= 24 || month == 11 && day <= 8) {
    return SvgPicture.asset(
      "assets/halloween.svg",
      color: color,
      height: size,
      width: size,
    );
  }
  // Easter
  final easter = calculateEaster(date.year);
  if (_dateIsNear(date, easter)) {
    return SvgPicture.asset(
      "assets/easter.svg",
      color: color,
      height: size,
      width: size,
    );
  }
  // Carnival
  final carnival = easter.subtract(const Duration(days: 47));
  if (_dateIsNear(date, carnival)) {
    return SvgPicture.asset(
      "assets/carnival.svg",
      color: color,
      height: size,
      width: size,
    );
  }

  // Default
  return Icon(
    Icons.celebration,
    size: size,
    color: color,
  );
}

/// Calculate the date of easter
// https://en.wikipedia.org/wiki/Date_of_Easter#Meeus.27s_Julian_algorithm
UtcDateTime calculateEaster(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final g = (8 * b + 13) ~/ 25;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 19 * l) ~/ 433;
  final n = (h + l - 7 * m + 90) ~/ 25;
  final p = (h + l - 7 * m + 33 * n + 19) % 32;
  return UtcDateTime(year, n, p);
}

/// The background of a calendar tile: icons that fit the subject, or in the
/// brainrot style the teacher's (own) picture, darkened for readability.
class _TeacherPhotoBackground extends StatelessWidget {
  final CalendarHour hour;
  final Color accent;
  final Widget child;

  const _TeacherPhotoBackground({
    required this.hour,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: teacherImageChanges,
      builder: (context, _) {
        // The holo style shows icons that fit the subject; the teacher's
        // picture is only the background in the brainrot style.
        if (!isBrainrot) {
          return Stack(
            fit: StackFit.passthrough,
            children: [
              Positioned.fill(
                child: SubjectIconPattern(
                  subject: hour.subject,
                  color: accent,
                ),
              ),
              child,
            ],
          );
        }
        final image =
            hour.teachers.isEmpty ? null : teacherImage(hour.teachers.first);
        if (image == null) return child;
        final surface = Theme.of(context).colorScheme.surface;
        return Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: Image(
                image: image,
                fit: BoxFit.cover,
                alignment: const Alignment(0, -0.5),
                errorBuilder: (_, __, ___) => const SizedBox(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      surface.withValues(alpha: 0.45),
                      surface.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}
