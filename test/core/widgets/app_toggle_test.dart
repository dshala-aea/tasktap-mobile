import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/widgets/app_toggle.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('AppToggle', () {
    testWidgets('renders in off state (BM track color)', (tester) async {
      await tester.pumpWidget(_wrap(AppToggle(value: false, onChanged: (_) {})));
      await tester.pump();

      // Find the track (first AnimatedContainer)
      final track = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
      final decoration = track.decoration as BoxDecoration;
      expect(decoration.color, equals(AppColors.BM));
    });

    testWidgets('renders in on state (Vetro tint track color)', (tester) async {
      await tester.pumpWidget(_wrap(AppToggle(value: true, onChanged: (_) {})));
      await tester.pump();

      final track = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
      final decoration = track.decoration as BoxDecoration;
      expect(decoration.color, equals(AppVetroPalette.light.tint));
    });

    testWidgets('tap calls onChanged(true) when off', (tester) async {
      bool? received;
      await tester.pumpWidget(_wrap(AppToggle(value: false, onChanged: (v) => received = v)));
      await tester.tap(find.byType(AppToggle));
      expect(received, isTrue);
    });

    testWidgets('tap calls onChanged(false) when on', (tester) async {
      bool? received;
      await tester.pumpWidget(_wrap(AppToggle(value: true, onChanged: (v) => received = v)));
      await tester.tap(find.byType(AppToggle));
      expect(received, isFalse);
    });

    testWidgets('disabled (onChanged null) does not throw on tap', (tester) async {
      await tester.pumpWidget(_wrap(const AppToggle(value: false, onChanged: null)));
      await tester.tap(find.byType(AppToggle), warnIfMissed: false);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hit area is at least 44×44', (tester) async {
      await tester.pumpWidget(_wrap(AppToggle(value: false, onChanged: (_) {})));
      await tester.pump();
      final sizedBox = tester.widget<SizedBox>(
        find.descendant(of: find.byType(AppToggle), matching: find.byType(SizedBox)).first,
      );
      expect(sizedBox.width, greaterThanOrEqualTo(44));
      expect(sizedBox.height, greaterThanOrEqualTo(44));
    });

    testWidgets('animates on state change', (tester) async {
      bool value = false;
      late StateSetter setter;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (ctx, setState) {
              setter = setState;
              return Scaffold(
                body: AppToggle(value: value, onChanged: (v) => setter(() => value = v)),
              );
            },
          ),
        ),
      );

      // Toggle on
      await tester.tap(find.byType(AppToggle));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Mid-animation — no exception
      expect(tester.takeException(), isNull);

      await tester.pumpAndSettle();

      final track = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
      final decoration = track.decoration as BoxDecoration;
      expect(decoration.color, equals(AppVetroPalette.light.tint));
    });
  });
}
