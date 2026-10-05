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

import 'dart:async';

import 'package:badges/badges.dart' as badge;
import 'package:dr/desktop_notifications.dart' show refreshInterval;
import 'package:built_collection/built_collection.dart';
import 'package:deleteable_tile/deleteable_tile.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/days_container.dart';
import 'package:dr/container/homework_filter_container.dart';
import 'package:dr/container/notification_icon_container.dart';
import 'package:dr/container/sidebar_container.dart';
import 'package:dr/data.dart';
import 'package:dr/main.dart';
import 'package:dr/middleware/middleware.dart';
import 'package:dr/ui/animated_linear_progress_indicator.dart';
import 'package:dr/ui/dialog.dart';
import 'package:dr/ui/holo.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/theme.dart';
import 'package:dr/utc_date_time.dart';
import 'package:dr/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tuple/tuple.dart';

typedef AddReminderCallback = void Function(Day day, String reminder);
typedef RemoveReminderCallback = void Function(Homework hw, Day day);
typedef ToggleDoneCallback = void Function(Homework hw, bool done);
typedef MarkAsNotNewOrChangedCallback = void Function(Homework hw);
typedef MarkDeletedHomeworkAsSeenCallback = void Function(Day day);

class DaysWidget extends StatefulWidget {
  final DaysViewModel vm;

  final MarkAsNotNewOrChangedCallback markAsSeenCallback;
  final MarkDeletedHomeworkAsSeenCallback markDeletedHomeworkAsSeenCallback;
  final VoidCallback markAllAsSeenCallback;
  final AddReminderCallback addReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final VoidCallback onSwitchFuture;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final VoidCallback refresh;
  final VoidCallback refreshNoInternet;
  final AttachmentCallback onOpenAttachment;
  final MoveHomeworkCallback moveHomeworkCallback;
  final ResetMovedHomeworkCallback resetMovedHomeworkCallback;

  const DaysWidget({
    super.key,
    required this.vm,
    required this.markAsSeenCallback,
    required this.markDeletedHomeworkAsSeenCallback,
    required this.addReminderCallback,
    required this.removeReminderCallback,
    required this.markAllAsSeenCallback,
    required this.onSwitchFuture,
    required this.toggleDoneCallback,
    required this.setDoNotAskWhenDeleteCallback,
    required this.refresh,
    required this.refreshNoInternet,
    required this.onOpenAttachment,
    required this.moveHomeworkCallback,
    required this.resetMovedHomeworkCallback,
  });
  @override
  _DaysWidgetState createState() => _DaysWidgetState();
}

class _DaysWidgetState extends State<DaysWidget> {
  final controller = AutoScrollController(suggestedRowHeight: 100);

  bool _afterFirstFrame = false;

  final List<int> _targets = [];
  final List<int> _focused = [];
  final Map<int, int> _dayStartIndices = {};
  final Map<int, Homework> _homeworkIndexes = {};
  final Map<int, Day> _dayIndexes = {};

  final ValueNotifier<bool> _showScrollUp = ValueNotifier(false);

  void _updateShowScrollUp() {
    if (controller.hasClients) {
      _showScrollUp.value = controller.offset > 250;
    }
  }

  double? _distanceToItem(int item) {
    final ctx = controller.tagMap[item]?.context;
    if (ctx != null) {
      final renderBox = ctx.findRenderObject()! as RenderBox;
      final RenderAbstractViewport viewport =
          RenderAbstractViewport.of(renderBox);
      var offsetToReveal = viewport.getOffsetToReveal(renderBox, 0.5).offset;
      if (offsetToReveal < 0) offsetToReveal = 0;
      final currentOffset = controller.offset;
      return (offsetToReveal - currentOffset).abs();
    }
    return null;
  }

