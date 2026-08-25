// dart format width=100
// test/features/admin/contracts/admin_contract_form_screen_test.dart
//
// Feature audit module #11 (Fatturazione/Contratti), Gap A: the original scaffold form only ever
// collected name/customerId/locationId/description/startDate/endDate/frequencyValue/
// frequencyUnit/price/notes. This covers the new numero/codice/tipo/externalId/autoRenewal/
// scadenzaGiorni/condizioni fields and the prodottoAssistenzaId picker (scoped by customer,
// mirroring admin_prodotto_form_screen.dart's own Contratto picker in reverse), plus the
// frequencyUnit fix: the backend's ContractFrequencyUnit carries its own
// [JsonConverter(typeof(JsonStringEnumConverter))] (Contract.cs), so the wire shape is the
// string "Days"/"Months"/"Years", not the ordinal int this form used to send.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/contracts/admin_contract_form_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Acme Srl',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ),
        );

    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok({
        'items': [
          {'id': 'prod-1', 'name': 'Caldaia'},
        ],
      }, '/api/prodottoassistenza'),
    );

    when(
      () => mockDio.post<Map<String, dynamic>>('/api/contracts', data: any(named: 'data')),
    ).thenAnswer((_) async => _ok({'id': 'new-contr'}, '/api/contracts'));

    when(
      () => mockDio.put<dynamic>(any(that: contains('/api/contracts/')), data: any(named: 'data')),
    ).thenAnswer((_) async => _ok(null, '/api/contracts/contr-1'));
  });

  tearDown(() async => db.close());

  Widget buildHarness({Map<String, dynamic>? contract}) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/form'),
                child: const Text('Apri form'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          builder: (context, state) => AdminContractFormScreen(contract: contract),
        ),
      ],
    );

    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
        isOnlineProvider.overrideWithValue(true),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// Tall surface: this form's field count roughly doubled — mirrors
  /// admin_prodotto_form_screen_test.dart's own convention for the same reason.
  Future<void> openForm(WidgetTester tester, {Map<String, dynamic>? contract}) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    await tester.pumpWidget(buildHarness(contract: contract));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri form'));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('create sends the new Gap A fields under their wire names', () {
    testWidgets('fills every new field and sends frequencyUnit as a string, not an int', (
      tester,
    ) async {
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Manutenzione annuale');
      // Numero — the second TextFormField (after Nome).
      await tester.enterText(find.byType(TextFormField).at(1), 'CTR-2026-001');
      // Codice — the third.
      await tester.enterText(find.byType(TextFormField).at(2), 'C-001');

      // Cliente — first `<String>` dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Srl').last);
      await tester.pumpAndSettle();

      // Prodotto in assistenza — first `<String?>` dropdown, scoped to the now-selected cliente.
      await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Caldaia').last);
      await tester.pumpAndSettle();

      // Tipo — second `<String?>` dropdown.
      await tester.tap(find.byType(DropdownButtonFormField<String?>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manutenzione').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea contratto'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/contracts', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['name'], 'Manutenzione annuale');
      expect(captured['numero'], 'CTR-2026-001');
      expect(captured['codice'], 'C-001');
      expect(captured['customerId'], 'cust-1');
      expect(captured['prodottoAssistenzaId'], 'prod-1');
      expect(captured['tipo'], 'Manutenzione');
      expect(captured['frequencyUnit'], 'Months');
      expect(captured['frequencyUnit'], isA<String>());
      expect(captured['autoRenewal'], false);
      await teardown(tester);
    });

    testWidgets('omits the new optional fields when left blank', (tester) async {
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Manutenzione annuale');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Srl').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea contratto'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/contracts', data: captureAny(named: 'data')),
      ).captured.single as Map;
      for (final key in [
        'numero',
        'codice',
        'tipo',
        'externalId',
        'scadenzaGiorni',
        'condizioni',
        'prodottoAssistenzaId',
      ]) {
        expect(captured.containsKey(key), isFalse, reason: '"$key" should be omitted');
      }
      await teardown(tester);
    });

    testWidgets('the Rinnovo automatico toggle sends autoRenewal: true', (tester) async {
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Manutenzione annuale');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Srl').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppToggle));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea contratto'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>('/api/contracts', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['autoRenewal'], true);
      await teardown(tester);
    });
  });

  group('editing prefills the new Gap A fields', () {
    testWidgets('reads a string frequencyUnit off the contract map, re-sends it on save', (
      tester,
    ) async {
      await openForm(
        tester,
        contract: {
          'id': 'contr-1',
          'name': 'Manutenzione annuale',
          'customerId': 'cust-1',
          'numero': 'CTR-2026-001',
          'codice': 'C-001',
          'tipo': 'Assistenza',
          'frequencyUnit': 'Years',
          'frequencyValue': 2,
          'startDate': '2026-01-01T00:00:00Z',
        },
      );

      expect(find.text('CTR-2026-001'), findsOneWidget);
      expect(find.text('C-001'), findsOneWidget);
      expect(find.text('Anni'), findsOneWidget);

      await tester.tap(find.text('Salva modifiche'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>('/api/contracts/contr-1', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['frequencyUnit'], 'Years');
      expect(captured['numero'], 'CTR-2026-001');
      expect(captured['codice'], 'C-001');
      expect(captured['tipo'], 'Assistenza');
      await teardown(tester);
    });

    testWidgets('falls back to Mesi when frequencyUnit is missing or unrecognized', (
      tester,
    ) async {
      await openForm(
        tester,
        contract: {
          'id': 'contr-1',
          'name': 'Manutenzione annuale',
          'customerId': 'cust-1',
          'startDate': '2026-01-01T00:00:00Z',
        },
      );

      expect(find.text('Mesi'), findsOneWidget);
      await teardown(tester);
    });
  });
}
