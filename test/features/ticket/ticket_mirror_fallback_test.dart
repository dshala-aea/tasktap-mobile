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
//
// For the prodotti section the mirror has two sources: the ticket's own coverage list (schema 59,
// filled from the join table) and the checklist's `ticket_assets` rows, which the sync caps and
// which are empty for a job with no controls. The coverage list wins when it has anything to say.

import 'dart:convert';

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

  /// The unit in the local catalogue, plus the ticket row that says it covers it. This is the pair
  /// the server actually sends: `TicketDto.prodottoAssistenzaIds` off the join table, and the
  /// `prodottiAssistenza` catalogue rows beside it.
  Future<void> insertCoveredProduct({
    required String id,
    required String name,
    List<String>? ticketCovers,
  }) async {
    await db
        .into(db.prodottiAssistenza)
        .insert(
          ProdottiAssistenzaCompanion.insert(
            id: id,
            tenantId: 't',
            createdAt: DateTime.utc(2026, 10, 1),
            name: name,
            customerId: 'c1',
            locationId: 'l1',
          ),
        );
    if (ticketCovers != null) {
      await db
          .into(db.tickets)
          .insertOnConflictUpdate(
            TicketsCompanion.insert(
              id: 'ticket-1',
              tenantId: 't',
              createdAt: DateTime.utc(2026, 10, 1),
              title: 'Sostituzione caldaia',
              customerId: 'c1',
              locationId: 'l1',
              statusId: 1,
              typeId: 1,
              prodottoAssistenzaIdsJson: Value(jsonEncode(ticketCovers)),
            ),
          );
    }
  }

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

    // The checklist mirror is a *capped* view of the units (`MaxAssetControlRowsPerSync`) and is
    // empty for a job with no controls at all, so on a dead request it under-reports coverage. The
    // ticket's own list is the authority the server filled from the join table.
    test('coverage on the ticket row wins over the checklist mirror', () async {
      await insertCoveredAsset(assetId: 'p1', name: 'Caldaia');
      await insertCoveredAsset(assetId: 'p2', name: 'Split');
      await insertCoveredProduct(id: 'p2', name: 'Split', ticketCovers: const ['p2']);

      final c = container(online: true);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.map((r) => r['id']), ['p2']);
    });

    test('coverage answers even when the checklist mirror is empty', () async {
      await insertCoveredProduct(id: 'p1', name: 'Caldaia', ticketCovers: const ['p1']);

      final c = container(online: true, serverStatus: 503);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.single['name'], 'Caldaia');
      expect(rows.single['serialNumber'], isNull);
    });

    test('an empty coverage list is not "nothing here" — the mirror still answers', () async {
      // The server sends `[]` for a ticket with no join rows, and a ticket whose coverage rows have
      // not arrived yet is also a real state. Neither is evidence against the checklist mirror.
      await insertCoveredAsset(assetId: 'p1', name: 'Caldaia');
      await insertCoveredProduct(id: 'p9', name: 'Non coperto', ticketCovers: const []);

      final c = container(online: true, serverStatus: 500);
      final rows = await c.read(ticketProdottiProvider('ticket-1').future);

      expect(rows.map((r) => r['id']), ['p1']);
    });
  });
}
