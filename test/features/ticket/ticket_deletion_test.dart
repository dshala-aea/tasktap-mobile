// dart format width=100
// test/features/ticket/ticket_deletion_test.dart
//
// Deleting a ticket from the device (ClickUp 12493t4pm3t). Two genuinely different operations:
//   - a local-only ticket (`pending_tickets`) deletes with NO network, always;
//   - a server-side ticket (`tickets`) calls DELETE /api/tickets/{id}, treats a 404 as success, and
//     only then drops the local rows — refusing outright when offline.
//
// Same mock-Dio pattern the rest of test/features/ticket/** uses (mocktail `MockDio`), plus an
// in-memory Drift database for the local side.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/tickets/ticket_deletion.dart';
import 'package:tasktap_mobile/features/ticket/ticket_workflow_api_client.dart';

class MockDio extends Mock implements Dio {}

Response<void> _ok(String path) =>
    Response<void>(requestOptions: RequestOptions(path: path), statusCode: 200);

DioException _dio({required int status, Object? body}) => DioException(
  requestOptions: RequestOptions(path: '/api/tickets/t1'),
  type: DioExceptionType.badResponse,
  response: Response<dynamic>(
    requestOptions: RequestOptions(path: '/api/tickets/t1'),
    statusCode: status,
    data: body,
  ),
);

/// A server-side ticket and every local row that points at it — used to prove the delete leaves no
/// orphans. The schema declares no foreign keys on these tables, so nothing cascades and the
/// service has to remove each one explicitly; if it stops doing so, these assertions fail.
Future<void> _seedServerTicket(AppDatabase db, String id) async {
  await db.into(db.tickets).insert(
    TicketsCompanion.insert(
      id: id,
      tenantId: 'ten-1',
      createdAt: DateTime.utc(2026, 1, 1),
      title: 'Perdita idrica',
      customerId: 'cust-1',
      locationId: 'loc-1',
      statusId: 1,
      typeId: 1,
    ),
  );
  await db.into(db.ticketMateriali).insert(
    TicketMaterialiCompanion.insert(
      id: 'mat-1',
      tenantId: 'ten-1',
      createdAt: DateTime.utc(2026, 1, 1),
      ticketId: id,
      quantity: 2,
    ),
  );
  await db.into(db.cachedTicketControls).insert(
    CachedTicketControlsCompanion.insert(
      ticketId: id,
      controlsJson: '[]',
      cachedAt: DateTime.utc(2026, 1, 1),
    ),
  );
  await db.into(db.ticketAssets).insert(
    TicketAssetsCompanion.insert(ticketId: id, prodottoAssistenzaId: 'prod-1'),
  );
  await db.into(db.checklistOmittedTickets).insert(
    ChecklistOmittedTicketsCompanion.insert(ticketId: id),
  );
  await db.into(db.pendingTicketAttachments).insert(
    PendingTicketAttachmentsCompanion.insert(
      id: 'att-1',
      createdAt: DateTime.utc(2026, 1, 1),
      ticketId: id,
      localPath: '/tmp/photo.jpg',
      fileName: 'photo.jpg',
      contentType: 'image/jpeg',
      sizeBytes: 1234,
    ),
  );
}

/// True when every ticket-scoped table has no row for [id].
Future<bool> _noLocalRowsLeft(AppDatabase db, String id) async {
  final tickets = await (db.select(db.tickets)..where((t) => t.id.equals(id))).get();
  final materiali = await (db.select(
    db.ticketMateriali,
  )..where((m) => m.ticketId.equals(id))).get();
  final cachedControls = await (db.select(
    db.cachedTicketControls,
  )..where((c) => c.ticketId.equals(id))).get();
  final assets = await (db.select(db.ticketAssets)..where((a) => a.ticketId.equals(id))).get();
  final omitted = await (db.select(
    db.checklistOmittedTickets,
  )..where((o) => o.ticketId.equals(id))).get();
  final attachments = await (db.select(
    db.pendingTicketAttachments,
  )..where((a) => a.ticketId.equals(id))).get();
  return tickets.isEmpty &&
      materiali.isEmpty &&
      cachedControls.isEmpty &&
      assets.isEmpty &&
      omitted.isEmpty &&
      attachments.isEmpty;
}

