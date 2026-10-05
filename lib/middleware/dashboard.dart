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

part of 'middleware.dart';

final _dashboardMiddleware = MiddlewareBuilder<AppState, AppStateBuilder,
    AppActions>()
  ..add(DashboardActionsNames.load, _loadDays)
  ..add(DashboardActionsNames.switchFuture, _switchFuture)
  ..add(DashboardActionsNames.addReminder, _addReminder)
  ..add(DashboardActionsNames.deleteHomework, _deleteHomework)
  ..add(DashboardActionsNames.toggleDone, _toggleDone)
  ..add(DashboardActionsNames.openAttachment, _openAttachment)
  ..add(DashboardActionsNames.moveHomework, _moveHomework)
  ..add(DashboardActionsNames.loaded, _notifyNewEntries)
  ..add(DashboardActionsNames.resetMovedHomework, _resetMovedHomework)
  ..add(SettingsActionsNames.markNotSeenDashboardEntries, _markNotSeenEntries);

Future<void> _loadDays(MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next, Action<bool> action) async {
  if (api.state.noInternet) return;

  await next(action);
  // Keep this and next week up to date even if the calendar is never opened:
  // for the desktop widget and to notice substitutions.
  final thisWeek = toMonday(UtcDateTime.now());
  unawaited(api.actions.calendarActions.load(thisWeek));
  unawaited(
    api.actions.calendarActions.load(thisWeek.add(const Duration(days: 7))),
  );
  if (widgetSupported) {
    if (!_gradesLoadedForWidget) {
      _gradesLoadedForWidget = true;
      unawaited(api.actions.gradesActions.load(api.state.gradesState.semester));
    }
  }
  final dynamic data = await wrapper.send("api/student/dashboard/dashboard",
      args: {"viewFuture": action.payload});

  if (data is! List) {
    await api.actions.dashboardActions.notLoaded();
    return;
  }
  await api.actions.dashboardActions.loaded(
    DaysLoadedPayload(
      (b) => b
        ..data = data
        ..future = action.payload
        ..markNewOrChangedEntries =
            api.state.settingsState.dashboardMarkNewOrChangedEntries
        ..deduplicateEntries =
            api.state.settingsState.dashboardDeduplicateEntries,
    ),
  );
}

Future<void> _switchFuture(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  await next(action);
  await api.actions.dashboardActions.load(api.state.dashboardState.future);
}

Future<void> _addReminder(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<AddReminderPayload> action) async {
  await next(action);
  final dynamic result = await wrapper.send(
    "api/student/dashboard/save_reminder",
    args: {
      "date": DateFormat("yyyy-MM-dd").format(action.payload.date),
      "text": action.payload.msg,
    },
  );
  if (result == null && !wrapper.noInternet) {
    showSnackBar("Beim Speichern ist ein Fehler aufgetreten");
    return;
  }
  await api.actions.dashboardActions.homeworkAdded(
    HomeworkAddedPayload(
      (b) => b
        ..data = result
        ..date = action.payload.date,
    ),
  );
}

Future<void> _deleteHomework(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<Homework> action) async {
  final dynamic result = await wrapper.send(
    "api/student/dashboard/delete_reminder",
    args: {
      "id": action.payload.id,
    },
  );
  if (result != null && result["success"] == true) {
    await next(action);
  } else if (!wrapper.noInternet) {
    showSnackBar("Beim Speichern ist ein Fehler aufgetreten");
  }
}

Future<void> _toggleDone(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<ToggleDonePayload> action) async {
  await next(action);
  final dynamic result = await wrapper.send(
    "api/student/dashboard/toggle_reminder",
    args: {
      "id": action.payload.homeworkId,
      "type": action.payload.type,
      "value": action.payload.done,
    },
  );
  if (result != null && result["success"] == true) {
    // duplicate - protection from multiple, failing and not failing requests
    // TODO: Does this even work??
    await next(action);
  } else {
    await next(
      Action<ToggleDonePayload>(
        DashboardActionsNames.toggleDone.name,
        ToggleDonePayload(
          (b) => b
            ..homeworkId = action.payload.homeworkId
            ..type = action.payload.type
            ..done = !action.payload.done,
        ),
      ),
    );
    if (!wrapper.noInternet) {
      showSnackBar("Beim Speichern ist ein Fehler aufgetreten");
    }
  }
}

