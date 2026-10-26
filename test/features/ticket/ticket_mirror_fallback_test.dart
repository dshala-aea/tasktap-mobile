// dart format width=100
// The ticket detail providers that read server data on a tab the technician opens *on site* must
// not blank out because the request died. The mirror already holds what the last sync delivered,
// and that is strictly better than an error page — but only when the server failed to answer.
//
//    online + answered      → the server (it may know about a change from a minute ago);
//    online + no answer     → the mirror (a dead request is not evidence about the data);
//    online + server fault  → the mirror (a 503 is not "this ticket covers no prodotti");
//    online + 4xx           → thrown (that IS an answer: gone, or not yours to see);
//    mirror empty as well   → TicketDetailOfflineException, never "nothing here".

import 'dart:convert' show jsonEncode;

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart' show dioProvider;
import 'package:tasktap_mobile/data/attachments/attachment_content_cache.dart' show AllegatoEntityType;
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart'
    show TicketDetailOfflineException;
import 'package:tasktap_mobile/features/ticket/ticket_providers.dart';

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
        type: status == null ? DioExceptionType.connectionError : DioExceptionType.badResponse,
        response: status == null
            ? null
            : Response<dynamic>(requestOptions: options, statusCode: status),
      );
    });
}

void main() {
  late AppDatabase db;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase(NativeDatabase.memory());
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

  Future<void> insertAttachment(String id) => db
      .into(db.reportAllegati)
      .insert(
        ReportAllegatiCompanion.insert(
          id: id,
          tenantId: 't',
          createdAt: DateTime.utc(2026, 10, 1),
          fileName: 'foto-caldaia.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 2048,
          storagePath: '/content/$id',
          url: '/content/$id',
          entityType: AllegatoEntityType.ticket,
          entityId: 'ticket-1',
          uploadedByUserId: 'u1',
        ),
      );

  Future<void> insertCoveredAsset({required String assetId, required String name}) async {
    await db.into(db.assets).insert(AssetsCompanion.insert(id: assetId, name: name));
    await db
        .into(db.ticketAssets)
        .insert(
          TicketAssetsCompanion.insert(ticketId: 'ticket-1', prodottoAssistenzaId: assetId),
        );
  }

  /// [coverageIds] null models a ticket synced before `prodottoAssistenzaIdsJson` was backfilled.
  Future<void> insertTicket({required List<String>? coverageIds}) => db
      .into(db.tickets)
      .insert(
        TicketsCompanion.insert(
          id: 'ticket-1',
          tenantId: 't',
          createdAt: DateTime.utc(2026, 10, 1),
          title: 'Manutenzione caldaia',
          customerId: 'c',
          locationId: 'l',
          statusId: 1,
          typeId: 1,
          prodottoAssistenzaIdsJson: coverageIds == null
              ? const Value.absent()
              : Value(jsonEncode(coverageIds)),
        ),
      );

  Future<void> insertProdotto({required String id, required String name}) => db
      .into(db.prodottiAssistenza)
      .insert(
        ProdottiAssistenzaCompanion.insert(
          id: id,
          tenantId: 't',
          createdAt: DateTime.utc(2026, 10, 1),
          name: name,
          customerId: 'c',
          locationId: 'l',
          codice: Value('COD-$id'),
        ),
      );

  group('ticketAttachmentsProvider', () {
    test('online, a request that never arrived answers from the mirror', () async {
      await insertAttachment('a1');

      final c = container(online: true);
      final rows = await c.read(ticketAttachmentsProvider('ticket-1').future);

      expect(rows.map((r) => r.id), ['a1']);
      expect(rows.single.fileName, 'foto-caldaia.jpg');
    });

    test('online, a server fault answers from the mirror too', () async {
      await insertAttachment('a1');

      final c = container(online: true, serverStatus: 503);
      final rows = await c.read(ticketAttachmentsProvider('ticket-1').future);

      expect(rows.map((r) => r.id), ['a1']);
    });

    test('online, a 404 is the answer and the mirror is not consulted', () async {
      await insertAttachment('a1');

      final c = container(online: true, serverStatus: 404);

      await expectLater(
        c.read(ticketAttachmentsProvider('ticket-1').future),
        throwsA(isA<DioException>()),
      );
    });

    test('a fault with an empty mirror says so, rather than listing nothing', () async {
      final c = container(online: true, serverStatus: 503);

      await expectLater(
        c.read(ticketAttachmentsProvider('ticket-1').future),
        throwsA(isA<TicketDetailOfflineException>()),
      );
    });
  });

  group('ticketProdottiProvider', () {
    test('online, a dead request answers from the mirror, sorted by name', () async {
      await insertCoveredAsset(assetId: 'p2', name: 'Split');
      await insertCoveredAsset(assetId: 'p1', name: 'Caldaia');

      final c = container(online: true);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.map((r) => r['name']), ['Caldaia', 'Split']);
    });

    test('online, a server fault answers from the mirror too', () async {
      await insertCoveredAsset(assetId: 'p1', name: 'Caldaia');

      final c = container(online: true, serverStatus: 500);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.map((r) => r['id']), ['p1']);
    });

    test('a fault with an empty mirror says so, rather than listing nothing', () async {
      final c = container(online: true, serverStatus: 500);

      await expectLater(
        c.read(ticketProdottiProvider('ticket-1').future),
        throwsA(isA<TicketDetailOfflineException>()),
      );
    });
  });

  // The ticket's own coverage list (`prodottoAssistenzaIds`) answers the compartment on its own:
  // the asset tree is a second, older source and it is only consulted when the coverage column has
  // nothing to say. The three states are distinct and each one has a different right answer.
  group('ticketProdottiProvider — the ticket\'s coverage list', () {
    test('offline, the coverage list names the units without the asset tree', () async {
      await insertTicket(coverageIds: ['p1', 'p2']);
      await insertProdotto(id: 'p2', name: 'Split');
      await insertProdotto(id: 'p1', name: 'Caldaia');

      final c = container(online: false);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.map((r) => r['name']), ['Caldaia', 'Split']);
      expect(rows.first['codice'], 'COD-p1');
    });

    test('a ticket synced before the column was filled still answers from the asset tree', () async {
      await insertTicket(coverageIds: null);
      await insertCoveredAsset(assetId: 'p1', name: 'Caldaia');

      final c = container(online: false);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.map((r) => r['id']), ['p1']);
    });

    test('the server saying "no units" wins over a stale asset tree', () async {
      await insertTicket(coverageIds: const []);
      await insertCoveredAsset(assetId: 'p1', name: 'Caldaia');

      final c = container(online: false);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      // An empty list is an answer, not a gap: falling through to the tree would show a machine the
      // ticket no longer covers.
      expect(rows, isEmpty);
    });

    test('ids the mirror cannot resolve fall back to the asset tree, not to a blank tab', () async {
      await insertTicket(coverageIds: ['never-downloaded']);
      await insertCoveredAsset(assetId: 'p1', name: 'Caldaia');

      final c = container(online: false);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.map((r) => r['id']), ['p1']);
    });
  });
}
