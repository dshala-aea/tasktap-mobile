import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_vetro_palette.dart';
import 'package:tasktap_mobile/core/widgets/empty_state.dart';
import 'package:tasktap_mobile/core/widgets/error_state.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('ErrorState', () {
    testWidgets('renders default title, body, and retry button', (
      tester,
    ) async {
      var retried = false;
      await tester.pumpWidget(_wrap(ErrorState(onRetry: () => retried = true)));

      expect(find.text('Impossibile caricare i dati'), findsOneWidget);
      expect(find.text('Controlla la connessione e riprova.'), findsOneWidget);
      expect(find.text('Riprova'), findsOneWidget);

      await tester.tap(find.text('Riprova'));
      expect(retried, isTrue);
    });

    testWidgets('no retry button when onRetry is omitted', (tester) async {
      await tester.pumpWidget(_wrap(const ErrorState()));
      expect(find.text('Riprova'), findsNothing);
    });

    testWidgets(
      "icon-badge tint comes from AppVetroPalette's statusBad, not AppPalette's red",
      (tester) async {
        // Regression coverage: error_state.dart's status color was briefly (and wrongly)
        // repointed from AppVetroPalette to AppPalette.red before being reverted — the two carry
        // materially different hex values. Pinning the badge tint to the vetro token (and away
        // from the AppPalette one) would fail if that swap ever comes back.
        await tester.pumpWidget(_wrap(const ErrorState()));

        final badge = tester.widget<VetroStateIconBadge>(
          find.byType(VetroStateIconBadge),
        );
        expect(badge.tint, equals(AppVetroPalette.light.statusBad));
        expect(badge.tint, isNot(equals(AppPalette.light.red)));
      },
    );
  });
}
