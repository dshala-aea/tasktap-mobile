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

      // Priority is deliberately absent — see StepDettagliTicket.showPriority's doc comment
      // (the local ticket mirror carries no priorita column to pre-fill from).
      expect(find.text('Priorità'), findsNothing);

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
      // Never sent: no PUT field for it (see UpdateTicketRequest / AdminApiClient.updateTicket's
      // own doc comment), and it would silently reset the ticket's real priority to whatever the
      // picker defaulted to if it were.
      expect(sentData.containsKey('priorita'), isFalse);
      expect(sentData.containsKey('statusId'), isFalse);

      final row = await (db.select(db.tickets)..where((t) => t.id.equals('ticket-1'))).getSingle();
      expect(row.title, 'Perdita idrica bagno — riparata parzialmente');

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
