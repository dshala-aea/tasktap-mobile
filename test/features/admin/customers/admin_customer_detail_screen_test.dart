// test/features/admin/customers/admin_customer_detail_screen_test.dart
//
// Gaps 3/7/8 of the feature audit: the customer detail screen had no Sedi, Contratti, or
// Prodotti assistenza sections at all. Sedi reads the local Drift mirror (locations are synced,
// unlike cantiere contacts/assignments); Contratti/Prodotti have no local mirror and are fetched
// live, server-filtered by customerId.
//
// CRITICAL: every test that pumps this screen (it watches several Drift streams) MUST end with
// the `teardown` helper below — mirrors the same documented convention in
// admin_cantiere_detail_screen_test.dart, otherwise Drift's StreamQueryStore leaves a pending
// Timer behind and the test framework fails the *next* test with "A Timer is still pending".
//
// The screen also stacks many sections (anagrafica, panoramica, sedi, contratti, prodotti, note,
// stato, storico interventi) in one CustomScrollView — taller than the default 800×600 test
// surface, so content past the first couple of sections lays out below the fold and `find.text`
// misses it. `pumpScreen` uses the same tall-surface convention as that same cantiere test file.
import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/customers/admin_customer_detail_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    // Overview endpoint — always hit by the (already-shipped) Panoramica card. Not under test
    // here; stubbed just so it doesn't leave a dangling unstubbed-call error in the log.
    when(
      () => mockDio.get<Map<String, dynamic>>(any(that: startsWith('/api/app/clienti/'))),
    ).thenAnswer((i) async => _okResponse({'id': 'cust-1', 'ragioneSociale': 'ACME'}, ''));

    // Contratti/Prodotti default to empty unless a test overrides them.
    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/contracts',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _okResponse({'items': <dynamic>[]}, '/api/contracts'));
    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _okResponse({'items': <dynamic>[]}, '/api/prodottoassistenza'));
  });

  tearDown(() async => db.close());

  Future<void> seedCustomer(String id, {String name = 'ACME Srl'}) async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: name,
          ),
        );
  }

  Future<void> seedLocation(String id, {required String customerId, required String name}) async {
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: customerId,
            name: name,
          ),
        );
  }

  Widget buildScreen(String customerId) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(mockDio),
      isOnlineProvider.overrideWithValue(true),
    ],
    child: MaterialApp(home: AdminCustomerDetailScreen(customerId: customerId)),
  );

  Future<void> pumpScreen(WidgetTester tester, {String customerId = 'cust-1'}) async {
    await tester.binding.setSurfaceSize(const Size(800, 2600));
    await tester.pumpWidget(buildScreen(customerId));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('Sedi section (Gap 3)', () {
    testWidgets('lists only locations belonging to this customer', (tester) async {
      await seedCustomer('cust-1');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Nord');
      await seedLocation('loc-2', customerId: 'cust-1', name: 'Sede Sud');
      await seedLocation('loc-3', customerId: 'cust-2', name: 'Sede di un altro cliente');

      await pumpScreen(tester);

      expect(find.text('Sedi'), findsOneWidget);
      expect(find.text('Sede Nord'), findsOneWidget);
      expect(find.text('Sede Sud'), findsOneWidget);
      expect(find.text('Sede di un altro cliente'), findsNothing);

      await teardown(tester);
    });

    testWidgets('shows an empty state with no sedi', (tester) async {
      await seedCustomer('cust-1');

      await pumpScreen(tester);

      expect(find.text('Nessuna sede'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('delete asks for confirmation, then calls the API on confirm', (tester) async {
      await seedCustomer('cust-1');
      await seedLocation('loc-1', customerId: 'cust-1', name: 'Sede Nord');
      when(
        () => mockDio.delete<dynamic>('/api/locations/loc-1'),
      ).thenAnswer((_) async => _okResponse(null, '/api/locations/loc-1'));

      await pumpScreen(tester);

      await tester.tap(find.byTooltip('Elimina sede'));
      await tester.pumpAndSettle();

      expect(find.text('Eliminare la sede?'), findsOneWidget);

      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      verify(() => mockDio.delete<dynamic>('/api/locations/loc-1')).called(1);

      await teardown(tester);
    });
  });

  group('Contratti section (Gap 7)', () {
    testWidgets('lists contracts fetched server-side filtered by customerId', (tester) async {
      await seedCustomer('cust-1');
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {'id': 'contr-1', 'name': 'Manutenzione annuale', 'customerId': 'cust-1', 'isActive': true},
          ],
        }, '/api/contracts'),
      );

      await pumpScreen(tester);

      // Not asserting on the section title text itself: the Panoramica overview card (already
      // shipped, out of scope here) has its own "Contratti" stat label, so `find.text('Contratti')`
      // is ambiguous on this screen. The contract's own name is unambiguous evidence the section
      // rendered its data.
      expect(find.text('Manutenzione annuale'), findsOneWidget);

      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/contracts',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured['customerId'], 'cust-1');

      await teardown(tester);
    });

    testWidgets('shows an empty state with no contracts', (tester) async {
      await seedCustomer('cust-1');

      await pumpScreen(tester);

      expect(find.text('Nessun contratto'), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Prodotti assistenza section (Gap 8)', () {
    testWidgets('lists prodotti fetched server-side filtered by customerId', (tester) async {
      await seedCustomer('cust-1');
      when(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'prod-1',
              'name': 'Caldaia condominio',
              'customerId': 'cust-1',
              'isActive': true,
              'serialNumber': 'SN-42',
            },
          ],
        }, '/api/prodottoassistenza'),
      );

      await pumpScreen(tester);

      expect(find.text('Prodotti assistenza'), findsOneWidget);
      expect(find.text('Caldaia condominio'), findsOneWidget);
      expect(find.text('SN-42'), findsOneWidget);

      final captured = verify(
        () => mockDio.get<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          queryParameters: captureAny(named: 'queryParameters'),
        ),
      ).captured.single as Map;
      expect(captured['customerId'], 'cust-1');

      await teardown(tester);
    });

    testWidgets('shows an empty state with no prodotti', (tester) async {
      await seedCustomer('cust-1');

      await pumpScreen(tester);

      expect(find.text('Nessun prodotto'), findsOneWidget);

      await teardown(tester);
    });
  });
}
