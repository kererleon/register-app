import 'package:dr/ui/holo.dart';
import 'package:dr/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  // No network in tests: fonts fall back to the default font.
  GoogleFonts.config.allowRuntimeFetching = false;

  for (final style in AppStyle.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${style.name} looks render (${brightness.name})',
          (tester) async {
        appStyle.value = style;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            home: Scaffold(
              body: AuroraBackdrop(
                child: ListView(
                  children: [
                    const SectionLabel("Abschnitt"),
                    const GlowCard(child: Text("Karte")),
                    HoloPanel(
                      accent: Colors.orange,
                      highlighted: true,
                      onTap: () {},
                      child: const Text("Panel"),
                    ),
                    const HoloPanel(child: Text("Panel")),
                    const Row(
                      children: [
                        NeonRing(value: 7.5, label: "7½"),
                        NeonRing(value: 5, label: "5", crossedOut: true),
                        NeonCheck(value: true),
                      ],
                    ),
                    StatusPill(label: "neu", color: AppColors.cyan),
                    HoloToggle(
                      labels: const ["A", "B"],
                      selected: 0,
                      onChanged: (_) {},
                    ),
                    GradientText("Register"),
                    GlowButton(onPressed: () {}, child: const Text("Login")),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.text("Karte"), findsOneWidget);
      });
    }
  }
}
