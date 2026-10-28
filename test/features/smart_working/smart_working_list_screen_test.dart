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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart' show StatusPill;
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_service.dart'
    show internalUserIdPrefsKey;
import 'package:tasktap_mobile/data/smart_working/smart_working_request_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/smart_working/smart_working_list_screen.dart';

class _FakeSmartWorkingRequestApiClient extends SmartWorkingRequestApiClient {
  _FakeSmartWorkingRequestApiClient(this.items) : super(Dio());

  List<SmartWorkingRequestDto> items;
  final List<String> cancelledCalls = [];
  String? lastUserId;

  @override
  Future<List<SmartWorkingRequestDto>> fetchMine({String? userId}) async {
    lastUserId = userId;
    return items;
  }

  @override
  Future<void> cancel(String id) async {
    cancelledCalls.add(id);
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

Widget _buildScreen(_FakeSmartWorkingRequestApiClient fake) {
  return ProviderScope(
    overrides: [
      smartWorkingRequestApiClientProvider.overrideWithValue(fake),
      // Cancel goes through ensureOnlineOrWarn, the same guard the sibling create flow uses.
      isOnlineProvider.overrideWithValue(true),
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: const MaterialApp(home: SmartWorkingListScreen()),
  );
}

void main() {
  setUpAll(() async {
    // The row's label uses Italian month abbreviations, same as the ferie rows.
    await initializeDateFormatting('it', null);
  });

  setUp(() {
    // The real provider reads the signed-in user's internal id from prefs on every read.
    SharedPreferences.setMockInitialValues({internalUserIdPrefsKey: 'user-1'});
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

    await tester.pumpWidget(_buildScreen(fake));
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

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.text('Nessuna richiesta'), findsOneWidget);
    expect(find.textContaining('pulsante +'), findsOneWidget);
  });

  testWidgets('pendingRow_offersCancel_afterConfirmation', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1', status: 0)]);

    await tester.pumpWidget(_buildScreen(fake));
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

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Annulla richiesta'), findsOneWidget);
    expect(find.text('APPROVATA'), findsOneWidget);
  });

  testWidgets('cancelledRow_offersNoAction', (tester) async {
    final fake = _FakeSmartWorkingRequestApiClient([_request(id: 'sw-1', status: 3)]);

    await tester.pumpWidget(_buildScreen(fake));
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

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    // The window as the technician reads it, in Italian prose — and still the same civil days the
    // server sent, because a UTC civil-date label formats on its own y/m/d fields.
    expect(find.text('2 nov – 4 nov'), findsOneWidget);
    expect(find.byType(StatusPill), findsOneWidget);
    expect(find.text('IN ATTESA'), findsOneWidget);
    expect(find.text('Assistenza da remoto al cliente'), findsOneWidget);
  });
}