  void _updateReachedHomeworks() {
    for (final target in _targets.toList()) {
      final distance = _distanceToItem(target);
      if (distance != null && distance < 50) {
        _focused.add(target);
        _targets.remove(target);
        controller.highlight(
          target,
          highlightDuration: const Duration(milliseconds: 500),
          cancelExistHighlights: false,
        );
        if (_targets.isEmpty) setState(() {});
      }
    }
    for (final focusedItem in _focused.toList()) {
      final distance = _distanceToItem(focusedItem);
      if (distance == null || distance > 50) {
        _focused.remove(focusedItem);
        if (_dayIndexes.containsKey(focusedItem)) {
          widget.markDeletedHomeworkAsSeenCallback(_dayIndexes[focusedItem]!);
        } else if (_homeworkIndexes.containsKey(focusedItem)) {
          widget.markAsSeenCallback(_homeworkIndexes[focusedItem]!);
        } else {
          assert(
            false,
            "A target index should either be a new/changed homework or a day (deleted homework)",
          );
        }
      }
    }
  }

  void update() {
    _updateShowScrollUp();
    _updateReachedHomeworks();
  }

  void updateValues() {
    _targets.clear();
    _focused.clear();
    var index = 0;
    var dayIndex = 0;
    for (final day in widget.vm.days) {
      _dayStartIndices[dayIndex] = index;
      if (day.deletedHomework.any((h) => h.isChanged)) {
        _targets.add(index);
        _dayIndexes[index] = day;
      }
      index++;
      for (final hw in day.homework) {
        if (hw.isNew || hw.isChanged) {
          _targets.add(index);
        }
        _homeworkIndexes[index] = hw;
        index++;
      }
      dayIndex++;
    }
  }

