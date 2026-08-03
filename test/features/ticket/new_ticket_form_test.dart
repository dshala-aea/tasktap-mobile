// test/features/ticket/new_ticket_form_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tasktap_mobile/features/ticket/new_ticket_form_state.dart';

void main() {
  group('NewTicketFormState', () {
    test('initial state has all fields null', () {
      const state = NewTicketFormState();
      expect(state.customerId, isNull);
      expect(state.locationId, isNull);
      expect(state.title, isNull);
      expect(state.description, isNull);
      expect(state.typeId, isNull);
      expect(state.statusId, isNull);
      expect(state.assignedUserId, isNull);
    });

    test('copyWith preserves unmentioned fields', () {
      const initial = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: 'Test',
        typeId: 2,
        statusId: 1,
      );

      final updated = initial.copyWith(title: 'Updated');
      expect(updated.customerId, 'c1');
      expect(updated.locationId, 'l1');
      expect(updated.title, 'Updated');
      expect(updated.typeId, 2);
      expect(updated.statusId, 1);
    });

    test('copyWith with clear flags sets fields to null', () {
      const initial = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: 'Test',
      );

      final updated = initial.copyWith(
        clearCustomerId: true,
        clearLocationId: true,
      );
      expect(updated.customerId, isNull);
      expect(updated.locationId, isNull);
      expect(updated.title, 'Test');
    });

    test('isValid returns false when required fields are missing', () {
      const empty = NewTicketFormState();
      expect(empty.isValid, isFalse);

      const justCustomer = NewTicketFormState(customerId: 'c1');
      expect(justCustomer.isValid, isFalse);

      const justTitle = NewTicketFormState(title: 'Test');
      expect(justTitle.isValid, isFalse);
    });

    test('isValid returns true when all required fields are set', () {
      const valid = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: 'Manutenzione',
        typeId: 1,
        statusId: 1,
      );
      expect(valid.isValid, isTrue);
    });

    test('isValid returns false for empty title', () {
      const state = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: '   ',
        typeId: 1,
        statusId: 1,
      );
      expect(state.isValid, isFalse);
    });

    test('isValid does not require assignedUserId', () {
      const withoutAssignment = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: 'Test',
        typeId: 1,
        statusId: 1,
      );
      expect(withoutAssignment.isValid, isTrue);

      const withAssignment = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: 'Test',
        typeId: 1,
        statusId: 1,
        assignedUserId: 'u1',
      );
      expect(withAssignment.isValid, isTrue);
    });

    test('copyWith cascade preserves all fields', () {
      const initial = NewTicketFormState();
      final step1 = initial.copyWith(customerId: 'c1');
      final step2 = step1.copyWith(locationId: 'l1');
      final step3 = step2.copyWith(title: 'Manutenzione', typeId: 2);
      final step4 = step3.copyWith(statusId: 1);

      expect(step4.isValid, isTrue);
      expect(step4.customerId, 'c1');
      expect(step4.locationId, 'l1');
      expect(step4.title, 'Manutenzione');
      expect(step4.typeId, 2);
      expect(step4.statusId, 1);
    });
  });
}
