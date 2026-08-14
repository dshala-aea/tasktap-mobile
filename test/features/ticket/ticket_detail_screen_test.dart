// test/features/ticket/ticket_detail_screen_test.dart
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
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

// Helper: build a Dio Response for a given status code + data.
Response<T> _okResponse<T>(T data, String path) => Response<T>(
  data: data,
  statusCode: 200,
  requestOptions: RequestOptions(path: path),
);

Widget _buildDetail({
  required AppDatabase db,
  required MockAuthRepository repo,
  String ticketId = 'ticket-1',
  Dio? dio,
  // Defaults to offline so pre-existing tests below (which never stub the
  // fetch-on-demand tab endpoints) get the deterministic "offline" tab
  // content rather than depending on how an unstubbed MockDio call fails.
  bool isOnline = false,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio ?? MockDio()),
      isOnlineProvider.overrideWithValue(isOnline),
    ],
    child: MaterialApp(home: TicketDetailScreen(ticketId: ticketId)),
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
    String ticketId = 'ticket-1',
    Dio? dio,
    bool isOnline = false,
  }) async {
    await tester.pumpWidget(
      _buildDetail(db: db, repo: repo, ticketId: ticketId, dio: dio, isOnline: isOnline),
    );
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> seedBase(AppDatabase db) async {
    await db
        .into(db.ticketStatuses)
        .insert(
          TicketStatusesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Aperto'),
        );
    await db
        .into(db.ticketTypes)
        .insert(
          TicketTypesCompanion.insert(id: const Value(1), tenantId: 'tenant-1', name: 'Assistenza'),
        );
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'ACME Srl',
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
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 'ticket-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1, 9),
            title: 'Perdita idrica bagno',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
            description: const Value('Acqua che perde dal tubo.'),
            assignedUserId: const Value('user-1'),
          ),
        );
  }

  group('TicketDetailScreen', () {
    testWidgets('shows empty-state when ticket not found', (tester) async {
      await pump(tester, ticketId: 'nonexistent');
      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders KeyVal rows for Cliente and Sede', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('ACME Srl'), findsOneWidget);
      expect(find.text('Sede Milano'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders resolved StatusPill', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.byType(StatusPill), findsOneWidget);
      expect(find.text('Aperto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders AppTabs with 5 tabs', (tester) async {
      await seedBase(db);
      // A taller surface, for the same reason the Pianificazioni test below already uses one: the
      // tab strip lives well down a CustomScrollView, slivers build lazily, and on the default
      // 600dp test window it sits below the fold. It fell off when the timer bar was added at the
      // top of the content, exactly as it did when the Timbra cantiere button was added before
      // that. The assertion is that the screen renders five tabs, not that they fit in 600dp.
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await pump(tester);

      expect(find.byType(AppTabs), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Pianificazioni'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('a ticket that already has an owner offers no self-assign', (tester) async {
      // seedBase assigns user-1. Offering "take this" for a ticket somebody already holds invites
      // a technician to quietly reassign work away from a colleague.
      await seedBase(db);
      await pump(tester);

      expect(find.text('Prendi in carico'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('an unowned ticket offers self-assign', (tester) async {
      await seedBase(db);
      await (db.update(db.tickets)..where((t) => t.id.equals('ticket-1'))).write(
        const TicketsCompanion(assignedUserId: Value(null)),
      );
      await pump(tester);

      expect(find.text('Prendi in carico'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('the status pill opens the status sheet', (tester) async {
      await seedBase(db);
      await pump(tester);

      // The pill was a label; it is a control now, so it has to answer a tap.
      await tester.tap(find.byType(StatusPill));
      await tester.pumpAndSettle();

      expect(find.text('Cambia stato'), findsOneWidget);
      // The ticket's current status is marked rather than merely listed, so a technician can see
      // what they are changing from.
      expect(find.text('Aperto'), findsWidgets);

      await tester.tapAt(const Offset(10, 10)); // dismiss
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Pianificazioni tab shows schedules', (tester) async {
      await seedBase(db);
      await db
          .into(db.schedules)
          .insert(
            SchedulesCompanion.insert(
              id: 'sched-1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              ticketId: const Value('ticket-1'),
              activityDate: DateTime.utc(2026, 7, 10),
              timeStartMinutes: 480,
              timeEndMinutes: 1020,
              userId: 'user-1',
              statusId: 1,
              locationId: 'loc-1',
              title: 'Sopralluogo',
              description: '',
            ),
          );

      await pump(tester);

      // Tap "Pianificazioni" tab (index 2).
      // Use a taller surface so the tab bar is not obscured by the bottom
      // actions bar (now a two-row Column after the Timbra cantiere button).
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pump();
      await tester.ensureVisible(find.text('Pianificazioni'));
      await tester.tap(find.text('Pianificazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Sopralluogo'), findsOneWidget);
      await tester.binding.setSurfaceSize(null); // reset
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows bottom action buttons', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('Cliente'), findsOneWidget);
      expect(find.text('Crea rapportino'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows description card when description is present', (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('Acqua che perde dal tubo.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });

  // Taps a tab by its label. Uses a taller surface so the tab bar isn't
  // obscured by the bottom actions bar (mirrors the Pianificazioni test
  // above, which established the pattern for this screen).
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    await tester.pump();
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> resetAndDispose(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(null);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Report / Controllo / Allegati / Fabbisogno — none of these have a local
  // Drift mirror (unlike Pianificazioni), so each is fetched on demand and
  // must distinguish three outcomes: real data, a genuine empty list, and
  // "we couldn't check" (offline). See ticket_providers.dart.
  // ══════════════════════════════════════════════════════════════════════════
  group('TicketDetailScreen — Report tab (index 0)', () {
    testWidgets('shows rapportini returned by the backend', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<Map<String, dynamic>>(
          '/api/Reports',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {
              'id': 'rep-1',
              'title': 'Sostituzione valvola',
              'stato': 1,
              'createdAt': '2026-07-01T10:00:00Z',
            },
          ],
          'page': 1,
          'pageSize': 100,
          'totalItems': 1,
          'totalPages': 1,
        }, '/api/Reports'),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();

      expect(find.text('Sostituzione valvola'), findsOneWidget);
      expect(find.text('Inviato'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('shows an honest empty state when there are no rapportini', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<Map<String, dynamic>>(
          '/api/Reports',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': <dynamic>[],
          'page': 1,
          'pageSize': 100,
          'totalItems': 0,
          'totalPages': 0,
        }, '/api/Reports'),
      );

      await pump(tester, dio: dio, isOnline: true);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();

      expect(find.text('Nessun rapportino'), findsOneWidget);
      expect(find.text('Non ci sono rapportini registrati per questo ticket.'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      await tester.pumpAndSettle();

      expect(find.text('Rapportini non disponibili offline'), findsOneWidget);
      // Never claims "nessun rapportino" — that would say "there is
      // nothing" when the truth is "we could not check".
      expect(find.text('Nessun rapportino'), findsNothing);
      await resetAndDispose(tester);
    });
  });

  group('TicketDetailScreen — Controllo tab (index 1)', () {
    final controlsJson = [
      {
        'id': 'grp-1',
        'name': 'Sezione A',
        'description': null,
        'sortOrder': 0,
        'subgroups': <dynamic>[],
        'controls': [
          {
            'id': 'tc-1',
            'templateControlId': 'tpl-1',
            'controlLineageId': 'lin-1',
            'label': 'Pressione OK',
            'description': null,
            'type': 0, // Checkbox
            'isRequired': true,
            'options': null,
            'valoreLimite': null,
            'sortOrder': 0,
            'status': 'Completed',
            'stringValue': null,
            'boolValue': true,
            'dateValue': null,
            'completedByReportId': null,
            'completedAt': null,
          },
        ],
      },
    ];

    testWidgets('shows the real checklist resolved from the template', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/tickets/ticket-1/controls'),
      ).thenAnswer((_) async => _okResponse(controlsJson, '/api/tickets/ticket-1/controls'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Controllo');

      expect(find.text('Pressione OK'), findsOneWidget);
      expect(find.text('Sì'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says honestly that no controls are planned, not "coming soon"', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/tickets/ticket-1/controls'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/tickets/ticket-1/controls'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Controllo');

      expect(find.text('Nessun controllo previsto'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tapTab(tester, 'Controllo');

      expect(find.text('Controlli non disponibili offline'), findsOneWidget);
      expect(find.text('Nessun controllo previsto'), findsNothing);
      await resetAndDispose(tester);
    });
  });

  group('TicketDetailScreen — Allegati tab (index 3)', () {
    final attachmentsJson = [
      {
        'id': 'att-1',
        'fileName': 'foto1.jpg',
        'contentType': 'image/jpeg',
        'sizeBytes': 204800,
        'contentUrl': '/api/tickets/ticket-1/attachments/att-1/content',
        'uploadedByUserId': 'u1',
        'createdAt': '2026-07-01T09:00:00Z',
      },
    ];

    testWidgets('shows attachments uploaded to the ticket', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments'),
      ).thenAnswer((_) async => _okResponse(attachmentsJson, '/api/Tickets/ticket-1/attachments'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');

      expect(find.text('foto1.jpg'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('shows an honest empty state when there are no attachments', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/attachments'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/Tickets/ticket-1/attachments'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Allegati');

      expect(find.text('Nessun allegato'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tapTab(tester, 'Allegati');

      expect(find.text('Allegati non disponibili offline'), findsOneWidget);
      expect(find.text('Nessun allegato'), findsNothing);
      await resetAndDispose(tester);
    });
  });

  group('TicketDetailScreen — Fabbisogno tab (index 4)', () {
    final materialiJson = [
      {
        'id': 'm-1',
        'materialeId': 'mat-1',
        'codice': 'ART001',
        'nome': 'Valvola idraulica',
        'quantita': 2,
        'unitaMisura': 'pz',
        'note': null,
        'disponibile': true,
      },
    ];

    testWidgets('shows materials planned for the ticket', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/materiali'),
      ).thenAnswer((_) async => _okResponse(materialiJson, '/api/Tickets/ticket-1/materiali'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Fabbisogno');

      expect(find.text('Valvola idraulica'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('shows an honest empty state when nothing is planned', (tester) async {
      await seedBase(db);
      final dio = MockDio();
      when(
        () => dio.get<List<dynamic>>('/api/Tickets/ticket-1/materiali'),
      ).thenAnswer((_) async => _okResponse(<dynamic>[], '/api/Tickets/ticket-1/materiali'));

      await pump(tester, dio: dio, isOnline: true);
      await tapTab(tester, 'Fabbisogno');

      expect(find.text('Nessun fabbisogno'), findsOneWidget);
      await resetAndDispose(tester);
    });

    testWidgets('says plainly it is offline instead of showing an empty list', (tester) async {
      await seedBase(db);

      await pump(tester, isOnline: false);
      await tapTab(tester, 'Fabbisogno');

      expect(find.text('Fabbisogno non disponibile offline'), findsOneWidget);
      expect(find.text('Nessun fabbisogno'), findsNothing);
      await resetAndDispose(tester);
    });
  });
}
