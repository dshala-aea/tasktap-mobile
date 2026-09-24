// dart format width=100
// test/features/ticket/edit_ticket_screen_test.dart
//
// Covers the three load-bearing behaviours of EditTicketScreen: it pre-fills
// from the current ticket (reusing StepClienteSede/StepDettagliTicket in
// "edit mode"), a save sends a correct PUT and mirrors the accepted values
// into the local Drift ticket row, and a failed save surfaces the error to
// the technician instead of silently discarding what they typed.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/app_button.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/ticket/edit_ticket_screen.dart';

class MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
  });

  late AppDatabase db;
  late MockDio mockDio;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    mockDio = MockDio();

    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Acme Srl',
          ),
        );
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'Beta Spa',
          ),
        );
    await db
        .into(db.locations)
        .insert(
          LocationsCompanion.insert(
            id: 'loc-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            customerId: 'cust-1',
            name: 'Sede Milano',
          ),
        );
    await db
        .into(db.ticketTypes)
        .insert(
          TicketTypesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Assistenza'),
        );
    await db
        .into(db.ticketTypes)
        .insert(
          TicketTypesCompanion.insert(id: const Value(2), tenantId: 'tenant-1', name: 'Manutenzione'),
        );
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Aperto'),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1, 9),
            title: 'Perdita idrica bagno',
            description: const Value('Acqua che perde dal tubo.'),
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            priority: const Value('Alta'),
          ),
        );

    // Field-parity gap fixture: a technician list for the Riferimento picker's techniciansProvider.
    when(
      () => mockDio.get<Map<String, dynamic>>('/api/users', queryParameters: any(named: 'queryParameters')),
    ).thenAnswer(
      (_) async => Response<Map<String, dynamic>>(
        statusCode: 200,
        requestOptions: RequestOptions(path: '/api/users'),
        data: {
          'items': [
            {'id': 'usr-agent-1', 'firstName': 'Luca', 'lastName': 'Bianchi'},
          ],
        },
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  // Wraps the screen behind a launcher (mirrors _openEditTicket's own Navigator.push, and
  // new_ticket_form_test.dart's identical reasoning): EditTicketScreen calls Navigator.pop() on
  // save, and popping MaterialApp's lone root route is not what production ever does.
  Widget buildLauncher() {
    return ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        dioProvider.overrideWithValue(mockDio),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const EditTicketScreen(ticketId: 'ticket-1')),
                ),
                child: const Text('Apri modifica'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openEditor(WidgetTester tester) async {
    await tester.pumpWidget(buildLauncher());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apri modifica'));
    await tester.pumpAndSettle();
  }

  AppButton salvaOrAvantiButton(WidgetTester tester, String label) =>
      tester.widget<AppButton>(find.widgetWithText(AppButton, label));

  group('EditTicketScreen — pre-fill', () {
    testWidgets('opens pre-filled with the current customer, location and title', (tester) async {
      await openEditor(tester);

      // Step 1 (Cliente/Sede): the dropdowns show the ticket's current selections closed, not
      // an empty "Seleziona cliente…" hint — that is the whole point of "edit", not "recreate".
      expect(find.text('Acme Srl'), findsOneWidget);
      expect(find.text('Sede Milano'), findsOneWidget);

      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      // Step 2 (Dettagli): title/description pre-filled, type dropdown shows the current type.
      expect(find.text('Perdita idrica bagno'), findsOneWidget);
      expect(find.text('Acqua che perde dal tubo.'), findsOneWidget);
      expect(find.text('Assistenza'), findsOneWidget);

      // Priority pre-fills from the ticket's real value (schema 20 already syncs it down) rather
      // than defaulting to "Media" and silently resetting it on the next save. AppFieldLabel
      // upper-cases its text, so the rendered label is "PRIORITÀ", not "Priorità".
      expect(find.text('PRIORITÀ'), findsOneWidget);
      expect(find.text('Alta'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // Field-parity gap: web's ticket edit form has dueDate/technicianNotes/agentId/tags, mobile had
  // no way to set any of them (pre-fill or save).
  group('EditTicketScreen — field-parity fields (dueDate/technicianNotes/agentId/tags)', () {
    testWidgets('opens pre-filled with the ticket\'s current dueDate/technicianNotes/agentId/tags', (
      tester,
    ) async {
      await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
        TicketsCompanion(
          dueDate: Value(DateTime.utc(2026, 10, 1)),
          technicianNotes: const Value('Verificare guarnizione'),
          agentId: const Value('usr-agent-1'),
          tagsJson: const Value('["urgente","garanzia"]'),
        ),
      );

      await openEditor(tester);
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      // The new fields sit below Priority — off the test surface's default viewport until
      // scrolled into it (standard Sliver behaviour, same reasoning as new_ticket_form_test.dart's
      // own scrollUntilVisible for "Crea ticket" — a fixed drag here, not scrollUntilVisible,
      // since that helper's own scroll-and-recheck loop transiently double-matches these keyed
      // fields; see the next test's identical comment).
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('01/10/2026'), findsOneWidget);
      expect(find.text('Verificare guarnizione'), findsOneWidget);
      expect(find.text('Luca Bianchi'), findsOneWidget);
      expect(find.text('urgente, garanzia'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('editing technicianNotes and tags sends them on the PUT and mirrors them locally', (
      tester,
    ) async {
      when(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/tickets/ticket-1'),
        ),
      );

      await openEditor(tester);
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      // Below the fold — see the pre-fill test's own comment on scrollUntilVisible.
      final notesField = find.descendant(
        of: find.byKey(const ValueKey('technician-notes-field')),
        matching: find.byType(TextFormField),
      );
      final tagsField = find.descendant(
        of: find.byKey(const ValueKey('tags-field')),
        matching: find.byType(TextFormField),
      );
      // Below the fold — scrollUntilVisible's own iterative scroll-and-recheck loop transiently
      // double-matches these keyed fields (repro'd, root cause not pinned down); a single fixed
      // drag avoids it and is exactly what a technician's own swipe does anyway.
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.enterText(notesField, 'Verificare guarnizione');
      await tester.enterText(tagsField, 'urgente, garanzia');
      await tester.pump();

      final salva = salvaOrAvantiButton(tester, 'Salva');
      salva.onPressed!();
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: captureAny(named: 'data')),
      ).captured;
      final sentData = captured.single as Map<String, dynamic>;
      expect(sentData['technicianNotes'], 'Verificare guarnizione');
      expect(sentData['tags'], ['urgente', 'garanzia']);

      final row = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
      expect(row.technicianNotes, 'Verificare guarnizione');
      expect(row.tagsJson, '["urgente","garanzia"]');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('picking Riferimento sends agentId on the PUT and mirrors it locally', (
      tester,
    ) async {
      when(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/tickets/ticket-1'),
        ),
      );

      await openEditor(tester);
      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      // Below the fold — see the pre-fill test's own comment on the fixed-drag approach.
      final agentField = find.byKey(const ValueKey('agent-field'));
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.tap(agentField);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agent-picker-usr-agent-1')));
      await tester.pumpAndSettle();

      final salva = salvaOrAvantiButton(tester, 'Salva');
      salva.onPressed!();
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: captureAny(named: 'data')),
      ).captured;
      final sentData = captured.single as Map<String, dynamic>;
      expect(sentData['agentId'], 'usr-agent-1');

      final row = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
      expect(row.agentId, 'usr-agent-1');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('EditTicketScreen — save', () {
    testWidgets('submitting sends a PUT with the edited fields and mirrors them locally', (
      tester,
    ) async {
      when(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/tickets/ticket-1'),
        ),
      );

      await openEditor(tester);

      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Perdita idrica bagno'),
        'Perdita idrica bagno — riparata parzialmente',
      );
      await tester.pump();

      final salva = salvaOrAvantiButton(tester, 'Salva');
      salva.onPressed!();
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: captureAny(named: 'data')),
      ).captured;
      final sentData = captured.single as Map<String, dynamic>;
      expect(sentData['title'], 'Perdita idrica bagno — riparata parzialmente');
      expect(sentData['description'], 'Acqua che perde dal tubo.');
      expect(sentData['customerId'], 'cust-1');
      expect(sentData['locationId'], 'loc-1');
      expect(sentData['typeId'], 1);
      // The ticket's real, unchanged priority — round-tripped, not reset to a picker default.
      expect(sentData['priorita'], 'Alta');
      // Status has its own dedicated PUT (_TicketStatusRowState._changeStatus) — never sent here.
      expect(sentData.containsKey('statusId'), isFalse);

      final row = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
      expect(row.title, 'Perdita idrica bagno — riparata parzialmente');
      expect(row.priority, 'Alta');

      expect(find.text('Ticket aggiornato'), findsOneWidget);
      // Popped back to the caller — the screen didn't get stuck on save.
      expect(find.text('Apri modifica'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('changing the sede and the tipo both thread through to the PUT', (tester) async {
      when(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: RequestOptions(path: '/api/tickets/ticket-1'),
        ),
      );
      await db
          .into(db.locations)
          .insert(
            LocationsCompanion.insert(
              id: 'loc-2',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              customerId: 'cust-1',
              name: 'Sede Torino',
            ),
          );

      await openEditor(tester);

      // Step 1: same cliente, different sede. The field opens already resolved (locationId:
      // 'loc-1'), and AppLookupField shows no suggestions for an already-resolved field until
      // its text actually changes (see lookup_field.dart's own _suggestions getter) — a tap alone
      // doesn't surface the list the way it does on the new-ticket form's empty fields.
      await tester.tap(find.byKey(const ValueKey('sede-loc-1')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('sede-loc-1')),
          matching: find.byType(TextFormField),
        ),
        'Torino',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede Torino').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      // Step 2: different tipo.
      await tester.tap(find.byKey(const ValueKey('tipo-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manutenzione').last);
      await tester.pumpAndSettle();

      final salva = salvaOrAvantiButton(tester, 'Salva');
      salva.onPressed!();
      await tester.pumpAndSettle();

      final captured = verify(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: captureAny(named: 'data')),
      ).captured;
      final sentData = captured.single as Map<String, dynamic>;
      expect(sentData['customerId'], 'cust-1');
      expect(sentData['locationId'], 'loc-2');
      expect(sentData['typeId'], 2);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  group('EditTicketScreen — error handling', () {
    testWidgets('a failed save surfaces the error and keeps the edit in place', (tester) async {
      when(
        () => mockDio.put<dynamic>('/api/tickets/ticket-1', data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/tickets/ticket-1'),
          type: DioExceptionType.connectionError,
        ),
      );

      await openEditor(tester);

      await tester.tap(find.text('Avanti'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Perdita idrica bagno'),
        'Titolo che non deve andare perso',
      );
      await tester.pump();

      final salva = salvaOrAvantiButton(tester, 'Salva');
      salva.onPressed!();
      await tester.pumpAndSettle();

      // The technician's edit is not silently dropped: an honest, actionable message appears...
      expect(
        find.textContaining('Nessuna connessione: impossibile salvare le modifiche ora'),
        findsOneWidget,
      );
      // ...the screen stays put with what was typed still on screen (never popped)...
      expect(find.text('Titolo che non deve andare perso'), findsOneWidget);
      expect(find.byType(EditTicketScreen), findsOneWidget);

      // ...and the local ticket record is untouched — nothing unconfirmed by the server was
      // mirrored locally.
      final row = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
      expect(row.title, 'Perdita idrica bagno');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
