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

import 'package:built_redux/built_redux.dart';

part 'absences_actions.g.dart';

abstract class AbsencesActions extends ReduxActions {
  factory AbsencesActions() => _$AbsencesActions();
  AbsencesActions._();

  abstract final VoidActionDispatcher load;
  abstract final ActionDispatcher<dynamic> loaded;
  abstract final ActionDispatcher<AddFutureAbsencePayload> addFuture;
  abstract final ActionDispatcher<int> removeFuture;
  abstract final ActionDispatcher<JustifyAbsencePayload> justify;
}

class AddFutureAbsencePayload {
  final DateTime startDate;
  final DateTime endDate;
  final int startHour;
  final int endHour;
  final String reason;
  final String signature;

  const AddFutureAbsencePayload({
    required this.startDate,
    required this.endDate,
    required this.startHour,
    required this.endHour,
    required this.reason,
    required this.signature,
  });
}

class JustifyAbsencePayload {
  /// Index into [AbsencesState.absences], which keeps the server's order.
  final int group;
  final String reason;
  final String signature;

  const JustifyAbsencePayload({
    required this.group,
    required this.reason,
    required this.signature,
  });
}
