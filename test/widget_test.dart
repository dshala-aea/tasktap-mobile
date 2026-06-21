// Widget smoke test — verifies the app tree assembles without error.
// Full shell tests are in test/presentation/app_shell_test.dart.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/main.dart';

void main() {
  testWidgets('TaskTapApp smoke test — renders without error',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: TaskTapApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // App should mount a MaterialApp at minimum.
    expect(find.byType(MaterialApp), findsWidgets);
  });
}
