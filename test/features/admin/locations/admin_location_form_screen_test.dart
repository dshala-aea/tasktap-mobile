// test/features/admin/locations/admin_location_form_screen_test.dart
//
// Covers the fields added to Sedi CRUD in this pass (Gap 3 of the feature audit):
// - plain numeric latitude/longitude fields (no map-picker widget exists anywhere in this app,
//   so this is the documented fallback, not a placeholder for one).
// - `initialCustomerId`, used when the form is pushed pre-scoped from the customer detail
//   screen's Sedi section.
//
// CRITICAL: this form watches `allLocationsProvider`/`allCustomersProvider` (Drift streams), so
// every test ends with an explicit unmount (`teardown`) — otherwise Drift's StreamQueryStore
// leaves a pending Timer behind and the test framework fails the *next* test with "A Timer is
// still pending". Mirrors the documented convention in admin_cantiere_detail_screen_test.dart.
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
import 'package:tasktap_mobile/features/admin/locations/admin_location_form_screen.dart';

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

  Widget wrap(Widget child) => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(mockDio),
      isOnlineProvider.overrideWithValue(true),
    ],
    child: MaterialApp(home: child),
  );

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    await tester.pumpWidget(wrap(child));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  testWidgets('pre-selects the customer passed via initialCustomerId', (tester) async {
    await seedCustomer('cust-1', name: 'ACME Srl');
    when(
      () => mockDio.post<Map<String, dynamic>>('/api/locations', data: any(named: 'data')),
    ).thenAnswer((_) async => _okResponse({'id': 'loc-1'}, '/api/locations'));

    await pump(tester, const AdminLocationFormScreen(initialCustomerId: 'cust-1'));

    expect(find.text('ACME Srl'), findsOneWidget);

    // Field order in the form: Nome, Indirizzo, Città, CAP, Telefono, Latitudine, Longitudine,
    // Note — the Cliente selector above them is a DropdownButtonFormField, not a TextFormField.
    await tester.enterText(find.byType(TextFormField).at(0), 'Sede Nord');
    await tester.tap(find.text('Crea sede'));
    await tester.pumpAndSettle();

    final captured = verify(
      () => mockDio.post<Map<String, dynamic>>('/api/locations', data: captureAny(named: 'data')),
    ).captured.single as Map;
    expect(captured['customerId'], 'cust-1');

    await teardown(tester);
  });

  testWidgets('create sends latitude/longitude when filled in', (tester) async {
    await seedCustomer('cust-1');
    when(
      () => mockDio.post<Map<String, dynamic>>('/api/locations', data: any(named: 'data')),
    ).thenAnswer((_) async => _okResponse({'id': 'loc-1'}, '/api/locations'));

    await pump(tester, const AdminLocationFormScreen(initialCustomerId: 'cust-1'));

    // Field order: Nome(0), Indirizzo(1), Città(2), CAP(3), Telefono(4), Latitudine(5),
    // Longitudine(6), Note(7).
    await tester.enterText(find.byType(TextFormField).at(0), 'Sede Nord');
    await tester.enterText(find.byType(TextFormField).at(5), '45.4642'); // Latitudine
    await tester.enterText(find.byType(TextFormField).at(6), '9.19'); // Longitudine
    await tester.tap(find.text('Crea sede'));
    await tester.pumpAndSettle();

    final captured = verify(
      () => mockDio.post<Map<String, dynamic>>('/api/locations', data: captureAny(named: 'data')),
    ).captured.single as Map;
    expect(captured['latitude'], 45.4642);
    expect(captured['longitude'], 9.19);

    await teardown(tester);
  });

  testWidgets('edit mode pre-fills latitude/longitude from the cached location', (tester) async {
    await seedCustomer('cust-1');
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Nord',
            latitude: const Value(45.4642),
            longitude: const Value(9.19),
          ),
        );

    await pump(tester, const AdminLocationFormScreen(locationId: 'loc-1'));

    // find.text also matches an EditableText's current value, so this asserts the controllers
    // were actually pre-filled from the cached location, not just that the string exists on
    // screen somewhere.
    expect(find.text('45.4642'), findsOneWidget);
    expect(find.text('9.19'), findsOneWidget);

    await teardown(tester);
  });
}
