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
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/ticket/ticket_detail_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Widget _buildDetail({
  required AppDatabase db,
  required MockAuthRepository repo,
  String ticketId = 'ticket-1',
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
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

  Future<void> pump(WidgetTester tester, {String ticketId = 'ticket-1'}) async {
    await tester.pumpWidget(_buildDetail(db: db, repo: repo, ticketId: ticketId));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> seedBase(AppDatabase db) async {
    await db.into(db.ticketStatuses).insert(TicketStatusesCompanion.insert(
        id: const Value(1), tenantId: 'tenant-1', name: 'Aperto'));
    await db.into(db.ticketTypes).insert(TicketTypesCompanion.insert(
        id: const Value(1), tenantId: 'tenant-1', name: 'Assistenza'));
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'cust-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: 'ACME Srl',
        ));
    await db.into(db.locations).insert(LocationsCompanion.insert(
          id: 'loc-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          customerId: 'cust-1',
          name: 'Sede Milano',
        ));
    await db.into(db.tickets).insert(TicketsCompanion.insert(
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
        ));
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
      await pump(tester);

      expect(find.byType(AppTabs), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Pianificazioni'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('Pianificazioni tab shows schedules', (tester) async {
      await seedBase(db);
      await db.into(db.schedules).insert(SchedulesCompanion.insert(
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
          ));

      await pump(tester);

      // Tap "Pianificazioni" tab (index 2)
      await tester.ensureVisible(find.text('Pianificazioni'));
      await tester.tap(find.text('Pianificazioni'));
      await tester.pumpAndSettle();

      expect(find.text('Sopralluogo', skipOffstage: false), findsOneWidget);
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

    testWidgets('shows description card when description is present',
        (tester) async {
      await seedBase(db);
      await pump(tester);

      expect(find.text('Acqua che perde dal tubo.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
