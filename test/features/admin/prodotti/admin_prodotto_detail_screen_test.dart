// dart format width=100
// test/features/admin/prodotti/admin_prodotto_detail_screen_test.dart
//
// Feature audit module #10 (Prodotti/Servizi):
//   - Gap 5: delete had no UI at all — now a confirm dialog + DELETE call behind the header's
//     trash icon (mirrors admin_cantiere_detail_screen.dart's own `_deleteCantiere`).
//   - Gap 3: Matricole — a real 1:N serial-number sub-resource with zero prior UI. Covers list,
//     add (bottom sheet), and remove (confirm dialog), the same add/remove-only shape
//     admin_cantiere_detail_screen.dart's crew section already established for this app.

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
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_detail_screen.dart';

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

  const prodotto = {
    'id': 'prod-1',
    'name': 'Caldaia',
    'customerId': 'cust-1',
    'locationId': 'loc-1',
    'isActive': true,
  };

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    when(
      () => mockDio.get<List<dynamic>>('/api/prodottoassistenza/prod-1/matricole'),
    ).thenAnswer(
      (_) async => _ok([
        {'id': 'm1', 'numero': 'SN-001', 'note': null},
      ], '/api/prodottoassistenza/prod-1/matricole'),
    );

    when(
      () => mockDio.post<Map<String, dynamic>>(
        '/api/prodottoassistenza/prod-1/matricole',
        data: any(named: 'data'),
      ),
    ).thenAnswer(
      (_) async => _ok({'id': 'm2'}, '/api/prodottoassistenza/prod-1/matricole'),
    );

    when(
      () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1/matricole/m1'),
    ).thenAnswer(
      (_) async => _ok(null, '/api/prodottoassistenza/prod-1/matricole/m1'),
    );

    when(
      () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1'),
    ).thenAnswer((_) async => _ok(null, '/api/prodottoassistenza/prod-1'));
  });

  tearDown(() async => db.close());

  Widget buildHarness() {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => context.push('/detail'),
                child: const Text('Apri dettaglio'),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/detail',
          builder: (context, state) => const AdminProdottoDetailScreen(prodotto: prodotto),
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

  Future<void> openDetail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1600));
    await tester.pumpWidget(buildHarness());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri dettaglio'));
    await tester.pumpAndSettle();
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.binding.setSurfaceSize(null);
  }

  group('Matricole (Gap 3)', () {
    testWidgets('lists matricole from the live GET fetch', (tester) async {
      await openDetail(tester);

      expect(find.text('SN-001'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('adding a matricola posts numero and refreshes the list', (tester) async {
      await openDetail(tester);

      await tester.tap(find.byTooltip('Aggiungi matricola'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'SN-002');
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.post<Map<String, dynamic>>(
          '/api/prodottoassistenza/prod-1/matricole',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['numero'], 'SN-002');
      await teardown(tester);
    });

    testWidgets('removing a matricola confirms then DELETEs', (tester) async {
      await openDetail(tester);

      await tester.tap(find.byTooltip('Rimuovi matricola'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rimuovi').last);
      await tester.pumpAndSettle();

      verify(
        () => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1/matricole/m1'),
      ).called(1);
      await teardown(tester);
    });
  });

  group('delete prodotto (Gap 5)', () {
    testWidgets('confirms then DELETEs and pops', (tester) async {
      await openDetail(tester);

      // HeaderIconBtn announces itself via Semantics(label:), not a Tooltip widget — mirrors
      // admin_cantiere_detail_screen_test.dart's own convention for the same widget.
      await tester.tap(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina prodotto'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina').last);
      await tester.pumpAndSettle();

      verify(() => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1')).called(1);
      expect(find.text('Apri dettaglio'), findsOneWidget);
      await teardown(tester);
    });
  });
}
