import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_tappable.dart';

/// Press feedback on a decorated surface.
///
/// The property worth a test is not "onTap fires" — a [GestureDetector] does that, and it is what
/// these call sites used to be. It is that a splash can actually appear, which is the part that
/// silently fails: an [InkWell] whose child paints its own opaque colour shows nothing at all,
/// because ink is drawn on the [Material] *beneath* the child. Someone "fixing" this widget by
/// moving the colour back onto a wrapping Container would leave every test below passing except
/// the last one.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: child)),
    ),
  );

  testWidgets('calls onTap', (tester) async {
    var taps = 0;
    await pump(tester, AppTappable(onTap: () => taps++, child: const Text('Apri')));

    await tester.tap(find.text('Apri'));
    expect(taps, 1);
  });

  testWidgets('calls onLongPress', (tester) async {
    var longPresses = 0;
    await pump(tester, AppTappable(onLongPress: () => longPresses++, child: const Text('Apri')));

    await tester.longPress(find.text('Apri'));
    expect(longPresses, 1);
  });

  testWidgets('a null onTap leaves the surface inert rather than swallowing the tap', (
    tester,
  ) async {
    var outerTaps = 0;
    await pump(
      tester,
      GestureDetector(
        onTap: () => outerTaps++,
        child: const AppTappable(child: Text('Apri')),
      ),
    );

    await tester.tap(find.text('Apri'));
    expect(outerTaps, 1, reason: 'a disabled row must not eat a parent gesture');
  });

  testWidgets('names itself for a screen reader when asked', (tester) async {
    await pump(
      tester,
      const AppTappable(semanticLabel: 'Apri intervento', child: Icon(Icons.circle)),
    );

    expect(find.bySemanticsLabel('Apri intervento'), findsOneWidget);
  });

  testWidgets('paints its colour on the ink layer, not over it', (tester) async {
    const surface = Color(0xFF112233);
    await pump(
      tester,
      const AppTappable(
        color: surface,
        borderRadius: BorderRadius.all(Radius.circular(6)),
        child: SizedBox(width: 80, height: 44),
      ),
    );

    // Ink hands the decoration to the Material layer; a plain Container would not, and the splash
    // would be painted underneath the fill where nobody can see it.
    final ink = tester.widget<Ink>(find.byType(Ink));
    expect((ink.decoration as BoxDecoration).color, surface);

    expect(
      find.descendant(of: find.byType(Ink), matching: find.byType(InkWell)),
      findsOneWidget,
      reason: 'the InkWell must sit inside the Ink whose decoration it splashes over',
    );
  });
}
