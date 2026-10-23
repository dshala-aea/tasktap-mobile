// dart format width=100
//
// The Asset hub list with no signal.
//
// It was a live-only call, so tapping Asset in the Altro hub offline produced an error screen —
// on the surface where a technician checks what a customer actually has. The mirror now answers,
// with one honest caveat: it only holds the customers this phone carries, and the screen says so.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_list_screen.dart';

class MockDio extends Mock implements Dio {}

Response<T> _ok<T>(T data) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: '/'));

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
    when(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => _ok({'items': <dynamic>[]}));

    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 't',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'ACME Srl',
          ),
        );
    await db
        .into(db.prodottiAssistenza)
        .insert(
          ProdottiAssistenzaCompanion.insert(
            id: 'p1',
            tenantId: 't',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Caldaia condominio',
            customerId: 'cust-1',
            locationId: 'loc-1',
            codice: const Value('CD-01'),
          ),
        );
  });

  tearDown(() async => db.close());

  Future<void> pump(WidgetTester tester, {required bool online, String? query}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(mockDio),
          isOnlineProvider.overrideWithValue(online),
          if (query != null) adminProdottiQueryProvider.overrideWith((ref) => query),
        ],
        child: const MaterialApp(home: AdminProdottoListScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offline lists the mirrored assets with their customer, and says it is partial', (
    tester,
  ) async {
    await pump(tester, online: false);

    expect(find.text('CD-01 · Caldaia condominio'), findsOneWidget);
    // Whose asset it is — the reason the row exists.
    expect(find.textContaining('ACME Srl'), findsOneWidget);
    expect(
      find.text('Offline: solo gli asset dei clienti sincronizzati su questo telefono.'),
      findsOneWidget,
    );
    verifyNever(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    );
  });

  testWidgets('offline, the search text filters the mirrored rows locally', (tester) async {
    await db
        .into(db.prodottiAssistenza)
        .insert(
          ProdottiAssistenzaCompanion.insert(
            id: 'p2',
            tenantId: 't',
            createdAt: DateTime.utc(2026, 1, 1),
            name: 'Pompa di calore',
            customerId: 'cust-1',
            locationId: 'loc-1',
          ),
        );

    await pump(tester, online: false, query: 'pompa');

    expect(find.text('Pompa di calore'), findsOneWidget);
    expect(find.text('CD-01 · Caldaia condominio'), findsNothing);
    verifyNever(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    );
  });

  testWidgets('online the API is the answer, with no offline banner', (tester) async {
    await pump(tester, online: true);

    verify(
      () => mockDio.get<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).called(1);
    expect(
      find.text('Offline: solo gli asset dei clienti sincronizzati su questo telefono.'),
      findsNothing,
    );
    // Online the list does not fall back to the mirror: an empty API answer is an empty list.
    expect(find.text('Nessun asset'), findsOneWidget);
  });
}
