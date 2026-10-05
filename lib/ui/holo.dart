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

// Building blocks of the "Holo cockpit" look: glass panels with HUD corner
// brackets, neon rings for grades and a monospace face for data.

import 'dart:math' as math;

import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Monospace style for dates, hours and numbers.
TextStyle mono(TextStyle? base, {FontWeight? weight}) {
  // Looking up a Google font is not free and this runs for every label in
  // long lists, so the font part is created once per look and weight.
  final font = _monoFonts.putIfAbsent(
    (appStyle.value, weight),
    () => switch (appStyle.value) {
      AppStyle.brainrot => GoogleFonts.bangers(letterSpacing: 1.1),
      AppStyle.israel => GoogleFonts.rubik(
          fontWeight: weight ?? FontWeight.w700,
          letterSpacing: 0.4,
        ),
      AppStyle.holo => GoogleFonts.jetBrainsMono(fontWeight: weight),
      // The calm looks keep their own font, with even-width digits.
      AppStyle.clean || AppStyle.glass => TextStyle(
          fontWeight: weight ?? FontWeight.w600,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
    },
  );
  return (base ?? const TextStyle()).merge(font);
}

final _monoFonts = <(AppStyle, FontWeight?), TextStyle>{};

/// Color for a grade on the 1–10 scale used in South Tyrol.
Color gradeColor(double? grade) {
  if (grade == null) return AppColors.violet;
  if (grade < 6) return AppColors.danger;
  if (grade < 7) return AppColors.warning;
  if (grade < 8.5) return AppColors.violet;
  return AppColors.cyan;
}

/// Turns grade labels like "7+", "8½", "6-" or "7,25" into a number.
double? parseGradeLabel(String? label) {
  if (label == null) return null;
  final text = label.trim().replaceAll(",", ".");
  final match = RegExp(r"^(\d+(?:\.\d+)?)").firstMatch(text);
  if (match == null) return null;
  var value = double.parse(match.group(1)!);
  final rest = text.substring(match.end);
  if (rest.contains("½")) value += 0.5;
  if (rest.startsWith("+")) value += 0.25;
  if (rest.startsWith("-")) value -= 0.25;
  return value;
}

/// Small uppercase monospace label, the HUD's captions.
class HudLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const HudLabel(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: mono(
        theme.textTheme.labelSmall?.copyWith(
          color: color ?? theme.colorScheme.onSurfaceVariant,
          letterSpacing: 1.6,
          fontSize: 10.5,
        ),
        weight: FontWeight.w600,
      ),
    );
  }
}

