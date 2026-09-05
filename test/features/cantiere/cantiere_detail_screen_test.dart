// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/cantiere_report_api_client.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_detail_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Records the cantiereId it was called with, and returns a fixed report id with no staff rows
/// (the zero-worklogs case — hours hydration itself is covered by create_draft_test.dart's
/// `createCantiereReportDraft` group, not re-tested at the screen level here).
class _FakeCantiereReportApiClient extends CantiereReportApiClient {
  _FakeCantiereReportApiClient() : super(Dio());

  String? calledWithCantiereId;
  String reportIdToReturn = 'report-from-worklogs-1';

  /// When set, [createFromCantiereWorklogs] throws instead of succeeding.
  Object? throwsOnCreate;

  @override
  Future<String> createFromCantiereWorklogs(String cantiereId) async {
    calledWithCantiereId = cantiereId;
    if (throwsOnCreate != null) throw throwsOnCreate!;
    return reportIdToReturn;
  }

  @override
  Future<List<ReportStaffSeedDto>> fetchReportStaff(String reportId) async => const [];
}

final _testUser = AuthUser(
  id: 'user-1',
  email: 'tecnico@example.com',
  accessToken: 'tok',
  refreshToken: 'ref',
  expiresAt: DateTime.utc(2030, 1, 1),
);

/// Builds this screen's `/cantieri/:id` route behind a real [GoRouter], with a marker screen at
/// the cantiere-timbra route that echoes back its `ticketId` query param. Verifies the router-level
/// gap this fix wave closed: `CantiereDetailScreen`'s own forwarding of `widget.ticketId` into
/// `AppRoutes.cantiereTimbraPath` was already correct — the bug was that no real call site ever
/// passed a `ticketId` into `CantiereDetailScreen` in the first place. This test drives the whole
/// chain through the router (as `/cantieri/c1?ticketId=ticket-9` would arrive from the ticket-detail
/// chip) rather than passing `ticketId` directly to the widget, which wouldn't catch that gap.
GoRouter _makeTimbraForwardingRouter({required String cantiereId, required String ticketId}) =>
    GoRouter(
      initialLocation: '/cantieri/$cantiereId?ticketId=$ticketId',
      routes: [
        GoRoute(
          path: AppRoutes.cantieriDetail,
          builder: (_, state) => CantiereDetailScreen(
            cantiereId: state.pathParameters['id']!,
            ticketId: state.uri.queryParameters['ticketId'],
          ),
        ),
        GoRoute(
          path: AppRoutes.cantiereTimbra,
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text(
                'CANTIERE-TIMBRA-MARKER:ticketId=${state.uri.queryParameters['ticketId']}',
              ),
            ),
          ),
        ),
      ],
    );

