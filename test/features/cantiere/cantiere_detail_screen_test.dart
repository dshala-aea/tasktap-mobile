// dart format width=100
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/location/geocoding_service.dart';
import 'package:tasktap_mobile/core/router/app_router.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/cantiere_report_api_client.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/data/timbratura/cantiere_worklog_api_client.dart';
import 'package:tasktap_mobile/domain/auth/auth_user.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_detail_screen.dart';
import 'package:tasktap_mobile/features/cantiere/cantiere_map_card.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

/// Never geocodes for real — every test in this file overrides `geocodingServiceProvider` with
/// this, so a cantiere with an address exercises `CantiereMapCard`'s fallback path
/// (`AppMapCard`, unchanged) deterministically instead of racing a real Nominatim request.
class _NullGeocodingService extends GeocodingService {
  _NullGeocodingService() : super(dio: null);

  @override
  Future<GeocodedPoint?> geocode(String address) async => null;
}

/// No crew assigned, no network call — every test in this file overrides
/// `cantiereWorklogApiClientProvider` with this so the new "Squadra assegnata" section (which
/// this screen now renders unconditionally, same as every other cantiere detail screen section)
/// never races a real `GET /api/cantieri/{id}/assegnazioni` call.
class _FakeCantiereWorklogApiClient extends CantiereWorklogApiClient {
  _FakeCantiereWorklogApiClient() : super(Dio());

  /// Overridable per test — empty by default (the "Squadra assegnata" section then renders its
  /// "nessuna squadra" copy), set to a non-empty list by the section-order test below, which needs
  /// the section actually rendered to check its position.
  List<CantiereCrewAssignmentDto> assignments = const [];

  /// When true every call throws. The offline tests set this to prove the mirror path never
  /// reaches the network — a real call would surface as an error, not as the mirrored crew.
  bool throwsIfCalled = false;
  int calls = 0;

