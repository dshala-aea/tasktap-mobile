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

  testWidgets('offers the nine current types and not the legacy Permesso', (tester) async {
    final fake = _FakeAbsenceRequestApiClient();

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();

    for (final label in ['ROL', 'Ex festività', 'Permesso retribuito', 'Legge 104']) {
      expect(
        find.text(label),
        findsWidgets,
        reason: 'a type the client asked for must be fileable from the phone',
      );
    }
    expect(
      find.text('Permesso'),
      findsNothing,
      reason: 'legacy value 1 still renders on old rows but must not be offered for new ones',
    );
  });

  testWidgets('Altri congedi/permessi cannot be sent without the note the server requires', (
    tester,
  ) async {
    final fake = _FakeAbsenceRequestApiClient();

    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Altri congedi/permessi').last);
    await tester.pumpAndSettle();

    expect(find.text('MOTIVO (OBBLIGATORIO)', findRichText: true), findsOneWidget);
    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();
    expect(
      fake.lastCreate,
      isNull,
      reason: 'the server answers reason_required_for_altri; the form must not send it blind',
    );

    await tester.enterText(find.byType(TextField).last, 'Assistenza a un familiare');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();

    expect(fake.lastCreate!['type'], kAltriCongediPermessiType);
    expect(fake.lastCreate!['reason'], 'Assistenza a un familiare');
  });
}
