// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/widgets/app_toast.dart';

Widget _buildApp(void Function(BuildContext) captureContext) {
  return MaterialApp(
    home: Builder(
      builder: (context) {
        captureContext(context);
        return const SizedBox();
      },
    ),
  );
}

void main() {
  testWidgets('shows the message', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_buildApp((c) => ctx = c));
    // Short, explicit duration — never the ~3.5s default, which would leave its auto-dismiss
    // Timer pending past this test's own end (flutter_test asserts none survive a test).
    showAppToast(ctx, message: 'Salvato', duration: const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Salvato'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  });

  testWidgets('auto-dismisses after its duration', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_buildApp((c) => ctx = c));
    showAppToast(ctx, message: 'Salvato', duration: const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Salvato'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('Salvato'), findsNothing);
  });

  testWidgets('a second call replaces the first rather than queuing it', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_buildApp((c) => ctx = c));
    // "Primo"'s own timer is cancelled the moment "Secondo" calls showAppToast — only
    // "Secondo"'s needs pumping past before this test ends.
    showAppToast(ctx, message: 'Primo', duration: const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('Primo'), findsOneWidget);

    showAppToast(ctx, message: 'Secondo', duration: const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Primo'), findsNothing);
    expect(find.text('Secondo'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 150));
    await tester.pumpAndSettle();
  });

  testWidgets('swiping the toast dismisses it', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_buildApp((c) => ctx = c));
    showAppToast(ctx, message: 'Salvato', duration: const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Salvato'), findsOneWidget);

    await tester.drag(find.text('Salvato'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Salvato'), findsNothing);
  });

  testWidgets('an action label calls onAction and dismisses', (tester) async {
    late BuildContext ctx;
    var tapped = false;
    await tester.pumpWidget(_buildApp((c) => ctx = c));
    showAppToast(
      ctx,
      message: 'Salvato',
      actionLabel: 'Annulla',
      onAction: () => tapped = true,
      duration: const Duration(seconds: 10),
    );
    await tester.pump();

    await tester.tap(find.text('Annulla'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(find.text('Salvato'), findsNothing);
  });
}
