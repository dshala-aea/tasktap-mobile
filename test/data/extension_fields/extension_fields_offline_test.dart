// Covers the offline half of the "Altri campi" section: the definitions the sync mirrored, the
// values the sync carried inside each entity, and the parser that turns the server's raw
// `extensionValues` text into the flat map the section renders.
//
// Before P2-7 both providers threw an offline exception, so the section silently vanished on the
// rapportino Dettagli, the ticket Dettagli and the cantiere form — exactly the screens a technician
// uses on site. The widget-level rendering is covered by
// test/core/widgets/extension_fields_section_test.dart; what is pinned here is where the data comes
// from when there is no connection.

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/extension_fields/extension_fields_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;

/// A bare container, no widget tree. Any call reaching the API client is a failure — offline must
/// never touch the wire.
class _ExplodingApiClient implements ExtensionFieldsApiClient {
  @override
  Future<List<ExtensionFieldDefinitionDto>> fetchDefinitions(String entityType) =>
      throw StateError('offline: fetchDefinitions must not be called');

  @override
  Future<Map<String, String>> fetchValues(String entityType, String entityId) =>
      throw StateError('offline: fetchValues must not be called');

  @override
  Future<void> saveValues(String entityType, String entityId, Map<String, String> values) =>
      throw StateError('offline: saveValues must not be called');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> seedDefinition(
    String id, {
    required String key,
    required String entityType,
    int sortOrder = 0,
    String fieldType = 'text',
  }) => db
      .into(db.extensionFieldDefinitions)
      .insert(
        ExtensionFieldDefinitionsCompanion.insert(
          id: id,
          key: key,
          label: 'Campo $key',
          entityType: entityType,
          fieldType: fieldType,
          sortOrder: Value(sortOrder),
        ),
      );

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(false),
        extensionFieldsApiClientProvider.overrideWithValue(_ExplodingApiClient()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  group('decodeExtensionValues', () {
    test('parses the server text into a flat key/value map', () {
      expect(decodeExtensionValues('{"zona":"Nord","note":"porta chiusa"}'), {
        'zona': 'Nord',
        'note': 'porta chiusa',
      });
    });

    /// The stored value is a JSON object whose values are not necessarily strings — the backend's
    /// `jsonb` accepts numbers and booleans, and the section renders every field from a string.
    test('stringifies non-string JSON values', () {
      expect(decodeExtensionValues('{"priorita":3,"urgente":true,"peso":1.5}'), {
        'priorita': '3',
        'urgente': 'true',
        'peso': '1.5',
      });
    });

    test('null, empty and whitespace all mean "no values recorded"', () {
      expect(decodeExtensionValues(null), isEmpty);
      expect(decodeExtensionValues(''), isEmpty);
      expect(decodeExtensionValues('   '), isEmpty);
    });

    /// A corrupt mirror must not take the whole form down with it.
    test('malformed text yields an empty map instead of throwing', () {
      expect(decodeExtensionValues('{not json'), isEmpty);
      expect(decodeExtensionValues('"a string"'), isEmpty);
      expect(decodeExtensionValues('[1,2]'), isEmpty);
    });

    test('a null JSON value renders as an empty string', () {
      expect(decodeExtensionValues('{"zona":null}'), {'zona': ''});
    });
  });

  group('definitions provider, offline', () {
    test('answers from the mirrored definitions instead of the wire', () async {
      await seedDefinition('d1', key: 'zona', entityType: 'ticket');

      final defs = await container().read(extensionFieldDefinitionsProvider('ticket').future);

      expect(defs.single.key, 'zona');
      expect(defs.single.label, 'Campo zona');
    });

    test('returns only the requested entity type, ordered by sortOrder', () async {
      await seedDefinition('d2', key: 'secondo', entityType: 'ticket', sortOrder: 2);
      await seedDefinition('d1', key: 'primo', entityType: 'ticket', sortOrder: 1);
      await seedDefinition('d3', key: 'meteo', entityType: 'cantiere', sortOrder: 1);

      final defs = await container().read(extensionFieldDefinitionsProvider('ticket').future);

      expect(defs.map((d) => d.key), ['primo', 'secondo']);
    });

    /// An empty mirror means "the last sync carried nothing readable" — the section renders nothing
    /// (its own contract) rather than failing.
    test('an empty mirror yields an empty list, not an error', () async {
      expect(await container().read(extensionFieldDefinitionsProvider('ticket').future), isEmpty);
    });
  });

  group('values provider, offline', () {
    Future<void> seedTicket(String id, String? extensionValues) => db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: id,
            tenantId: 'ten1',
            createdAt: DateTime.utc(2026, 10, 1),
            title: 'Ticket $id',
            customerId: 'cu1',
            locationId: 'loc1',
            statusId: 1,
            typeId: 1,
            extensionValues: Value(extensionValues),
          ),
        );

    test('answers from the ticket row', () async {
      await seedTicket('tk1', '{"zona":"Nord"}');

      final values = await container().read(extensionFieldValuesProvider(('ticket', 'tk1')).future);

      expect(values, {'zona': 'Nord'});
    });

    test('answers from the cantiere row', () async {
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'ca1',
              tenantId: 'ten1',
              createdAt: DateTime.utc(2026, 10, 1),
              name: 'Cantiere 1',
              extensionValues: const Value('{"meteo":"pioggia"}'),
            ),
          );

      final values = await container().read(extensionFieldValuesProvider(('cantiere', 'ca1')).future);

      expect(values, {'meteo': 'pioggia'});
    });

    test('answers from the rapportino row', () async {
      await db
          .into(db.draftReports)
          .insert(
            DraftReportsCompanion.insert(
              id: 'rp1',
              tenantId: 'ten1',
              createdAt: DateTime.utc(2026, 10, 1),
              title: 'Rapportino 1',
              insertedUserId: 'u1',
              locationId: 'loc1',
              extensionValues: const Value('{"rif":"A-12"}'),
            ),
          );

      final values = await container().read(extensionFieldValuesProvider(('report', 'rp1')).future);

      expect(values, {'rif': 'A-12'});
    });

    test('a row with no values yields an empty map', () async {
      await seedTicket('tk1', null);

      expect(
        await container().read(extensionFieldValuesProvider(('ticket', 'tk1')).future),
        isEmpty,
      );
    });

    test('an entity that is not mirrored locally yields an empty map', () async {
      expect(
        await container().read(extensionFieldValuesProvider(('customer', 'cu1')).future),
        isEmpty,
      );
    });
  });
}
