// dart format width=100
// test/features/ticket/new_ticket_form_state_test.dart
//
// The mobile ticket creation flow had no priority/SLA field anywhere, despite the backend
// (TicketPriorityEnum) and web both supporting it. Covers NewTicketFormState's new `priority`
// field: it must default to the backend's own default ("Media") rather than null, so a
// technician who never touches the picker still sends an explicit, correct value — and
// copyWith must carry it like every other field.

import 'package:flutter_test/flutter_test.dart';
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
}
