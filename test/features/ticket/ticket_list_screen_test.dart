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
import 'package:tasktap_mobile/core/time/business_time.dart' show BusinessTime, formatDateOnly;
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/api/dio_client.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_providers.dart';
import 'package:tasktap_mobile/data/entitlements/entitlement_repository.dart';
import 'package:tasktap_mobile/data/local/app_database.dart' hide Entitlement;
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart' show appDatabaseProvider;
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/ticket/steps/blamed_field_notice.dart';
import 'package:tasktap_mobile/features/ticket/ticket_list_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

class _FakeConnectivity extends ConnectivityNotifier {
  _FakeConnectivity(this._value);
  final bool _value;

  @override
  Future<bool> build() async => _value;
}

Entitlement _entitlementWith(Set<String> capabilities) => Entitlement(
  features: const {'interventi'},
  capabilities: capabilities,
  seatType: 'field',
  fetchedAt: DateTime.utc(2026, 11, 9),
);

Widget _buildList({
  required AppDatabase db,
  required MockAuthRepository repo,
  bool online = true,
  String? myId = 'u1',
  Entitlement? entitlement,
}) {
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
      connectivityProvider.overrideWith(() => _FakeConnectivity(online)),
      internalUserIdProvider.overrideWith((ref) async => myId),
      cachedEntitlementProvider.overrideWith(
        (ref) async => entitlement ?? _entitlementWith(const {'interventi.ticket.write'}),
      ),
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

  Future<void> pump(
    WidgetTester tester, {
    bool online = true,
    String? myId = 'u1',
    Entitlement? entitlement,
  }) async {
    await tester.pumpWidget(
      _buildList(
        db: db,
        repo: repo,
        online: online,
        myId: myId,
        entitlement: entitlement,
      ),
    );
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> disposeScreen(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  Future<void> seedStatus(
    int id,
    String name, {
    bool isInProgress = false,
    bool isClosed = false,
  }) async {
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(
            id: Value(id),
            tenantId: 'tenant-1',
            name: name,
            isInProgress: Value(isInProgress),
            isClosed: Value(isClosed),
          ),
        );
  }

  Future<void> seedTicket({
    required String id,
    required String title,
    int statusId = 1,
    String customerId = 'cust-1',
    String locationId = 'loc-1',
    String? dueDate,
    String? priority,
    String? assignedUserId,
    String? agentId,
    DateTime? createdAt,
  }) async {
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: id,
            tenantId: 'tenant-1',
            createdAt: createdAt ?? DateTime.utc(2026, 6, 1),
            title: title,
            customerId: customerId,
            locationId: locationId,
            statusId: statusId,
            typeId: 1,
            dueDate: Value(dueDate),
            priority: Value(priority),
            assignedUserId: Value(assignedUserId),
            agentId: Value(agentId),
          ),
        );
  }

  group('TicketListScreen', () {
    testWidgets('shows empty state when no tickets', (tester) async {
      await pump(tester);
      expect(find.byType(EmptyState), findsOneWidget);
      await disposeScreen(tester);
    });

    /// Three different things reach the empty branch and only two of them are answers: a search
    /// that matches nothing, a phone that has never downloaded anything, and a tenant with no
    /// ticket. Showing one message for all three turned a typo into "this company has no tickets".
    testWidgets('a device that never synced says so, not "no tickets"', (tester) async {
      await pump(tester);

      expect(find.text('Ticket non ancora scaricati'), findsOneWidget);
      expect(find.text('Nessun ticket'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('after a sync, an empty mirror reads as "no ticket", not "not downloaded"', (
      tester,
    ) async {
      await db.setLastSync(DateTime.utc(2026, 10, 1));
      await pump(tester);

      expect(find.text('Nessun ticket'), findsOneWidget);
      expect(find.text('Ticket non ancora scaricati'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('a search that matches nothing is "no result", never "no tickets"', (tester) async {
      await db.setLastSync(DateTime.utc(2026, 10, 1));
      await seedStatus(1, 'Aperto');
      await seedTicket(id: 't1', title: 'Perdita idrica');
      await pump(tester);

      await tester.enterText(find.byType(TextField).first, 'inesistente');
      await tester.pumpAndSettle();

      expect(find.text('Nessun risultato'), findsOneWidget);
      expect(find.text('Nessun ticket'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('renders a row per ticket, titled', (tester) async {
      await seedStatus(1, 'Aperto');
      await seedStatus(2, 'In corso', isInProgress: true);
      await seedTicket(id: 't1', title: 'Perdita idrica');
      await seedTicket(
        id: 't2',
        title: 'Manutenzione caldaia',
        statusId: 2,
        createdAt: DateTime.utc(2026, 6, 2),
      );

      await pump(tester);

      expect(find.text('Perdita idrica'), findsOneWidget);
      expect(find.text('Manutenzione caldaia'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('search matches cliente, sede and numero, as the hint promises', (tester) async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'cust-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              companyName: 'Rossi Srl',
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
              city: const Value('Milano'),
            ),
          );
      await seedStatus(1, 'Aperto');
      await seedTicket(id: 't1', title: 'Perdita idrica');
      await (db.update(
        db.tickets,
      )..where((t) => t.id.equals('t1'))).write(const TicketsCompanion(numero: Value('000123')));
      await pump(tester);

      await tester.enterText(find.byType(TextField).first, 'rossi');
      await tester.pumpAndSettle();
      expect(find.text('Perdita idrica'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'milano');
      await tester.pumpAndSettle();
      expect(find.text('Perdita idrica'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '#000123');
      await tester.pumpAndSettle();
      expect(find.text('Perdita idrica'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('filter chip narrows list to matching status', (tester) async {
      await seedStatus(1, 'Aperto');
      await seedStatus(2, 'In corso', isInProgress: true);
      await seedTicket(id: 't1', title: 'Ticket aperto');
      await seedTicket(id: 't2', title: 'Ticket in corso', statusId: 2);

      await pump(tester);

      // The chip row uppercases its labels; the status stamp does too, so `.first` is the chip.
      await tester.tap(find.text('IN CORSO').first);
      await tester.pumpAndSettle();

      expect(find.text('Ticket in corso'), findsOneWidget);
      expect(find.text('Ticket aperto'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('the Oggi chip shows due-today tickets, not every open ticket', (tester) async {
      final todayCivil = BusinessTime.fallback().businessToday();
      final todayLabel = formatDateOnly(todayCivil)!;
      final tomorrowLabel = formatDateOnly(todayCivil.add(const Duration(days: 1)))!;

      await seedStatus(1, 'Aperto');
      await seedTicket(id: 't-oggi', title: 'Oggi per scadenza', dueDate: todayLabel);
      await seedTicket(id: 't-domani', title: 'Aperto ma domani', dueDate: tomorrowLabel);

      await pump(tester);

      await tester.tap(find.text('OGGI'));
      await tester.pumpAndSettle();

      expect(find.text('Oggi per scadenza'), findsOneWidget);
      expect(find.text('Aperto ma domani'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('shows a status stamp with the resolved status name', (tester) async {
      await seedStatus(1, 'Aperto');
      await seedTicket(id: 't1', title: 'Un ticket');

      await pump(tester);

      expect(find.byType(StatusStamp), findsOneWidget);
      expect(find.text('APERTO'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('groups tickets as Oggi / In corso / Altri aperti / In attesa / Chiusi', (
      tester,
    ) async {
      // The screen groups by the business-zone civil date; seed `Oggi` against that same date.
      final todayCivil = BusinessTime.fallback().businessToday();
      final todayLabel = formatDateOnly(todayCivil)!;

      await seedStatus(1, 'Aperto');
      await seedStatus(2, 'In corso', isInProgress: true);
      await seedStatus(3, 'In attesa');
      await seedStatus(4, 'Completato', isClosed: true);

      await seedTicket(id: 't-oggi', title: 'Oggi per scadenza', dueDate: todayLabel);
      await seedTicket(id: 't-corso', title: 'Lavorazione', statusId: 2);
      await seedTicket(id: 't-altro', title: 'Altro aperto');
      await seedTicket(id: 't-attesa', title: 'In attesa cliente', statusId: 3);
      await seedTicket(id: 't-chiuso', title: 'Chiuso davvero', statusId: 4);

      await pump(tester);

      expect(find.text('Oggi'), findsOneWidget);
      expect(find.text('In corso'), findsOneWidget);
      expect(find.text('Altri aperti'), findsOneWidget);
      expect(find.text('In attesa'), findsOneWidget);
      expect(find.text('Chiusi'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('row carries cliente/sede, tecnico and the priority line', (tester) async {
      await db
          .into(db.customers)
          .insert(
            CustomersCompanion.insert(
              id: 'cust-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 1, 1),
              companyName: 'Rossi Srl',
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
              city: const Value('Milano'),
            ),
          );
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'u2', displayName: 'Daniel Shala'));
      await seedStatus(2, 'In corso', isInProgress: true);
      await seedTicket(
        id: 't1',
        title: 'Perdita acqua sotto il lavello',
        statusId: 2,
        priority: 'Alta',
        assignedUserId: 'u2',
      );

      await pump(tester);

      expect(find.text('Rossi Srl · Milano · Daniel Shala'), findsOneWidget);
      expect(find.text('alta priorità'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('long titles clamp to two lines instead of overflowing', (tester) async {
      await seedStatus(1, 'Aperto');
      const longTitle =
          'Manutenzione straordinaria dell’impianto idraulico completo con verifica '
          'pressione, sostituzione valvole e controllo perdite su ogni piano';
      await seedTicket(id: 't1', title: longTitle);
      await pump(tester);

      final text = tester.widget<Text>(find.text(longTitle));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      await disposeScreen(tester);
    });

    testWidgets('the Filtri chip opens the real filter sheet with every facet', (tester) async {
      await seedStatus(1, 'Aperto');
      await seedTicket(id: 't1', title: 'Un ticket');
      await pump(tester);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();

      expect(find.text('CLIENTE'), findsOneWidget);
      expect(find.text('SEDE'), findsOneWidget);
      expect(find.text('TECNICO'), findsOneWidget);
      expect(find.text('PRIORITÀ'), findsOneWidget);
      expect(find.text('PERIODO'), findsOneWidget);
      expect(find.text('Solo i miei ticket'), findsOneWidget);
      expect(find.text('Applica'), findsOneWidget);
      expect(find.text('Azzera'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('the sheet status chip and Applica filter the list', (tester) async {
      await seedStatus(4, 'Completato', isClosed: true);
      await seedTicket(id: 't1', title: 'Aperto ancora');
      await seedTicket(id: 't2', title: 'Chiuso davvero', statusId: 4);
      await pump(tester);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppChip, 'Chiusi'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Chiuso davvero'), findsOneWidget);
      expect(find.text('Aperto ancora'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('the Aperti sheet facet keeps the pre-redesign open-status filter', (tester) async {
      await seedStatus(1, 'Aperto');
      await seedStatus(2, 'In corso', isInProgress: true);
      await seedTicket(id: 't1', title: 'Solo aperto');
      await seedTicket(id: 't2', title: 'In lavorazione', statusId: 2);
      await pump(tester);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(AppChip, 'Aperti'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Applica'));
      await tester.tap(find.text('Applica'));
      await tester.pumpAndSettle();

      expect(find.text('Solo aperto'), findsOneWidget);
      expect(find.text('In lavorazione'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('a tenant status flagged in-progress groups and filters as In corso', (
      tester,
    ) async {
      // A renamed status must not fall through to "Altri aperti" just because its string is not
      // literally "In corso": chips, groups and the footer share the flag predicate.
      await seedStatus(7, 'In lavorazione', isInProgress: true);
      await seedTicket(id: 't1', title: 'Lavoro in corso', statusId: 7);
      await pump(tester);

      expect(find.text('In corso'), findsOneWidget);
      await tester.tap(find.text('IN CORSO').first);
      await tester.pumpAndSettle();
      expect(find.text('Lavoro in corso'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('Azzera clears an applied filter and shows every ticket again', (tester) async {
      await seedStatus(1, 'Aperto');
      await seedStatus(2, 'In corso', isInProgress: true);
      await seedTicket(id: 't1', title: 'Aperto ancora');
      await seedTicket(id: 't2', title: 'Chiuso non in status', statusId: 2);
      await pump(tester);

      await tester.tap(find.text('IN CORSO').first);
      await tester.pumpAndSettle();
      expect(find.text('Aperto ancora'), findsNothing);

      await tester.tap(find.text('FILTRI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Azzera'));
      await tester.tap(find.text('Azzera'));
      await tester.pumpAndSettle();

      expect(find.text('Aperto ancora'), findsOneWidget);
      expect(find.text('Chiuso non in status'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('the Tecnico facet and row use the assignee, not the Riferimento agent', (
      tester,
    ) async {
      await db
          .into(db.colleagues)
          .insert(ColleaguesCompanion.insert(id: 'agent-1', displayName: 'Riferimento Uno'));
      await seedStatus(1, 'Aperto');
      await seedTicket(id: 't1', title: 'Senza assegnatario', agentId: 'agent-1');
      await pump(tester);

      // `agentId` is the detail screen's Riferimento, not the technician working the job.
      expect(find.textContaining('Riferimento Uno'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('an empty filter result is shown even when pending rows are visible', (
      tester,
    ) async {
      await seedStatus(1, 'Aperto');
      await seedTicket(id: 't1', title: 'Ticket sincronizzato');
      await db
          .into(db.pendingTickets)
          .insert(
            PendingTicketsCompanion.insert(
              id: 'pt-empty',
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

      await tester.enterText(find.byType(TextField).first, 'inesistente');
      await tester.pumpAndSettle();

      expect(find.text('Ticket in coda'), findsOneWidget);
      expect(find.text('Nessun risultato'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('the summary footer counts pending rows too', (tester) async {
      await seedStatus(1, 'Aperto');
      await seedStatus(2, 'In corso', isInProgress: true);
      await seedTicket(id: 't1', title: 'Uno');
      await seedTicket(id: 't2', title: 'Due', statusId: 2);
      await db
          .into(db.pendingTickets)
          .insert(
            PendingTicketsCompanion.insert(
              id: 'pt-summary',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Tre in coda',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
              state: const Value('pendingSync'),
            ),
          );
      await pump(tester);

      expect(find.text('3 TICKET'), findsOneWidget);
      expect(find.text('1 IN CORSO'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('Nuovo is shown with interventi.ticket.write', (tester) async {
      await pump(tester);

      expect(find.byType(ListHeaderAction), findsOneWidget);
      expect(find.text('NUOVO'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('Nuovo is hidden without interventi.ticket.write', (tester) async {
      await pump(tester, entitlement: _entitlementWith(const {}));

      expect(find.byType(ListHeaderAction), findsNothing);
      expect(find.text('NUOVO'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('renders at 320px without overflowing', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await seedStatus(1, 'Aperto');
      await seedTicket(
        id: 't1',
        title: 'Manutenzione straordinaria impianto idraulico con verifica pressione',
        priority: 'Urgente',
      );
      await pump(tester);

      expect(find.textContaining('Manutenzione straordinaria'), findsOneWidget);
      await disposeScreen(tester);
    });

    // ── Pending tickets (2026-08-30 polish pass) ────────────────────────────
    //
    // Pending rows are grouped under `In sospeso` at the top of the list. The shared row contract
    // has no action slot, so each shared row is followed by its original inline action strip;
    // these tests assert the same choices that existed before the redesign.

    testWidgets('a failed pending ticket offers retry inline', (tester) async {
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

      expect(find.text('In sospeso'), findsOneWidget);
      expect(find.text('Ticket in sospeso'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pending-pt-1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Invio non riuscito'), findsWidgets);
      expect(find.text('Riprova'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('a queued-offline pending ticket has no retry button', (tester) async {
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
      expect(find.byTooltip('Elimina'), findsOneWidget);
      await disposeScreen(tester);
    });

    // ── A row the server refused for one bad reference (Task B6) ────────────

    testWidgets('a rejected queue row is offered as "Da correggere", not as a retry', (
      tester,
    ) async {
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
              error: const Value('Non trovato sul server. Potrebbe essere stato eliminato.'),
              repairableField: const Value('customerId'),
            ),
          );

      await pump(tester);

      expect(find.text('DA CORREGGERE'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pending-pt-rep')));
      await tester.pumpAndSettle();
      expect(find.text('Correggi'), findsOneWidget);
      // No "Riprova": a resend would carry the very id the server just refused.
      expect(find.text('Riprova'), findsNothing);
      await disposeScreen(tester);
    });

    testWidgets('a row the client cannot repair shows the ordinary failure, not a repair', (
      tester,
    ) async {
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

      await tester.tap(find.byKey(const ValueKey('pending-pt-norep')));
      await tester.pumpAndSettle();
      expect(find.text('Correggi'), findsNothing);
      expect(find.textContaining('Errore del server'), findsWidgets);
      expect(find.text('Riprova'), findsOneWidget);
      await disposeScreen(tester);
    });

    testWidgets('"Correggi" opens the wizard in repair mode, on the step that owns the field', (
      tester,
    ) async {
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
      await tester.tap(find.byKey(const ValueKey('pending-pt-rep2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Correggi'));
      await tester.pumpAndSettle();

      // The wizard, in its repair wording, opened on Dettagli — the step that owns `agentId` —
      // and not on the first step, which is what it opens for references that live there.
      expect(find.text('Correggi ticket'), findsOneWidget);
      expect(find.text('Dettagli'), findsOneWidget);
      expect(find.text('2 di 4'), findsOneWidget);
      expect(find.text('Perdita idrica'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text(kBlamedFieldNotice),
        find.byType(ListView).first,
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text(kBlamedFieldNotice), findsOneWidget);

      await disposeScreen(tester);
    });

    testWidgets('a blamed customer opens on the first step, where that field is', (tester) async {
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
      expect(find.text('1 di 4'), findsOneWidget);
      expect(find.text(kBlamedFieldNotice), findsOneWidget);
      // The title lives on step 2 and is not on screen — the seed is there, the step is here.
      expect(find.text('Perdita idrica'), findsNothing);

      await disposeScreen(tester);
    });
  });
}
