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

import 'package:dr/container/absence_group_container.dart';
import 'package:dr/data.dart';
import 'package:dr/ui/absence_forms.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

StatusPill justifiedPill(AbsenceJustified justified) {
  switch (justified) {
    case AbsenceJustified.justified:
      return StatusPill(
        label: "Entschuldigt",
        color: AppColors.success,
        icon: Icons.check_rounded,
      );
    case AbsenceJustified.forSchool:
      return StatusPill(
        label: "Im Auftrag der Schule",
        color: AppColors.cyan,
        icon: Icons.school_outlined,
      );
    case AbsenceJustified.notJustified:
      return StatusPill(
        label: "Nicht entschuldigt",
        color: AppColors.danger,
        icon: Icons.close_rounded,
      );
    default:
      return StatusPill(
        label: "Offen",
        color: AppColors.warning,
        icon: Icons.schedule_rounded,
      );
  }
}

class _AbsenceCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final AbsenceJustified justified;
  final List<String> texts;
  final String? footer;
  final Widget? action;

  const _AbsenceCard({
    required this.title,
    required this.justified,
    this.subtitle,
    this.texts = const [],
    this.footer,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!, style: muted),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: justifiedPill(justified),
                ),
              ],
            ),
            for (final text in texts) ...[
              const SizedBox(height: 10),
              Text(text, style: theme.textTheme.bodyMedium),
            ],
            if (footer != null || action != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  if (footer != null)
                    Expanded(child: Text(footer!, style: muted)),
                  if (footer == null) const Spacer(),
                  if (action != null) action!,
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AbsenceGroupWidget extends StatelessWidget {
  final AbsencesViewModel vm;
  final void Function(String reason, String signature) onJustify;

  const AbsenceGroupWidget({
    super.key,
    required this.vm,
    required this.onJustify,
  });

  @override
  Widget build(BuildContext context) {
    return _AbsenceCard(
      title: vm.fromTo,
      subtitle: vm.duration,
      justified: vm.justified,
      texts: [
        if (vm.reason != null) vm.reason!,
        if (vm.note != null) vm.note!,
      ],
      footer: vm.signatureInfo,
      action: vm.canJustify
          ? FilledButton.tonalIcon(
              onPressed: () async {
                final result = await showJustifyAbsenceSheet(
                  context,
                  fromTo: vm.fromTo,
                  defaultSignature: vm.defaultSignature,
                );
                if (result != null) onJustify(result.$1, result.$2);
              },
              icon: const Icon(Icons.edit_note_rounded, size: 20),
              label: const Text("Entschuldigen"),
            )
          : null,
    );
  }
}

String formatFutureAbsenceRange(FutureAbsence absence) {
  final date = DateFormat("EE d.M.yyyy", "de");
  if (absence.startDate == absence.endDate) {
    final hours = absence.startHour == absence.endHour
        ? "${absence.startHour}. Stunde"
        : "${absence.startHour}.–${absence.endHour}. Stunde";
    return "${date.format(absence.startDate)}, $hours";
  }
  return "${date.format(absence.startDate)} ${absence.startHour}. h – "
      "${date.format(absence.endDate)} ${absence.endHour}. h";
}

class FutureAbsenceWidget extends StatelessWidget {
  final FutureAbsence absence;
  final VoidCallback? onRemove;

  const FutureAbsenceWidget({
    super.key,
    required this.absence,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final range = formatFutureAbsenceRange(absence);
    return _AbsenceCard(
      title: range,
      subtitle: "Im Voraus gemeldet",
      justified: absence.justified,
      texts: [
        if (absence.reason != null) absence.reason!,
        if (absence.note != null) absence.note!,
      ],
      footer: absence.reasonTimestamp != null && absence.reasonSignature != null
          ? "${DateFormat("d.M.yyyy, HH:mm", "de").format(absence.reasonTimestamp!)} · ${absence.reasonSignature}"
          : null,
      action: onRemove == null
          ? null
          : IconButton(
              tooltip: "Abwesenheit löschen",
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text("Abwesenheit löschen?"),
                    content: Text("$range wird aus dem Register entfernt."),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text("Abbrechen"),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text("Löschen"),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) onRemove!();
              },
            ),
    );
  }
}
