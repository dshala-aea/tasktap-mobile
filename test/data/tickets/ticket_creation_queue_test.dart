// dart format width=100
import 'package:dio/dio.dart';
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

/// Stubs `createTicket` with the one answer a test cares about. The call's parameter list is long
/// enough that a hand-copied one drifts, so it lives here once — same matchers the tests below spell
/// out inline.
void _stubCreateTicket(MockTicketApiClient api, Future<String> Function(Invocation) answer) {
  when(
    () => api.createTicket(
      title: any(named: 'title'),
      description: any(named: 'description'),
      customerId: any(named: 'customerId'),
      locationId: any(named: 'locationId'),
      assignedUserId: any(named: 'assignedUserId'),
      statusId: any(named: 'statusId'),
      typeId: any(named: 'typeId'),
      priorita: any(named: 'priorita'),
      dueDate: any(named: 'dueDate'),
      technicianNotes: any(named: 'technicianNotes'),
      agentId: any(named: 'agentId'),
      contractId: any(named: 'contractId'),
      commessaId: any(named: 'commessaId'),
      cantiereId: any(named: 'cantiereId'),
      prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
      tags: any(named: 'tags'),
      clientId: any(named: 'clientId'),
    ),
  ).thenAnswer(answer);
}

/// A `not_found` as it reaches the queue's catch block: a raw [DioException] carrying the problem
/// body. The backend writes its extensions flat at the ROOT of the body (see
/// `lib/data/api/problem_details.dart`), so `{'field': 'customerId'}` is the real shape, not
/// `{'extensions': {...}}`.
DioException _notFound(Map<String, dynamic> body) => DioException(
  requestOptions: RequestOptions(path: '/api/tickets'),
  response: Response(
    requestOptions: RequestOptions(path: '/api/tickets'),
    statusCode: 404,
    data: {'code': 'not_found', ...body},
  ),
);

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
      expect(PendingTicketState.fromString('pendingSync'), PendingTicketState.pendingSync);
      expect(PendingTicketState.fromString('submitting'), PendingTicketState.submitting);
      expect(PendingTicketState.fromString('submitted'), PendingTicketState.submitted);
      expect(PendingTicketState.fromString('failed'), PendingTicketState.failed);
    });

    test('fromString returns pendingSync for null or unknown', () {
      expect(PendingTicketState.fromString(null), PendingTicketState.pendingSync);
      expect(PendingTicketState.fromString('garbage'), PendingTicketState.pendingSync);
    });
  });

  group('TicketCreationQueue.create — offline (the load-bearing case)', () {
    test('a ticket created offline is persisted locally and never touches the network', () async {
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

      verifyNever(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      );
    });

    test('an offline ticket survives and is sent automatically on reconnect', () async {
      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: false,
      );

      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((_) async => 'server-ticket-1');

      // Simulates the reconnect hook (TicketCreationQueueWatcher).
      await queue.processAll();

      final row = await repo.getById(outcome.localId);
      expect(row!.state, 'submitted');
      expect(row.serverTicketId, 'server-ticket-1');
      expect(onSubmittedCalls, 1);
    });

    test('nothing is lost when the device never reconnects — draft stays queued', () async {
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
      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((_) async => 'server-ticket-2');

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

    test('defaults to Media priority and threads it through to the API call', () async {
      String? capturedPriorita;
      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((inv) async {
        capturedPriorita = inv.namedArguments[#priorita] as String?;
        return 'server-ticket-3';
      });

      await queue.create(
        title: 'Nessuna priorità scelta',
        customerId: 'cust-3',
        locationId: 'loc-3',
        statusId: 1,
        typeId: 1,
        isOnline: true,
      );

      expect(capturedPriorita, 'Media');
    });

    test('an explicit priority survives local persistence and reaches the API call', () async {
      String? capturedPriorita;
      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((inv) async {
        capturedPriorita = inv.namedArguments[#priorita] as String?;
        return 'server-ticket-4';
      });

      final outcome = await queue.create(
        title: 'Guasto critico',
        customerId: 'cust-4',
        locationId: 'loc-4',
        statusId: 1,
        typeId: 1,
        priorita: 'Urgente',
        isOnline: true,
      );

      final row = await repo.getById(outcome.localId);
      expect(row!.priorita, 'Urgente');
      expect(capturedPriorita, 'Urgente');
    });
  });

  group('TicketCreationQueue.create — online failure (ambiguous outcome)', () {
    test('failed attempt is preserved locally, never deleted', () async {
      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenThrow(Exception('Network error'));

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
      // Rendered verbatim on the ticket list as "Invio non riuscito: …", so it is a sentence and
      // never the exception.
      expect(row.error, isNot(contains('Network error')));
      expect(row.error, isNot(contains('Exception')));
      expect(row.error, contains('Niente è andato perso'));
      expect(onSubmittedCalls, 0);
    });

    /// Changed deliberately when `clientId` shipped. This used to assert the opposite — that a
    /// `failed` ticket was left alone until a human tapped Riprova — because the outcome of the
    /// first send was unknown and a blind resend could raise a second customer-visible ticket.
    /// The server now keys on the client id and returns the ticket it already created, so the
    /// resend is safe and the technician is no longer asked to adjudicate it.
    test(
      'processAll retries a failed (already-sent) ticket, because clientId makes it safe',
      () async {
        when(
          () => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
            priorita: any(named: 'priorita'),
            dueDate: any(named: 'dueDate'),
            technicianNotes: any(named: 'technicianNotes'),
            agentId: any(named: 'agentId'),
            contractId: any(named: 'contractId'),
            commessaId: any(named: 'commessaId'),
            cantiereId: any(named: 'cantiereId'),
            prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
            tags: any(named: 'tags'),
            clientId: any(named: 'clientId'),
          ),
        ).thenThrow(Exception('Timeout'));

        final outcome = await queue.create(
          title: 'Sostituzione filtro',
          customerId: 'cust-2',
          locationId: 'loc-2',
          statusId: 1,
          typeId: 1,
          isOnline: true,
        );
        expect((await repo.getById(outcome.localId))!.state, 'failed');

        // The connection comes back and the send succeeds this time.
        clearInteractions(mockApiClient);
        when(
          () => mockApiClient.createTicket(
            title: any(named: 'title'),
            description: any(named: 'description'),
            customerId: any(named: 'customerId'),
            locationId: any(named: 'locationId'),
            assignedUserId: any(named: 'assignedUserId'),
            statusId: any(named: 'statusId'),
            typeId: any(named: 'typeId'),
            priorita: any(named: 'priorita'),
            dueDate: any(named: 'dueDate'),
            technicianNotes: any(named: 'technicianNotes'),
            agentId: any(named: 'agentId'),
            contractId: any(named: 'contractId'),
            commessaId: any(named: 'commessaId'),
            cantiereId: any(named: 'cantiereId'),
            prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
            tags: any(named: 'tags'),
            clientId: any(named: 'clientId'),
          ),
        ).thenAnswer((_) async => 'server-ticket-9');

        await queue.processAll();

        final row = await repo.getById(outcome.localId);
        expect(row!.state, 'submitted');
        expect(row.serverTicketId, 'server-ticket-9');
      },
    );

    /// Every attempt must carry the SAME id. A fresh one per attempt would deduplicate nothing —
    /// the server would see two unrelated creates and make two tickets, which is the exact
    /// failure the key exists to prevent.
    test('every attempt sends the local row id as clientId, unchanged', () async {
      final sentClientIds = <String?>[];
      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((invocation) async {
        sentClientIds.add(invocation.namedArguments[#clientId] as String?);
        throw Exception('Timeout');
      });

      final outcome = await queue.create(
        title: 'Sostituzione filtro',
        customerId: 'cust-2',
        locationId: 'loc-2',
        statusId: 1,
        typeId: 1,
        isOnline: true,
      );

      await queue.processAll();
      await queue.retry(outcome.localId);

      expect(sentClientIds, hasLength(3), reason: 'initial send, auto-retry, manual retry');
      expect(sentClientIds, everyElement(equals(outcome.localId)));
    });

    test('an explicit user-initiated retry can resend a failed ticket', () async {
      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenThrow(Exception('Network error'));

      final firstOutcome = await queue.create(
        title: 'Sostituzione filtro',
        customerId: 'cust-2',
        locationId: 'loc-2',
        statusId: 1,
        typeId: 1,
        isOnline: true,
      );
      expect(firstOutcome.isFailed, isTrue);

      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((_) async => 'server-ticket-3');

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

      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((inv) async {
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
    test('excludes submitted rows, includes pendingSync/submitting/failed', () async {
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

  // Ticket parity with web's TicketCreatePanel: the wizard now asks for contract, commessa,
  // cantiere and products, and CreateTicketRequest validates each of them. Without this chain the
  // pickers would collect values the server never receives — the ticket would be created bare.
  group('TicketCreationQueue — the wizard\'s reference fields', () {
    test('survive the outbox as JSON and reach the API call on reconnect', () async {
      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        contractId: 'con-1',
        commessaId: 'com-1',
        cantiereId: 'can-1',
        prodottoAssistenzaIds: const ['prod-1', 'prod-2'],
        isOnline: false,
      );

      final row = await repo.getById(outcome.localId);
      expect(row!.contractId, 'con-1');
      expect(row.commessaId, 'com-1');
      expect(row.cantiereId, 'can-1');
      expect(row.prodottoAssistenzaIdsJson, '["prod-1","prod-2"]');

      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((_) async => 'server-ticket-1');

      await queue.processAll();

      verify(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: 'con-1',
          commessaId: 'com-1',
          cantiereId: 'can-1',
          prodottoAssistenzaIds: ['prod-1', 'prod-2'],
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).called(1);
    });

    test('a ticket with no references sends them absent, not as empty values', () async {
      when(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: any(named: 'contractId'),
          commessaId: any(named: 'commessaId'),
          cantiereId: any(named: 'cantiereId'),
          prodottoAssistenzaIds: any(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).thenAnswer((_) async => 'server-ticket-2');

      await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: true,
      );

      final sentProdotti = verify(
        () => mockApiClient.createTicket(
          title: any(named: 'title'),
          description: any(named: 'description'),
          customerId: any(named: 'customerId'),
          locationId: any(named: 'locationId'),
          assignedUserId: any(named: 'assignedUserId'),
          statusId: any(named: 'statusId'),
          typeId: any(named: 'typeId'),
          priorita: any(named: 'priorita'),
          dueDate: any(named: 'dueDate'),
          technicianNotes: any(named: 'technicianNotes'),
          agentId: any(named: 'agentId'),
          contractId: null,
          commessaId: null,
          cantiereId: null,
          prodottoAssistenzaIds: captureAny(named: 'prodottoAssistenzaIds'),
          tags: any(named: 'tags'),
          clientId: any(named: 'clientId'),
        ),
      ).captured.single;

      expect(sentProdotti, isEmpty, reason: 'no picker was opened, so nothing was claimed');
    });
  });

  // ── A rejected reference (Task B6) ──────────────────────────────────────────
  //
  // A queued ticket the server answered 404 `not_found` for, naming one of the request's reference
  // fields, can never be fixed by sending it again: the next attempt carries the same rejected id.
  // The queue's whole job here is to notice that, record WHICH field, and stop asking.
  group('TicketCreationQueue — a rejected reference is repairable, not retryable', () {
    test('a 404 naming a field marks the row repairable and stops its auto-retry', () async {
      var sendCalls = 0;
      _stubCreateTicket(mockApiClient, (inv) async {
        sendCalls++;
        throw _notFound({'field': 'customerId'});
      });

      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-gone',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: true,
      );

      expect(outcome.isFailed, isTrue);
      final row = (await db.select(db.pendingTickets).get()).single;
      expect(row.state, 'failed');
      expect(row.repairableField, 'customerId');

      // The stored message is `humanErrorMessage`'s own sentence for a 404 — it short-circuits
      // before the problem body's prose is ever read, so the field name CANNOT be in the message
      // and is only ever in the column above. (The plan's first draft asserted `contains('customerId')`
      // here; that is false by construction, see the report.)
      expect(row.error, contains('Non trovato'));

      // A second pass must not resubmit it: no answer will ever differ.
      await queue.processAll();
      expect(sendCalls, 1, reason: 'a repairable row waits for a human, not a timer');
      expect((await repo.getById(outcome.localId))!.state, 'failed');
    });

    test('the same refusal on a pendingSync row is held back too', () async {
      // The exclusion is a property of the QUERY, on both sweeps (plan Step 4), not a branch in the
      // loop — so a repaired row re-enters by the same path every other row uses. Today only the
      // `failed` sweep can realistically hold a flagged row (a rejection needs a send to happen);
      // this pins the `pendingSync` half, which is the one nothing else would notice going missing.
      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-gone',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: false,
      );
      await repo.markFailed(
        id: outcome.localId,
        error: 'Non trovato sul server.',
        repairableField: 'customerId',
      );
      // Back to the state a never-sent row has, flag and all.
      await repo.updateState(id: outcome.localId, state: PendingTicketState.pendingSync);

      var sendCalls = 0;
      _stubCreateTicket(mockApiClient, (inv) async {
        sendCalls++;
        return 'server-ticket-x';
      });

      await queue.processAll();
      expect(sendCalls, 0, reason: 'the pendingSync sweep excludes repairable rows as well');
    });

    test('a 404 without a field keeps the row on the ordinary retry path', () async {
      var sendCalls = 0;
      _stubCreateTicket(mockApiClient, (inv) async {
        sendCalls++;
        throw _notFound(const {});
      });

      final outcome = await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: true,
      );

      expect((await db.select(db.pendingTickets).get()).single.repairableField, isNull);
      expect(sendCalls, 1);

      await queue.processAll();
      expect(sendCalls, 2, reason: 'nothing here is repairable — the old failure path is intact');
      expect(await repo.getById(outcome.localId), isNotNull);
    });

    test('a field the client cannot repair is left null, not guessed at', () async {
      _stubCreateTicket(mockApiClient, (inv) async => throw _notFound({'field': 'sourceId'}));

      await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: true,
      );

      // The client must not offer a repair screen that cannot fix the problem — a field it cannot
      // render leaves the row showing today's failure, with the server's message.
      expect((await db.select(db.pendingTickets).get()).single.repairableField, isNull);
    });

    test('a field with no picker to repair it is left null too — cantiereId and statusId', () {
      // Both are in the server's vocabulary but not in this wizard's: no step holds a cantiere
      // (`grep -i cantiere lib/features/ticket/steps/` finds none), and the status is defaulted from
      // the default TicketStatus rather than picked, so a "repair" would re-send the very id the
      // server refused. See the plan's third-pass revision note, item 1.
      expect(TicketCreationQueue.repairableFieldOf(_notFound({'field': 'cantiereId'})), isNull);
      expect(TicketCreationQueue.repairableFieldOf(_notFound({'field': 'statusId'})), isNull);

      // The other two spellings of "not repairable", kept beside them so the set's edges are all in
      // one place: a body that is not a 404 at all, and the nested shape the server never sends.
      expect(
        TicketCreationQueue.repairableFieldOf(
          DioException(
            requestOptions: RequestOptions(path: '/api/tickets'),
            response: Response(
              requestOptions: RequestOptions(path: '/api/tickets'),
              statusCode: 400,
              data: {'code': 'validation_failed', 'field': 'customerId'},
            ),
          ),
        ),
        isNull,
      );
      expect(
        TicketCreationQueue.repairableFieldOf(
          _notFound({
            'extensions': {'field': 'customerId'},
          }),
        ),
        isNull,
      );
    });

    test('exactly the eight fields the wizard can re-pick are repairable', () {
      // Pinned one by one, so widening or narrowing the set has to be a deliberate edit rather than
      // a quiet one. The wizard's steps own each of these fields; a ninth name would need a picker.
      const repairable = [
        'customerId',
        'locationId',
        'contractId',
        'commessaId',
        'assignedUserId',
        'typeId',
        'agentId',
        'prodottoAssistenzaIds',
      ];
      for (final field in repairable) {
        expect(
          TicketCreationQueue.repairableFieldOf(_notFound({'field': field})),
          field,
          reason: '$field is re-pickable in the wizard and must be offered for repair',
        );
      }
      expect(repairable, hasLength(8));
    });

    test('a non-404 never sets the flag, however the same field is named', () async {
      _stubCreateTicket(
        mockApiClient,
        (inv) async => throw DioException(
          requestOptions: RequestOptions(path: '/api/tickets'),
          response: Response(
            requestOptions: RequestOptions(path: '/api/tickets'),
            statusCode: 500,
            data: {'code': 'server_error', 'field': 'customerId'},
          ),
        ),
      );

      await queue.create(
        title: 'Perdita idrica',
        customerId: 'cust-1',
        locationId: 'loc-1',
        statusId: 1,
        typeId: 2,
        isOnline: true,
      );

      expect((await db.select(db.pendingTickets).get()).single.repairableField, isNull);
    });

    /// The row count and the id are the point: a repair is an UPDATE of the row the server refused,
    /// never a second ticket. `create` here would leave the rejected one sitting beside a new pending
    /// row, and `PUT /api/tickets` would reach for a server ticket that has never existed.
    test('repairing updates the row in place, clears the flag and returns it to auto-retry', () async {
      _stubCreateTicket(mockApiClient, (inv) async => throw _notFound({'field': 'agentId'}));

      final outcome = await queue.create(
        title: 'Perdita idrica',
        description: 'Dal bagno',
        customerId: 'cust-1',
        locationId: 'loc-1',
        assignedUserId: 'tech-1',
        statusId: 1,
        typeId: 2,
        priorita: 'Alta',
        technicianNotes: 'Portare guarnizione',
        agentId: 'agent-gone',
        contractId: 'con-1',
        commessaId: 'com-1',
        cantiereId: 'can-1',
        prodottoAssistenzaIds: const ['prod-1', 'prod-2'],
        tags: const ['urgente'],
        isOnline: true,
      );
      final before = (await repo.getById(outcome.localId))!;
      expect(before.repairableField, 'agentId');

      await queue.repair(
        outcome.localId,
        title: 'Perdita idrica',
        description: 'Dal bagno',
        customerId: 'cust-1',
        locationId: 'loc-1',
        assignedUserId: 'tech-1',
        statusId: 1,
        typeId: 2,
        priorita: 'Alta',
        technicianNotes: 'Portare guarnizione',
        agentId: 'agent-2',
        contractId: 'con-1',
        commessaId: 'com-1',
        cantiereId: 'can-1',
        prodottoAssistenzaIds: const ['prod-1', 'prod-2'],
        tags: const ['urgente'],
      );

      final rows = await db.select(db.pendingTickets).get();
      expect(rows, hasLength(1), reason: 'a repair is not a second ticket');
      expect(rows.single.id, outcome.localId, reason: 'the same row, so the same clientId');
      expect(rows.single.agentId, 'agent-2');
      expect(rows.single.repairableField, isNull);

      // Every other column the create carried is still there: the repair writes the whole row, not
      // only the field it corrected, which is why `repair` and `create` share one row writer.
      expect(rows.single.title, 'Perdita idrica');
      expect(rows.single.description, 'Dal bagno');
      expect(rows.single.customerId, 'cust-1');
      expect(rows.single.locationId, 'loc-1');
      expect(rows.single.assignedUserId, 'tech-1');
      expect(rows.single.statusId, 1);
      expect(rows.single.typeId, 2);
      expect(rows.single.priorita, 'Alta');
      expect(rows.single.technicianNotes, 'Portare guarnizione');
      expect(rows.single.contractId, 'con-1');
      expect(rows.single.commessaId, 'com-1');
      expect(rows.single.cantiereId, 'can-1');
      expect(rows.single.prodottoAssistenzaIdsJson, '["prod-1","prod-2"]');
      expect(rows.single.tagsJson, '["urgente"]');
      // The row's own bookkeeping is left as it was: the last send did fail, and that is still true.
      expect(rows.single.state, 'failed');
      expect(rows.single.createdAt, before.createdAt);

      // And it is back on the ordinary path — which is what actually sends it. Nothing was sent by
      // `repair` itself.
      _stubCreateTicket(mockApiClient, (inv) async => 'server-ticket-7');
      await queue.processAll();
      final after = (await repo.getById(outcome.localId))!;
      expect(after.state, 'submitted');
      expect(after.serverTicketId, 'server-ticket-7');
      expect(onSubmittedCalls, 1);
    });

    test(
      'a repair that drops an optional reference writes the absence, not the old value',
      () async {
        _stubCreateTicket(mockApiClient, (inv) async => throw _notFound({'field': 'agentId'}));
        final outcome = await queue.create(
          title: 'Perdita idrica',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 2,
          agentId: 'agent-gone',
          prodottoAssistenzaIds: const ['prod-gone'],
          isOnline: true,
        );

        // The technician's repair: no Riferimento at all, and the stale product dropped.
        await queue.repair(
          outcome.localId,
          title: 'Perdita idrica',
          customerId: 'cust-1',
          locationId: 'loc-1',
          statusId: 1,
          typeId: 2,
        );

        final row = (await repo.getById(outcome.localId))!;
        expect(row.agentId, isNull);
        expect(
          row.prodottoAssistenzaIdsJson,
          isNull,
          reason: 'an emptied list is an absent member',
        );
        expect(row.repairableField, isNull);
      },
    );
  });
}
