// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/ferie/absence_request_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/features/ferie/ferie_permessi_form_screen.dart';

class _FakeAbsenceRequestApiClient extends AbsenceRequestApiClient {
  _FakeAbsenceRequestApiClient() : super(Dio());

  Map<String, dynamic>? lastCreate;
  Object? throwOnCreate;

  @override
  Future<String> create({
    required int type,
    required DateTime startDate,
    required DateTime endDate,
    String? startTime,
    String? endTime,
    String? reason,
  }) async {
    if (throwOnCreate != null) throw throwOnCreate!;
    lastCreate = {
      'type': type,
      'startDate': startDate,
      'endDate': endDate,
      'startTime': startTime,
      'endTime': endTime,
      'reason': reason,
    };
    return 'ar-new';
  }
}

Widget _buildScreen(_FakeAbsenceRequestApiClient fake) {
  return ProviderScope(
    overrides: [
      absenceRequestApiClientProvider.overrideWithValue(fake),
      isOnlineProvider.overrideWithValue(true),
      cachedEntitlementProvider.overrideWith((ref) => null),
    ],
    child: const MaterialApp(home: FeriePermessiFormScreen()),
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('it', null);
  });

  testWidgets('creates a Ferie request with the default (today) dates', (tester) async {
    final fake = _FakeAbsenceRequestApiClient();

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(fake.lastCreate, isNotNull);
    expect(fake.lastCreate!['type'], 0);
  });

  testWidgets('surfaces the server validation message on a failed create', (tester) async {
    final fake = _FakeAbsenceRequestApiClient()
      ..throwOnCreate = const AbsenceRequestValidationError(
        'La data di fine non può precedere la data di inizio.',
      );

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(find.text('La data di fine non può precedere la data di inizio.'), findsOneWidget);
  });

  testWidgets('shows a generic message for a non-validation failure', (tester) async {
    final fake = _FakeAbsenceRequestApiClient()..throwOnCreate = Exception('network down');

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(find.text('Impossibile inviare la richiesta. Riprova.'), findsOneWidget);
  });
}
