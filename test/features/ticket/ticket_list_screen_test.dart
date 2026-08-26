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
      expect(find.text('Aperto'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows AppFab', (tester) async {
      await pump(tester);
      expect(find.byType(AppFab), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
