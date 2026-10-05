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

import 'package:dr/actions/app_actions.dart';
import 'package:dr/actions/dashboard_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/ui/today_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_built_redux/flutter_built_redux.dart';
import 'package:intl/intl.dart';

class TodayContainer extends StatelessWidget {
  const TodayContainer({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreConnection<AppState, AppActions, AppState>(
      connect: (state) => state,
      builder: (context, state, actions) {
        return TodayPage(
          data: TodayData.from(state),
          noInternet: state.noInternet,
          onShowGrades: actions.routingActions.showGrades.call,
          onShowAbsences: actions.routingActions.showAbsences.call,
          onShowCalendar: actions.routingActions.showCalendar.call,
          onCreateStudyPlan: (test, days) async {
            final what = [
              if (test.homework.label != null) test.homework.label!,
              test.homework.title,
            ].join(" – ");
            final testDay = DateFormat("EE dd.MM.", "de").format(test.date);
            for (var i = 0; i < days.length; i++) {
              await actions.dashboardActions.addReminder(
                AddReminderPayload(
                  (b) => b
                    ..date = days[i]
                    ..msg = "Lernen ${i + 1}/${days.length}: $what "
                        "(Test am $testDay)",
                ),
              );
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Lernplan mit ${days.length} Erinnerungen eingetragen",
                  ),
                ),
              );
            }
          },
        );
      },
    );
  }
}
