// test/features/magazzino/magazzino_screen_test.dart
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
import 'package:tasktap_mobile/features/magazzino/magazzino_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Widget _buildMagazzino({
  required AppDatabase db,
  required MockAuthRepository repo,
}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(MockDio()),
    ],
    child: const MaterialApp(home: MagazzinoScreen()),
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
    await tester.pumpWidget(_buildMagazzino(db: db, repo: repo));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> seedMateriali(AppDatabase db) async {
    await db.into(db.materiali).insert(MaterialiCompanion.insert(
          id: 'mat-1',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          code: 'ART001',
          name: 'Valvola idraulica',
          category: const Value('Idraulica'),
          marca: const Value('HydroFlow'),
          unitOfMeasure: const Value('pz'),
          salePrice: const Value(25.50),
        ));
    await db.into(db.materiali).insert(MaterialiCompanion.insert(
          id: 'mat-2',
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 2),
          code: 'ART002',
          name: 'Tubo flessibile',
          category: const Value('Raccorderia'),
          marca: const Value('FlexTube'),
          unitOfMeasure: const Value('mt'),
          salePrice: const Value(8.75),
        ));
  }

  group('MagazzinoScreen', () {
    testWidgets('shows unavailable state when no materiali', (tester) async {
      await pump(tester);
      expect(find.byType(UnavailableState), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('renders a ListRow per materiale', (tester) async {
      await seedMateriali(db);
      await pump(tester);

      expect(find.byType(ListRow), findsNWidgets(2));
      expect(find.text('Valvola idraulica'), findsOneWidget);
      expect(find.text('Tubo flessibile'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('search narrows list by name', (tester) async {
      await seedMateriali(db);
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'valvola');
      await tester.pumpAndSettle();

      expect(find.text('Valvola idraulica'), findsOneWidget);
      expect(find.text('Tubo flessibile'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('search narrows list by code', (tester) async {
      await seedMateriali(db);
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'ART002');
      await tester.pumpAndSettle();

      expect(find.text('Tubo flessibile'), findsOneWidget);
      expect(find.text('Valvola idraulica'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('search narrows list by marca', (tester) async {
      await seedMateriali(db);
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'hydroflow');
      await tester.pumpAndSettle();

      expect(find.text('Valvola idraulica'), findsOneWidget);
      expect(find.text('Tubo flessibile'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows category filter chips', (tester) async {
      await seedMateriali(db);
      await pump(tester);

      expect(find.text('Idraulica'), findsOneWidget);
      expect(find.text('Raccorderia'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('category chip filters list', (tester) async {
      await seedMateriali(db);
      await pump(tester);

      // Tap the 'Idraulica' category chip
      await tester.tap(find.text('Idraulica'));
      await tester.pumpAndSettle();

      expect(find.text('Valvola idraulica'), findsOneWidget);
      expect(find.text('Tubo flessibile'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows sale price formatted in euro', (tester) async {
      await seedMateriali(db);
      await pump(tester);

      // €25,50 or € 25,50 Italian format
      expect(find.textContaining('25'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('shows header title Magazzino', (tester) async {
      await pump(tester);
      expect(find.text('Magazzino'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
