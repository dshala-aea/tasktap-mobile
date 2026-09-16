// test/features/timbra/scan_timbra_screen_test.dart
//
// Widget tests for ScanTimbraScreen (scan prompt only — driving the real camera isn't tested,
// same convention as step_materiali_fold_test.dart's "shows the scan button") and
// KioskConfirmTimbraScreen (the location-pick/confirm/error flow, fully testable since it takes
// the scanned token as a plain constructor parameter — see scan_timbra_screen.dart's own header
// comment for why it's split this way).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/worklog_api_client.dart';
import 'package:tasktap_mobile/features/timbra/scan_timbra_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

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
  Future<KioskScanResult> kioskScan({
    required String token,
    required String userId,
    required String locationId,
    required String customerId,
  }) async {
    calls.add({
      'token': token,
      'userId': userId,
      'locationId': locationId,
      'customerId': customerId,
    });
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
  required AppDatabase db,
  required _FakeWorklogApiClient client,
  String token = 'device-1:100:hmac',
  String? userId = 'user-1',
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
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

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  late AppDatabase db;
  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  Future<void> seedLocation(
    AppDatabase db, {
    String id = 'loc-1',
    String name = 'Sede Milano',
    String customerId = 'cust-1',
    String? city,
  }) => db
      .into(db.locations)
      .insert(
        LocationsCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: customerId,
          name: name,
          city: city == null ? const Value.absent() : Value(city),
        ),
      );

  group('ScanTimbraScreen', () {
    testWidgets('renders the header and the scan button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ScanTimbraScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Timbra con QR'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Scansiona QR'), findsOneWidget);

      await _teardown(tester);
    });
  });

  /// Pumps the marker+confirm-screen stack and pushes the confirm screen, so it starts with a
  /// real route to pop back to (see _buildConfirmScreen's own doc comment).
  Future<void> pushConfirmScreen(WidgetTester tester, Widget tree) async {
    await tester.pumpWidget(tree);
    await tester.pumpAndSettle();
    await tester.tap(find.text('MARKER-UNDERNEATH'));
    await tester.pumpAndSettle();
  }

  group('KioskConfirmTimbraScreen', () {
    testWidgets('shows an honest empty state when no sedi in cache', (tester) async {
      await pushConfirmScreen(
        tester,
        _buildConfirmScreen(db: db, client: _FakeWorklogApiClient()),
      );

      expect(find.text('Non risultano sedi sincronizzate su questo dispositivo.'), findsOneWidget);

      await _teardown(tester);
    });

    testWidgets('lists sedi from Drift and filters by search', (tester) async {
      await seedLocation(db, id: 'loc-1', name: 'Sede Milano', city: 'Milano');
      await seedLocation(db, id: 'loc-2', name: 'Sede Torino', city: 'Torino');
      await pushConfirmScreen(
        tester,
        _buildConfirmScreen(db: db, client: _FakeWorklogApiClient()),
      );

      expect(find.text('Sede Milano'), findsOneWidget);
      expect(find.text('Sede Torino'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Torino');
      await tester.pumpAndSettle();

      expect(find.text('Sede Torino'), findsOneWidget);
      expect(find.text('Sede Milano'), findsNothing);

      await _teardown(tester);
    });

    testWidgets('confirm is disabled until a sede is picked', (tester) async {
      await seedLocation(db);
      await pushConfirmScreen(
        tester,
        _buildConfirmScreen(db: db, client: _FakeWorklogApiClient()),
      );

      final button = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Conferma timbratura'),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.text('Sede Milano'));
      await tester.pumpAndSettle();

      final buttonAfter = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Conferma timbratura'),
      );
      expect(buttonAfter.onPressed, isNotNull);

      await _teardown(tester);
    });

    testWidgets(
      'confirm sends the picked sede\'s locationId/customerId and the caller\'s own userId, '
      'then returns to the previous screen',
      (tester) async {
        await seedLocation(db, id: 'loc-1', name: 'Sede Milano', customerId: 'cust-milano');
        final client = _FakeWorklogApiClient(
          result: const KioskScanResult(action: 'in', workLogId: 'wl-1'),
        );
        await pushConfirmScreen(
          tester,
          _buildConfirmScreen(db: db, client: client, token: 'dev-9:200:hmac', userId: 'user-9'),
        );

        await tester.tap(find.text('Sede Milano'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(AppButton, 'Conferma timbratura'));
        await tester.pumpAndSettle();

        expect(client.calls, [
          {
            'token': 'dev-9:200:hmac',
            'userId': 'user-9',
            'locationId': 'loc-1',
            'customerId': 'cust-milano',
          },
        ]);
        // Popped back to the marker screen on success.
        expect(find.text('MARKER-UNDERNEATH'), findsOneWidget);

        await _teardown(tester);
      },
    );

    testWidgets('an expired-token error shows a "torna indietro" state, not the picker', (
      tester,
    ) async {
      await seedLocation(db);
      final client = _FakeWorklogApiClient(
        error: const KioskScanException(KioskScanFailureReason.invalidOrExpiredToken, 'Token scaduto'),
      );
      await pushConfirmScreen(tester, _buildConfirmScreen(db: db, client: client));

      await tester.tap(find.text('Sede Milano'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Conferma timbratura'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Codice scaduto'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Torna indietro'), findsOneWidget);
      // The picker is gone — nothing left to confirm against an invalid token.
      expect(find.widgetWithText(AppButton, 'Conferma timbratura'), findsNothing);

      await _teardown(tester);
    });

    testWidgets('a forbidden error keeps the picker up so the technician can retry', (
      tester,
    ) async {
      await seedLocation(db);
      final client = _FakeWorklogApiClient(
        error: const KioskScanException(KioskScanFailureReason.forbidden),
      );
      await pushConfirmScreen(tester, _buildConfirmScreen(db: db, client: client));

      await tester.tap(find.text('Sede Milano'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppButton, 'Conferma timbratura'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Non hai i permessi'), findsOneWidget);
      // Unlike the expired-token case, this isn't a dead token — the picker/confirm stays up.
      expect(find.widgetWithText(AppButton, 'Conferma timbratura'), findsOneWidget);

      await _teardown(tester);
    });
  });
}