/// A glass panel with glowing corner brackets. [accent] adds a colored stripe
/// on the left edge, e.g. the subject's color.
class HoloPanel extends StatelessWidget {
  final Widget child;
  final Color? accent;
  final Color? bracketColor;
  final bool highlighted;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const HoloPanel({
    super.key,
    required this.child,
    this.accent,
    this.bracketColor,
    this.highlighted = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  Widget _buildSticker(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final edge = highlighted ? AppColors.cyan : (accent ?? AppColors.violet);
    return Padding(
      padding: margin.add(const EdgeInsets.only(right: 4, bottom: 4)),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? AppColors.nightSurface : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: dark ? edge : AppColors.ink, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: dark ? edge.withValues(alpha: 0.85) : AppColors.ink,
              offset: const Offset(5, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalm(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final radius = isGlass ? 22.0 : 12.0;
    final decoration = isGlass
        ? glassDecoration(dark, radius: radius).copyWith(
            border: highlighted
                ? Border.all(color: AppColors.violet.withValues(alpha: 0.7))
                : null,
          )
        : BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: highlighted ? AppColors.violet : scheme.outlineVariant,
              width: highlighted ? 1.5 : 1,
            ),
          );
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: decoration,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Stack(
                children: [
                  // The glass look keeps a small colored stripe for
                  // subjects; the clean look stays without extra colors.
                  if (isGlass && accent != null)
                    Positioned(
                      left: 0,
                      top: 14,
                      bottom: 14,
                      child: Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: isGlass && accent != null
                        ? padding.add(const EdgeInsets.only(left: 6))
                        : padding,
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isStickerStyle) return _buildSticker(context);
    if (isClean || isGlass) return _buildCalm(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final brackets =
        bracketColor ?? (highlighted ? scheme.secondary : scheme.primary);
    const radius = 16.0;
    return Padding(
      padding: margin,
      child: CustomPaint(
        foregroundPainter: _BracketPainter(
          color: brackets.withValues(alpha: highlighted ? 1 : 0.75),
          radius: radius,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color:
                scheme.surfaceContainer.withValues(alpha: dark ? 0.68 : 0.85),
            borderRadius: BorderRadius.circular(radius),
            // No blurred shadows here: panels fill long scrolling lists, and
            // blurring each of them every frame makes scrolling stutter.
            border: Border.all(
              color: highlighted
                  ? scheme.secondary.withValues(alpha: 0.6)
                  : scheme.outlineVariant,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  children: [
                    if (accent != null)
                      Positioned(
                        left: 0,
                        top: 10,
                        bottom: 10,
                        child: Container(
                          width: 3.5,
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4),
                            ),
                            // A soft edge without a blurred shadow.
                            gradient: LinearGradient(
                              colors: [
                                accent!,
                                accent!.withValues(alpha: 0.55),
                              ],
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: accent != null
                          ? padding.add(const EdgeInsets.only(left: 6))
                          : padding,
                      child: child,
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

class _BracketPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _BracketPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    const arm = 12.0;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final r = radius;
    // Each bracket follows the rounded corner and runs a short way along
    // both edges.
    void corner(Offset c, double startAngle) {
      final path = Path()
        ..addArc(
            Rect.fromCircle(center: c, radius: r), startAngle, math.pi / 2);
      canvas.drawPath(path, paint);
    }

    final w = size.width, h = size.height;
    corner(Offset(r, r), math.pi);
    canvas.drawLine(Offset(r, 0), Offset(r + arm, 0), paint);
    canvas.drawLine(Offset(0, r), Offset(0, r + arm), paint);

    corner(Offset(w - r, r), -math.pi / 2);
    canvas.drawLine(Offset(w - r, 0), Offset(w - r - arm, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, r + arm), paint);

    corner(Offset(w - r, h - r), 0);
    canvas.drawLine(Offset(w - r, h), Offset(w - r - arm, h), paint);
    canvas.drawLine(Offset(w, h - r), Offset(w, h - r - arm), paint);

    corner(Offset(r, h - r), math.pi / 2);
    canvas.drawLine(Offset(r, h), Offset(r + arm, h), paint);
    canvas.drawLine(Offset(0, h - r), Offset(0, h - r - arm), paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) =>
      old.color != color || old.radius != radius;
}

/// A circular gauge that fills up with a grade on the 1–10 scale.
class NeonRing extends StatelessWidget {
  final double? value;
  final String label;
  final double size;
  final double stroke;
  final bool crossedOut;

  const NeonRing({
    super.key,
    required this.value,
    required this.label,
    this.size = 48,
    this.stroke = 4,
    this.crossedOut = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        crossedOut ? theme.colorScheme.onSurfaceVariant : gradeColor(value);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction: ((value ?? 0) / 10).clamp(0, 1).toDouble(),
          color: color,
          track: theme.colorScheme.outlineVariant,
          stroke: stroke,
          glow: !crossedOut && !isClean,
        ),
        child: Center(
          child: FittedBox(
            child: Padding(
              padding: EdgeInsets.all(stroke + 4),
              child: Text(
                label,
                style: mono(
                  theme.textTheme.titleMedium?.copyWith(
                    color: crossedOut ? color : theme.colorScheme.onSurface,
                    fontSize: size * 0.3,
                    decoration: crossedOut ? TextDecoration.lineThrough : null,
                  ),
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;
  final double stroke;
  final bool glow;

  const _RingPainter({
    required this.fraction,
    required this.color,
    required this.track,
    required this.stroke,
    required this.glow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (fraction <= 0) return;
    final sweep = math.pi * 2 * fraction;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: [color.withValues(alpha: 0.35), color],
      stops: [0, fraction.clamp(0.01, 1)],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);
    if (glow) {
      // A wide, faint stroke instead of a blur: looks like a glow but costs
      // almost nothing to draw.
      canvas.drawArc(
        rect,
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..color = color.withValues(alpha: 0.22)
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 2.4
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.drawArc(
      rect,
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}

/// A round check toggle that lights up when done.
class NeonCheck extends StatelessWidget {
  final bool value;
  final VoidCallback? onTap;
  const NeonCheck({super.key, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      checked: value,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 26,
          height: 26,
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: value ? AppColors.accentGradient : null,
            border: value
                ? null
                : Border.all(
                    color:
                        onTap == null ? scheme.outlineVariant : scheme.outline,
                    width: 1.6,
                  ),
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: value ? 1 : 0,
            child:
                const Icon(Icons.check_rounded, size: 18, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// A two-way pill switch, e.g. "Kommend | Vergangen".
class HoloToggle extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  const HoloToggle({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              onTap: i == selected ? null : () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  gradient: i == selected ? AppColors.accentGradient : null,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    if (i == selected)
                      BoxShadow(
                        color: AppColors.violet.withValues(alpha: 0.45),
                        blurRadius: 16,
                        spreadRadius: -4,
                      ),
                  ],
                ),
                child: Text(
                  labels[i].toUpperCase(),
                  style: mono(
                    theme.textTheme.labelMedium?.copyWith(
                      color: i == selected
                          ? Colors.white
                          : scheme.onSurfaceVariant,
                      letterSpacing: 1.2,
                    ),
                    weight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded square with the first letter of a subject in its color.
class SubjectGlyph extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const SubjectGlyph({
    super.key,
    required this.name,
    required this.color,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(size * 0.3),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.4),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isEmpty ? "?" : name.characters.first.toUpperCase(),
        style: GoogleFonts.sora(
          fontSize: size * 0.45,
          fontWeight: FontWeight.w700,
          color: Color.lerp(color, Colors.white, 0.35),
        ),
      ),
    );
  }
}
