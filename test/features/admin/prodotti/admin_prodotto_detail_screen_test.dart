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
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
// Hides the Drift row class of the same name: `Entitlement` below is the entitlement repository's.
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/prodotti/admin_prodotto_detail_screen.dart';

class MockDio extends Mock implements Dio {}

/// Answers the extension-fields reads/writes the "Altri campi" section makes, and records what it
/// was asked for — the entity-type key is the part worth pinning: an asset is
/// `prodottoassistenza` to the backend, not `asset`.
class _FakeExtensionFieldsApiClient implements ExtensionFieldsApiClient {
  _FakeExtensionFieldsApiClient({required this.defs, required this.values});

  final List<ExtensionFieldDefinitionDto> defs;
  final Map<String, String> values;

  String? definitionsEntityType;
  (String, String)? valuesKey;
  (String, String, Map<String, String>)? saved;

  @override
  Future<List<ExtensionFieldDefinitionDto>> fetchDefinitions(String entityType) async {
    definitionsEntityType = entityType;
    return defs;
  }

  @override
  Future<Map<String, String>> fetchValues(String entityType, String entityId) async {
    valuesKey = (entityType, entityId);
    return values;
  }

  @override
  Future<void> saveValues(String entityType, String entityId, Map<String, String> values) async {
    saved = (entityType, entityId, values);
    this.values
      ..clear()
      ..addAll(values);
  }
}

/// Answers the extension-fields reads/writes the "Altri campi" section makes, and records what it
/// was asked for — the entity-type key is the part worth pinning: an asset is
/// `prodottoassistenza` to the backend, not `asset`.
class _FakeExtensionFieldsApiClient implements ExtensionFieldsApiClient {
  _FakeExtensionFieldsApiClient({required this.defs, required this.values});

  final List<ExtensionFieldDefinitionDto> defs;
  final Map<String, String> values;

  String? definitionsEntityType;
  (String, String)? valuesKey;
  (String, String, Map<String, String>)? saved;

  @override
  Future<List<ExtensionFieldDefinitionDto>> fetchDefinitions(String entityType) async {
    definitionsEntityType = entityType;
    return defs;
  }

  @override
  Future<Map<String, String>> fetchValues(String entityType, String entityId) async {
    valuesKey = (entityType, entityId);
    return values;
  }

  @override
  Future<void> saveValues(String entityType, String entityId, Map<String, String> values) async {
    saved = (entityType, entityId, values);
    this.values
      ..clear()
      ..addAll(values);
  }
}

Response<T> _ok<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

Entitlement _entitlementWith(Set<String> capabilities) => Entitlement(
  features: const {},
  capabilities: capabilities,
  seatType: 'office',
  fetchedAt: DateTime.utc(2026, 9, 23),
);

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;
  late _FakeExtensionFieldsApiClient extensionFields;

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
    // One tenant-configured asset field, the ordinary case: an admin added a custom field and the
    // technician has already filled it in once.
    extensionFields = _FakeExtensionFieldsApiClient(
      defs: [
        const ExtensionFieldDefinitionDto(
          id: 'def-1',
          key: 'codice_impianto',
          label: 'Codice impianto',
          entityType: 'prodottoassistenza',
          fieldType: 'text',
          isRequired: false,
          showInCard: false,
          sortOrder: 0,
        ),
      ],
      values: {'codice_impianto': 'IMP-9'},
    );

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

  // Edit and delete are contract-write operations; the tests below act as someone who holds it.
  var entitlement = _entitlementWith({'contratti.contract.write'});
  setUp(() => entitlement = _entitlementWith({'contratti.contract.write'}));

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
        extensionFieldsApiClientProvider.overrideWithValue(extensionFields),
        cachedEntitlementProvider.overrideWith((ref) => Future.value(entitlement)),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> openDetail(WidgetTester tester, {Size size = const Size(800, 1600)}) async {
    await tester.binding.setSurfaceSize(size);
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
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina asset'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina').last);
      await tester.pumpAndSettle();

      verify(() => mockDio.delete<dynamic>('/api/prodottoassistenza/prod-1')).called(1);
      expect(find.text('Apri dettaglio'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('a user without contract-write is not offered edit or delete', (tester) async {
      entitlement = _entitlementWith({'contratti.contract.read'});
      await openDetail(tester);

      expect(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina asset'),
        findsNothing,
      );
      expect(find.byTooltip('Modifica'), findsNothing);
      await teardown(tester);
    });
  });

  group('altri campi (asset extension fields)', () {
    testWidgets('reads the asset\'s fields under the backend\'s prodottoassistenza key', (
      tester,
    ) async {
      // The asset was the one entity a technician opens on every visit and could not fill in; the
      // key matters because the API knows it as `prodottoassistenza`, not `asset`
      // (ClickUp 12493t4r8yg).
      await openDetail(tester, size: const Size(800, 2800));

      expect(extensionFields.definitionsEntityType, 'prodottoassistenza');
      expect(extensionFields.valuesKey, ('prodottoassistenza', 'prod-1'));
      expect(find.text('Altri campi'), findsOneWidget);
      expect(find.text('Codice impianto'), findsOneWidget);
      expect(find.text('IMP-9'), findsOneWidget);
      await teardown(tester);
    });

    testWidgets('saves what the technician typed against that same key', (tester) async {
      await openDetail(tester, size: const Size(800, 2800));

      await tester.enterText(find.byType(TextFormField), 'IMP-10');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      expect(extensionFields.saved, isNotNull);
      expect((extensionFields.saved!.$1, extensionFields.saved!.$2), ('prodottoassistenza', 'prod-1'));
      expect(extensionFields.saved!.$3, {'codice_impianto': 'IMP-10'});
      await teardown(tester);
    });
  });
}
