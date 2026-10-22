// The by-id reference providers, offline (P2-2).
//
// A ticket carries `contractId`/`commessaId` as bare synced columns, and until now the row behind
// them was fetched live — so "Contratto: Non disponibile offline" on a site with no signal, on a
// contract the device already held. These tests pin the three-tier rule:
//
//   online + answered   → the server, always (it may hold an edit made a minute ago);
//   online + no answer  → the mirror (the radio said online and the request died);
//   offline             → the mirror;
//   mirror empty        → TicketDetailOfflineException, never a "not found".

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart' show dioProvider;
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reference/reference_cache_repository.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_dto.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart'
    show TicketDetailOfflineException;
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';

/// Answers every request the way the test needs.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions options) respond;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) => respond(options);
}

/// [status] null means "no response at all" — the radio said online and the request died.
Dio _dioThatFails({int? status}) {
  return Dio()
    ..httpClientAdapter = _Adapter((options) async {
      throw DioException(
        requestOptions: options,
        type: status == null
            ? DioExceptionType.connectionError
            : DioExceptionType.badResponse,
        response: status == null
            ? null
            : Response<dynamic>(requestOptions: options, statusCode: status),
      );
    });
}

void main() {
  late AppDatabase db;
  late ReferenceCacheRepository repo;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
    repo = ReferenceCacheRepository(db);
  });
  tearDown(() => db.close());

  ProviderContainer container({required bool online, int? serverStatus}) {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        isOnlineProvider.overrideWithValue(online),
        dioProvider.overrideWithValue(_dioThatFails(status: serverStatus)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('offline, a mirrored contract answers by id', () async {
    await repo.upsertContracts([
      ContractSyncDto(
        id: 'c1',
        tenantId: 't',
        createdAt: DateTime.utc(2026, 1, 1),
        name: 'Manutenzione annuale',
        customerId: 'cu1',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 12, 31),
        isActive: true,
        numero: 'C-2026-01',
      ),
    ]);

    final c = container(online: false);
    final contract = await c.read(contractByIdProvider('c1').future);

    expect(contract, isNotNull);
    expect(contract!['name'], 'Manutenzione annuale');
    expect(contract['numero'], 'C-2026-01');
    expect(
      DateTime.parse(contract['endDate'] as String),
      DateTime.utc(2026, 12, 31),
      reason: 'consumers parse this into dd/MM/yyyy; a raw Drift DateTime would break them',
    );
  });

  test('offline with nothing mirrored is unknown, not "not found"', () async {
    final c = container(online: false);

    await expectLater(
      c.read(contractByIdProvider('missing').future),
      throwsA(isA<TicketDetailOfflineException>()),
    );
  });

  test('online, a request that never arrived falls back to the mirror', () async {
    await repo.upsertCommesse([
      CommessaSyncDto(
        id: 'm1',
        tenantId: 't',
        createdAt: DateTime.utc(2026, 1, 1),
        codice: 'COM-7',
        descrizione: 'Rifacimento centrale',
        customerId: 'cu1',
      ),
    ]);

    final c = container(online: true);
    final commessa = await c.read(commessaByIdProvider('m1').future);

    expect(commessa, isNotNull);
    expect(commessa!['codice'], 'COM-7');
    expect(commessa['descrizione'], 'Rifacimento centrale');
  });

  test('online, a server fault falls back to the mirror — a 503 is not "this commessa is gone"',
      () async {
    await repo.upsertCommesse([
      CommessaSyncDto(
        id: 'm1',
        tenantId: 't',
        createdAt: DateTime.utc(2026, 1, 1),
        codice: 'COM-7',
        descrizione: 'Rifacimento centrale',
        customerId: 'cu1',
      ),
    ]);

    final c = container(online: true, serverStatus: 503);
    final commessa = await c.read(commessaByIdProvider('m1').future);

    expect(commessa, isNotNull);
    expect(commessa!['codice'], 'COM-7');
  });

  test('online, a server 404 is the answer and the mirror is not consulted', () async {
    await repo.upsertCommesse([
      CommessaSyncDto(
        id: 'm1',
        tenantId: 't',
        createdAt: DateTime.utc(2026, 1, 1),
        codice: 'COM-7',
        customerId: 'cu1',
      ),
    ]);

    final c = container(online: true, serverStatus: 404);

    await expectLater(
      c.read(commessaByIdProvider('m1').future),
      throwsA(isA<DioException>()),
      reason: 'showing a deleted commessa from the mirror would state it still exists',
    );
  });

  test('offline, a mirrored prodotto assistenza answers by id', () async {
    await repo.upsertProdottiAssistenza([
      ProdottoAssistenzaSyncDto(
        id: 'p1',
        tenantId: 't',
        createdAt: DateTime.utc(2026, 1, 1),
        name: 'Caldaia X20',
        customerId: 'cu1',
        locationId: 'loc1',
        isActive: true,
        serialNumber: 'SN-1',
      ),
    ]);

    final c = container(online: false);
    final prodotto = await c.read(prodottoAssistenzaByIdProvider('p1').future);

    expect(prodotto, isNotNull);
    expect(prodotto!['name'], 'Caldaia X20');
    expect(prodotto['serialNumber'], 'SN-1');
  });
}
