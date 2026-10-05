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

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The looks of the app, switchable in the settings.
enum AppStyle {
  /// Night blue, violet and cyan with glowing HUD panels.
  holo,

  /// Loud meme look: neon pink, toxic lime, comic type and sticker cards.
  brainrot,

  /// Blue and white like the flag of Israel, with Rubik type, stars of David
  /// and Israeli everyday slang. Uses the clean holo panels.
  israel,
}

/// The current look. Changing it rebuilds the whole app (see [setAppStyle]).
final appStyle = ValueNotifier(AppStyle.holo);

bool get isBrainrot => appStyle.value == AppStyle.brainrot;
bool get isIsrael => appStyle.value == AppStyle.israel;

/// Picks the text for the current look. Without an [israel] text, the
/// israel look uses the holo text.
String br(String holo, String brainrot, [String? israel]) =>
    switch (appStyle.value) {
      AppStyle.brainrot => brainrot,
      AppStyle.israel => israel ?? holo,
      AppStyle.holo => holo,
    };

const _styleKey = "appStyle";

Future<void> loadAppStyle() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_styleKey);
    if (stored != null) appStyle.value = AppStyle.values.byName(stored);
  } on Object {
    // Keep the default look.
  }
}

Future<void> setAppStyle(AppStyle style) async {
  appStyle.value = style;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_styleKey, style.name);
}

Color _pick(int holo, int brainrot, int israel) => Color(
      switch (appStyle.value) {
        AppStyle.holo => holo,
        AppStyle.brainrot => brainrot,
        AppStyle.israel => israel,
      },
    );

/// Colors of the current look. "violet" and "cyan" are the two accent roles:
/// hot pink and toxic lime in the brainrot look, flag blue and sky blue in
/// the israel look.
class AppColors {
  static Color get violet => _pick(0xFF7C5CFF, 0xFFFF2E93, 0xFF2F6BFF);
  static Color get violetDeep => _pick(0xFF5B3DF5, 0xFFD1006E, 0xFF0038B8);
  static Color get cyan => _pick(0xFF22D3EE, 0xFFB6FF00, 0xFF7CC4FF);
  static Color get cyanDeep => _pick(0xFF0891B2, 0xFF4F7A00, 0xFF1F6FD1);

  static Color get success => _pick(0xFF2DD4A3, 0xFF00FF85, 0xFF2DBE8C);
  static Color get warning => _pick(0xFFF5B544, 0xFFFFE600, 0xFFF2B33D);
  static Color get danger => _pick(0xFFFF5C7A, 0xFFFF3B30, 0xFFE5484D);

  // dark
  static Color get night => _pick(0xFF0A0E1A, 0xFF14001F, 0xFF06102E);
  static Color get nightSurface => _pick(0xFF111729, 0xFF23003A, 0xFF0C1A45);
  static Color get nightSurfaceHigh =>
      _pick(0xFF182038, 0xFF320A52, 0xFF132558);
  static Color get nightOutline => _pick(0xFF26304D, 0xFF7A2BC4, 0xFF24407F);

  // light
  static Color get frost => _pick(0xFFF4F6FB, 0xFFFFF6B0, 0xFFF7FAFF);
  static Color get frostSurfaceHigh =>
      _pick(0xFFEAEEF8, 0xFFFFE94D, 0xFFE8EFFC);
  static Color get frostOutline => _pick(0xFFD8DEEC, 0xFF111111, 0xFFC9D6F2);
  static Color get ink => _pick(0xFF0E1426, 0xFF111111, 0xFF0A1A44);

  static LinearGradient get accentGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isBrainrot ? [violet, warning, cyan] : [violet, cyan],
      );
}

