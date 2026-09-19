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
}
