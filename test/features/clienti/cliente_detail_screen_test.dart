// test/features/clienti/cliente_detail_screen_test.dart
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
import 'package:tasktap_mobile/features/clienti/cliente_detail_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Widget _buildDetail({
  required AppDatabase db,
  required MockAuthRepository repo,
  String customerId = 'cust-1',
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
    ],
    child: MaterialApp(home: ClienteDetailScreen(customerId: customerId)),
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
    String customerId = 'cust-1',
  }) async {
    await tester
        .pumpWidget(_buildDetail(db: db, repo: repo, customerId: customerId));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> seedCustomer(AppDatabase db) async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: 'cust-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          companyName: 'ACME Srl',
          city: const Value('Milano'),
          taxId: const Value('IT12345678901'),
          address: const Value('Via Roma 1'),
          phone: const Value('+39 02 1234567'),
          email: const Value('info@acme.it'),
          contactPerson: const Value('Luca Rossi'),
          notes: const Value('Cliente storico, priorità alta.'),
        ));
  }

  group('ClienteDetailScreen', () {
    testWidgets('shows empty-state when customer not found', (tester) async {
      await pump(tester, customerId: 'nonexistent');
      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders companyName in header', (tester) async {
      await seedCustomer(db);
      await pump(tester);
      expect(find.text('ACME Srl'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders KeyVal card rows', (tester) async {
      await seedCustomer(db);
      await pump(tester);

      expect(find.text('IT12345678901'), findsOneWidget);
      expect(find.text('+39 02 1234567'), findsOneWidget);
      expect(find.text('info@acme.it'), findsOneWidget);
      expect(find.text('Luca Rossi'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders notes card when notes present', (tester) async {
      await seedCustomer(db);
      await pump(tester);

      expect(
        find.text('Cliente storico, priorità alta.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows empty ticket section when no tickets', (tester) async {
      await seedCustomer(db);
      await pump(tester);

      expect(find.byType(EmptyState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows ticket list rows when tickets exist', (tester) async {
      await seedCustomer(db);
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 1),
            title: 'Perdita idrica',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ));
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            id: 't2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 6, 2),
            title: 'Manutenzione',
            customerId: 'cust-1',
            locationId: 'loc-1',
            statusId: 1,
            typeId: 1,
          ));

      await pump(tester);

      // Scroll down to reveal ticket rows below the KeyVal card + notes.
      await tester.scrollUntilVisible(
        find.text('Perdita idrica'),
        50,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Perdita idrica'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