Future<void> _markNotSeenEntries(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<bool> action) async {
  if (!action.payload) {
    await api.actions.dashboardActions.markAllAsSeen();
  }
  await next(action);
}

Future<void> _openAttachment(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<GradeGroupSubmission> action) async {
  await next(action);

  if (!action.payload.fileAvailable ||
      !await canOpenFile(action.payload.uniqueName)) {
    await api.actions.dashboardActions.downloadAttachment(action.payload);

    await next(action);
    final success = await downloadFile(
      "${wrapper.baseAddress}api/gradeGroup/gradeGroupSubmissionDownloadEntry",
      action.payload.uniqueName,
      <String, dynamic>{
        "submissionId": action.payload.id,
        "parentId": action.payload.gradeGroupId,
      },
    );
    await api.actions.dashboardActions.attachmentReady(
        action.payload.rebuild((b) => b..fileAvailable = success));
    if (!success) {
      return;
    }
  }

  await openFile(action.payload.uniqueName);
}

Future<void> _moveHomework(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<MoveHomeworkPayload> action) async {
  await next(action);
  final hw = action.payload.homework;
  final key = homeworkMoveKey(hw);
  final ownReminder = isOwnReminder(hw);
  // Entries of teachers cannot be changed. Instead, a reminder on the new day
  // makes the move visible everywhere, including the website.
  final text =
      ownReminder ? hw.subtitle : _movedReminderText(hw, action.payload.from);
  final dynamic created = await wrapper.send(
    "api/student/dashboard/save_reminder",
    args: {
      "date": DateFormat("yyyy-MM-dd").format(action.payload.to),
      "text": text,
    },
  );
  final createdId = getInt(getMap(created)?["id"]);
  if (created == null || createdId == null) {
    if (!wrapper.noInternet) {
      showSnackBar("Die Aufgabe konnte nicht verschoben werden");
    }
    return;
  }
  // Remove what the new reminder replaces: the old reminder itself, or the
  // reminder of an earlier move of the same entry.
  final replacedId =
      ownReminder ? hw.id : api.state.dashboardState.movedReminderIds[key];
  if (replacedId != null) {
    await wrapper.send(
      "api/student/dashboard/delete_reminder",
      args: {"id": replacedId},
    );
  }
  if (!ownReminder) {
    await api.actions.dashboardActions.homeworkMoved(
      HomeworkMovedPayload(
        key: key,
        to: action.payload.to,
        reminderId: createdId,
      ),
    );
  }
  showSnackBar(
    "Auf ${DateFormat("EEEE, d. MMMM", "de").format(action.payload.to)} verschoben",
  );
  await api.actions.dashboardActions.load(api.state.dashboardState.future);
}

String _movedReminderText(Homework hw, UtcDateTime from) {
  final parts = [
    if (hw.label != null) hw.label!,
    hw.title,
    if (!hw.subtitle.isNullOrEmpty) hw.subtitle,
  ];
  return "Verschoben: ${parts.join(" – ")} "
      "(eigentlich ${DateFormat("EE dd.MM.", "de").format(from)})";
}

Future<void> _resetMovedHomework(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<Homework> action) async {
  final reminderId = api
      .state.dashboardState.movedReminderIds[homeworkMoveKey(action.payload)];
  if (reminderId != null) {
    final dynamic result = await wrapper.send(
      "api/student/dashboard/delete_reminder",
      args: {"id": reminderId},
    );
    if (result == null && !wrapper.noInternet) {
      showSnackBar("Die Erinnerung konnte nicht gelöscht werden");
      return;
    }
  }
  await next(action);
  showSnackBar("Verschiebung zurückgesetzt");
  await api.actions.dashboardActions.load(api.state.dashboardState.future);
}

Future<void> _notifyNewEntries(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<DaysLoadedPayload> action) async {
  await next(action);
  await notifyNewEntries(api.state);
  await exportWeekForWidget(api.state);
}

/// The grades widget needs the grades once per app start.
var _gradesLoadedForWidget = false;
