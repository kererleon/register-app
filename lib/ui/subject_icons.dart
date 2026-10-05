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

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Icons that fit a subject, matched by words in its name.
const _subjectIcons = <List<String>, List<IconData>>{
  ["mathe"]: [
    Icons.functions,
    Icons.calculate_outlined,
    Icons.square_foot,
    Icons.percent,
    Icons.show_chart,
  ],
  ["deutsch"]: [
    Icons.menu_book_outlined,
    Icons.edit_note,
    Icons.auto_stories_outlined,
    Icons.format_quote,
  ],
  ["englisch", "english"]: [
    Icons.translate,
    Icons.language,
    Icons.chat_bubble_outline,
    Icons.menu_book_outlined,
  ],
  ["italienisch", "italiano"]: [
    Icons.translate,
    Icons.local_pizza_outlined,
    Icons.chat_bubble_outline,
    Icons.menu_book_outlined,
  ],
  ["informatik"]: [
    Icons.code,
    Icons.memory,
    Icons.terminal,
    Icons.computer,
    Icons.data_object,
  ],
  ["systeme", "netz"]: [
    Icons.lan_outlined,
    Icons.router_outlined,
    Icons.dns_outlined,
    Icons.hub_outlined,
    Icons.cable,
  ],
  ["telekom", "elektro"]: [
    Icons.cell_tower,
    Icons.wifi,
    Icons.settings_input_antenna,
    Icons.electric_bolt,
    Icons.waves,
  ],
  ["technologie", "planung", "technik"]: [
    Icons.architecture,
    Icons.precision_manufacturing_outlined,
    Icons.engineering_outlined,
    Icons.design_services_outlined,
  ],
  ["geschichte"]: [
    Icons.account_balance_outlined,
    Icons.history_edu,
    Icons.castle_outlined,
    Icons.hourglass_empty,
  ],
  ["religion", "ethik"]: [
    Icons.church_outlined,
    Icons.self_improvement,
    Icons.auto_awesome_outlined,
    Icons.favorite_border,
  ],
  ["bewegung", "sport"]: [
    Icons.sports_soccer,
    Icons.fitness_center,
    Icons.directions_run,
    Icons.sports_basketball_outlined,
  ],
  ["physik"]: [Icons.science_outlined, Icons.bolt, Icons.speed, Icons.waves],
  ["chemie"]: [
    Icons.science_outlined,
    Icons.biotech_outlined,
    Icons.bubble_chart_outlined
  ],
  ["biologie", "natur"]: [
    Icons.eco_outlined,
    Icons.biotech_outlined,
    Icons.pets_outlined,
    Icons.spa_outlined
  ],
  ["geo", "erdkunde"]: [
    Icons.public,
    Icons.map_outlined,
    Icons.terrain_outlined,
    Icons.explore_outlined
  ],
  ["wirtschaft", "recht", "betrieb"]: [
    Icons.gavel,
    Icons.euro,
    Icons.trending_up,
    Icons.business_center_outlined
  ],
  ["kunst", "zeichnen"]: [
    Icons.palette_outlined,
    Icons.brush_outlined,
    Icons.draw_outlined
  ],
  ["musik"]: [Icons.music_note, Icons.piano, Icons.headphones_outlined],
};

const _fallbackIcons = [
  Icons.school_outlined,
  Icons.lightbulb_outline,
  Icons.auto_stories_outlined,
  Icons.edit_outlined,
];

List<IconData> iconsForSubject(String subject) {
  final name = subject.toLowerCase();
  for (final entry in _subjectIcons.entries) {
    if (entry.key.any(name.contains)) return entry.value;
  }
  return _fallbackIcons;
}

/// A faint pattern of icons that fit [subject], in the subject's [color].
class SubjectIconPattern extends StatelessWidget {
  final String subject;
  final Color color;

  const SubjectIconPattern({
    super.key,
    required this.subject,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _IconPatternPainter(
          icons: iconsForSubject(subject),
          color: color.withValues(alpha: 0.22),
          seed: subject.hashCode,
        ),
      ),
    );
  }
}

/// Laid-out icon glyphs, shared by all calendar tiles.
final _glyphs = <(IconData, Color), TextPainter>{};

TextPainter _glyph(IconData icon, Color color) => _glyphs.putIfAbsent(
      (icon, color),
      () => TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            fontSize: 16,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );

class _IconPatternPainter extends CustomPainter {
  final List<IconData> icons;
  final Color color;
  final int seed;

  const _IconPatternPainter({
    required this.icons,
    required this.color,
    required this.seed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 30.0;
    final random = math.Random(seed);
    var i = 0;
    for (var y = 4.0; y < size.height; y += cell) {
      // Every other row is shifted, like a pattern on wrapping paper.
      final offset = ((y / cell).floor().isOdd) ? cell / 2 : 0.0;
      for (var x = 2.0 - offset; x < size.width; x += cell) {
        final icon = icons[i++ % icons.length];
        final painter = _glyph(icon, color);
        canvas.save();
        canvas.translate(x + 8, y + 8);
        canvas.rotate((random.nextDouble() - 0.5) * 0.6);
        painter.paint(canvas, const Offset(-8, -8));
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_IconPatternPainter old) =>
      old.color != color || old.seed != seed || old.icons != icons;
}
