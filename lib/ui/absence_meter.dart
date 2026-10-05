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

import 'package:dr/ui/holo.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';

/// Students who miss more than a quarter of the lessons can not be admitted
/// to the end-of-year assessment (except for documented reasons).
const absenceLimitPercent = 25.0;

double? parseAbsencePercentage(String? value) =>
    value == null ? null : double.tryParse(value.replaceAll(",", "."));

/// Traffic light for the share of missed lessons.
(Color, String) absenceLevel(double percent) {
  if (percent < 10)
    return (
      AppColors.success,
      br("Im grünen Bereich", "Chillig 😎", "Sababa 👌")
    );
  if (percent < 18)
    return (
      AppColors.warning,
      br("Aufpassen", "Sus 👀", "Aufpassen, chabibi 👀")
    );
  if (percent < absenceLimitPercent)
    return (AppColors.danger, br("Kritisch", "Gefährlich 💀", "Oy vey! 😬"));
  return (
    AppColors.danger,
    br("Über der Grenze", "Game over 💀", "Über der Grenze 😬")
  );
}

/// A bar from 0 to the 25 % limit with the student's current share.
class AbsenceMeter extends StatelessWidget {
  final double percent;
  const AbsenceMeter({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, label) = absenceLevel(percent);
    final left = (absenceLimitPercent - percent).clamp(0, absenceLimitPercent);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusPill(label: label, color: color),
            const Spacer(),
            HudLabel(
              percent >= absenceLimitPercent
                  ? "Grenze 25 % überschritten"
                  : "noch ${left.toStringAsFixed(1).replaceAll(".", ",")} % bis 25 %",
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final fraction = (percent / absenceLimitPercent).clamp(0.0, 1.0);
            return Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  height: 8,
                  width: constraints.maxWidth * fraction,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.6), color],
                    ),
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