  Timer? _autoRefresh;

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    // Reload regularly so that new entries show up (and are announced)
    // while the app is open.
    _autoRefresh = Timer.periodic(refreshInterval, (_) {
      if (!widget.vm.noInternet && !widget.vm.loading) widget.refresh();
    });
    updateValues();
    controller.addListener(() {
      update();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      update();
      _afterFirstFrame = true;
      setState(() {});
    });
    super.initState();
  }

  @override
  void didUpdateWidget(DaysWidget oldWidget) {
    updateValues();
    update();

    super.didUpdateWidget(oldWidget);
  }

  Widget getItem(
    int n, {
    required bool isLast,
    required bool showLastFetched,
  }) {
    if (n == 0) {
      return DashboardHeader(
        future: widget.vm.future,
        onSwitchFuture: widget.onSwitchFuture,
      );
    }
    if (isLast) {
      return const SizedBox(
        height: 160,
      );
    }
    if (n.isEven) {
      return const SizedBox(height: 6);
    }
    final itemIndex = (n - 1) ~/ 2;
    return DayWidget(
      day: widget.vm.days[itemIndex],
      vm: widget.vm,
      controller: controller,
      index: _dayStartIndices[itemIndex]!,
      addReminderCallback: widget.addReminderCallback,
      removeReminderCallback: widget.removeReminderCallback,
      toggleDoneCallback: widget.toggleDoneCallback,
      setDoNotAskWhenDeleteCallback: widget.setDoNotAskWhenDeleteCallback,
      onOpenAttachment: widget.onOpenAttachment,
      moveHomeworkCallback: widget.moveHomeworkCallback,
      resetMovedHomeworkCallback: widget.resetMovedHomeworkCallback,
      colorBorders: widget.vm.colorBorders,
      colorTestsInRed: widget.vm.colorTestsInRed,
      subjectThemes: widget.vm.subjectThemes,
      showLastFetched: showLastFetched,
    );
  }

  @override
  Widget build(BuildContext context) {
    final noInternet = widget.vm.noInternet;
    final noEntries = widget.vm.days.isEmpty;
    Widget body;
    if (noEntries) {
      Widget fullScreenBody;
      if (widget.vm.loading) {
        fullScreenBody = const CircularProgressIndicator();
      } else if (noInternet) {
        fullScreenBody = const NoInternet();
      } else {
        fullScreenBody = Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            "Keine Einträge vorhanden",
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
        );
      }
      body = Column(
        children: [
          DashboardHeader(
            future: widget.vm.future,
            onSwitchFuture: widget.onSwitchFuture,
          ),
          Expanded(
            child: Center(child: fullScreenBody),
          ),
        ],
      );
    } else {
      UtcDateTime? lastFetched;
      // If not all days were fetched at the same time we want to show a string
      // for each day individually.
      bool daysShouldShowLastFetched = false;
      if (widget.vm.days.first.lastRequested ==
          widget.vm.days.last.lastRequested) {
        lastFetched = widget.vm.days.first.lastRequested;
      } else {
        daysShouldShowLastFetched = true;
      }
      body = LastFetchedOverlay(
        noInternet: widget.vm.noInternet,
        lastFetched: lastFetched,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          controller: controller,
          // Times two for the divider, minus one because there's no divider after the last item.
          // The first item is the DashboardHeader, the last one a SizedBox (a spacer).
          itemCount: (widget.vm.days.length * 2 - 1) + 2,
          itemBuilder: (context, n) {
            return getItem(
              n,
              isLast: n == (widget.vm.days.length * 2 - 1) + 1,
              showLastFetched:
                  widget.vm.noInternet && daysShouldShowLastFetched,
            );
          },
        ),
      );
      if (!noInternet && !widget.vm.loading) {
        body = RefreshIndicator(
          onRefresh: () async => widget.refresh(),
          child: body,
        );
      }
      body = Stack(
        children: [
          body,
          AnimatedLinearProgressIndicator(show: widget.vm.loading),
        ],
      );
    }
    return ResponsiveScaffold<Pages>(
      key: scaffoldKey,
      homeBody: body,
      onRouteChanged: (route) {
        if (route == Pages.homework) {
          widget.refresh();
        }
      },
      homeFloatingActionButton: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          ValueListenableBuilder(
            valueListenable: _showScrollUp,
            builder: (context, bool value, child) {
              if (value) {
                return child!;
              } else {
                return const SizedBox();
              }
            },
            child: FloatingActionButton(
              backgroundColor: Theme.of(context).colorScheme.surface,
              heroTag: null,
              onPressed: () {
                controller.animateTo(
                  0,
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.decelerate,
                );
              },
              mini: true,
              child: Icon(
                Icons.arrow_drop_up,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
              ),
            ),
          ),
          if (_targets.isNotEmpty || _focused.isNotEmpty)
            FloatingActionButton(
              backgroundColor: AppColors.danger,
              heroTag: null,
              onPressed: () {
                widget.markAllAsSeenCallback();
              },
              mini: true,
              child: const Icon(Icons.close),
            ),
          if (_targets.isNotEmpty && _afterFirstFrame)
            FloatingActionButton.extended(
              backgroundColor: AppColors.danger,
              icon: const Icon(Icons.arrow_drop_down),
              label: const Text("Neue Einträge"),
              onPressed: () async {
                await controller.scrollToIndex(
                  _targets.first,
                  preferPosition: AutoScrollPosition.middle,
                );
              },
            ),
        ],
      ),
      homeAppBar: ResponsiveAppBar(
        title: Text(br("Register", "Register 🧠🔥")),
        actions: <Widget>[
          if (widget.vm.noInternet)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.warning,
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: widget.refreshNoInternet,
              child: const Row(
                children: [
                  Text("Keine Verbindung"),
                  SizedBox(width: 8),
                  Icon(Icons.refresh),
                ],
              ),
            ),
          if (widget.vm.showNotifications) NotificationIconContainer(),
        ],
      ),
      drawerBuilder: (widgetSelected, goHome, currentSelected, tabletMode) {
        // _widgetSelected is not passed down because routing is done by
        // accessing the ResponsiveScaffoldState via the GlobalKey and calling
        // selectContentWidget on it.
        return SidebarContainer(
          currentSelected: currentSelected,
          goHome: goHome,
          tabletMode: tabletMode,
        );
      },
      homeId: Pages.homework,
      navKey: nestedNavKey,
    );
  }
}

