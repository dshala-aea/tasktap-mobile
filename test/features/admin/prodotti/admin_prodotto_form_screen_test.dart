// dart format width=100
// test/features/admin/prodotti/admin_prodotto_form_screen_test.dart
//
// Feature audit module #10 (Prodotti/Servizi), Gaps 1/2/7: the original scaffold form only ever
// collected name/customerId/locationId/description/serialNumber/warrantyExpiryDate/notes. This
// covers the new commercial (codice/categoria/um/prezzoAcquisto/prezzoVendita) and lifecycle
// (marca/modello/tipo/dataInstallazione/ultimaManutenzione/prossimaManutenzione/contrattoId)
// fields, plus externalId:
//   - creating with the new fields filled in sends them under their Italian wire names;
//   - editing prefills every new field, including reading `marchio` (not `marca`) back off the
//     prodotto map for the Marca field — the one field whose Dart param name and wire name differ;
//   - the Contratto picker is fed by a live GET /api/contracts scoped to the selected customer
//     (no local Drift mirror for contracts, same shape as Squadre/Commesse elsewhere in admin).

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_form_screen.dart';

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
        '/api/contracts',
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer(
      (_) async => _ok({
        'items': [
          {'id': 'contr-1', 'name': 'Manutenzione annuale'},
        ],
      }, '/api/contracts'),
    );

    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/prodottoassistenza',
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok({'id': 'new-prod'}, '/api/prodottoassistenza'));

    when(
      () => mockDio.put<dynamic>(
        any(that: contains('/api/prodottoassistenza/')),
        data: any(named: 'data'),
      ),
    ).thenAnswer((_) async => _ok(null, '/api/prodottoassistenza/prod-1'));
  });

  tearDown(() async => db.close());

  Widget buildHarness({Map<String, dynamic>? prodotto}) {
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
          builder: (context, state) => AdminProdottoFormScreen(prodotto: prodotto),
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
  /// admin_cantiere_form_screen_test.dart's own convention for the same reason.
  Future<void> openForm(WidgetTester tester, {Map<String, dynamic>? prodotto}) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    await tester.pumpWidget(buildHarness(prodotto: prodotto));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri form'));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('create sends the new commercial + lifecycle fields (Gaps 1/2/7)', () {
    testWidgets('fills every new field and sends it under its wire name', (tester) async {
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Caldaia');

      // Cliente
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Srl').last);
      await tester.pumpAndSettle();

      // Sede
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede Milano').last);
      await tester.pumpAndSettle();

      // Codice — the second TextFormField on the form (after Nome).
      await tester.enterText(find.byType(TextFormField).at(1), 'PROD-001');

      // Contratto — scoped to the now-selected cliente.
      await tester.tap(find.byType(DropdownButtonFormField<String?>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manutenzione annuale').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea prodotto'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['name'], 'Caldaia');
      expect(captured['customerId'], 'cust-1');
      expect(captured['locationId'], 'loc-1');
      expect(captured['codice'], 'PROD-001');
      expect(captured['contrattoId'], 'contr-1');
      await teardown(tester);
    });

    testWidgets('omits the new fields when left blank', (tester) async {
      await openForm(tester);

      await tester.enterText(find.byType(TextFormField).first, 'Caldaia');
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Srl').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede Milano').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea prodotto'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      for (final key in ['codice', 'marchio', 'categoria', 'contrattoId']) {
        expect(captured.containsKey(key), isFalse, reason: '"$key" should be omitted');
      }
      await teardown(tester);
    });
  });

  group('editing prefills the new fields (Gaps 1/2/7)', () {
    testWidgets('reads "marchio" off the prodotto map into the Marca field, re-sends on save', (
      tester,
    ) async {
      await openForm(
        tester,
        prodotto: {
          'id': 'prod-1',
          'name': 'Caldaia',
          'customerId': 'cust-1',
          'locationId': 'loc-1',
          'codice': 'PROD-001',
          'marchio': 'Baxi',
          'isActive': true,
        },
      );

      expect(find.text('Baxi'), findsOneWidget);
      expect(find.text('PROD-001'), findsOneWidget);

      await tester.tap(find.text('Salva modifiche'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>(
          '/api/prodottoassistenza/prod-1',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['marchio'], 'Baxi');
      expect(captured['codice'], 'PROD-001');
      await teardown(tester);
    });

    testWidgets('shows the Attivo toggle only in edit mode', (tester) async {
      await openForm(tester);
      expect(find.text('Attivo'), findsNothing);
      await teardown(tester);
    });
  });
}