void main() {
  late AppDatabase db;
  late MockDio mockDio;
  late TicketDeletionService service;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();
    service = TicketDeletionService(db: db, api: TicketWorkflowApiClient(mockDio));
  });

  tearDown(() => db.close());

  group('local-only ticket', () {
    test('deletes with no HTTP call at all', () async {
      await db
          .into(db.pendingTickets)
          .insert(
            PendingTicketsCompanion.insert(
              id: 'local-1',
              createdAt: DateTime.utc(2026, 1, 1),
              title: 'Ticket fallito',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
            ),
          );

      await service.deleteLocalOnly('local-1');

      final row = await (db.select(
        db.pendingTickets,
      )..where((t) => t.id.equals('local-1'))).getSingleOrNull();
      expect(row, isNull);
      // The whole point of the local path: it must never reach for the network.
      verifyNever(() => mockDio.delete<void>(any()));
    });

    test('removes queued attachments the local ticket id owns', () async {
      await db
          .into(db.pendingTickets)
          .insert(
            PendingTicketsCompanion.insert(
              id: 'local-1',
              createdAt: DateTime.utc(2026, 1, 1),
              title: 'Ticket fallito',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
            ),
          );
      await db
          .into(db.pendingTicketAttachments)
          .insert(
            PendingTicketAttachmentsCompanion.insert(
              id: 'att-local-1',
              createdAt: DateTime.utc(2026, 1, 1),
              ticketId: 'local-1',
              localPath: '/tmp/a.jpg',
              fileName: 'a.jpg',
              contentType: 'image/jpeg',
              sizeBytes: 10,
            ),
          );

      await service.deleteLocalOnly('local-1');

      final attachments = await (db.select(
        db.pendingTicketAttachments,
      )..where((a) => a.ticketId.equals('local-1'))).get();
      expect(attachments, isEmpty);
    });
  });

  group('server-side ticket', () {
    test('calls DELETE and removes the local row and its children', () async {
      await _seedServerTicket(db, 't1');
      when(() => mockDio.delete<void>('/api/tickets/t1')).thenAnswer((_) async => _ok('/api/tickets/t1'));

      await service.deleteServerTicket(ticketId: 't1', isOnline: true);

      verify(() => mockDio.delete<void>('/api/tickets/t1')).called(1);
      expect(await _noLocalRowsLeft(db, 't1'), isTrue);
    });

    test('a 404 is treated as success and still removes the local rows', () async {
      await _seedServerTicket(db, 't1');
      when(
        () => mockDio.delete<void>('/api/tickets/t1'),
      ).thenThrow(_dio(status: 404, body: 'Ticket not found'));

      // Must not throw — the ticket is already gone server-side, which is what deletion wanted.
      await service.deleteServerTicket(ticketId: 't1', isOnline: true);

      expect(await _noLocalRowsLeft(db, 't1'), isTrue);
    });

    test('offline refuses with a clear message and deletes nothing', () async {
      await _seedServerTicket(db, 't1');

      await expectLater(
        () => service.deleteServerTicket(ticketId: 't1', isOnline: false),
        throwsA(
          isA<TicketDeleteOfflineException>().having(
            (e) => e.toString(),
            'message',
            contains('connessione'),
          ),
        ),
      );

      verifyNever(() => mockDio.delete<void>(any()));
      // Nothing touched: the row and every child are still there.
      expect(await _noLocalRowsLeft(db, 't1'), isFalse);
    });

    test('a non-404 failure surfaces the server message and leaves the row', () async {
      await _seedServerTicket(db, 't1');
      when(
        () => mockDio.delete<void>('/api/tickets/t1'),
      ).thenThrow(_dio(status: 403, body: 'Non sei autorizzato a eliminare il ticket'));

      await expectLater(
        () => service.deleteServerTicket(ticketId: 't1', isOnline: true),
        throwsA(
          isA<TicketWorkflowFailure>().having(
            (f) => f.message,
            'message',
            'Non sei autorizzato a eliminare il ticket',
          ),
        ),
      );

      expect(await _noLocalRowsLeft(db, 't1'), isFalse);
    });
  });
}
