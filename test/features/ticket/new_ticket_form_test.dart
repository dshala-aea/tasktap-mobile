// test/features/ticket/new_ticket_form_test.dart
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/new_ticket_form_screen.dart';
import 'package:tasktap_mobile/features/ticket/new_ticket_form_state.dart';

class MockDio extends Mock implements Dio {}

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

    // CreateTicketRequest on the backend requires customerId, locationId,
    // statusId and typeId as non-nullable — verify each one individually
    // blocks submission when missing, not just the aggregate empty-state case.
    test('isValid is false when only customerId is missing', () {
      const state = NewTicketFormState(
        locationId: 'l1',
        title: 'Manutenzione',
        typeId: 1,
        statusId: 1,
      );
      expect(state.isValid, isFalse);
    });

    test('isValid is false when only locationId is missing', () {
      const state = NewTicketFormState(
        customerId: 'c1',
        title: 'Manutenzione',
        typeId: 1,
        statusId: 1,
      );
      expect(state.isValid, isFalse);
    });

    test('isValid is false when only statusId is missing', () {
      const state = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: 'Manutenzione',
        typeId: 1,
      );
      expect(state.isValid, isFalse);
    });

    test('isValid is false when only typeId is missing', () {
      const state = NewTicketFormState(
        customerId: 'c1',
        locationId: 'l1',
        title: 'Manutenzione',
        statusId: 1,
      );
      expect(state.isValid, isFalse);
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

  // ══════════════════════════════════════════════════════════════════════════
  // Widget-level: the wizard actually blocks progression on the real screen.
  //
  // The four required fields aren't validated behind a single submit button —
  // NewTicketFormScreen is a 4-step wizard (Cliente/Sede → Dettagli →
  // Assegna → Riepilogo) and the "Avanti" button on each step is disabled
  // (onPressed: null) until that step's required fields are set:
  //   - Cliente/Sede step: customerId + locationId
  //   - Dettagli step:     title + typeId
  // statusId is auto-assigned from the cached TicketStatuses the moment the
  // screen loads (see _ensureDefaultStatus), which is why it's covered by
  // the isValid unit tests above rather than a UI step of its own.
  group('NewTicketFormScreen wizard', () {
    late AppDatabase db;
    late MockDio mockDio;

    setUpAll(() {
      registerFallbackValue(RequestOptions(path: '/'));
    });

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase(NativeDatabase.memory());
      mockDio = MockDio();

      await db.into(db.customers).insert(CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Acme Srl',
          ));
      await db.into(db.locations).insert(LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ));
      await db.into(db.ticketTypes).insert(TicketTypesCompanion.insert(
            id: const Value(1),
            tenantId: 'tenant-1',
            name: 'Manutenzione',
          ));
      await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
            id: const Value(1),
            tenantId: 'tenant-1',
            name: 'Aperto',
          ));
    });

    tearDown(() async {
      await db.close();
    });

    Widget buildScreen() {
      return ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dioProvider.overrideWithValue(mockDio),
        ],
        child: const MaterialApp(home: NewTicketFormScreen()),
      );
    }

    AppButton avantiButton(WidgetTester tester) =>
        tester.widget<AppButton>(find.widgetWithText(AppButton, 'Avanti'));

    testWidgets(
        'blocks submit until cliente, sede, titolo and tipo are chosen',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pumpAndSettle();

      // ── Step 1 (Cliente/Sede): neither field chosen → Avanti disabled ──
      expect(avantiButton(tester).onPressed, isNull);

      // Choose cliente only — sede still missing, still blocked.
      await tester.tap(find.byKey(const ValueKey('cliente-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Srl').last);
      await tester.pumpAndSettle();
      expect(avantiButton(tester).onPressed, isNull);

      // Choose sede too — step 1's requirements are now satisfied.
      await tester.tap(find.byKey(const ValueKey('sede-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede Milano').last);
      await tester.pumpAndSettle();
      expect(avantiButton(tester).onPressed, isNotNull);

      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      // ── Step 2 (Dettagli): titolo + tipo required ───────────────────────
      expect(avantiButton(tester).onPressed, isNull);

      await tester.enterText(
        find.byType(TextFormField).first,
        'Perdita idrica',
      );
      await tester.pump();
      // Titolo alone isn't enough — tipo is still missing.
      expect(avantiButton(tester).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('tipo-null')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manutenzione').last);
      await tester.pumpAndSettle();
      expect(avantiButton(tester).onPressed, isNotNull);

      // Never reached Riepilogo, and the mock Dio was never asked to POST —
      // proof that nothing got submitted while fields were missing.
      verifyNever(() => mockDio.post<Map<String, dynamic>>(
            any(),
            data: any(named: 'data'),
          ));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
