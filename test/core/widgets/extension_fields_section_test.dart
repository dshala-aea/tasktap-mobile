// dart format width=100
// Covers ExtensionFieldsSection's field-type dispatch (text/number/boolean/date/select, with an
// unrecognized FieldType falling back to plain text rather than crashing — see the widget's own
// class doc comment) and its save gate (disabled until something changes, then a single PUT with
// every current value).

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/core/widgets/app_text_field.dart';
import 'package:tasktap_mobile/core/widgets/app_toggle.dart';
import 'package:tasktap_mobile/core/widgets/extension_fields_section.dart';
import 'package:tasktap_mobile/data/extension_fields/extension_fields_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;

class _FakeExtensionFieldsApiClient implements ExtensionFieldsApiClient {
  _FakeExtensionFieldsApiClient({
    required this.defs,
    required this.values,
    this.failDefinitions = false,
  });

  final List<ExtensionFieldDefinitionDto> defs;
  final Map<String, String> values;
  final bool failDefinitions;

  /// Every values read/write the widget attempted — a local draft must make none.
  int valueCalls = 0;

  /// What the widget last tried to save — null until a save happens.
  Map<String, String>? savedValues;

  @override
  Future<List<ExtensionFieldDefinitionDto>> fetchDefinitions(String entityType) async {
    if (failDefinitions) throw Exception('network down');
    return defs;
  }

  @override
  Future<Map<String, String>> fetchValues(String entityType, String entityId) async {
    valueCalls++;
    return values;
  }

  @override
  Future<void> saveValues(String entityType, String entityId, Map<String, String> values) async {
    valueCalls++;
    savedValues = values;
  }
}

ExtensionFieldDefinitionDto _def({
  required String key,
  required String label,
  required String fieldType,
  bool isRequired = false,
  String? options,
  String? unit,
  int sortOrder = 0,
}) => ExtensionFieldDefinitionDto(
  id: key,
  key: key,
  label: label,
  entityType: 'ticket',
  fieldType: fieldType,
  isRequired: isRequired,
  showInCard: false,
  sortOrder: sortOrder,
  options: options,
  unit: unit,
);

Widget _wrap(ExtensionFieldsApiClient client) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      isOnlineProvider.overrideWithValue(true),
      extensionFieldsApiClientProvider.overrideWithValue(client),
    ],
    child: const MaterialApp(
      home: Scaffold(body: ExtensionFieldsSection(entityType: 'ticket', entityId: 'tk-1')),
    ),
  );
}

class _MemoryStore implements ExtensionValuesStore {
  _MemoryStore(this.initial);

  final Map<String, String> initial;

  /// What the section last stored — null until it stores something.
  Map<String, String>? saved;

  @override
  Future<Map<String, String>> load() async => initial;

  @override
  Future<void> save(Map<String, String> values) async => saved = values;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('renders nothing when the tenant has no active definitions', (tester) async {
    final client = _FakeExtensionFieldsApiClient(defs: const [], values: const {});
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Altri campi'), findsNothing);
    expect(find.byType(AppTextField), findsNothing);
  });

  testWidgets('renders one input per definition, dispatched by FieldType', (tester) async {
    final client = _FakeExtensionFieldsApiClient(
      defs: [
        _def(key: 'note', label: 'Nota', fieldType: 'text'),
        _def(key: 'peso', label: 'Peso', fieldType: 'number', unit: 'kg', sortOrder: 1),
        _def(key: 'urgente', label: 'Urgente', fieldType: 'boolean', sortOrder: 2),
        _def(key: 'scadenza', label: 'Scadenza', fieldType: 'date', sortOrder: 3),
        _def(
          key: 'colore',
          label: 'Colore',
          fieldType: 'select',
          options: '["Rosso","Verde"]',
          sortOrder: 4,
        ),
        // Unrecognized FieldType — falls back to a plain text field.
        _def(key: 'misterioso', label: 'Misterioso', fieldType: 'wat', sortOrder: 5),
      ],
      values: const {'note': 'ciao', 'peso': '12.5', 'urgente': 'true', 'colore': 'Verde'},
    );
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(find.text('Altri campi'), findsOneWidget);
    // text + number + unrecognized-falls-back-to-text = 3 AppTextFields.
    expect(find.byType(AppTextField), findsNWidgets(3));
    expect(find.byType(AppToggle), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
  });

  testWidgets('a select with no usable Options falls back to a plain text field', (tester) async {
    final client = _FakeExtensionFieldsApiClient(
      defs: [_def(key: 'colore', label: 'Colore', fieldType: 'select', options: null)],
      values: const {},
    );
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(AppTextField), findsOneWidget);
  });

