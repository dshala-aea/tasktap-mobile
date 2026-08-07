// dart format width=100
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_repository.dart';
import 'package:tasktap_mobile/data/tickets/pending_ticket_state.dart';
import 'package:tasktap_mobile/data/tickets/ticket_creation_queue.dart';
import 'package:tasktap_mobile/features/ticket/ticket_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Mocks
// ══════════════════════════════════════════════════════════════════════════════

class MockTicketApiClient extends Mock implements TicketApiClient {}

// ══════════════════════════════════════════════════════════════════════════════
// Helpers
// ══════════════════════════════════════════════════════════════════════════════

AppDatabase _makeInMemoryDb() => AppDatabase(NativeDatabase.memory());

// ══════════════════════════════════════════════════════════════════════════════
// Tests
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  late AppDatabase db;
  late PendingTicketRepository repo;
  late MockTicketApiClient mockApiClient;
  late TicketCreationQueue queue;
  late int onSubmittedCalls;

  setUp(() {
    db = _makeInMemoryDb();
    repo = PendingTicketRepository(db);
    mockApiClient = MockTicketApiClient();
    onSubmittedCalls = 0;
    queue = TicketCreationQueue(
      repo: repo,
      apiClient: mockApiClient,
      onSubmitted: () => onSubmittedCalls++,
    );
  });

  tearDown(() => db.close());

  group('PendingTicketState', () {
    test('fromString maps all known values', () {
      expect(PendingTicketState.fromString('pendingSync'),
          PendingTicketState.pendingSync);
      expect(PendingTicketState.fromString('submitting'),
          PendingTicketState.submitting);
      expect(PendingTicketState.fromString('submitted'),
          PendingTicketState.submitted);
      expect(PendingTicketState.fromString('failed'),
          PendingTicketState.failed);
    });

    test('fromString returns pendingSync for null or unknown', () {
      expect(PendingTicketState.fromString(null), PendingTicketState.pendingSync);
      expect(
          PendingTicketState.fromString('garbage'), PendingTicketState.pendingSync);
    });
  });

  group('TicketCreationQueue.create — offline (the load-bearing case)', () {
    test(
        'a ticket created offline is persisted locally and never touches the network',
        () async {
      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: false,
      );

      expect(outcome.isQueuedOffline, isTrue);

      final row = await repo.getById(outcome.localId);
      expect(row, isNotNull);
      expect(row!.state, 'pendingSync');
      expect(row.title, 'Perdita idrica');
      expect(row.customerId, 'cust-1');
      expect(row.locationId, 'loc-1');
      expect(row.statusId, 1);
      expect(row.typeId, 2);

      verifyNever(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          ));
    });

    test('an offline ticket survives and is sent automatically on reconnect',
        () async {
      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: false,
      );

      when(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          )).thenAnswer((_) async => 'server-ticket-1');

      // Simulates the reconnect hook (TicketCreationQueueWatcher).
      await queue.processAll();

      final row = await repo.getById(outcome.localId);
      expect(row!.state, 'submitted');
      expect(row.serverTicketId, 'server-ticket-1');
      expect(onSubmittedCalls, 1);
    });

    test('nothing is lost when the device never reconnects — draft stays queued',
        () async {
      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: false,
      );

      // No processAll() call — device stays offline.
      final row = await repo.getById(outcome.localId);
      expect(row, isNotNull); // never deleted
      expect(row!.state, 'pendingSync');
    });
  });

  group('TicketCreationQueue.create — online success', () {
    test('creates immediately when online and marks submitted', () async {
      when(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          )).thenAnswer((_) async => 'server-ticket-2');

      final outcome = await queue.create(
        title: 'Sostituzione filtro',
        customerId: 'cust-2',
        locationId: 'loc-2',
        statusId: 1,
        typeId: 1,
        isOnline: true,
      );

      expect(outcome.isSubmitted, isTrue);
      expect(outcome.serverTicketId, 'server-ticket-2');
      expect(onSubmittedCalls, 1);

      final row = await repo.getById(outcome.localId);
      expect(row!.state, 'submitted');
    });
  });

  group('TicketCreationQueue.create — online failure (ambiguous outcome)', () {
    test('failed attempt is preserved locally, never deleted', () async {
      when(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          )).thenThrow(Exception('Network error'));

      final outcome = await queue.create(
        title: 'Sostituzione filtro',
        customerId: 'cust-2',
        locationId: 'loc-2',
        statusId: 1,
        typeId: 1,
        isOnline: true,
      );

      expect(outcome.isFailed, isTrue);

      final row = await repo.getById(outcome.localId);
      expect(row, isNotNull);
      expect(row!.state, 'failed');
      expect(row.error, contains('Network error'));
      expect(onSubmittedCalls, 0);
    });

    test(
        'processAll (auto reconnect) never retries a failed (already-sent) ticket',
        () async {
      when(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          )).thenThrow(Exception('Timeout'));

      await queue.create(
        title: 'Sostituzione filtro',
        customerId: 'cust-2',
        locationId: 'loc-2',
        statusId: 1,
        typeId: 1,
        isOnline: true,
      );

      // Clear the mock's throw behaviour and verify a later auto-flush
      // (processAll — what the reconnect watcher calls) does NOT retry it.
      clearInteractions(mockApiClient);
      await queue.processAll();

      verifyNever(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          ));
    });

    test('an explicit user-initiated retry can resend a failed ticket',
        () async {
      when(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          )).thenThrow(Exception('Network error'));

      final firstOutcome = await queue.create(
        title: 'Sostituzione filtro',
        customerId: 'cust-2',
        locationId: 'loc-2',
        statusId: 1,
        typeId: 1,
        isOnline: true,
      );
      expect(firstOutcome.isFailed, isTrue);

      when(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          )).thenAnswer((_) async => 'server-ticket-3');

      final retryOutcome = await queue.retry(firstOutcome.localId);
      expect(retryOutcome.isSubmitted, isTrue);

      final row = await repo.getById(firstOutcome.localId);
      expect(row!.state, 'submitted');
      expect(row.serverTicketId, 'server-ticket-3');
    });
  });

  group('TicketCreationQueue.processAll — multiple pending tickets', () {
    test('processes each pendingSync ticket independently', () async {
      final a = await queue.create(
        title: 'Ticket A',
        customerId: 'c-1',
        locationId: 'l-1',
        statusId: 1,
        typeId: 1,
        isOnline: false,
      );
      final b = await queue.create(
        title: 'Ticket B',
        customerId: 'c-2',
        locationId: 'l-2',
        statusId: 1,
        typeId: 1,
        isOnline: false,
      );

      when(() => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
          )).thenAnswer((inv) async {
        final title = inv.namedArguments[#title] as String;
        return 'server-$title';
      });

      await queue.processAll();

      final rowA = await repo.getById(a.localId);
      final rowB = await repo.getById(b.localId);
      expect(rowA!.state, 'submitted');
      expect(rowA.serverTicketId, 'server-Ticket A');
      expect(rowB!.state, 'submitted');
      expect(rowB.serverTicketId, 'server-Ticket B');
    });
  });

  group('PendingTicketRepository.watchUnresolved', () {
    test('excludes submitted rows, includes pendingSync/submitting/failed',
        () async {
      await repo.insert(
        id: 'p1',
        title: 'A',
        customerId: 'c1',
        locationId: 'l1',
        statusId: 1,
        typeId: 1,
        state: PendingTicketState.pendingSync,
      );
      await repo.insert(
        id: 'p2',
        title: 'B',
        customerId: 'c1',
        locationId: 'l1',
        statusId: 1,
        typeId: 1,
        state: PendingTicketState.failed,
      );
      await repo.insert(
        id: 'p3',
        title: 'C',
        customerId: 'c1',
        locationId: 'l1',
        statusId: 1,
        typeId: 1,
        state: PendingTicketState.submitted,
      );

      final unresolved = await repo.watchUnresolved().first;
      final ids = unresolved.map((t) => t.id).toSet();
      expect(ids, {'p1', 'p2'});
      expect(ids.contains('p3'), isFalse);
    });
  });
}