  @override
  Future<List<CantiereCrewAssignmentDto>> getAssegnazioni(String cantiereId) async {
    calls++;
    if (throwsIfCalled) throw StateError('network call attempted while offline');
    return assignments;
  }
}

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
  Future<ReportSeedDto> fetchReportSeed(String reportId) async =>
      const ReportSeedDto(locationId: null, staff: []);
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
      builder: (_, state) => Scaffold(
        body: Center(child: Text('RAPPORTINI-EDITOR-MARKER:${state.pathParameters['id']}')),
      ),
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
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
          cantiereWorklogApiClientProvider.overrideWithValue(_FakeCantiereWorklogApiClient()),
          // `cantiereCrewAssignmentsProvider` reads the Drift crew mirror when offline instead of
          // calling the client; these tests exercise the online path.
          isOnlineProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cantiere Alpha'), findsOneWidget);
    // Twice: the info card's own address line, plus CantiereMapCard's fallback AppMapCard (the
    // geocoder above never resolves, so the map falls back to the same pin-and-address panel
    // admin_cantiere_detail_screen.dart's own map section already shows alongside its own
    // address row — this screen now matches that same accepted duplication).
    expect(find.text('Via Roma 1'), findsNWidgets(2));
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
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
          cantiereWorklogApiClientProvider.overrideWithValue(_FakeCantiereWorklogApiClient()),
          // `cantiereCrewAssignmentsProvider` reads the Drift crew mirror when offline instead of
          // calling the client; these tests exercise the online path.
          isOnlineProvider.overrideWithValue(true),
        ],
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
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
            cantiereWorklogApiClientProvider.overrideWithValue(_FakeCantiereWorklogApiClient()),
            // Online path: see the note in the first test's overrides above.
            isOnlineProvider.overrideWithValue(true),
          ],
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
            geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
            cantiereWorklogApiClientProvider.overrideWithValue(_FakeCantiereWorklogApiClient()),
            // Online path: see the note in the first test's overrides above.
            isOnlineProvider.overrideWithValue(true),
            currentUserProvider.overrideWithValue(null),
            internalUserIdProvider.overrideWith((ref) async => null),
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
              geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
              cantiereWorklogApiClientProvider.overrideWithValue(_FakeCantiereWorklogApiClient()),
              // Online path: see the note in the first test's overrides above.
              isOnlineProvider.overrideWithValue(true),
              currentUserProvider.overrideWithValue(_testUser),
              internalUserIdProvider.overrideWith((ref) async => 'internal-user-1'),
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
            geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
            cantiereWorklogApiClientProvider.overrideWithValue(_FakeCantiereWorklogApiClient()),
            // Online path: see the note in the first test's overrides above.
            isOnlineProvider.overrideWithValue(true),
            currentUserProvider.overrideWithValue(null),
            internalUserIdProvider.overrideWith((ref) async => null),
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

    testWidgets(
      'falls back to an offline draft and opens its editor when the backend call fails (P2-6)',
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

        final fakeApi = _FakeCantiereReportApiClient()
          ..throwsOnCreate = DioException.connectionError(
            requestOptions: RequestOptions(path: '/api/reports/from-cantiere-worklogs'),
            reason: 'offline',
          );
        final router = _makeCreaRapportinoRouter(cantiereId: 'c1');

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
              cantiereWorklogApiClientProvider.overrideWithValue(_FakeCantiereWorklogApiClient()),
              // Online path: see the note in the first test's overrides above.
              isOnlineProvider.overrideWithValue(true),
              currentUserProvider.overrideWithValue(_testUser),
              internalUserIdProvider.overrideWith((ref) async => 'internal-user-1'),
              cantiereReportApiClientProvider.overrideWithValue(fakeApi),
            ],
            child: MaterialApp.router(routerConfig: router),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Crea rapportino'));
        await tester.pumpAndSettle();

        expect(fakeApi.calledWithCantiereId, 'c1');
        // P2-6: a transport failure no longer dead-ends in a toast. `createCantiereReportDraft`
        // owns the fallback (covered in depth by create_draft_test.dart); the screen's remaining
        // job is to open the editor on the draft it hands back — a client GUID here, since the
        // server never issued one.
        final marker = tester.widget<Text>(find.textContaining('RAPPORTINI-EDITOR-MARKER:'));
        final reportId = marker.data!.replaceFirst('RAPPORTINI-EDITOR-MARKER:', '');
        final drafts = await db.select(db.draftReports).get();
        expect(drafts.single.id, reportId);
        expect(
          drafts.single.cantiereId,
          'c1',
          reason: 'the cantiere link is what makes the later submit claim this site\'s punches',
        );
        expect(drafts.single.isLocalOnly, isTrue);

        await db.close();
      },
    );
  });

  group('Squadra assegnata offline', () {
    /// A cantiere in the local mirror plus a client that would fail loudly if the offline path
    /// ever called it.
    Future<_FakeCantiereWorklogApiClient> buildOffline(
      WidgetTester tester,
      AppDatabase db, {
      bool seedMirroredCrew = true,
      bool synced = true,
    }) async {
      // Offline, the crew list comes from the Drift mirror, and an empty mirror only means "no
      // crew" once a sync has actually filled it. `synced: false` is the first-run phone.
      if (synced) await db.setLastSync(DateTime.utc(2026, 10, 1));
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
      if (seedMirroredCrew) {
        await db
            .into(db.colleagues)
            .insert(ColleaguesCompanion.insert(id: 'u1', displayName: 'Mario Rossi'));
        await db
            .into(db.cantiereCrewAssignments)
            .insert(
              CantiereCrewAssignmentsCompanion.insert(
                id: 'a1',
                cantiereId: 'c1',
                userId: 'u1',
                isLead: const Value(true),
              ),
            );
      }

      final client = _FakeCantiereWorklogApiClient()..throwsIfCalled = true;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
            cantiereWorklogApiClientProvider.overrideWithValue(client),
            isOnlineProvider.overrideWithValue(false),
          ],
          child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
        ),
      );
      await tester.pumpAndSettle();
      return client;
    }

    testWidgets('renders the mirrored crew without a network call', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final client = await buildOffline(tester, db);

      expect(find.text('Squadra assegnata'), findsOneWidget);
      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.text('LEAD'), findsOneWidget);
      expect(client.calls, 0, reason: 'offline is answered from the Drift mirror');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    });

    testWidgets('an empty mirror reads as "nessuna squadra", not as a failure', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await buildOffline(tester, db, seedMirroredCrew: false);

      expect(find.text('Squadra assegnata'), findsOneWidget);
      expect(find.text('Nessuna squadra assegnata'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    });

    /// The same empty mirror on a phone that has never synced proves nothing, so the section must
    /// not turn it into "nobody is assigned to this cantiere".
    testWidgets('an empty mirror on a never-synced phone is "not downloaded", not "no crew"', (
      tester,
    ) async {
      final db = AppDatabase(NativeDatabase.memory());
      await buildOffline(tester, db, seedMirroredCrew: false, synced: false);

      expect(find.text('Squadra non ancora scaricata'), findsOneWidget);
      expect(find.text('Nessuna squadra assegnata'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
    });
  });

  group('section order', () {
    testWidgets(
      'renders Dettagli, then Squadra assegnata, then the map, then the CTA buttons '
      '(ADR: details before map, map before actions)',
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
                address: const Value('Via Roma 1'),
                notes: const Value('Nota di cantiere'),
              ),
            );

        // Non-empty crew + a non-empty Dettagli field, so every section this test checks the
        // position of actually renders instead of collapsing to SizedBox.shrink.
        final crewClient = _FakeCantiereWorklogApiClient()
          ..assignments = const [
            CantiereCrewAssignmentDto(id: 'a1', userId: 'user-1', isLead: true),
          ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              geocodingServiceProvider.overrideWithValue(_NullGeocodingService()),
              cantiereWorklogApiClientProvider.overrideWithValue(crewClient),
              // Online path: see the note in the first test's overrides above.
              isOnlineProvider.overrideWithValue(true),
            ],
            child: const MaterialApp(home: CantiereDetailScreen(cantiereId: 'c1')),
          ),
        );
        await tester.pumpAndSettle();

        final dettagliY = tester.getTopLeft(find.text('Dettagli')).dy;
        final squadraY = tester.getTopLeft(find.text('Squadra assegnata')).dy;
        final mapY = tester.getTopLeft(find.byType(CantiereMapCard)).dy;
        final timbraY = tester.getTopLeft(find.text('Timbra cantiere')).dy;
        final creaRapportinoY = tester.getTopLeft(find.text('Crea rapportino')).dy;

        expect(dettagliY, lessThan(squadraY));
        expect(squadraY, lessThan(mapY));
        expect(mapY, lessThan(timbraY));
        expect(timbraY, lessThan(creaRapportinoY));

        await db.close();
      },
    );
  });
}