ThemeData buildAppTheme(Brightness brightness, {TargetPlatform? platform}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: dark ? AppColors.violet : AppColors.violetDeep,
    onPrimary: Colors.white,
    primaryContainer: isIsrael
        ? (dark ? const Color(0xFF102A6B) : const Color(0xFFDCE7FF))
        : (dark ? const Color(0xFF2A2163) : const Color(0xFFE6E0FF)),
    onPrimaryContainer:
        dark ? const Color(0xFFE3DCFF) : const Color(0xFF1C1060),
    secondary: dark ? AppColors.cyan : AppColors.cyanDeep,
    onSecondary: dark ? AppColors.night : Colors.white,
    secondaryContainer:
        dark ? const Color(0xFF0E3A47) : const Color(0xFFCFF5FC),
    onSecondaryContainer:
        dark ? const Color(0xFFC9F6FF) : const Color(0xFF053340),
    tertiary: AppColors.success,
    onTertiary: AppColors.night,
    error: AppColors.danger,
    onError: Colors.white,
    surface: dark ? AppColors.night : AppColors.frost,
    onSurface: dark ? const Color(0xFFE7EAF6) : AppColors.ink,
    onSurfaceVariant: dark ? const Color(0xFF98A2C3) : const Color(0xFF59627E),
    surfaceContainerLowest: dark ? const Color(0xFF070A13) : Colors.white,
    surfaceContainerLow: dark ? AppColors.nightSurface : Colors.white,
    surfaceContainer: dark ? AppColors.nightSurface : Colors.white,
    surfaceContainerHigh:
        dark ? AppColors.nightSurfaceHigh : AppColors.frostSurfaceHigh,
    surfaceContainerHighest:
        dark ? const Color(0xFF1F2844) : const Color(0xFFE2E7F3),
    outline: dark ? const Color(0xFF3A4566) : const Color(0xFFB9C2D9),
    outlineVariant: dark ? AppColors.nightOutline : AppColors.frostOutline,
    inverseSurface: dark ? const Color(0xFFE7EAF6) : AppColors.ink,
    onInverseSurface: dark ? AppColors.night : const Color(0xFFF4F6FB),
    inversePrimary: dark ? AppColors.violetDeep : AppColors.violet,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  final baseText = (isBrainrot
          ? GoogleFonts.comicNeueTextTheme(
              ThemeData(brightness: brightness).textTheme,
            )
          : isIsrael
              ? GoogleFonts.rubikTextTheme(
                  ThemeData(brightness: brightness).textTheme,
                )
              : GoogleFonts.interTextTheme(
                  ThemeData(brightness: brightness).textTheme,
                ))
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  TextStyle? display(TextStyle? s, {FontWeight weight = FontWeight.w600}) =>
      isBrainrot
          ? GoogleFonts.bangers(
              textStyle: s,
              fontWeight: FontWeight.w400,
              letterSpacing: 1.2,
            )
          : isIsrael
              ? GoogleFonts.rubik(
                  textStyle: s,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                )
              : GoogleFonts.sora(
                  textStyle: s,
                  fontWeight: weight,
                  letterSpacing: -0.4,
                );
  final textTheme = baseText.copyWith(
    displayLarge: display(baseText.displayLarge),
    displayMedium: display(baseText.displayMedium),
    displaySmall: display(baseText.displaySmall),
    headlineLarge: display(baseText.headlineLarge),
    headlineMedium: display(baseText.headlineMedium),
    headlineSmall: display(baseText.headlineSmall),
    titleLarge: display(baseText.titleLarge),
    titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelSmall: baseText.labelSmall?.copyWith(letterSpacing: 0.8),
  );

  final radius = isBrainrot ? 8.0 : 18.0;
  final outline = isBrainrot
      ? BorderSide(color: dark ? AppColors.violet : AppColors.ink, width: 2)
      : BorderSide(color: scheme.outlineVariant);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    platform: platform,
    textTheme: textTheme,
    // Pages are drawn on top of an [AuroraBackdrop] (see [_BackdropTransitions]).
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: scheme.surface,
    // InkSparkle runs a shader per tap; the classic ripple is much cheaper.
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface.withValues(alpha: dark ? 0.55 : 0.7),
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 20),
      shape: Border(bottom: outline),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer.withValues(alpha: dark ? 0.72 : 0.82),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: outline,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      iconColor: scheme.onSurfaceVariant,
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
      ),
    ),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: outline,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: outline,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        minimumSize: const Size(64, 48),
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : scheme.onSurfaceVariant,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.surfaceContainerHighest,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        side: BorderSide(color: scheme.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      side: outline,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: outline,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle:
          textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: scheme.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android:
            _BackdropTransitions(FadeForwardsPageTransitionsBuilder()),
        TargetPlatform.iOS:
            _BackdropTransitions(CupertinoPageTransitionsBuilder()),
        TargetPlatform.macOS:
            _BackdropTransitions(FadeForwardsPageTransitionsBuilder()),
        TargetPlatform.windows:
            _BackdropTransitions(FadeForwardsPageTransitionsBuilder()),
        TargetPlatform.linux:
            _BackdropTransitions(FadeForwardsPageTransitionsBuilder()),
      },
    ),
  );
}

