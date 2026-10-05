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

import 'package:dr/actions/absences_actions.dart';
import 'package:dr/app_state.dart';
import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence.dart';
import 'package:dr/ui/absence_forms.dart';
import 'package:dr/ui/absence_meter.dart';
import 'package:dr/ui/last_fetched_overlay.dart';
import 'package:dr/ui/no_internet.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:responsive_scaffold/responsive_scaffold.dart';

class AbsencesPage extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final String? defaultSignature;
  final ValueChanged<AddFutureAbsencePayload> onAddFuture;
  final ValueChanged<int> onRemoveFuture;

  const AbsencesPage({
    super.key,
    required this.state,
    required this.noInternet,
    required this.defaultSignature,
    required this.onAddFuture,
    required this.onRemoveFuture,
  });

  bool get _canEdit =>
      !noInternet && state.statistic != null && state.canEdit != false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ResponsiveAppBar(
        title: Text("Absenzen"),
      ),
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () async {
                final payload = await showAddFutureAbsenceSheet(
                  context,
                  defaultSignature: defaultSignature,
                );
                if (payload != null) onAddFuture(payload);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text("Abwesenheit melden"),
            )
          : null,
      body: LastFetchedOverlay(
        lastFetched: state.lastFetched,
        noInternet: noInternet,
        child: AbsencesBody(
          state: state,
          noInternet: noInternet,
          onRemoveFuture: _canEdit ? onRemoveFuture : null,
        ),
      ),
    );
  }
}

class AbsencesBody extends StatelessWidget {
  final AbsencesState state;
  final bool noInternet;
  final ValueChanged<int>? onRemoveFuture;

  const AbsencesBody({
    super.key,
    required this.state,
    required this.noInternet,
    this.onRemoveFuture,
  });

  @override
  Widget build(BuildContext context) {
    if (state.statistic == null) {
      return noInternet
          ? const NoInternet()
          : const Center(child: CircularProgressIndicator());
    }
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: <Widget>[
        AbsencesStatisticWidget(stat: state.statistic!),
        if (state.absences.isEmpty && state.futureAbsences.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
            child: Column(
              children: [
                Icon(
                  Icons.event_available_rounded,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  br(
                      "Noch keine Absenzen",
                      "Noch keine Absenzen, absolute Unit 💪",
                      "Noch keine Absenzen – Mazal tov achi! 🎉"),
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  "Wenn du weißt, dass du fehlen wirst, melde es mit „Abwesenheit melden“ im Voraus.",
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        if (state.futureAbsences.isNotEmpty)
          const SectionLabel("Im Voraus gemeldet"),
        for (var i = 0; i < state.futureAbsences.length; i++)
          FutureAbsenceWidget(
            absence: state.futureAbsences[i],
            onRemove: onRemoveFuture == null ? null : () => onRemoveFuture!(i),
          ),
        if (state.absences.isNotEmpty) const SectionLabel("Absenzen"),
        ...List.generate(
          state.absences.length,
          (n) => AbsenceGroupContainer(
            group: state.absences.length - n - 1,
          ),
        ),
      ],
    );
  }
}

class AbsencesStatisticWidget extends StatelessWidget {
  final AbsenceStatistic stat;

  const AbsencesStatisticWidget({super.key, required this.stat});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final tiles = <(String, int?, Color?)>[
      ("Absenzen", stat.counter, null),
      ("Entschuldigt", stat.justified, AppColors.success),
      ("Nicht entsch.", stat.notJustified, AppColors.danger),
      ("Verspätungen", stat.delayed, AppColors.warning),
    ];
    return GlowCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("ABWESENHEIT", style: muted?.copyWith(letterSpacing: 1.4)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ShaderMask(
                shaderCallback: (rect) =>
                    AppColors.accentGradient.createShader(rect),
                child: Text(
                  stat.percentage != null ? "${stat.percentage} %" : "–",
                  style: theme.textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text("der Unterrichtszeit", style: muted),
              ),
            ],
          ),
          if (parseAbsencePercentage(stat.percentage) != null) ...[
            const SizedBox(height: 14),
            AbsenceMeter(percent: parseAbsencePercentage(stat.percentage)!),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              for (final (label, value, color) in tiles)
                if (value != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.toString(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: value > 0 ? color : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(label, style: muted),
                    ],
                  ),
            ],
          ),
          if (stat.counterForSchool != null && stat.counterForSchool! > 0) ...[
            const SizedBox(height: 12),
            Text(
              "${stat.counterForSchool} davon im Auftrag der Schule",
              style: muted,
            ),
          ],
        ],
      ),
    );
  }
}
