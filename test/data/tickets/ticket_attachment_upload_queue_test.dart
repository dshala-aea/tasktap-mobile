// dart format width=100
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_attachment_repository.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_attachment_state.dart';
import 'package:tasktap_mobile/data/tickets/ticket_attachment_upload_queue.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Mocks
// ══════════════════════════════════════════════════════════════════════════════

class MockTicketDetailApiClient extends Mock implements TicketDetailApiClient {}

// ══════════════════════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════════════════════

AppDatabase _makeInMemoryDb() => AppDatabase(NativeDatabase.memory());

void main() {
  late AppDatabase db;
  late PendingTicketAttachmentRepository repo;
  late MockTicketDetailApiClient mockApiClient;
  late TicketAttachmentUploadQueue queue;
  late List<String> uploadedForTicket;

  setUp(() {
    db = _makeInMemoryDb();
    repo = PendingTicketAttachmentRepository(db);
    mockApiClient = MockTicketDetailApiClient();
    uploadedForTicket = [];
    queue = TicketAttachmentUploadQueue(
      repo: repo,
      apiClient: mockApiClient,
      onUploaded: (ticketId) => uploadedForTicket.add(ticketId),
    );
  });

  tearDown(() => db.close());

  group('PendingTicketAttachmentState', () {
    test('fromString maps all known values', () {
      expect(
        PendingTicketAttachmentState.fromString('pendingSync'),
        PendingTicketAttachmentState.pendingSync,
      );
      expect(
        PendingTicketAttachmentState.fromString('submitting'),
        PendingTicketAttachmentState.submitting,
      );
      expect(
        PendingTicketAttachmentState.fromString('submitted'),
        PendingTicketAttachmentState.submitted,
      );
      expect(
        PendingTicketAttachmentState.fromString('failed'),
        PendingTicketAttachmentState.failed,
      );
    });

    test('fromString returns pendingSync for null or unknown', () {
      expect(PendingTicketAttachmentState.fromString(null), PendingTicketAttachmentState.pendingSync);
      expect(
        PendingTicketAttachmentState.fromString('garbage'),
        PendingTicketAttachmentState.pendingSync,
      );
    });
  });

  group('TicketAttachmentUploadQueue.upload — offline (the load-bearing case)', () {
    test('an attachment picked offline is persisted locally and never touches the network', () async {
      final outcome = await queue.upload(
        ticketId: 'ticket-1',
        localPath: '/tmp/foto.jpg',
        fileName: 'foto.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        isOnline: false,
      );

      expect(outcome.isQueuedOffline, isTrue);

      final row = await repo.getById(outcome.localId);
      expect(row, isNotNull);
      expect(row!.state, 'pendingSync');
      expect(row.ticketId, 'ticket-1');
      expect(row.fileName, 'foto.jpg');
      expect(row.sizeBytes, 1024);

      verifyNever(
        () => mockApiClient.uploadAttachment(
          ticketId: any(named: 'ticketId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      );
    });

    test('an offline attachment survives and is sent automatically on reconnect', () async {
      final outcome = await queue.upload(
        ticketId: 'ticket-1',
        localPath: '/tmp/foto.jpg',
        fileName: 'foto.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        isOnline: false,
      );

      when(
        () => mockApiClient.uploadAttachment(
          ticketId: any(named: 'ticketId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer(
        (_) async => const TicketAttachmentUploadResponse(
          allegatoId: 'srv-att-1',
          contentUrl: '/content/1',
        ),
      );

      // Simulates the reconnect hook (TicketAttachmentUploadQueueWatcher).
      await queue.processAll();

      final row = await repo.getById(outcome.localId);
      expect(row!.state, 'submitted');
      expect(row.serverAttachmentId, 'srv-att-1');
      expect(uploadedForTicket, ['ticket-1']);
    });

    test('nothing is lost when the device never reconnects — the row stays queued', () async {
      final outcome = await queue.upload(
        ticketId: 'ticket-1',
        localPath: '/tmp/foto.jpg',
        fileName: 'foto.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        isOnline: false,
      );

      final row = await repo.getById(outcome.localId);
      expect(row, isNotNull); // never deleted
      expect(row!.state, 'pendingSync');
    });
  });

  group('TicketAttachmentUploadQueue.upload — online success', () {
    test('uploads immediately when online and marks submitted', () async {
      when(
        () => mockApiClient.uploadAttachment(
          ticketId: any(named: 'ticketId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer(
        (_) async => const TicketAttachmentUploadResponse(
          allegatoId: 'srv-att-2',
          contentUrl: '/content/2',
        ),
      );

      final outcome = await queue.upload(
        ticketId: 'ticket-2',
        localPath: '/tmp/foto2.jpg',
        fileName: 'foto2.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 2048,
        isOnline: true,
      );

      expect(outcome.isSubmitted, isTrue);
      expect(outcome.serverAttachmentId, 'srv-att-2');
      expect(uploadedForTicket, ['ticket-2']);

      final row = await repo.getById(outcome.localId);
      expect(row!.state, 'submitted');
    });
  });

  group('TicketAttachmentUploadQueue.upload — online failure (ambiguous outcome)', () {
    test('a failed attempt is preserved locally, never deleted, with a human message', () async {
      when(
        () => mockApiClient.uploadAttachment(
          ticketId: any(named: 'ticketId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenThrow(Exception('Network error'));

      final outcome = await queue.upload(
        ticketId: 'ticket-3',
        localPath: '/tmp/foto3.jpg',
        fileName: 'foto3.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 4096,
        isOnline: true,
      );

      expect(outcome.isFailed, isTrue);

      final row = await repo.getById(outcome.localId);
      expect(row, isNotNull);
      expect(row!.state, 'failed');
      expect(row.error, isNot(contains('Network error')));
      expect(row.error, isNot(contains('Exception')));
      expect(uploadedForTicket, isEmpty);
    });

    test(
      'processAll does NOT auto-retry a failed attachment — no idempotency key to make a resend safe',
      () async {
        when(
          () => mockApiClient.uploadAttachment(
            ticketId: any(named: 'ticketId'),
            localPath: any(named: 'localPath'),
            fileName: any(named: 'fileName'),
            contentType: any(named: 'contentType'),
          ),
        ).thenThrow(Exception('Timeout'));

        final outcome = await queue.upload(
          ticketId: 'ticket-4',
          localPath: '/tmp/foto4.jpg',
          fileName: 'foto4.jpg',
          contentType: 'image/jpeg',
          sizeBytes: 1024,
          isOnline: true,
        );
        expect((await repo.getById(outcome.localId))!.state, 'failed');

        clearInteractions(mockApiClient);
        when(
          () => mockApiClient.uploadAttachment(
            ticketId: any(named: 'ticketId'),
            localPath: any(named: 'localPath'),
            fileName: any(named: 'fileName'),
            contentType: any(named: 'contentType'),
          ),
        ).thenAnswer(
          (_) async => const TicketAttachmentUploadResponse(
            allegatoId: 'srv-should-not-happen',
            contentUrl: '/content/x',
          ),
        );

        await queue.processAll();

        // Still failed: processAll only sweeps pendingSync rows.
        final row = await repo.getById(outcome.localId);
        expect(row!.state, 'failed');
        verifyNever(
          () => mockApiClient.uploadAttachment(
            ticketId: any(named: 'ticketId'),
            localPath: any(named: 'localPath'),
            fileName: any(named: 'fileName'),
            contentType: any(named: 'contentType'),
          ),
        );
      },
    );

    test('an explicit user-initiated retry can resend a failed attachment', () async {
      when(
        () => mockApiClient.uploadAttachment(
          ticketId: any(named: 'ticketId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenThrow(Exception('Network error'));

      final firstOutcome = await queue.upload(
        ticketId: 'ticket-5',
        localPath: '/tmp/foto5.jpg',
        fileName: 'foto5.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 1024,
        isOnline: true,
      );
      expect(firstOutcome.isFailed, isTrue);

      when(
        () => mockApiClient.uploadAttachment(
          ticketId: any(named: 'ticketId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer(
        (_) async => const TicketAttachmentUploadResponse(
          allegatoId: 'srv-att-5',
          contentUrl: '/content/5',
        ),
      );

      final retryOutcome = await queue.retry(firstOutcome.localId);
      expect(retryOutcome.isSubmitted, isTrue);

      final row = await repo.getById(firstOutcome.localId);
      expect(row!.state, 'submitted');
      expect(row.serverAttachmentId, 'srv-att-5');
    });
  });

  group('TicketAttachmentUploadQueue.processAll — multiple pending attachments', () {
    test('processes each pendingSync attachment independently', () async {
      final a = await queue.upload(
        ticketId: 'ticket-a',
        localPath: '/tmp/a.jpg',
        fileName: 'a.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 100,
        isOnline: false,
      );
      final b = await queue.upload(
        ticketId: 'ticket-b',
        localPath: '/tmp/b.jpg',
        fileName: 'b.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 200,
        isOnline: false,
      );

      when(
        () => mockApiClient.uploadAttachment(
          ticketId: any(named: 'ticketId'),
          localPath: any(named: 'localPath'),
          fileName: any(named: 'fileName'),
          contentType: any(named: 'contentType'),
        ),
      ).thenAnswer((inv) async {
        final fileName = inv.namedArguments[#fileName] as String;
        return TicketAttachmentUploadResponse(allegatoId: 'srv-$fileName', contentUrl: '/x');
      });

      await queue.processAll();

      final rowA = await repo.getById(a.localId);
      final rowB = await repo.getById(b.localId);
      expect(rowA!.state, 'submitted');
      expect(rowA.serverAttachmentId, 'srv-a.jpg');
      expect(rowB!.state, 'submitted');
      expect(rowB.serverAttachmentId, 'srv-b.jpg');
      expect(uploadedForTicket.toSet(), {'ticket-a', 'ticket-b'});
    });
  });

  group('PendingTicketAttachmentRepository.watchForTicket', () {
    test('excludes submitted rows and rows for other tickets', () async {
      await repo.insert(
        id: 'p1',
        ticketId: 'ticket-x',
        localPath: '/tmp/1.jpg',
        fileName: '1.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 10,
        state: PendingTicketAttachmentState.pendingSync,
      );
      await repo.insert(
        id: 'p2',
        ticketId: 'ticket-x',
        localPath: '/tmp/2.jpg',
        fileName: '2.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 10,
        state: PendingTicketAttachmentState.failed,
      );
      await repo.insert(
        id: 'p3',
        ticketId: 'ticket-x',
        localPath: '/tmp/3.jpg',
        fileName: '3.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 10,
        state: PendingTicketAttachmentState.submitted,
      );
      await repo.insert(
        id: 'p4',
        ticketId: 'ticket-y',
        localPath: '/tmp/4.jpg',
        fileName: '4.jpg',
        contentType: 'image/jpeg',
        sizeBytes: 10,
        state: PendingTicketAttachmentState.pendingSync,
      );

      final forX = await repo.watchForTicket('ticket-x').first;
      final ids = forX.map((a) => a.id).toSet();
      expect(ids, {'p1', 'p2'});
    });
  });
}
