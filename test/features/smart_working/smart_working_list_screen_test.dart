// dart format width=100
// test/features/smart_working/smart_working_list_screen_test.dart
//
// The technician's own smart-working requests: newest first, the civil dates they name, the
// shared absence-status pill, and a cancel affordance only while the server still accepts one
// (Pending and Approved; Rejected and Cancelled are over).
//
// The screen reads the REAL `mySmartWorkingRequestsProvider` — only the API client is faked — so
// this file also pins the thing the provider exists for: the list the screen shows is scoped to
// the caller's own id, never the tenant-wide queue an approve-holder would get from an unscoped
// `GET /api/smart-working-requests`.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart' show ErrorState, StatusPill;
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart'
    show EntitlementService, internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/smart_working/smart_working_request_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/smart_working/smart_working_list_screen.dart';

/// `refreshEntitlements` reaches `/auth/me` through this; a real one would open a database and hit
/// the network from the widget test.
class _MockEntitlementService extends Mock implements EntitlementService {}

class _FakeSmartWorkingRequestApiClient extends SmartWorkingRequestApiClient {
  _FakeSmartWorkingRequestApiClient(this.items) : super(Dio());

  List<SmartWorkingRequestDto> items;
  final List<String> cancelledCalls = [];
  String? lastUserId;

  /// Holds `cancel` open so a test can unmount the row, or try a second tap, while the POST is
  /// still on the wire.
  Completer<void>? cancelGate;
  Object? throwOnCancel;

  /// Makes the next read fail, so a test can break the refresh after the first successful one.
  Object? throwOnFetch;

  @override
  Future<List<SmartWorkingRequestDto>> fetchMine({String? userId}) async {
    lastUserId = userId;
    if (throwOnFetch != null) throw throwOnFetch!;
    return items;
  }

  @override
  Future<void> cancel(String id) async {
    cancelledCalls.add(id);
    if (cancelGate != null) await cancelGate!.future;
    if (throwOnCancel != null) throw throwOnCancel!;
    // What the server does on a successful cancel, so the refreshed list shows the new state.
    items = [
      for (final it in items)
        if (it.id == id)
          SmartWorkingRequestDto(
            id: it.id,
            requestedByUserId: it.requestedByUserId,
            createdByUserId: it.createdByUserId,
            startDate: it.startDate,
            endDate: it.endDate,
            reason: it.reason,
            status: 3, // Cancelled
          )
        else
          it,
    ];
  }
}

SmartWorkingRequestDto _request({
  required String id,
  int status = 0,
  DateTime? start,
  DateTime? end,
  String? reason,
}) => SmartWorkingRequestDto(
  id: id,
  requestedByUserId: 'user-1',
  createdByUserId: 'user-1',
  startDate: start ?? DateTime.utc(2026, 10, 5),
  endDate: end ?? DateTime.utc(2026, 10, 6),
  reason: reason,
  status: status,
);

Widget _buildScreen(
  _FakeSmartWorkingRequestApiClient fake, {
  required _MockEntitlementService service,
}) {
  return ProviderScope(
    overrides: [
      smartWorkingRequestApiClientProvider.overrideWithValue(fake),
      // Cancel goes through ensureOnlineOrWarn, the same guard the sibling create flow uses.
      isOnlineProvider.overrideWithValue(true),
      cachedEntitlementProvider.overrideWith((ref) => null),
      // A successful cancel re-asks /auth/me so the approved-day chip cannot keep claiming a day
      // the technician just withdrew.
      entitlementServiceProvider.overrideWithValue(service),
    ],
    child: const MaterialApp(home: SmartWorkingListScreen()),
  );
}