/// Builds this screen's `/cantieri/:id` route behind a real [GoRouter], with a marker screen at
/// the rapportini-editor route that echoes back its `:id` path parameter — the same shape
/// `AppRoutes.rapportiniEditor(id)` produces. Used to verify "Crea rapportino" pushes to the
/// editor with the report id [createCantiereReportDraft] returned, not just that it renders.
GoRouter _makeCreaRapportinoRouter({required String cantiereId}) => GoRouter(
  initialLocation: '/cantieri/$cantiereId',
  routes: [
    GoRoute(
      path: AppRoutes.cantieriDetail,
      builder: (_, state) => CantiereDetailScreen(cantiereId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/altro/rapportini/editor/:id',
      builder: (_, state) =>
          Scaffold(body: Center(child: Text('RAPPORTINI-EDITOR-MARKER:${state.pathParameters['id']}'))),
    ),
  ],
);

void main() {
  testWidgets('shows cantiere info and an empty tickets section', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
            address: const Value('Via Roma 1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Alpha'), findsOneWidget);
    expect(find.text('Via Roma 1'), findsOneWidget);
    expect(find.text('Timbra cantiere'), findsOneWidget);
    expect(find.text('Nessun ticket collegato'), findsOneWidget);

    await db.close();
  });

  testWidgets('lists linked tickets when present', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db
        .into(db.cantieri)
        .insert(
          CantieriCompanion.insert(
            id: 'c1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            name: 'Cantiere Alpha',
          ),
        );
    await db
        .into(db.tickets)
        .insert(
          TicketsCompanion.insert(
            id: 't1',
            tenantId: 'tenant1',
            createdAt: DateTime.utc(2026, 8, 31),
            title: 'Ticket collegato',
            customerId: 'cust1',
            locationId: 'l1',
            statusId: 1,
            typeId: 1,
            cantiereId: const Value('c1'),
          ),
        );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ticket collegato'), findsOneWidget);

    await db.close();
  });

  testWidgets(
    'a ticketId arriving via the router (as from the ticket-detail chip) reaches the Timbra push',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Alpha',
            ),
          );

      final router = _makeTimbraForwardingRouter(cantiereId: 'c1', ticketId: 'ticket-9');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(db)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Timbra cantiere'));
      await tester.pumpAndSettle();

      expect(find.text('CANTIERE-TIMBRA-MARKER:ticketId=ticket-9'), findsOneWidget);

      await db.close();
    },
  );

  group('Crea rapportino', () {
    testWidgets('renders the button', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Alpha',
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            currentUserProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Crea rapportino'), findsOneWidget);

      await db.close();
    });

    testWidgets(
      'tapping it calls createFromCantiereWorklogs with this cantiereId and opens the editor '
      'on the returned report id',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        await db
            .into(db.cantieri)
            .insert(
              CantieriCompanion.insert(
                id: 'c1',
                tenantId: 'tenant1',
                createdAt: DateTime.utc(2026, 8, 31),
                name: 'Cantiere Alpha',
                customerId: const Value('cust-1'),
              ),
            );

        final fakeApi = _FakeCantiereReportApiClient()..reportIdToReturn = 'report-xyz';
        final router = _makeCreaRapportinoRouter(cantiereId: 'c1');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              currentUserProvider.overrideWithValue(_testUser),
              cantiereReportApiClientProvider.overrideWithValue(fakeApi),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Crea rapportino'));
        await tester.pumpAndSettle();

        expect(fakeApi.calledWithCantiereId, 'c1');
        expect(find.text('RAPPORTINI-EDITOR-MARKER:report-xyz'), findsOneWidget);

        await db.close();
      },
    );

    testWidgets('refuses with a snackbar when not signed in, without calling the API', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Alpha',
            ),
          );

      final fakeApi = _FakeCantiereReportApiClient();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            currentUserProvider.overrideWithValue(null),
            cantiereReportApiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea rapportino'));
      await tester.pumpAndSettle();

      expect(find.text('Accedi per creare un rapportino.'), findsOneWidget);
      expect(fakeApi.calledWithCantiereId, isNull);
      expect(await db.select(db.draftReports).get(), isEmpty);

      await db.close();
    });

    testWidgets('surfaces an error toast and creates no local draft when the backend call fails', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db
          .into(db.cantieri)
          .insert(
            CantieriCompanion.insert(
              id: 'c1',
              tenantId: 'tenant1',
              createdAt: DateTime.utc(2026, 8, 31),
              name: 'Cantiere Alpha',
            ),
          );

      final fakeApi = _FakeCantiereReportApiClient()
        ..throwsOnCreate = DioException(
          requestOptions: RequestOptions(path: '/api/reports/from-cantiere-worklogs'),
        );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            currentUserProvider.overrideWithValue(_testUser),
            cantiereReportApiClientProvider.overrideWithValue(fakeApi),
          ],
          child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Crea rapportino'));
      await tester.pumpAndSettle();

      expect(await db.select(db.draftReports).get(), isEmpty);

      await db.close();
    });
  });
}
