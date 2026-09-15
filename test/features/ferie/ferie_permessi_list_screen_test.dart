// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/ferie/ferie_permessi_list_screen.dart';

class _FakeAbsenceRequestApiClient extends AbsenceRequestApiClient {
  _FakeAbsenceRequestApiClient(this._items) : super(Dio());

  List<AbsenceRequestDto> _items;
  final List<String> cancelledCalls = [];
  Object? throwOnCancel;
  Object? throwOnFetch;

  @override
  Future<List<AbsenceRequestDto>> fetchMine() async {
    if (throwOnFetch != null) throw throwOnFetch!;
    return _items;
  }

  @override
  Future<void> cancel(String id) async {
    cancelledCalls.add(id);
    if (throwOnCancel != null) throw throwOnCancel!;
    _items = [
      for (final it in _items)
        if (it.id == id)
          AbsenceRequestDto(
            id: it.id,
            requestedByUserId: it.requestedByUserId,
            createdByUserId: it.createdByUserId,
            type: it.type,
            startDate: it.startDate,
            endDate: it.endDate,
            status: 3, // Cancelled
          )
        else
          it,
    ];
  }
}

AbsenceRequestDto _request({
  required String id,
  int type = 0,
  int status = 0,
}) => AbsenceRequestDto(
  id: id,
  requestedByUserId: 'user-1',
  createdByUserId: 'user-1',
  type: type,
  startDate: DateTime(2026, 9, 10),
  endDate: DateTime(2026, 9, 12),
  status: status,
);

Widget _buildScreen(_FakeAbsenceRequestApiClient fake) {
  return ProviderScope(
    overrides: [
      absenceRequestApiClientProvider.overrideWithValue(fake),
      // Cancel now goes through ensureOnlineOrWarn (same guard the sibling create flow already
      // used) — without these, the unoverridden real providers resolve as offline/unknown in the
      // test harness and every cancel silently no-ops before it reaches the fake client.
      isOnlineProvider.overrideWithValue(true),
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: const MaterialApp(home: FeriePermessiListScreen()),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  testWidgets('renders requests the client returns', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1'), _request(id: 'ar-2', type: 1)]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.text('Ferie'), findsOneWidget);
    expect(find.text('Permesso'), findsOneWidget);
  });

  testWidgets('empty list shows an empty state', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.text('Nessuna richiesta'), findsOneWidget);
  });

  testWidgets('a Rejected request has no cancel affordance', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1', status: 2)]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    expect(find.byType(Dismissible), findsNothing);
  });

  testWidgets('swiping a Pending request then confirming cancels it', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')]);

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Annullare la richiesta?'), findsOneWidget);
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(fake.cancelledCalls, ['ar-1']);
  });

  testWidgets('a failed cancel surfaces a message rather than failing silently', (tester) async {
    final fake = _FakeAbsenceRequestApiClient([_request(id: 'ar-1')])
      ..throwOnCancel = Exception('boom');

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annulla richiesta'));
    await tester.pumpAndSettle();

    expect(fake.cancelledCalls, ['ar-1']);
    expect(find.text('Impossibile annullare la richiesta. Riprova.'), findsOneWidget);
  });
}
