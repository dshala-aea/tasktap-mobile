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
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/domain/auth/i_auth_repository.dart';
import 'package:tasktap_mobile/features/magazzino/magazzino_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

class MockDio extends Mock implements Dio {}

Response<T> _okResponse<T>(T data, String path) =>
    Response<T>(data: data, statusCode: 200, requestOptions: RequestOptions(path: path));

Widget _buildMagazzino({required AppDatabase db, required MockAuthRepository repo, Dio? dio}) {
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repo),
      appDatabaseProvider.overrideWithValue(db),
      dioProvider.overrideWithValue(dio ?? MockDio()),
      isOnlineProvider.overrideWithValue(true),
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

  Future<void> pump(WidgetTester tester, {Dio? dio}) async {
    await tester.pumpWidget(_buildMagazzino(db: db, repo: repo, dio: dio));
    await tester.pump();
    authStream.add(fakeUser);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

  Future<void> seedMateriali(AppDatabase db) async {
    await db
        .into(db.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-1',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 1),
            code: 'ART001',
            name: 'Valvola idraulica',
            category: const Value('Idraulica'),
            marca: const Value('HydroFlow'),
            unitOfMeasure: const Value('pz'),
            salePrice: const Value(25.50),
          ),
        );
    await db
        .into(db.materiali)
        .insert(
          MaterialiCompanion.insert(
            id: 'mat-2',
            tenantId: 'tenant-1',
            createdAt: DateTime.utc(2026, 1, 2),
            code: 'ART002',
            name: 'Tubo flessibile',
            category: const Value('Raccorderia'),
            marca: const Value('FlexTube'),
            unitOfMeasure: const Value('mt'),
            salePrice: const Value(8.75),
          ),
        );
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

  // ── Gap 3/4 of the feature audit: carico/scarico/trasferimento + stock-minimo actions ────────
  group('Giacenze row actions', () {
    late MockDio dio;

    setUp(() {
      dio = MockDio();
      when(
        () => dio.get<Map<String, dynamic>>(
          '/api/app/magazzino/giacenze',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'elementi': [
            {
              'id': 'stock-1',
              'magazzinoId': 'mag-1',
              'materialeId': 'mat-1',
              'materialeNome': 'Valvola idraulica',
              'magazzinoNome': 'Furgone Mario',
              'quantita': 4,
              'sottoScorta': false,
            },
          ],
          'pagina': 1,
          'dimensionePagina': 50,
          'totaleElementi': 1,
          'totalePagine': 1,
        }, '/api/app/magazzino/giacenze'),
      );
      when(
        () => dio.get<Map<String, dynamic>>(
          '/api/app/magazzino/movimenti',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'elementi': <Map<String, dynamic>>[],
          'pagina': 1,
          'dimensionePagina': 30,
          'totaleElementi': 0,
          'totalePagine': 0,
        }, '/api/app/magazzino/movimenti'),
      );
    });

    Future<void> openGiacenzeTab(WidgetTester tester) async {
      await pump(tester, dio: dio);
      await tester.tap(find.text('Giacenze'));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping a row opens the action sheet with all four actions', (tester) async {
      await openGiacenzeTab(tester);

      await tester.tap(find.text('Valvola idraulica'));
      await tester.pumpAndSettle();

      expect(find.text('Carico'), findsOneWidget);
      expect(find.text('Scarico'), findsOneWidget);
      expect(find.text('Trasferisci'), findsOneWidget);
      expect(find.text('Imposta soglia minima'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('carico posts to /api/magazzino/{id}/carico with the row\'s ids', (tester) async {
      when(
        () => dio.post<dynamic>('/api/magazzino/mag-1/carico', data: any(named: 'data')),
      ).thenAnswer((_) async => _okResponse({'message': 'ok'}, '/api/magazzino/mag-1/carico'));

      await openGiacenzeTab(tester);
      await tester.tap(find.text('Valvola idraulica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carico'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Conferma'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => dio.post<dynamic>('/api/magazzino/mag-1/carico', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['materialeId'], 'mat-1');
      expect(captured['quantita'], 1);
      expect(find.text('Carico registrato'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('scarico surfaces the server\'s insufficient-stock message verbatim', (
      tester,
    ) async {
      when(
        () => dio.post<dynamic>('/api/magazzino/mag-1/scarico', data: any(named: 'data')),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/api/magazzino/mag-1/scarico'),
          response: Response(
            statusCode: 400,
            data: 'Stock insufficiente: disponibili 4, richiesti 1',
            requestOptions: RequestOptions(path: '/api/magazzino/mag-1/scarico'),
          ),
        ),
      );

      await openGiacenzeTab(tester);
      await tester.tap(find.text('Valvola idraulica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scarico'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Conferma'));
      await tester.pumpAndSettle();

      expect(find.text('Stock insufficiente: disponibili 4, richiesti 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('trasferimento posts the source, destination and quantity', (tester) async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/api/magazzino',
          queryParameters: any(named: 'queryParameters'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({
          'items': [
            {'id': 'mag-1', 'nome': 'Furgone Mario', 'tipo': 'Furgone', 'isActive': true},
            {'id': 'mag-2', 'nome': 'Sede centrale', 'tipo': 'Sede', 'isActive': true},
          ],
        }, '/api/magazzino'),
      );
      when(
        () => dio.post<dynamic>('/api/magazzino/mag-1/trasferimento', data: any(named: 'data')),
      ).thenAnswer(
        (_) async => _okResponse({'message': 'ok'}, '/api/magazzino/mag-1/trasferimento'),
      );

      await openGiacenzeTab(tester);
      await tester.tap(find.text('Valvola idraulica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trasferisci'));
      await tester.pumpAndSettle();

      // The row's own warehouse (Furgone Mario) is excluded from the destination options.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sede centrale').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Conferma'));
      await tester.pumpAndSettle();

      final captured = verify(
        () =>
            dio.post<dynamic>('/api/magazzino/mag-1/trasferimento', data: captureAny(named: 'data')),
      ).captured.single as Map;
      expect(captured['magazzinoDestinazioneId'], 'mag-2');
      expect(captured['quantita'], 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('imposta soglia minima PUTs the stock row id, not the warehouse id', (
      tester,
    ) async {
      when(
        () => dio.put<dynamic>(
          '/api/magazzino/stock/stock-1/stock-minimo',
          data: any(named: 'data'),
        ),
      ).thenAnswer(
        (_) async => _okResponse({'message': 'ok'}, '/api/magazzino/stock/stock-1/stock-minimo'),
      );

      await openGiacenzeTab(tester);
      await tester.tap(find.text('Valvola idraulica'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Imposta soglia minima'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        '2',
      );
      await tester.tap(find.text('Salva'));
      await tester.pumpAndSettle();

      final captured = verify(
        () => dio.put<dynamic>(
          '/api/magazzino/stock/stock-1/stock-minimo',
          data: captureAny(named: 'data'),
        ),
      ).captured.single as Map;
      expect(captured['stockMinimo'], 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });
  });
}