class DashboardHeader extends StatelessWidget {
  final VoidCallback onSwitchFuture;
  final bool future;
  const DashboardHeader({
    super.key,
    required this.future,
    required this.onSwitchFuture,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HomeworkFilterContainer(),
        Positioned(
          top: 0,
          bottom: 0,
          left: 0,
          right: 0,
          child: Row(
            children: [
              Expanded(
                child: AbsorbPointer(child: Container()),
              ),
              const SizedBox(
                width: 60,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 4),
          child: Center(
            child: HoloToggle(
              labels: [
                br("Kommend", "Kommt noch 🔜"),
                br("Vergangen", "Schon passiert 💀")
              ],
              selected: future ? 0 : 1,
              onChanged: (_) => onSwitchFuture(),
            ),
          ),
        ),
      ],
    );
  }
}

class DayWidget extends StatelessWidget {
  final DaysViewModel vm;

  final AddReminderCallback addReminderCallback;
  final RemoveReminderCallback removeReminderCallback;
  final ToggleDoneCallback toggleDoneCallback;
  final VoidCallback setDoNotAskWhenDeleteCallback;
  final AttachmentCallback onOpenAttachment;
  final MoveHomeworkCallback moveHomeworkCallback;
  final ResetMovedHomeworkCallback resetMovedHomeworkCallback;
  final bool colorBorders, colorTestsInRed;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  final Day day;

  final AutoScrollController controller;
  final int index;

  final bool showLastFetched;

  const DayWidget({
    super.key,
    required this.day,
    required this.vm,
    required this.controller,
    required this.index,
    required this.addReminderCallback,
    required this.removeReminderCallback,
    required this.toggleDoneCallback,
    required this.setDoNotAskWhenDeleteCallback,
    required this.onOpenAttachment,
    required this.moveHomeworkCallback,
    required this.resetMovedHomeworkCallback,
    required this.colorBorders,
    required this.subjectThemes,
    required this.colorTestsInRed,
    required this.showLastFetched,
  });

