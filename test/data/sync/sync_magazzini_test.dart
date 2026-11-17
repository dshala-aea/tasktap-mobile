// The warehouses half of the sync: the rapportino material line's source.
//
// Before this member the device held no `magazzini` mirror, so offline both the "my van" default
// and the "cambia magazzino" picker needed a live REST call — the line was saved with a null
// magazzino and the submit lost the provenance the stock movement is keyed on.
//
// The member travels whole on every sync (no delta filter), so the mirror is replaced wholesale.
// The three semantics that matter and that an upsert would get wrong are pinned here: a warehouse
// the server stopped listing must disappear, an older backend (no member at all) must not look
// like "every warehouse was deleted", and an empty list must not wipe the mirror either.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show OrderingTerm, driftRuntimeOptions;
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

Map<String, dynamic> magazzinoJson(
  String id, {
  String nome = 'Magazzino',
  String tipo = 'Sede',
  String? assegnatoUserId,
  bool isActive = true,
}) => {
  'id': id,
  'tenantId': 'ten1',
  'createdAt': '2026-10-01T08:00:00Z',
  'updatedAt': null,
  'nome': nome,
  'tipo': tipo,
  'assegnatoUserId': assegnatoUserId,
  'isActive': isActive,
};

/// A payload with everything optional left out; callers add only the member under test, so an
/// absent member always means "an older backend", never "an empty collection I forgot to fill".
Map<String, dynamic> base({List<Map<String, dynamic>>? magazzini}) => {
  'syncedAt': '2026-10-08T08:00:00Z',
  'since': null,
  'customers': <Object>[],
  'tickets': <Object>[],
  'magazzini': ?magazzini,
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

  Future<List<MagazziniData>> mirrors() =>
      (db.select(db.magazzini)..orderBy([(w) => OrderingTerm.asc(w.id)])).get();

  test('a payload carrying the warehouses fills the local mirror', () async {
    respondWith(
      base(
        magazzini: [
          magazzinoJson(
            'w1',
            nome: 'Furgone Rossi',
            tipo: 'Furgone',
            assegnatoUserId: 'u1',
          ),
          magazzinoJson('w2', nome: 'Sede Milano'),
        ],
      ),
    );

    await SyncService(db: db, dio: dio).sync();

    final rows = await mirrors();
    expect(rows.map((r) => r.id), ['w1', 'w2']);
    expect(rows.map((r) => r.tipo), ['Furgone', 'Sede']);
  });

  test('the assignment and the tenant columns survive the round trip', () async {
    respondWith(
      base(
        magazzini: [
          magazzinoJson(
            'w1',
            nome: 'Furgone Rossi',
            tipo: 'Furgone',
            assegnatoUserId: 'u1',
          ),
        ],
      ),
    );

    await SyncService(db: db, dio: dio).sync();

    final row = (await mirrors()).single;
    expect(row.nome, 'Furgone Rossi');
    expect(row.tipo, 'Furgone');
    expect(row.assegnatoUserId, 'u1');
    expect(row.tenantId, 'ten1');
    // Drift keeps `dateTime()` as an epoch value and hands it back local-kinded, while `==` on
    // DateTime also compares isUtc — so compare the instant, not the kind. The mirror's contract
    // is "same moment the server sent", which is what this asserts.
    expect(row.createdAt.toUtc(), DateTime.utc(2026, 10, 1, 8));
    expect(row.updatedAt, isNull);
    expect(row.isActive, isTrue);
  });

  test('a warehouse the server stops listing removes it (wholesale replace)', () async {
    respondWith(
      base(
        magazzini: [
          magazzinoJson('w1', nome: 'Furgone Rossi', tipo: 'Furgone'),
          magazzinoJson('w2', nome: 'Sede Milano'),
        ],
      ),
    );
    await SyncService(db: db, dio: dio).sync();
    expect(await mirrors(), hasLength(2));

    // Deactivated office-side: the member carries active rows only, so the next sync simply
    // stops mentioning it. An upsert would leave it in the picker forever.
    respondWith(base(magazzini: [magazzinoJson('w1')]));
    await SyncService(db: db, dio: dio).sync();

    expect((await mirrors()).map((r) => r.id), ['w1']);
  });

  test('an older backend without the member leaves the mirror intact', () async {
    respondWith(
      base(
        magazzini: [
          magazzinoJson('w1', nome: 'Furgone Rossi', tipo: 'Furgone'),
        ],
      ),
    );
    await SyncService(db: db, dio: dio).sync();
    expect(await mirrors(), hasLength(1));

    // Key absent, not empty: nothing may be inferred about the tenant's warehouses.
    respondWith(base());
    await SyncService(db: db, dio: dio).sync();

    expect((await mirrors()).single.id, 'w1');
  });

  test('an empty list never wipes the mirror', () async {
    respondWith(base(magazzini: [magazzinoJson('w1')]));
    await SyncService(db: db, dio: dio).sync();

    respondWith(base(magazzini: const []));
    await SyncService(db: db, dio: dio).sync();

    expect((await mirrors()).single.id, 'w1');
  });
}