void main() {
  late _MockEntitlementService service;

  setUpAll(() async {
    // The row's label uses Italian month abbreviations, same as the ferie rows.
    await initializeDateFormatting('it', null);
  });

  setUp(() {
    // The real provider reads the signed-in user's internal id from prefs on every read.
    SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'});
    service = _MockEntitlementService();
    when(() => service.refresh()).thenAnswer((_) async => false);
  });

  testWidgets('listsRequestsNewestFirst', (tester) async {
    // The server answers newest-created first and this entity carries no createdAt on the client,
    // so the screen must render the order it is handed rather than shuffling it.
    final fake = _FakeSmartWorkingRequestApiClient([
      _request(
        id: 'sw-new',
        start: DateTime.utc(2026, 10, 12),
        end: DateTime.utc(2026, 10, 13),
      ),
      _request(
        id: 'sw-old',
        start: DateTime.utc(2026, 9, 1),
        end: DateTime.utc(2026, 9, 2),
      ),
    ]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    final newest = find.text('12 ott – 13 ott');
    final oldest = find.text('1 set – 2 set');
    expect(newest, findsOneWidget);
    expect(oldest, findsOneWidget);
    expect(
      tester.getTopLeft(newest).dy < tester.getTopLeft(oldest).dy,
      isTrue,
      reason: 'the newest request must sit above the older one',
    );
    expect(fake.lastUserId, 'user-1', reason: 'the list is always scoped to the caller');
  });

  testWidgets('emptyState_asksForANewRequest', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    expect(find.text('Nessuna richiesta'), findsOneWidget);
    expect(find.textContaining('pulsante +'), findsOneWidget);
  });

  testWidgets('pendingRow_offersCancel_afterConfirmation', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1', status: 0)]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(find.text('Annullare la richiesta?'), findsOneWidget);
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(fake.cancelledCalls, ['sw-1']);
    // The invalidation is what keeps the row honest after the server accepts the cancel.
    expect(find.text('ANNULLATA'), findsOneWidget);
  });

  testWidgets('approvedRow_isStillCancellable', (tester) async {
    // Approved is a state the server still lets the technician withdraw from — the button must
    // not disappear the moment a manager says yes.
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1', status: 1)]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Annulla richiesta'), findsOneWidget);
    expect(find.text('APPROVATA'), findsOneWidget);
  });

  testWidgets('cancelledRow_offersNoAction', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1', status: 3)]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Annulla richiesta'), findsNothing);
    expect(find.text('ANNULLATA'), findsOneWidget);
  });

  testWidgets('row_rendersTheCivilDatesAndTheStatusPill', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([
      _request(
        id: 'sw-1',
        start: DateTime.utc(2026, 11, 2),
        end: DateTime.utc(2026, 11, 4),
        reason: 'Assistenza da remoto al cliente',
      ),
    ]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    // The window as the technician reads it, in Italian prose — and still the same civil days the
    // server sent, because a UTC civil-date label formats on its own y/m/d fields.
    expect(find.text('2 nov – 4 nov'), findsOneWidget);
    expect(find.byType(StatusPill), findsOneWidget);
    expect(find.text('IN ATTESA'), findsOneWidget);
    expect(find.text('Assistenza da remoto al cliente'), findsOneWidget);
  });

  // ── Robustness around the cancel round trip ──────────────────────────────────

  /// Confirms the cancel dialog and processes just enough frames for the dialog to close, without
  /// `pumpAndSettle` — which would never settle while the in-flight spinner is animating.
  Future<void> tapConfirmAndLetThePostStart(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Annulla richiesta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('unmountingMidCancel_neitherThrowsNorUsesTheDisposedRef', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1')]);
    final gate = Completer<void>();
    fake.cancelGate = gate;

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();
    await tapConfirmAndLetThePostStart(tester);

    expect(fake.cancelledCalls, ['sw-1']);

    // The technician pops the screen while the POST is still on the wire.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    // Reaching the end is the assertion: `ref.invalidate` on a disposed state raises
    // `StateError('Cannot use "ref" after the widget was disposed.')`, and because
    // `IconButton.onPressed` does not await this future it would surface as an unhandled async
    // error the test harness reports as a failure.
    expect(fake.cancelledCalls, ['sw-1']);
    verifyNever(() => service.refresh());
  });

  testWidgets('aStaleRequest_surfacesTheServersItalianDetail', (tester) async {
    // The office decided this row while the screen sat open: retrying can never succeed, so the
    // server's own sentence is the only useful thing to show.
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1')])
      ..throwOnCancel = const SmartWorkingValidationError('La richiesta è già stata decisa.');

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Annulla richiesta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(find.text('La richiesta è già stata decisa.'), findsOneWidget);
    expect(find.text('Impossibile annullare la richiesta. Riprova.'), findsNothing);
    // A failed cancel must not claim the approved day was withdrawn.
    verifyNever(() => service.refresh());
  });

  testWidgets('aSecondTapWhileTheCancelIsInFlight_doesNotPostAgain', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1')]);
    final gate = Completer<void>();
    fake.cancelGate = gate;

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();
    await tapConfirmAndLetThePostStart(tester);

    // The cancel control gives way to a spinner of the same footprint while the POST is out.
    expect(find.byTooltip('Annulla richiesta'), findsNothing);
    final spinner = find.byType(CircularProgressIndicator);
    expect(spinner, findsOneWidget);

    // Tapping where the button was must not fire a second cancel.
    await tester.tap(spinner);
    await tester.pump();
    expect(fake.cancelledCalls, ['sw-1']);

    gate.complete();
    await tester.pumpAndSettle();
    expect(fake.cancelledCalls, ['sw-1']);
  });

  // ── Robustness around pull-to-refresh ────────────────────────────────────────

  testWidgets('aFailedPullToRefresh_keepsTheRowsAndSaysSo', (tester) async {
    // A failed read of a list the technician can already read must not replace it with an error
    // card, and the failure must not be silent: `RefreshIndicator` does not catch the future it is
    // handed, so an uncaught rejection here would tell the technician nothing at all.
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1')]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();
    expect(find.text('5 ott – 6 ott'), findsOneWidget);

    fake.throwOnFetch = DioException(
      requestOptions: RequestOptions(path: '/api/smart-working-requests'),
    );

    await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();

    expect(find.text('Impossibile aggiornare. Riprova.'), findsOneWidget);
    expect(
      find.text('5 ott – 6 ott'),
      findsOneWidget,
      reason: 'the rows already on screen survive a failed refresh',
    );
    expect(find.byType(ErrorState), findsNothing);

    // Disposes the toast, which cancels its auto-dismiss timer (flutter_test fails a test that
    // leaves one pending).
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('aSuccessfulCancel_reasksTheEntitlementAnswer', (tester) async {
    // Cancelling a request that covers TODAY leaves `smartWorkingTodayProvider` (memory-only)
    // claiming an approved remote day, so the timbra chip and Home's punch prompt would disagree
    // with the list until the next app resume. The cancel re-asks /auth/me to close that gap.
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1', status: 1)]);

    await tester.pumpWidget(_buildScreen(fake, service: service));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Annulla richiesta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(fake.cancelledCalls, ['sw-1']);
    verify(() => service.refresh()).called(1);
  });
}
