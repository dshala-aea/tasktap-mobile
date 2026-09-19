// test/features/clienti/clienti_list_screen_test.dart
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
import 'package:tasktap_mobile/features/clienti/clienti_list_screen.dart';
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
    child: const MaterialApp(home: ClientiListScreen()),
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

  Future<void> seedCustomers(AppDatabase db) async {
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            companyName: 'ACME Srl',
            city: const Value('Milano'),
          ),
        );
    await db
        .into(db.customers)
        .insert(
          CustomersCompanion.insert(
            id: 'cust-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 2),
            companyName: 'Beta SpA',
            city: const Value('Roma'),
          ),
        );
  }

  group('ClientiListScreen', () {
    testWidgets('shows empty state when no customers', (tester) async {
      await pump(tester);
      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders a ListRow per customer', (tester) async {
      await seedCustomers(db);
      await pump(tester);

      expect(find.byType(ListRow), findsNWidgets(2));
      expect(find.text('ACME Srl'), findsOneWidget);
      expect(find.text('Beta SpA'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('search narrows list by company name', (tester) async {
      await seedCustomers(db);
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'acme');
      await tester.pumpAndSettle();

      expect(find.text('ACME Srl'), findsOneWidget);
      expect(find.text('Beta SpA'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('search narrows list by city', (tester) async {
      await seedCustomers(db);
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'roma');
      await tester.pumpAndSettle();

      expect(find.text('Beta SpA'), findsOneWidget);
      expect(find.text('ACME Srl'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows ticket count in subtitle', (tester) async {
      await seedCustomers(db);
      // seed a ticket for cust-1
      await db
          .into(db.tickets)
          .insert(
            TicketsCompanion.insert(
              id: 't1',
              tenantId: 'tenant-1',
              createdAt: DateTime.utc(2026, 6, 1),
              title: 'Ticket test',
              customerId: 'cust-1',
              locationId: 'loc-1',
              statusId: 1,
              typeId: 1,
            ),
          );
      await pump(tester);

      expect(find.textContaining('1 ticket'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows avatar initials for each customer', (tester) async {
      await seedCustomers(db);
      await pump(tester);

      expect(find.byType(AppAvatar), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows total count in subtitle', (tester) async {
      await seedCustomers(db);
      await pump(tester);

      expect(find.textContaining('2 totali'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
