// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
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

  Future<void> pickType(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  const noteHint = 'Il motivo è obbligatorio per «Altri congedi/permessi»';
  const partialHint =
      'Per un permesso a ore indica un solo giorno e l\u2019ora di inizio e di fine';

  testWidgets('Altri congedi: the button stays tappable, says why, and sends nothing', (
    tester,
  ) async {
    final fake = _FakeAbsenceRequestApiClient();
    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();
    await pickType(tester, 'Altri congedi/permessi');

    // Proactive: the requirement is stated before the technician taps anything.
    expect(find.text(noteHint), findsOneWidget);

    await tester.tap(find.text('Invia richiesta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.lastCreate, isNull, reason: 'no blind request');
    // Inline error plus the toast: the message now appears at least twice.
    expect(find.text(noteHint), findsAtLeastNWidgets(2));

    await tester.enterText(find.byType(TextField).last, 'Visita medica');
    await tester.pumpAndSettle();
    expect(find.byType(InlineAlert), findsNothing, reason: 'typing a note clears the error');
    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();
    expect(fake.lastCreate!['reason'], 'Visita medica');
  });

  testWidgets('an incomplete hourly permesso says what is missing instead of going dead', (
    tester,
  ) async {
    final fake = _FakeAbsenceRequestApiClient();
    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();
    await pickType(tester, 'ROL');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Invia richiesta'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Invia richiesta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.lastCreate, isNull);
    expect(find.text(partialHint), findsAtLeastNWidgets(1));
  });

  testWidgets('a normal permesso with no note submits', (tester) async {
    final fake = _FakeAbsenceRequestApiClient();
    await tester.pumpWidget(_buildScreen(fake));
    await tester.pumpAndSettle();
    await pickType(tester, 'Permesso retribuito');

    expect(find.text(noteHint), findsNothing);
    await tester.tap(find.text('Invia richiesta'));
    await tester.pumpAndSettle();
    expect(fake.lastCreate!['reason'], isNull);
  });
}
