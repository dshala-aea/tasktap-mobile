// test/features/timbra/scan_timbra_screen_test.dart
//
// Widget tests for ScanTimbraScreen (scan prompt only — driving the real camera isn't tested,
// same convention as step_materiali_fold_test.dart's "shows the scan button") and
// KioskConfirmTimbraScreen (the auto-submit/error/retry flow, fully testable since it takes the
// scanned token as a plain constructor parameter — see scan_timbra_screen.dart's own header
// comment for why it's split this way). No location/customer here: the backend now resolves the
// kiosk device's own registered site server-side (WorkLogController.KioskScan), so this screen
// has nothing to pick — it submits automatically on mount.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/scan_timbra_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

class _FakeWorklogApiClient extends WorklogApiClient {
  _FakeWorklogApiClient({this.result, this.error}) : super(Dio());

  final KioskScanResult? result;
  final KioskScanException? error;

  final List<Map<String, String>> calls = [];

  @override
  Future<KioskScanResult> kioskScan({required String token, required String userId}) async {
    calls.add({'token': token, 'userId': userId});
    if (error != null) throw error!;
    return result!;
  }
}

/// Wraps KioskConfirmTimbraScreen in a real two-route Navigator stack (a marker screen
/// underneath, this one pushed on top) rather than pumping it as `MaterialApp.home` directly —
/// on success it calls `Navigator.of(context).pop()`, which needs somewhere to pop to. Popping
/// the sole root route of a bare `MaterialApp.home` left a toast Timer orphaned and hung the
/// test (`!timersPending` framework invariant) — same class of Timer-lifecycle pitfall already
/// documented against this app's toast, see app_toast.dart.
Widget _buildConfirmScreen({
  required WorklogApiClient client,
  String token = 'device-1:100:hmac',
  String? userId = 'user-1',
}) {
  return ProviderScope(
    overrides: [
      worklogApiClientProvider.overrideWithValue(client),
      internalUserIdProvider.overrideWith((ref) async => userId),
    ],
    child: MaterialApp(
      home: Navigator(
        onGenerateRoute: (settings) => MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => KioskConfirmTimbraScreen(token: token)),
                ),
                child: const Text('MARKER-UNDERNEATH'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps the marker+confirm-screen stack and pushes the confirm screen, so it starts with a
/// real route to pop back to (see _buildConfirmScreen's own doc comment).
Future<void> _pushConfirmScreen(WidgetTester tester, Widget tree) async {
  await tester.pumpWidget(tree);
  await tester.pumpAndSettle();
  await tester.tap(find.text('MARKER-UNDERNEATH'));
  await tester.pumpAndSettle();
}

void main() {
  group('ScanTimbraScreen', () {
    testWidgets('renders the header and the scan button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ScanTimbraScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Timbra con QR'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Scansiona QR'), findsOneWidget);

      await _teardown(tester);
    });
  });

  group('KioskConfirmTimbraScreen', () {
    testWidgets(
      'submits automatically on mount with the token and the caller\'s own userId, '
      'then returns to the previous screen on success',
      (tester) async {
        final client = _FakeWorklogApiClient(
          result: const KioskScanResult(action: 'in', workLogId: 'wl-1'),
        );
        await _pushConfirmScreen(
          tester,
          _buildConfirmScreen(client: client, token: 'dev-9:200:hmac', userId: 'user-9'),
        );

        expect(client.calls, [
          {'token': 'dev-9:200:hmac', 'userId': 'user-9'},
        ]);
        // Popped back to the marker screen on success — no confirm button, no picker to tap.
        expect(find.text('MARKER-UNDERNEATH'), findsOneWidget);

        await _teardown(tester);
      },
    );

    testWidgets('shows a spinner while the call is in flight', (tester) async {
      final completer = Future<KioskScanResult>.delayed(
        const Duration(milliseconds: 50),
        () => const KioskScanResult(action: 'in', workLogId: 'wl-1'),
      );
      final client = _SlowFakeWorklogApiClient(completer);
      await tester.pumpWidget(_buildConfirmScreen(client: client));
      await tester.pump();
      await tester.tap(find.text('MARKER-UNDERNEATH'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      await _teardown(tester);
    });

    testWidgets(
      'an expired-token error shows a "torna indietro" state with no retry',
      (tester) async {
        final client = _FakeWorklogApiClient(
          error: const KioskScanException(
            KioskScanFailureReason.invalidOrExpiredToken,
            'Token scaduto',
          ),
        );
        await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

        expect(find.textContaining('Codice scaduto'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Torna indietro'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Riprova'), findsNothing);

        await tester.tap(find.widgetWithText(AppButton, 'Torna indietro'));
        await tester.pumpAndSettle();
        expect(find.text('MARKER-UNDERNEATH'), findsOneWidget);
        expect(client.calls, hasLength(1)); // did not retry

        await _teardown(tester);
      },
    );

    testWidgets('a forbidden error offers Riprova, which resubmits the same token', (
      tester,
    ) async {
      var callCount = 0;
      final client = _CountingFakeWorklogApiClient(() {
        callCount++;
        if (callCount == 1) {
          throw const KioskScanException(KioskScanFailureReason.forbidden);
        }
        return const KioskScanResult(action: 'in', workLogId: 'wl-1');
      });
      await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

      expect(find.textContaining('Non hai i permessi'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Riprova'), findsOneWidget);

      await tester.tap(find.widgetWithText(AppButton, 'Riprova'));
      await tester.pumpAndSettle();

      expect(callCount, 2);
      // Second attempt succeeded — popped back to the marker screen.
      expect(find.text('MARKER-UNDERNEATH'), findsOneWidget);

      await _teardown(tester);
    });
  });
}

class _SlowFakeWorklogApiClient extends WorklogApiClient {
  _SlowFakeWorklogApiClient(this.pending) : super(Dio());

  final Future<KioskScanResult> pending;

  @override
  Future<KioskScanResult> kioskScan({required String token, required String userId}) => pending;
}

class _CountingFakeWorklogApiClient extends WorklogApiClient {
  _CountingFakeWorklogApiClient(this.onCall) : super(Dio());

  final KioskScanResult Function() onCall;

  @override
  Future<KioskScanResult> kioskScan({required String token, required String userId}) async =>
      onCall();
}
