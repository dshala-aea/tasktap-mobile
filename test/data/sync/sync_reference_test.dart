import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';

class MockDio extends Mock implements Dio {}

Response<Map<String, dynamic>> ok(Map<String, dynamic> data) => Response(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: '/api/sync/mobile'),
);

Map<String, dynamic> customerJson(String id) => {
  'id': id,
  'tenantId': 'x',
  'createdAt': '2026-10-01T00:00:00Z',
  'companyName': 'Cliente $id',
};

/// The base payload, with the customer set this sync carries. The reference prune is keyed on this
/// set, so the tests vary it to change what the payload vouches for.
Map<String, dynamic> base({List<String> customerIds = const ['cu1']}) => {
  'syncedAt': '2026-10-08T08:00:00Z',
  'since': null,
  'customers': customerIds.map(customerJson).toList(),
  'tickets': <Object>[],
};

Map<String, dynamic> contractJson(String id, {String customerId = 'cu1'}) => {
  'id': id,
  'tenantId': 'x',
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': null,
  'name': 'Manutenzione $id',
  'customerId': customerId,
  'locationId': null,
  'startDate': '2026-01-01T00:00:00Z',
  'endDate': null,
  'isActive': true,
  'numero': 'N-$id',
  'codice': null,
  'tipo': 0,
  'externalId': null,
};

Map<String, dynamic> commessaJson(String id, {String? customerId = 'cu1'}) => {
  'id': id,
  'tenantId': 'x',
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': null,
  'codice': 'C-$id',
  'descrizione': null,
  'customerId': customerId,
  'isActive': true,
  'stato': null,
  'externalId': null,
};

Map<String, dynamic> prodottoJson(String id, {String customerId = 'cu1'}) => {
  'id': id,
  'tenantId': 'x',
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': null,
  'name': 'Caldaia $id',
  'customerId': customerId,
  'locationId': 'l1',
  'isActive': true,
  'codice': 'P-$id',
  'serialNumber': null,
  'categoria': null,
  'marchio': null,
  'externalId': null,
};

Map<String, dynamic> agentJson(String id) => {
  'id': id,
  'tenantId': 'x',
  'createdAt': '2026-10-01T00:00:00Z',
  'updatedAt': null,
  'nome': 'Agente $id',
  'email': null,
  'cellulare': null,
  'isActive': true,
};

Map<String, dynamic> reference() => {
  'contracts': [contractJson('c1')],
  'commesse': [commessaJson('m1')],
  'prodottiAssistenza': [prodottoJson('p1')],
  'agents': [agentJson('a1')],
};

void main() {
  late AppDatabase db;
  late MockDio dio;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    dio = MockDio();
  });
  tearDown(() => db.close());

  void respondWith(Map<String, dynamic> body) {
    when(
      () => dio.get<Map<String, dynamic>>(
        any(),
        queryParameters: any(named: 'queryParameters'),
      ),
    ).thenAnswer((_) async => ok(body));
  }

  test('a payload with the reference members fills the local mirror', () async {
    respondWith({...base(), ...reference()});
    await SyncService(db: db, dio: dio).sync();

    expect(
      (await db.select(db.contracts).get()).single.name,
      'Manutenzione c1',
    );
    expect((await db.select(db.commesse).get()).single.codice, 'C-m1');
    expect(
      (await db.select(db.prodottiAssistenza).get()).single.name,
      'Caldaia p1',
    );
    expect((await db.select(db.agents).get()).single.nome, 'Agente a1');
  });

  /// An older backend omits the four reference members entirely. That must NOT read as "every
  /// reference row was deleted": a device talking to a server that has not been upgraded (or an
  /// old reverse-proxy cache) keeps the mirror it already has.
  test(
    'a payload from an older backend leaves every cached reference row alone',
    () async {
      respondWith({...base(), ...reference()});
      await SyncService(db: db, dio: dio).sync();

      respondWith(base()); // none of the four reference keys at all
      await SyncService(db: db, dio: dio).sync();

      expect(await db.select(db.contracts).get(), hasLength(1));
      expect(await db.select(db.commesse).get(), hasLength(1));
      expect(await db.select(db.prodottiAssistenza).get(), hasLength(1));
      expect(await db.select(db.agents).get(), hasLength(1));
    },
  );

  /// Each entity is gated by its own flag, not by a single "reference" switch. A payload that
  /// carries an empty `commesse` for a customer it carries prunes that customer's commesse, while
  /// every other table — whose keys are absent from this payload — is left untouched.
  test('each carries flag gates its own table, independently', () async {
    respondWith({...base(), ...reference()});
    await SyncService(db: db, dio: dio).sync();

    respondWith({...base(), 'commesse': <Object>[]});
    await SyncService(db: db, dio: dio).sync();

    expect(await db.select(db.commesse).get(), isEmpty);
    expect(await db.select(db.contracts).get(), hasLength(1));
    expect(await db.select(db.prodottiAssistenza).get(), hasLength(1));
    expect(await db.select(db.agents).get(), hasLength(1));
  });

  test(
    "a payload that no longer lists a carried customer's contract removes it",
    () async {
      respondWith({...base(), ...reference()});
      await SyncService(db: db, dio: dio).sync();

      respondWith({
        ...base(),
        'contracts': <Object>[],
      }); // same customer, no contracts
      await SyncService(db: db, dio: dio).sync();

      expect(await db.select(db.contracts).get(), isEmpty);
    },
  );

  test('a contract of a customer absent from the payload survives', () async {
    respondWith({...base(), ...reference()});
    await SyncService(db: db, dio: dio).sync();

    // A payload about a different customer says nothing about cu1 — absence is not deletion.
    respondWith({
      ...base(customerIds: ['cu2']),
      'contracts': <Object>[],
    });
    await SyncService(db: db, dio: dio).sync();

    expect(await db.select(db.contracts).get(), hasLength(1));
  });
}