  Future<String?> showEnterReminderDialog(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) {
        String message = "";
        return StatefulBuilder(
          builder: (context, setState) => InfoDialog(
            title: const Text("Erinnerung"),
            content: TextField(
              autofocus: true,
              maxLines: null,
              onChanged: (msg) {
                setState(() => message = msg);
              },
              decoration: const InputDecoration(hintText: 'zB. Hausaufgabe'),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("Abbrechen"),
              ),
              ElevatedButton(
                onPressed: message.isNullOrEmpty
                    ? null
                    : () {
                        Navigator.pop(context, message);
                      },
                child: const Text(
                  "Speichern",
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    var i = index;
    final theme = Theme.of(context);
    final now = DateTime.now();
    final isToday = day.date.year == now.year &&
        day.date.month == now.month &&
        day.date.day == now.day;
    return CustomPaint(
      painter: _TimelinePainter(
        line: theme.colorScheme.outlineVariant,
        highlighted: isToday,
      ),
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 56,
            child: Row(
              children: <Widget>[
                const SizedBox(width: _timelineInset),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HudLabel(
                        isToday
                            ? "Heute · ${DateFormat("dd.MM", "de").format(day.date)}"
                            : DateFormat("EE · dd.MM.yyyy", "de")
                                .format(day.date),
                        color: isToday ? theme.colorScheme.secondary : null,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        day.displayName,
                        style: theme.textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showLastFetched)
                        Text(
                          "Zuletzt synchronisiert ${formatTimeAgo(day.lastRequested)}.",
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (day.deletedHomework.isNotEmpty)
                  AutoScrollTag(
                    controller: controller,
                    index: index,
                    key: ValueKey(index),
                    highlightColor: AppColors.violet.withValues(alpha: 0.3),
                    child: IconButton(
                      icon: badge.Badge(
                        badgeContent: Icon(
                          Icons.delete,
                          size: 15,
                          color: day.deletedHomework.any((h) => h.isChanged)
                              ? Colors.white
                              : null,
                        ),
                        badgeColor: day.deletedHomework.any((h) => h.isChanged)
                            ? AppColors.danger
                            : Theme.of(context).colorScheme.surface,
                        toAnimate: day.deletedHomework.any((h) => h.isChanged),
                        padding: EdgeInsets.zero,
                        position: badge.BadgePosition.topStart(),
                        elevation: 0,
                        child: const Icon(Icons.info_outline),
                      ),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) {
                            return InfoDialog(
                              title: const Text("Gelöschte Einträge"),
                              content: SingleChildScrollView(
                                child: Column(
                                  children: day.deletedHomework
                                      .map(
                                        (i) => ItemWidget(
                                          item: i,
                                          isDeletedView: true,
                                          colorBorder: colorBorders,
                                          subjectThemes: subjectThemes,
                                          colorTestsInRed: colorTestsInRed,
                                          askWhenDelete: vm.askWhenDelete,
                                          noInternet: vm.noInternet,
                                        ),
                                      )
                                      .toList(),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                if (vm.showAddReminder)
                  IconButton(
                    tooltip: "Erinnerung hinzufügen",
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    color: theme.colorScheme.primary,
                    onPressed: vm.noInternet
                        ? null
                        : () async {
                            final message =
                                await showEnterReminderDialog(context);
                            if (message != null) {
                              addReminderCallback(day, message);
                            }
                          },
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          for (final hw in day.homework)
            ItemWidget(
              item: hw,
              toggleDone: () => toggleDoneCallback(hw, !hw.checked),
              removeThis: () => removeReminderCallback(hw, day),
              setDoNotAskWhenDelete: setDoNotAskWhenDeleteCallback,
              askWhenDelete: vm.askWhenDelete,
              noInternet: vm.noInternet,
              controller: controller,
              index: ++i,
              onOpenAttachment: onOpenAttachment,
              movedTo: vm.movedTo[homeworkMoveKey(hw)],
              onMove: (to) => moveHomeworkCallback(hw, day.date, to),
              onResetMove: () => resetMovedHomeworkCallback(hw),
              subjectThemes: subjectThemes,
              colorBorder: colorBorders,
              colorTestsInRed: colorTestsInRed,
            ),
        ],
      ),
    );
  }
}

/// Space left of the dashboard entries for the timeline.
const _timelineInset = 44.0;

/// Draws the dashboard's timeline: a vertical line with a glowing node next
/// to each day's title.
class _TimelinePainter extends CustomPainter {
  final Color line;
  final bool highlighted;
  const _TimelinePainter({required this.line, required this.highlighted});

  @override
  void paint(Canvas canvas, Size size) {
    const x = 24.0;
    const nodeY = 28.0;
    canvas.drawLine(
      const Offset(x, 0),
      Offset(x, size.height + 6),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.violet.withValues(alpha: 0.7),
            line,
          ],
        ).createShader(Rect.fromLTWH(x, 0, 1, size.height))
        ..strokeWidth = 1.5,
    );
    final nodeColor = highlighted ? AppColors.cyan : AppColors.violet;
    canvas.drawCircle(
      const Offset(x, nodeY),
      highlighted ? 11 : 8,
      Paint()
        ..color = nodeColor.withValues(alpha: 0.22),
    );
    canvas.drawCircle(
      const Offset(x, nodeY),
      highlighted ? 6 : 4.5,
      Paint()
        ..shader = AppColors.accentGradient.createShader(
          Rect.fromCircle(center: const Offset(x, nodeY), radius: 6),
        ),
    );
    canvas.drawCircle(
      const Offset(x, nodeY),
      2,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.line != line || old.highlighted != highlighted;
}

class ItemWidget extends StatelessWidget {
  final Homework item;
  final VoidCallback? removeThis;
  final VoidCallback? toggleDone;
  final VoidCallback? setDoNotAskWhenDelete;
  final bool askWhenDelete,
      isHistory,
      isDeletedView,
      noInternet,
      isCurrent,
      colorBorder,
      colorTestsInRed;
  final AttachmentCallback? onOpenAttachment;
  final BuiltMap<String, SubjectTheme> subjectThemes;

  /// Moves the entry to another day; null where moving makes no sense.
  final ValueChanged<UtcDateTime>? onMove;
  final VoidCallback? onResetMove;

  /// The day this entry of a teacher was moved to by the user.
  final UtcDateTime? movedTo;

  final AutoScrollController? controller;
  final int? index;

  const ItemWidget({
    super.key,
    required this.item,
    this.removeThis,
    this.toggleDone,
    required this.askWhenDelete,
    this.setDoNotAskWhenDelete,
    this.isHistory = false,
    this.controller,
    this.index,
    this.isDeletedView = false,
    required this.noInternet,
    this.isCurrent = true,
    this.onOpenAttachment,
    this.onMove,
    this.onResetMove,
    this.movedTo,
    required this.colorBorder,
    required this.subjectThemes,
    required this.colorTestsInRed,
  });

  Future<Tuple2<bool, bool>> _showConfirmDelete(BuildContext context) async {
    var ask = true;
    final delete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return InfoDialog(
          content: StatefulBuilder(
            builder: (context, setState) => SwitchListTile.adaptive(
              title: const Text("Nie fragen"),
              onChanged: (bool value) {
                setState(() => ask = !value);
              },
              value: !ask,
            ),
          ),
          title: const Text("Erinnerung löschen?"),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Abbrechen"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                "Löschen",
              ),
            )
          ],
        );
      },
    );
    return Tuple2(delete ?? false, ask);
  }

  void _showHistory(BuildContext context) {
    // if we are in the deleted view, show the history for the previous item
    final historyItem = isDeletedView ? item.previousVersion : item;
    showDialog<void>(
      context: context,
      builder: (context) {
        return InfoDialog(
          title: Text(historyItem!.title),
          content: SingleChildScrollView(
            child: Column(
              children: [
                Text(formatChanged(historyItem)),
                if (historyItem.previousVersion != null)
                  ExpansionTile(
                    title: const Text("Versionen"),
                    children: <Widget>[
                      ItemWidget(
                        item: historyItem,
                        isHistory: true,
                        colorBorder: colorBorder,
                        subjectThemes: subjectThemes,
                        colorTestsInRed: colorTestsInRed,
                        askWhenDelete: askWhenDelete,
                        noInternet: noInternet,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The color of the stripe on the entry's left edge, or null for none.
  Color? _accent() {
    if (isTestEntry(item) && colorTestsInRed) {
      return AppColors.danger;
    }
    if (colorBorder &&
        item.label != null &&
        subjectThemes.containsKey(item.label!)) {
      return Color(subjectThemes[item.label]!.color);
    }
    if (item.type == HomeworkType.grade || item.checked) {
      return AppColors.success;
    }
    return null;
  }

  (IconData, Color?) _typeIcon(ColorScheme scheme) {
    if (isTestEntry(item)) return (Icons.bolt_rounded, AppColors.danger);
    switch (item.type) {
      case HomeworkType.grade:
        return (Icons.insights_rounded, AppColors.success);
      case HomeworkType.observation:
        return (Icons.visibility_outlined, scheme.secondary);
      case HomeworkType.gradeGroup:
        return (Icons.event_note_rounded, scheme.secondary);
      case HomeworkType.homework:
        return (Icons.edit_note_rounded, scheme.primary);
      default:
        return (Icons.assignment_outlined, scheme.primary);
    }
  }

  Future<void> _pickMoveDate(BuildContext context) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      helpText: isOwnReminder(item)
          ? "Erinnerung verschieben"
          : "Als Erinnerung verschieben",
      initialDate: movedTo ?? today,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
      locale: const Locale("de"),
    );
    if (picked == null) return;
    final target = UtcDateTime(picked.year, picked.month, picked.day);
    if (movedTo == target) return;
    onMove!(target);
  }

  Future<void> _onDeletePressed(
      BuildContext context, Future<void> Function() delete) async {
    if (askWhenDelete) {
      final confirmationResult = await _showConfirmDelete(context);
      final shouldDelete = confirmationResult.item1;
      final ask = confirmationResult.item2;
      if (shouldDelete == true) {
        if (!ask) {
          setDoNotAskWhenDelete!();
        }
        await delete();
        removeThis!();
      }
    } else {
      await delete();
      removeThis!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (typeIcon, typeColor) = _typeIcon(scheme);
    final showBadge = (!isHistory && (item.isNew || item.isChanged)) ||
        (isHistory && isCurrent);
    final hasHistory = (isDeletedView
            ? item.previousVersion?.previousVersion
            : item.previousVersion) !=
        null;
    Widget child = Deleteable(
      // this is a new entry or a reminder the user has just entered
      showEntryAnimation:
          now.difference(item.firstSeen) < const Duration(seconds: 1),
      builder: (context, delete) => HoloPanel(
        margin: EdgeInsets.fromLTRB(
          isHistory || isDeletedView ? 0 : _timelineInset,
          5,
          12,
          5,
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        accent: _accent(),
        highlighted:
            !isHistory && !isDeletedView && (item.isNew || item.isChanged),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (!isHistory && !isDeletedView && item.deleteable)
                  IconButton(
                    tooltip: "Löschen",
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: noInternet
                        ? null
                        : () => _onDeletePressed(context, delete),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(typeIcon, size: 16, color: typeColor),
                          const SizedBox(width: 6),
                          if (item.label != null)
                            Flexible(
                              child: HudLabel(
                                item.label!,
                                color: typeColor,
                              ),
                            ),
                          if (showBadge) ...[
                            const SizedBox(width: 8),
                            StatusPill(
                              label: isHistory && isCurrent
                                  ? "aktuell"
                                  : item.isNew
                                      ? "neu"
                                      : item.deleted
                                          ? "gelöscht"
                                          : "geändert",
                              color: item.deleted
                                  ? AppColors.danger
                                  : AppColors.cyan,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (!item.subtitle.isNullOrEmpty) ...[
                        const SizedBox(height: 2),
                        SelectableText(
                          item.subtitle,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (movedTo != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            StatusPill(
                              label: "verschoben",
                              color: AppColors.warning,
                              icon: Icons.event_repeat_rounded,
                            ),
                            HudLabel(
                              "auf ${DateFormat("EE dd.MM.", "de").format(movedTo!)}",
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: noInternet ? null : onResetMove,
                              icon: const Icon(Icons.undo_rounded, size: 16),
                              label: const Text("Zurücksetzen"),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    if (!isHistory && !isDeletedView && onMove != null)
                      IconButton(
                        tooltip: "Verschieben",
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.event_repeat_rounded, size: 20),
                        onPressed:
                            noInternet ? null : () => _pickMoveDate(context),
                      ),
                    if (!isHistory && item.label != null)
                      IconButton(
                        tooltip: "Verlauf",
                        visualDensity: VisualDensity.compact,
                        icon: hasHistory
                            ? badge.Badge(
                                badgeContent: const Icon(Icons.edit,
                                    size: 11, color: Colors.white),
                                padding: const EdgeInsets.all(2),
                                badgeColor: AppColors.violet,
                                toAnimate: false,
                                elevation: 0,
                                child:
                                    const Icon(Icons.history_rounded, size: 20),
                              )
                            : const Icon(Icons.info_outline_rounded, size: 20),
                        onPressed: () {
                          _showHistory(context);
                        },
                      ),
                    if (item.type == HomeworkType.grade)
                      Padding(
                        padding: const EdgeInsets.only(right: 8, top: 2),
                        child: NeonRing(
                          value: parseGradeLabel(item.gradeFormatted),
                          label: item.gradeFormatted!,
                          size: 52,
                        ),
                      )
                    else if (!isHistory && !isDeletedView && item.checkable)
                      NeonCheck(
                        value: item.checked,
                        onTap: noInternet ? null : () => toggleDone!(),
                      ),
                  ],
                ),
              ],
            ),
            if (isHistory || isDeletedView) ...[
              const SizedBox(height: 8),
              Text(
                formatChanged(item),
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (item.gradeGroupSubmissions?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              const HudLabel("Anhang"),
              for (final attachment in item.gradeGroupSubmissions!)
                AttachmentWidget(
                  ggs: attachment,
                  noInternet: noInternet,
                  openCallback: onOpenAttachment!,
                )
            ]
          ],
        ),
      ),
    );
    if (!isHistory && !isDeletedView) {
      child = AutoScrollTag(
        index: index!,
        key: ValueKey(index),
        controller: controller!,
        highlightColor: AppColors.violet.withValues(alpha: 0.3),
        child: child,
      );
    }
    return Column(
      key: ValueKey(item.id),
      children: <Widget>[
        child,
        if (isHistory && item.previousVersion != null)
          ItemWidget(
            isHistory: true,
            isCurrent: false,
            item: item.previousVersion!,
            colorBorder: colorBorder,
            subjectThemes: subjectThemes,
            colorTestsInRed: colorTestsInRed,
            askWhenDelete: askWhenDelete,
            noInternet: noInternet,
          ),
      ],
    );
  }
}

String formatChanged(Homework hw) {
  String date;
  if (hw.lastNotSeen == null) {
    date =
        "Vor ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)}";
  } else if (toDate(hw.firstSeen) == toDate(hw.lastNotSeen!)) {
    date = "Am ${DateFormat("EEEE, dd.MM,", "de").format(hw.firstSeen)}"
        " zwischen ${DateFormat("HH:mm", "de").format(hw.lastNotSeen!)} und ${DateFormat("HH:mm", "de").format(hw.firstSeen)}";
  } else {
    date =
        "Zwischen ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.lastNotSeen!)} "
        "und ${DateFormat("EEEE, dd.MM, HH:mm,", "de").format(hw.firstSeen)}";
  }
  if (hw.deleted) {
    return "$date gelöscht.";
  } else if (hw.previousVersion == null) {
    return "$date eingetragen.";
  } else if (hw.previousVersion!.deleted) {
    return "$date wiederhergestellt.";
  } else {
    return "$date geändert.";
  }
}

UtcDateTime toDate(UtcDateTime dateTime) {
  return UtcDateTime(dateTime.year, dateTime.month, dateTime.day);
}

class AttachmentWidget extends StatelessWidget {
  final GradeGroupSubmission ggs;
  final AttachmentCallback openCallback;
  final bool noInternet;

  const AttachmentWidget(
      {super.key,
      required this.ggs,
      required this.noInternet,
      required this.openCallback});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          const Divider(
            indent: 16,
            height: 0,
          ),
          ListTile(title: Text(ggs.originalName)),
          AnimatedLinearProgressIndicator(show: ggs.downloading),
          TextButton(
            onPressed: !ggs.fileAvailable && noInternet
                ? null
                : () {
                    openCallback(ggs);
                  },
            child: const Text("Öffnen"),
          )
        ],
      ),
    );
  }
}
