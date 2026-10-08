// test/features/ticket/ticket_list_screen_test.dart
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/ticket/steps/blamed_field_notice.dart';
import 'package:tasktap_mobile/features/ticket/ticket_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Widget _buildList({required AppDatabase db, required MockAuthRepository repo}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
    ],
    child: const MaterialApp(home: TicketListScreen()),
  );
}

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    registerFallbackValue(RequestOptions(path: '/'));
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;
  late MockAuthRepository repo;
  late StreamController<AuthUser?> authStream;

  final fakeUser = AuthUser(
    id: 'u1',
    email: 'mario@tasktap.io',
    accessToken: 'token',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
  );

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MockAuthRepository();
    authStream = StreamController<AuthUser?>.broadcast();
    when(() => repo.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => repo.currentUser).thenReturn(fakeUser);
  });

  tearDown(() async {
    authStream.close();
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(_buildList(db: db, repo: repo));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  group('TicketListScreen', () {
    testWidgets('shows empty state when no tickets', (tester) async {
      await pump(tester);
      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders a row per ticket, titled', (tester) async {
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Perdita idrica',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
            ),
          );
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't2',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 2),
              title: 'Manutenzione caldaia',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 2,
              typeId: 1,
            ),
          );

      await pump(tester);

      // Vetro (module #2) replaced ListRow with a bespoke priority-striped row — the behaviour
      // that matters is "one row per ticket, showing its title," not the widget type underneath.
      expect(find.text('Perdita idrica'), findsOneWidget);
      expect(find.text('Manutenzione caldaia'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('filter chip narrows list to matching status', (tester) async {
      // Seed a status map
      await db
          .into(db.ticketStatuses)
          .insert(
            TicketStatusesCompanion.insert(
              id: const Value(1),
              tenantId: 'tenant-1',
              name: 'Aperto',
            ),
          );
      await db
          .into(db.ticketStatuses)
          .insert(
            TicketStatusesCompanion.insert(
              id: const Value(2),
              tenantId: 'tenant-1',
              name: 'In corso',
            ),
          );

      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Ticket aperto',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
            ),
          );
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't2',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 2),
              title: 'Ticket in corso',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 2,
              typeId: 1,
            ),
          );

      await pump(tester);

      // Tap "In corso" chip
      await tester.tap(find.text('In corso').first);
      await tester.pumpAndSettle();

      expect(find.text('Ticket in corso'), findsOneWidget);
      expect(find.text('Ticket aperto'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows StatusPill with resolved status name', (tester) async {
      await db
          .into(db.ticketStatuses)
          .insert(
            TicketStatusesCompanion.insert(
              id: const Value(1),
              tenantId: 'tenant-1',
              name: 'Aperto',
            ),
          );
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Un ticket',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
            ),
          );

      await pump(tester);

      expect(find.byType(StatusPill), findsOneWidget);
      // StatusPill renders through StatusStamp now, which uppercases per Il Documento's
      // all-caps stamp spec — see status_pill_test.dart's own note on this.
      expect(find.text('APERTO'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows AppFab', (tester) async {
      await pump(tester);
      expect(find.byType(AppFab), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    // ── Pending tickets (2026-08-30 polish pass) ────────────────────────────
    //
    // A queued-offline ticket that fails on retry used to flip its row's background and icon
    // instantly. AnimatedContainer/AnimatedSwitcher animate that now (see _PendingTicketRow) —
    // the assertions below cover the end state pumpAndSettle lands on, not the animation itself,
    // which is exactly what a widget test can verify without a golden/frame-by-frame capture.

    testWidgets(
      'a failed pending ticket shows the retry button and failure styling',
      (tester) async {
        await db
            .into(db.pendingTickets)
            .insert(
              PendingTicketsCompanion.insert(
                id: 'pt-1',
                createdAt: DateTime.utc(2026, 6, 1),
                title: 'Ticket in sospeso',
                customerId: 'cust-1',
                locationId: 'loc-1',
                statusId: 1,
                typeId: 1,
                state: const Value('failed'),
              ),
            );

        await pump(tester);

        expect(find.text('In sospeso (1)'), findsOneWidget);
        expect(find.text('Ticket in sospeso'), findsOneWidget);
        expect(find.textContaining('Invio non riuscito'), findsOneWidget);
        expect(find.text('Riprova'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a queued-offline pending ticket has no retry button', (
      tester,
    ) async {
      await db
          .into(db.pendingTickets)
          .insert(
            PendingTicketsCompanion.insert(
              id: 'pt-2',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Ticket in coda',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
              state: const Value('pendingSync'),
            ),
          );

      await pump(tester);

      expect(find.text('Ticket in coda'), findsOneWidget);
      expect(find.textContaining('attesa di connessione'), findsOneWidget);
      expect(find.text('Riprova'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    // ── A row the server refused for one bad reference (Task B6) ────────────
    //
    // The queue detected it and took the row out of the retry sweeps; this is the other half — the
    // list has to say so and get the technician into the wizard. Everything below is about which of
    // the two affordances a row is offered: a resend that cannot succeed, or a repair.

    testWidgets(
      'a rejected queue row is offered as "Da correggere", not as a retry',
      (tester) async {
        await db
            .into(db.pendingTickets)
            .insert(
              PendingTicketsCompanion.insert(
                id: 'pt-rep',
                createdAt: DateTime.utc(2026, 6, 1),
                title: 'Perdita idrica',
                customerId: 'cust-gone',
                locationId: 'loc-1',
                statusId: 1,
                typeId: 1,
                state: const Value('failed'),
                error: const Value(
                  'Non trovato sul server. Potrebbe essere stato eliminato.',
                ),
                repairableField: const Value('customerId'),
              ),
            );

        await pump(tester);

        expect(find.text('Da correggere'), findsOneWidget);
        expect(find.text('Correggi'), findsOneWidget);
        // No "Riprova": a resend would carry the very id the server just refused.
        expect(find.text('Riprova'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'a row the client cannot repair shows the ordinary failure, not a repair',
      (tester) async {
        await db
            .into(db.pendingTickets)
            .insert(
              PendingTicketsCompanion.insert(
                id: 'pt-norep',
                createdAt: DateTime.utc(2026, 6, 1),
                title: 'Guasto caldaia',
                customerId: 'cust-1',
                locationId: 'loc-1',
                statusId: 1,
                typeId: 1,
                state: const Value('failed'),
                error: const Value('Errore del server'),
              ),
            );

        await pump(tester);

        expect(find.text('Da correggere'), findsNothing);
        expect(find.text('Correggi'), findsNothing);
        expect(find.textContaining('Errore del server'), findsOneWidget);
        expect(find.text('Riprova'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '"Correggi" opens the wizard in repair mode, on the step that owns the field',
      (tester) async {
        await db
            .into(db.pendingTickets)
            .insert(
              PendingTicketsCompanion.insert(
                id: 'pt-rep2',
                createdAt: DateTime.utc(2026, 6, 1),
                title: 'Perdita idrica',
                customerId: 'cust-1',
                locationId: 'loc-1',
                statusId: 1,
                typeId: 1,
                state: const Value('failed'),
                agentId: const Value('agent-gone'),
                repairableField: const Value('agentId'),
              ),
            );

        await pump(tester);
        await tester.tap(find.text('Correggi'));
        await tester.pumpAndSettle();

        // The wizard, in its repair wording, opened on Dettagli — the step that owns `agentId` — and
        // not on the first step, which is what it opens for the references that live there. The title
        // field is itself the proof: it only exists on Dettagli, and it was seeded from the row rather
        // than reset.
        expect(find.text('Correggi ticket'), findsOneWidget);
        expect(find.text('Dettagli'), findsOneWidget);
        expect(find.text('2 di 4'), findsOneWidget);
        expect(find.text('Perdita idrica'), findsOneWidget);

        // The notice sits above the Riferimento field, at the bottom of the step — below the fold in a
        // test viewport, and a lazily-built ListView does not even create it until it is scrolled to.
        await tester.dragUntilVisible(
          find.text(kBlamedFieldNotice),
          find.byType(ListView).first,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(find.text(kBlamedFieldNotice), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );

    testWidgets('a blamed customer opens on the first step, where that field is', (
      tester,
    ) async {
      await db
          .into(db.pendingTickets)
          .insert(
            PendingTicketsCompanion.insert(
              id: 'pt-rep3',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Perdita idrica',
              customerId: 'cust-gone',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
              state: const Value('failed'),
              repairableField: const Value('customerId'),
            ),
          );

      await pump(tester);
      await tester.tap(find.text('Correggi'));
      await tester.pumpAndSettle();

      expect(find.text('Correggi ticket'), findsOneWidget);
      // Step 1, and the reason its Cliente field is empty — right where the field is, not in a banner
      // at the top of a step the technician would have to leave to act on it.
      expect(find.text('1 di 4'), findsOneWidget);
      expect(find.text(kBlamedFieldNotice), findsOneWidget);
      // The title lives on step 2 and is not on screen — the seed is there, the step is here.
      expect(find.text('Perdita idrica'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
