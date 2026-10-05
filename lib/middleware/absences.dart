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

final _absencesMiddleware =
    MiddlewareBuilder<AppState, AppStateBuilder, AppActions>()
      ..add(AbsencesActionsNames.load, _loadAbsences)
      ..add(AbsencesActionsNames.addFuture, _addFutureAbsence)
      ..add(AbsencesActionsNames.removeFuture, _removeFutureAbsence)
      ..add(AbsencesActionsNames.justify, _justifyAbsence);

Future<void> _loadAbsences(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<void> action) async {
  if (api.state.noInternet) return;
  await next(action);
  final dynamic response = await wrapper.send("api/student/dashboard/absences");
  if (response != null) {
    await api.actions.absencesActions.loaded(response);
  }
}

const _absencesUrl = "api/student/dashboard/absences";

Future<void> _addFutureAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<AddFutureAbsencePayload> action) async {
  await next(action);
  final p = action.payload;
  final dynamic result = await wrapper.send(
    "api/student/dashboard/absence_future",
    args: {
      "futureAbsence": {
        "startDate": DateFormat("yyyy-MM-dd").format(p.startDate),
        "endDate": DateFormat("yyyy-MM-dd").format(p.endDate),
        "startTime": p.startHour,
        "endTime": p.endHour,
        "reason": p.reason,
        "reason_signature": p.signature,
      },
    },
  );
  if (result == null && !wrapper.noInternet) {
    showSnackBar("Die Abwesenheit konnte nicht eingetragen werden");
    return;
  }
  showSnackBar("Abwesenheit eingetragen");
  await api.actions.absencesActions.load();
}

// The server expects the complete object it sent us, so we fetch the raw
// data again instead of rebuilding it from our parsed state.
Future<Map?> _rawAbsenceEntry(String list, int index) async {
  final raw = getMap(await wrapper.send(_absencesUrl));
  final entries = raw?[list];
  if (entries is! List || index < 0 || index >= entries.length) return null;
  return getMap(entries[index]);
}

Future<void> _removeFutureAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<int> action) async {
  await next(action);
  final entry = await _rawAbsenceEntry("futureAbsences", action.payload);
  final dynamic result = entry == null
      ? null
      : await wrapper.send(
          "api/student/dashboard/remove_absence_future",
          args: {"futureAbsence": entry},
        );
  if (result == null && !wrapper.noInternet) {
    showSnackBar("Die Abwesenheit konnte nicht gelöscht werden");
    return;
  }
  showSnackBar("Abwesenheit gelöscht");
  await api.actions.absencesActions.load();
}

Future<void> _justifyAbsence(
    MiddlewareApi<AppState, AppStateBuilder, AppActions> api,
    ActionHandler next,
    Action<JustifyAbsencePayload> action) async {
  await next(action);
  final p = action.payload;
  final entry = await _rawAbsenceEntry("absences", p.group);
  final dynamic result = entry == null
      ? null
      : await wrapper.send(
          "api/student/dashboard/absence_reason",
          args: {
            "absenceGroup": {
              ...entry,
              "reason": p.reason,
              "reason_signature": p.signature,
              "reason_timestamp": DateTime.now().toUtc().toIso8601String(),
              "selfdecl_id": 0,
              "selfdecl_input": "",
            },
          },
        );
  if (result == null && !wrapper.noInternet) {
    showSnackBar("Die Absenz konnte nicht entschuldigt werden");
    return;
  }
  showSnackBar("Absenz entschuldigt");
  await api.actions.absencesActions.load();
}
