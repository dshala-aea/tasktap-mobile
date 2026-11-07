import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_theme.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/widgets/status_stamp.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildAppTheme(brightness: Brightness.light),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('leans every stamp by the prototype fixed −3°', (tester) async {
    await tester.pumpWidget(_app(const StatusStamp(stato: 'Completato')));

    final transform = tester.widget<Transform>(
      find.descendant(
        of: find.byType(StatusStamp),
        matching: find.byType(Transform),
      ),
    );
    final matrix = transform.transform;
    final angle = math.atan2(matrix.entry(1, 0), matrix.entry(0, 0));

    expect(angle, closeTo(-3 * math.pi / 180, 1e-6));
  });

  testWidgets('carries the prototype 3px leading ink dot', (tester) async {
    await tester.pumpWidget(_app(const StatusStamp(stato: 'Completato')));

    final dot = find.byKey(const Key('status-stamp-dot'));
    expect(dot, findsOneWidget);
    expect(tester.getSize(dot), const Size(3, 3));

    final decoration =
        tester.widget<Container>(dot).decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, AppVetroPalette.light.statusGood);

    // The dot leads the label, not the other way around.
    final dotX = tester.getCenter(dot).dx;
    final labelX = tester.getCenter(find.text('COMPLETATO')).dx;
    expect(dotX, lessThan(labelX));
  });

  testWidgets('keeps the accessible status semantics', (tester) async {
    await tester.pumpWidget(_app(const StatusStamp(stato: 'In corso')));

    expect(find.bySemanticsLabel('Stato: In corso'), findsOneWidget);
  });
}
