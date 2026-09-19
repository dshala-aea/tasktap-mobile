// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/theme/app_colors.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
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

  group('tone colors come from AppVetroPalette, not AppPalette', () {
    // Regression coverage: app_toast.dart's tone → color mapping was briefly (and wrongly)
    // repointed from AppVetroPalette to AppPalette's green/amber/red fields before being reverted.
    // Those two sources carry materially different hex values, so pinning the icon color to the
    // vetro status tokens (and asserting it away from the AppPalette ones) would fail if that swap
    // ever comes back.
    testWidgets('success uses vetro statusGood', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_buildApp((c) => ctx = c));
      showAppToast(
        ctx,
        message: 'ok',
        tone: ToastTone.success,
        duration: const Duration(seconds: 10),
      );
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.checkCircle2));
      expect(icon.color, equals(AppVetroPalette.light.statusGood));
      expect(icon.color, isNot(equals(AppPalette.light.green)));
    });

    testWidgets('warning uses vetro statusWarn', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_buildApp((c) => ctx = c));
      showAppToast(
        ctx,
        message: 'attenzione',
        tone: ToastTone.warning,
        duration: const Duration(seconds: 10),
      );
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.alertTriangle));
      expect(icon.color, equals(AppVetroPalette.light.statusWarn));
      expect(icon.color, isNot(equals(AppPalette.light.amber)));
    });

    testWidgets('error uses vetro statusBad', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_buildApp((c) => ctx = c));
      showAppToast(
        ctx,
        message: 'errore',
        tone: ToastTone.error,
        duration: const Duration(seconds: 10),
      );
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.xCircle));
      expect(icon.color, equals(AppVetroPalette.light.statusBad));
      expect(icon.color, isNot(equals(AppPalette.light.red)));
    });

    testWidgets('info uses the brand accent, not a status color', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_buildApp((c) => ctx = c));
      showAppToast(
        ctx,
        message: 'info',
        tone: ToastTone.info,
        duration: const Duration(seconds: 10),
      );
      await tester.pump();

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.alertCircle));
      expect(icon.color, equals(AppColors.Y));
    });
  });
}
