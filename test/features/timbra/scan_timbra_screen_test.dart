// test/features/timbra/scan_timbra_screen_test.dart
//
// Widget tests for ScanTimbraScreen (scan prompt only — driving the real camera isn't tested,
// same convention as step_materiali_fold_test.dart's "shows the scan button") and
// KioskConfirmTimbraScreen (the auto-submit/error/retry flow, fully testable since it takes the
// scanned token as a plain constructor parameter — see scan_timbra_screen.dart's own header
// comment for why it's split this way). No location/customer here: the backend now resolves the
// kiosk device's own registered site server-side (WorkLogController.KioskScan), so this screen
// has nothing to pick. It reads the day first: clocked out submits immediately (a scan can only
// mean clock-in), anything else asks which transition was meant and sends it as a named action.

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
  _FakeWorklogApiClient({this.result, this.error, this.day}) : super(Dio());

  final KioskScanResult? result;
  final KioskScanException? error;

  /// The day `GET /worklog/today` would answer. Null means the read failed — the phone is
  /// offline, and the scan must fall back to the blind toggle rather than strand the technician.
  final GiornataDto? day;

  final List<Map<String, String?>> calls = [];

  @override
  Future<GiornataDto> getGiornata() async {
    final d = day;
    if (d == null) throw StateError('offline');
    return d;
  }

  @override
  Future<KioskScanResult> kioskScan({
    required String token,
    required String userId,
    String? action,
  }) async {
    calls.add({'token': token, 'userId': userId, 'action': action});
    if (error != null) throw error!;
    return result!;
  }
}

/// A day as the server would project it: [status] plus exactly the actions the prompt should
/// offer for it.
GiornataDto _day(String status, {List<GiornataActionDto> actions = const []}) => GiornataDto(
  status: status,
  workedMinutes: 0,
  breakMinutes: 0,
  isPayrollLocked: false,
  actions: actions,
);

GiornataActionDto _available(String action) => GiornataActionDto(action: action, enabled: true);

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
          // No day readable (this fake leaves `day` null) → the legacy toggle, exactly what
          // every app build before the prompt sent.
          {'token': 'dev-9:200:hmac', 'userId': 'user-9', 'action': null},
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

    testWidgets('a clocked-out day skips the prompt: a scan can only mean clock-in', (
      tester,
    ) async {
      final client = _FakeWorklogApiClient(
        result: const KioskScanResult(action: 'in', workLogId: 'wl-1'),
        day: _day(
          'ClockedOut',
          actions: [_available('ClockIn')],
        ),
      );
      await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

      expect(client.calls.single['action'], 'ClockIn');
      expect(find.text('Cosa vuoi fare?'), findsNothing);
      expect(find.text('MARKER-UNDERNEATH'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets(
      'a working day asks what the scan means, and "pausa" sends StartBreak',
      (tester) async {
        final client = _FakeWorklogApiClient(
          result: const KioskScanResult(action: 'breakStart', workLogId: 'wl-2'),
          day: _day(
            'Working',
            actions: [_available('StartBreak'), _available('ClockOut')],
          ),
        );
        await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

        // Nothing was punched just by scanning a totem while already on the clock.
        expect(client.calls, isEmpty);
        expect(find.text('Sei in servizio'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Inizia la pausa'), findsOneWidget);
        expect(find.widgetWithText(AppButton, 'Fine turno'), findsOneWidget);

        await tester.tap(find.widgetWithText(AppButton, 'Inizia la pausa'));
        await tester.pumpAndSettle();

        expect(client.calls.single['action'], 'StartBreak');
        expect(find.text('MARKER-UNDERNEATH'), findsOneWidget);

        await _teardown(tester);
      },
    );

    testWidgets('"fine turno" sends ClockOut — ending the turn, not a break', (tester) async {
      final client = _FakeWorklogApiClient(
        result: const KioskScanResult(action: 'out', workLogId: 'wl-3'),
        day: _day(
          'Working',
          actions: [_available('StartBreak'), _available('ClockOut')],
        ),
      );
      await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

      await tester.tap(find.widgetWithText(AppButton, 'Fine turno'));
      await tester.pumpAndSettle();

      expect(client.calls.single['action'], 'ClockOut');

      await _teardown(tester);
    });

    testWidgets('a day on break offers "riprendi" (EndBreak) rather than clocking out', (
      tester,
    ) async {
      final client = _FakeWorklogApiClient(
        result: const KioskScanResult(action: 'breakEnd', workLogId: 'wl-4'),
        day: _day(
          'OnBreak',
          actions: [_available('EndBreak'), _available('ClockOut')],
        ),
      );
      await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

      expect(find.text('Sei in pausa'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Riprendi il lavoro'));
      await tester.pumpAndSettle();

      expect(client.calls.single['action'], 'EndBreak');

      await _teardown(tester);
    });

    testWidgets('an action the server disabled is not tappable and explains itself', (
      tester,
    ) async {
      final client = _FakeWorklogApiClient(
        result: const KioskScanResult(action: 'breakStart', workLogId: 'wl-5'),
        day: _day(
          'Working',
          actions: [
            const GiornataActionDto(
              action: 'StartBreak',
              enabled: false,
              reasonCode: 'payroll_locked',
              reason: 'Periodo chiuso',
            ),
            const GiornataActionDto(
              action: 'ClockOut',
              enabled: false,
              reasonCode: 'payroll_locked',
              reason: 'Periodo chiuso',
            ),
          ],
        ),
      );
      await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

      expect(
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Inizia la pausa')).onPressed,
        isNull,
      );
      expect(
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Fine turno')).onPressed,
        isNull,
      );
      expect(find.textContaining('buste paga'), findsOneWidget);
      expect(client.calls, isEmpty);

      await _teardown(tester);
    });

    testWidgets('a conflict offers Riprova, which re-reads the day instead of repeating it', (
      tester,
    ) async {
      final client = _FakeWorklogApiClient(
        error: const KioskScanException(
          KioskScanFailureReason.conflict,
          'Sei già in pausa.',
          'on_break',
        ),
        day: _day(
          'Working',
          actions: [_available('StartBreak'), _available('ClockOut')],
        ),
      );
      await _pushConfirmScreen(tester, _buildConfirmScreen(client: client));

      await tester.tap(find.widgetWithText(AppButton, 'Inizia la pausa'));
      await tester.pumpAndSettle();

      expect(find.text('Sei già in pausa.'), findsOneWidget);
      await tester.tap(find.widgetWithText(AppButton, 'Riprova'));
      await tester.pumpAndSettle();

      // Re-read the day and asked again rather than resubmitting the refused action.
      expect(client.calls, hasLength(1));
      expect(find.text('Cosa vuoi fare?'), findsOneWidget);

      await _teardown(tester);
    });
  });
}

class _SlowFakeWorklogApiClient extends WorklogApiClient {
  _SlowFakeWorklogApiClient(this.pending) : super(Dio());

  final Future<KioskScanResult> pending;

  @override
  Future<GiornataDto> getGiornata() async => throw StateError('offline');

  @override
  Future<KioskScanResult> kioskScan({
    required String token,
    required String userId,
    String? action,
  }) => pending;
}

class _CountingFakeWorklogApiClient extends WorklogApiClient {
  _CountingFakeWorklogApiClient(this.onCall) : super(Dio());

  final KioskScanResult Function() onCall;

  @override
  Future<GiornataDto> getGiornata() async => throw StateError('offline');

  @override
  Future<KioskScanResult> kioskScan({
    required String token,
    required String userId,
    String? action,
  }) async => onCall();
}
