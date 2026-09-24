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
}