/// Gives every page its own opaque [AuroraBackdrop], so pages with a
/// transparent scaffold never show the page underneath during a transition.
class _BackdropTransitions extends PageTransitionsBuilder {
  final PageTransitionsBuilder inner;
  const _BackdropTransitions(this.inner);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return inner.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      AuroraBackdrop(child: child),
    );
  }
}

/// The app's background: night blue (or frost white) with two soft light
/// fields in violet and cyan and a faint technical grid.
class AuroraBackdrop extends StatelessWidget {
  final Widget child;
  const AuroraBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface),
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _AuroraPainter(dark: dark, style: appStyle.value),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final bool dark;
  final AppStyle style;
  const _AuroraPainter({required this.dark, required this.style});

  void _paintBrainrot(Canvas canvas, Size size) {
    // Diagonal stripes.
    final stripe = Paint()
      ..color = AppColors.violet.withValues(alpha: dark ? 0.07 : 0.12)
      ..strokeWidth = 18;
    for (var x = -size.height; x < size.width; x += 64) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        stripe,
      );
    }
    // Scattered meme emojis, always in the same places.
    const emojis = ["💀", "🗿", "🔥", "🤑", "🧠", "💯", "🫠", "😭", "🚀", "🌽"];
    final random = math.Random(7);
    final count = (size.width * size.height / 26000).clamp(12, 80).round();
    for (var i = 0; i < count; i++) {
      final painter = TextPainter(
        text: TextSpan(
          text: emojis[random.nextInt(emojis.length)],
          style: TextStyle(
            fontSize: 22 + random.nextDouble() * 26,
            color: Colors.white.withValues(alpha: dark ? 0.16 : 0.3),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      );
      canvas.rotate((random.nextDouble() - 0.5) * 0.8);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  /// Two equilateral triangles: a star of David.
  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    for (final start in [-math.pi / 2, math.pi / 2]) {
      final path = Path();
      for (var i = 0; i < 3; i++) {
        final a = start + i * 2 * math.pi / 3;
        final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, paint);
    }
  }

  void _paintIsrael(Canvas canvas, Size size) {
    final blue = AppColors.violetDeep;
    // The flag's two stripes.
    final stripe = Paint()..color = blue.withValues(alpha: dark ? 0.55 : 0.85);
    final h = size.height;
    final t = math.max(10.0, h * 0.022);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.05, size.width, t), stripe);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.95 - t, size.width, t), stripe);
    // A large, faint star in the middle.
    _star(
      canvas,
      size.center(Offset.zero),
      size.shortestSide * 0.32,
      Paint()
        ..color = blue.withValues(alpha: dark ? 0.10 : 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.02,
    );
    // Small stars and emojis, always in the same places.
    final random = math.Random(5);
    final small = Paint()
      ..color = blue.withValues(alpha: dark ? 0.16 : 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    const emojis = ["🇮🇱", "🥙", "🌊", "☀️", "🐪", "🫓", "🍊", "🏖️"];
    final count = (size.width * size.height / 30000).clamp(10, 60).round();
    for (var i = 0; i < count; i++) {
      final pos = Offset(
        random.nextDouble() * size.width,
        h * 0.08 + random.nextDouble() * h * 0.84,
      );
      if (i.isEven) {
        _star(canvas, pos, 9 + random.nextDouble() * 8, small);
      } else {
        final painter = TextPainter(
          text: TextSpan(
            text: emojis[random.nextInt(emojis.length)],
            style: TextStyle(
              fontSize: 18 + random.nextDouble() * 12,
              color: Colors.white.withValues(alpha: dark ? 0.18 : 0.35),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, pos);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (isBrainrot) {
      _paintBrainrot(canvas, size);
      return;
    }
    if (isIsrael) {
      _paintIsrael(canvas, size);
      return;
    }
    void glow(Offset center, double radius, Color color, double alpha) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
    }

    final shortest = size.shortestSide;
    glow(Offset(size.width * 0.05, size.height * 0.02), shortest * 0.95,
        AppColors.violet, dark ? 0.30 : 0.16);
    glow(Offset(size.width * 1.0, size.height * 0.85), shortest * 0.9,
        AppColors.cyan, dark ? 0.16 : 0.12);

    const step = 32.0;
    final grid = Paint()
      ..color = (dark ? Colors.white : AppColors.ink)
          .withValues(alpha: dark ? 0.035 : 0.04)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter oldDelegate) =>
      oldDelegate.dark != dark || oldDelegate.style != style;
}

/// Shows [text] filled with the violet-to-cyan accent gradient.
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const GradientText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) => AppColors.accentGradient.createShader(rect),
      child: Text(text,
          style: (style ?? const TextStyle()).copyWith(color: Colors.white)),
    );
  }
}

