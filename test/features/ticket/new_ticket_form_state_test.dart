// dart format width=100
// test/features/ticket/new_ticket_form_state_test.dart
//
// The mobile ticket creation flow had no priority/SLA field anywhere, despite the backend
// (TicketPriorityEnum) and web both supporting it. Covers NewTicketFormState's new `priority`
// field: it must default to the backend's own default ("Media") rather than null, so a
// technician who never touches the picker still sends an explicit, correct value — and
// copyWith must carry it like every other field.

import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/features/ticket/new_ticket_form_state.dart';

void main() {
  group('NewTicketFormState.priority', () {
    test('defaults to Media, matching the backend default', () {
      const state = NewTicketFormState();
      expect(state.priority, 'Media');
      expect(state.priority, kDefaultTicketPriority);
    });

    test('copyWith updates priority', () {
      const state = NewTicketFormState();
      final updated = state.copyWith(priority: 'Urgente');
      expect(updated.priority, 'Urgente');
    });

    test('copyWith preserves priority when not specified', () {
      const state = NewTicketFormState(priority: 'Alta');
      final updated = state.copyWith(title: 'Guasto');
      expect(updated.priority, 'Alta');
      expect(updated.title, 'Guasto');
    });

    test('kTicketPriorities matches TicketPriorityEnum exactly (Bassa/Media/Alta/Urgente)', () {
      expect(kTicketPriorities, ['Bassa', 'Media', 'Alta', 'Urgente']);
    });
  });

  // Field-parity gap: web's TicketCreatePanel has dueDate/technicianNotes/agentId/tags,
  // mobile had no way to set any of them (create or edit).
  group('NewTicketFormState field-parity fields', () {
    test('dueDate/technicianNotes/agentId/tags default to null/empty', () {
      const state = NewTicketFormState();
      expect(state.dueDate, isNull);
      expect(state.technicianNotes, isNull);
      expect(state.agentId, isNull);
      expect(state.tags, isEmpty);
    });

    test('copyWith updates dueDate/technicianNotes/agentId/tags', () {
      const state = NewTicketFormState();
      final due = DateTime.utc(2026, 10, 1);
      final updated = state.copyWith(
        dueDate: due,
        technicianNotes: 'Verificare guarnizione',
        agentId: 'usr-agent-1',
        tags: const ['urgente', 'garanzia'],
      );
      expect(updated.dueDate, due);
      expect(updated.technicianNotes, 'Verificare guarnizione');
      expect(updated.agentId, 'usr-agent-1');
      expect(updated.tags, ['urgente', 'garanzia']);
    });

    test('copyWith preserves dueDate/technicianNotes/agentId/tags when not specified', () {
      final due = DateTime.utc(2026, 10, 1);
      final state = NewTicketFormState(
        dueDate: due,
        technicianNotes: 'note',
        agentId: 'usr-1',
        tags: const ['a'],
      );
      final updated = state.copyWith(title: 'Guasto');
      expect(updated.dueDate, due);
      expect(updated.technicianNotes, 'note');
      expect(updated.agentId, 'usr-1');
      expect(updated.tags, ['a']);
    });

    test('clearX flags null out dueDate/technicianNotes/agentId', () {
      final state = NewTicketFormState(
        dueDate: DateTime.utc(2026, 10, 1),
        technicianNotes: 'note',
        agentId: 'usr-1',
      );
      final cleared = state.copyWith(
        clearDueDate: true,
        clearTechnicianNotes: true,
        clearAgentId: true,
      );
      expect(cleared.dueDate, isNull);
      expect(cleared.technicianNotes, isNull);
      expect(cleared.agentId, isNull);
    });
  });

  // Ticket parity with web's TicketCreatePanel: the create request can carry contractId,
  // commessaId, cantiereId and prodottoAssistenzaIds (CreateTicketRequest), and the wizard had no
  // way to fill any of them.
  group('NewTicketFormState reference fields', () {
    test('default to null/empty — a reference is an enrichment, not a required field', () {
      const state = NewTicketFormState();
      expect(state.contractId, isNull);
      expect(state.commessaId, isNull);
      expect(state.cantiereId, isNull);
      expect(state.prodottoAssistenzaIds, isEmpty);
    });

    test('the new reference fields round-trip through copyWith and clear independently', () {
      const s = NewTicketFormState();
      final withRefs = s.copyWith(
        contractId: 'c1',
        commessaId: 'm1',
        cantiereId: 'ca1',
        prodottoAssistenzaIds: const ['p1', 'p2'],
      );

      expect(withRefs.contractId, 'c1');
      expect(withRefs.commessaId, 'm1');
      expect(withRefs.cantiereId, 'ca1');
      expect(withRefs.prodottoAssistenzaIds, ['p1', 'p2']);
      expect(withRefs.copyWith(clearContractId: true).contractId, isNull);
      expect(
        withRefs.copyWith(clearContractId: true).commessaId,
        'm1',
        reason: 'clearing one reference must not clear its neighbours',
      );
      expect(withRefs.copyWith(clearCommessaId: true).commessaId, isNull);
      expect(withRefs.copyWith(clearCantiereId: true).cantiereId, isNull);
      expect(withRefs.copyWith(clearProdottoAssistenzaIds: true).prodottoAssistenzaIds, isEmpty);
    });

    test('copyWith preserves the reference fields when it does not mention them', () {
      const state = NewTicketFormState(
        contractId: 'c1',
        commessaId: 'm1',
        cantiereId: 'ca1',
        prodottoAssistenzaIds: ['p1'],
      );
      final updated = state.copyWith(title: 'Guasto');
      expect(updated.contractId, 'c1');
      expect(updated.commessaId, 'm1');
      expect(updated.cantiereId, 'ca1');
      expect(updated.prodottoAssistenzaIds, ['p1']);
    });

    test('none of the four is required to submit', () {
      // The existing isValid contract, unchanged: customerId, locationId, non-empty title, typeId,
      // statusId. A reference is an enrichment, and the wizard must not start blocking on it.
      expect(
        const NewTicketFormState(
          title: 'x',
          customerId: 'cu',
          locationId: 'l',
          typeId: 1,
          statusId: 1,
        ).isValid,
        isTrue,
      );
    });
  });

  // ── Repair-mode seeding (Task B6) ───────────────────────────────────────────
  //
  // The wizard opened on an outbox row the server refused. It is seeded from that row — every field
  // but the one the server would reject again if it were sent unchanged.
  group('NewTicketFormState.fromPendingRow (repair)', () {
    /// A queued row as `PendingTickets` holds it. The defaults here are the column defaults; the
    /// fields under test are the arguments.
    PendingTicket row({
      String? repairableField,
      String? agentId = 'agent-gone',
      String? contractId = 'con-1',
      String? commessaId = 'com-1',
      String? cantiereId = 'can-1',
      String? prodottoAssistenzaIdsJson = '["prod-1","prod-2"]',
      String? tagsJson = '["urgente"]',
    }) => PendingTicket(
      id: 'pt-1',
      createdAt: DateTime.utc(2026, 6, 1),
      title: 'Perdita idrica',
      description: 'Dal bagno',
      customerId: 'cust-1',
      locationId: 'loc-1',
      assignedUserId: 'tech-1',
      statusId: 1,
      typeId: 2,
      priorita: 'Alta',
      state: 'failed',
      error: 'Non trovato sul server.',
      dueDate: DateTime.utc(2026, 7, 1),
      technicianNotes: 'Portare guarnizione',
      agentId: agentId,
      contractId: contractId,
      commessaId: commessaId,
      cantiereId: cantiereId,
      prodottoAssistenzaIdsJson: prodottoAssistenzaIdsJson,
      repairableField: repairableField,
      tagsJson: tagsJson,
    );

    test('drops the blamed field and keeps every other value', () {
      final seed = NewTicketFormState.fromPendingRow(row(repairableField: 'agentId'));

      expect(seed.agentId, isNull, reason: 'preloading the rejected id makes Salva a no-op');
      expect(seed.customerId, 'cust-1');
      expect(seed.locationId, 'loc-1');
      expect(seed.title, 'Perdita idrica');
      expect(seed.description, 'Dal bagno');
      expect(seed.typeId, 2);
      expect(seed.statusId, 1);
      expect(seed.assignedUserId, 'tech-1');
      expect(seed.priority, 'Alta');
      expect(seed.dueDate, DateTime.utc(2026, 7, 1));
      expect(seed.technicianNotes, 'Portare guarnizione');
      expect(seed.contractId, 'con-1');
      expect(seed.commessaId, 'com-1');
      expect(seed.cantiereId, 'can-1');
      expect(seed.prodottoAssistenzaIds, ['prod-1', 'prod-2']);
      expect(seed.tags, ['urgente']);
      // Dropping the Riferimento does not make the ticket unsaveable — it was never required.
      expect(seed.isValid, isTrue);
    });

    test('an ordinary row (no blamed field) seeds every value, unchanged', () {
      final seed = NewTicketFormState.fromPendingRow(row());

      expect(seed.agentId, 'agent-gone');
      expect(seed.customerId, 'cust-1');
      expect(seed.prodottoAssistenzaIds, ['prod-1', 'prod-2']);
      expect(seed.isValid, isTrue);
    });

    test('a blamed required field leaves the seed invalid, so the save stays blocked', () {
      // customerId is required and is what the server refused. Seeding it back would re-send the
      // same rejected id; dropping it is what makes the wizard's own validation the thing that
      // forces a real replacement to be picked.
      final seed = NewTicketFormState.fromPendingRow(row(repairableField: 'customerId'));

      expect(seed.customerId, isNull);
      expect(
        seed.isValid,
        isFalse,
        reason: 'Salva must not be reachable until a customer is picked',
      );
      // The rest of the ticket survives the trip — the technician re-picks one field, not fifteen.
      expect(seed.title, 'Perdita idrica');
      expect(seed.typeId, 2);
      expect(seed.agentId, 'agent-gone');
    });

    test('each of the eight repairable fields is the one dropped, and only it', () {
      // Spelled out one by one rather than looped over the state's getters: `customerId` and
      // `locationId` are non-nullable on the ROW, so their drop can only be observed as a null on
      // the SEED — an asymmetry a loop over field names would paper straight over.
      final customerId = NewTicketFormState.fromPendingRow(row(repairableField: 'customerId'));
      expect(customerId.customerId, isNull);
      expect(customerId.locationId, 'loc-1');

      final locationId = NewTicketFormState.fromPendingRow(row(repairableField: 'locationId'));
      expect(locationId.locationId, isNull);
      expect(locationId.customerId, 'cust-1');

      final typeId = NewTicketFormState.fromPendingRow(row(repairableField: 'typeId'));
      expect(typeId.typeId, isNull);
      expect(typeId.title, 'Perdita idrica');

      final assignedUserId = NewTicketFormState.fromPendingRow(
        row(repairableField: 'assignedUserId'),
      );
      expect(assignedUserId.assignedUserId, isNull);

      final contractId = NewTicketFormState.fromPendingRow(row(repairableField: 'contractId'));
      expect(contractId.contractId, isNull);
      expect(contractId.commessaId, 'com-1', reason: 'only the blamed reference goes');

      final commessaId = NewTicketFormState.fromPendingRow(row(repairableField: 'commessaId'));
      expect(commessaId.commessaId, isNull);
      expect(commessaId.contractId, 'con-1');

      final prodotti = NewTicketFormState.fromPendingRow(
        row(repairableField: 'prodottoAssistenzaIds'),
      );
      expect(prodotti.prodottoAssistenzaIds, isEmpty);
      expect(prodotti.agentId, 'agent-gone');
    });

    test('a row with no products or tags at all seeds empties, not nulls', () {
      final seed = NewTicketFormState.fromPendingRow(
        row(prodottoAssistenzaIdsJson: null, tagsJson: null, agentId: null),
      );

      expect(seed.prodottoAssistenzaIds, isEmpty);
      expect(seed.tags, isEmpty);
      expect(seed.agentId, isNull);
    });
  });
}