  testWidgets('Salva is disabled until something changes, then sends the full value set', (
    tester,
  ) async {
    final client = _FakeExtensionFieldsApiClient(
      defs: [_def(key: 'note', label: 'Nota', fieldType: 'text')],
      values: const {'note': 'vecchio'},
    );
    await tester.pumpWidget(_wrap(client));
    await tester.pumpAndSettle();

    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNull);

    await tester.enterText(find.byType(TextFormField), 'nuovo');
    await tester.pump();

    expect(tester.widget<AppButton>(find.byType(AppButton)).onPressed, isNotNull);
    expect(client.savedValues, isNull);

    await tester.tap(find.byType(AppButton));
    await tester.pump();
    await tester.pump();

    expect(client.savedValues, {'note': 'nuovo'});
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // Offline rendering rule. The mirror carries values only for the entity types listed in
  // `mirroredExtensionValueEntityTypes`; for every other type the section must render nothing
  // rather than a card of blank read-only fields that claims the entity has no custom fields.
  // ══════════════════════════════════════════════════════════════════════════════

  group('offline', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> seedDefinition(String entityType) => db
        .into(db.extensionFieldDefinitions)
        .insert(
          ExtensionFieldDefinitionsCompanion.insert(
            id: 'd1',
            key: 'zona',
            label: 'Zona',
            entityType: entityType,
            fieldType: 'text',
          ),
        );

    Widget wrapOffline(String entityType) => ProviderScope(retry: (_, _) => null, 
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(false),
        extensionFieldsApiClientProvider.overrideWithValue(
          _FakeExtensionFieldsApiClient(defs: const [], values: const {}),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ExtensionFieldsSection(entityType: entityType, entityId: 'id-1'),
        ),
      ),
    );

    testWidgets('a mirrored type still renders, read-only', (tester) async {
      await seedDefinition('ticket');

      await tester.pumpWidget(wrapOffline('ticket'));
      await tester.pumpAndSettle();

      expect(find.text('Altri campi'), findsOneWidget);
      expect(find.text('Sola lettura finché non torna la connessione.'), findsOneWidget);
      expect(find.byType(AppButton), findsNothing);
    });

    testWidgets('a type the mirror does not carry renders nothing', (tester) async {
      // A definition exists, so the section is not hidden by "this tenant configured no fields":
      // it is hidden because a product's values never reach the device.
      await seedDefinition('prodottoassistenza');

      await tester.pumpWidget(wrapOffline('prodottoassistenza'));
      await tester.pumpAndSettle();

      expect(find.text('Altri campi'), findsNothing);
      expect(find.byType(AppTextField), findsNothing);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════════
  // A rapportino draft exists only on the phone until it is submitted: its values come from, and
  // go to, the draft itself — the same online and offline, never over the network.
  // ══════════════════════════════════════════════════════════════════════════════

  group('local draft', () {
    late AppDatabase db;

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> mirror(String key, {String label = 'Zona', bool required = false}) => db
        .into(db.extensionFieldDefinitions)
        .insert(
          ExtensionFieldDefinitionsCompanion.insert(
            id: 'm-$key',
            key: key,
            label: label,
            entityType: 'report',
            fieldType: 'text',
            isRequired: Value(required),
          ),
        );

    Widget wrapLocal(
      _FakeExtensionFieldsApiClient client,
      _MemoryStore store, {
      bool online = true,
    }) => ProviderScope(
      retry: (_, _) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
        extensionFieldsApiClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ExtensionFieldsSection(entityType: 'report', entityId: 'rep-1', localStore: store),
        ),
      ),
    );

    testWidgets('online: shows the draft\'s own values and never calls the values endpoints', (
      tester,
    ) async {
      final client = _FakeExtensionFieldsApiClient(
        defs: [_def(key: 'zona', label: 'Zona', fieldType: 'text')],
        values: const {'zona': 'DA-SERVER'},
      );
      final store = _MemoryStore({'zona': 'Nord'});

      await tester.pumpWidget(wrapLocal(client, store));
      await tester.pumpAndSettle();

      expect(find.text('Nord'), findsOneWidget);
      expect(find.text('DA-SERVER'), findsNothing);
      expect(client.valueCalls, 0, reason: 'the server has no row for an unsent draft: it would 404');
      expect(find.byType(AppButton), findsNothing, reason: 'no Save button: edits are stored as typed');
    });

    testWidgets('offline: same fields, still editable, from the mirror', (tester) async {
      await mirror('zona');
      final client = _FakeExtensionFieldsApiClient(defs: const [], values: const {});
      final store = _MemoryStore({'zona': 'Nord'});

      await tester.pumpWidget(wrapLocal(client, store, online: false));
      await tester.pumpAndSettle();

      expect(find.text('Altri campi'), findsOneWidget);
      expect(find.text('Nord'), findsOneWidget);
      expect(find.textContaining('Sola lettura'), findsNothing);
    });

    testWidgets('typing is stored on the draft after a short pause, as the full value set', (
      tester,
    ) async {
      final client = _FakeExtensionFieldsApiClient(
        defs: [
          _def(key: 'zona', label: 'Zona', fieldType: 'text'),
          _def(key: 'lotto', label: 'Lotto', fieldType: 'text', sortOrder: 1),
        ],
        values: const {},
      );
      final store = _MemoryStore({'lotto': '7'});

      await tester.pumpWidget(wrapLocal(client, store));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Sud');
      await tester.pump(const Duration(milliseconds: 500));

      expect(store.saved, {'zona': 'Sud', 'lotto': '7'});
    });

    testWidgets('an edit made just before leaving the step is not lost', (tester) async {
      final client = _FakeExtensionFieldsApiClient(
        defs: [_def(key: 'zona', label: 'Zona', fieldType: 'text')],
        values: const {},
      );
      final store = _MemoryStore({});

      await tester.pumpWidget(wrapLocal(client, store));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Est');
      // Leave before the debounce fires.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(store.saved, {'zona': 'Est'});
    });

    testWidgets('the mirror shows at once and the live list adds a new field without touching '
        'what was typed', (tester) async {
      await mirror('zona');
      final client = _FakeExtensionFieldsApiClient(
        defs: [
          _def(key: 'zona', label: 'Zona', fieldType: 'text'),
          _def(key: 'lotto', label: 'Lotto', fieldType: 'text', sortOrder: 1),
        ],
        values: const {},
      );
      final store = _MemoryStore({'zona': 'Nord'});

      await tester.pumpWidget(wrapLocal(client, store));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsNWidgets(2), reason: 'the live list added "Lotto"');
      expect(find.text('Nord'), findsOneWidget);
    });

    testWidgets('a failed live read keeps the mirrored fields instead of hiding the section', (
      tester,
    ) async {
      await mirror('zona');
      final client = _FakeExtensionFieldsApiClient(
        defs: const [],
        values: const {},
        failDefinitions: true,
      );

      await tester.pumpWidget(wrapLocal(client, _MemoryStore({})));
      await tester.pumpAndSettle();

      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Impossibile caricare i campi aggiuntivi.'), findsNothing);
    });

    testWidgets('a failed read with no mirror says so and offers a retry', (tester) async {
      final client = _FakeExtensionFieldsApiClient(
        defs: const [],
        values: const {},
        failDefinitions: true,
      );

      await tester.pumpWidget(wrapLocal(client, _MemoryStore({})));
      await tester.pumpAndSettle();

      expect(find.text('Impossibile caricare i campi aggiuntivi.'), findsOneWidget);
      expect(find.text('Riprova'), findsOneWidget);
    });
  });
}