/// The primary call to action: a gradient button with a soft glow.
class GlowButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  const GlowButton({super.key, required this.onPressed, required this.child});

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: enabled ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            if (enabled)
              BoxShadow(
                color: AppColors.violet.withValues(alpha: 0.45),
                blurRadius: 24,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 50),
              child: Center(
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        letterSpacing: 0.3,
                      ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A card with a faint violet-to-cyan glow along its border, used to set off
/// the single most important element of a page.
class GlowCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const GlowCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = const EdgeInsets.fromLTRB(16, 16, 16, 8),
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    if (isBrainrot) {
      return Container(
        margin: margin.add(const EdgeInsets.only(right: 6, bottom: 6)),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: dark ? AppColors.cyan : AppColors.ink,
              offset: const Offset(7, 7),
            ),
          ],
        ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: dark ? AppColors.nightSurface : Colors.white,
            borderRadius: BorderRadius.circular(9),
          ),
          child: child,
        ),
      );
    }
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: AppColors.accentGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.violet.withValues(alpha: dark ? 0.28 : 0.14),
            blurRadius: 28,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(21),
        ),
        child: child,
      ),
    );
  }
}

/// A small rounded label that shows a state in color and word.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    if (isBrainrot) {
      // A slightly tilted sticker.
      return Transform.rotate(
        angle: -0.05,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.black, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Colors.black, offset: Offset(2, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: Colors.black),
                const SizedBox(width: 3),
              ],
              Text(
                label.toUpperCase(),
                style: _stickerLabelStyle,
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

/// Uppercase section label with an accent dot.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          if (isBrainrot)
            const Text("💥 ", style: TextStyle(fontSize: 14))
          else ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.accentGradient,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

final _stickerLabelStyle = GoogleFonts.bangers(
  fontSize: 13,
  letterSpacing: 1,
  color: Colors.black,
);
