// dart format width=100
// test/features/admin/cantieri/admin_cantiere_detail_screen_test.dart
//
// Cantieri module #8 gap-fill: contacts CRUD (Gap 1), crew/assignment CRUD (Gap 2), and read-only
// linked-records sections — ore/interventi/rapportini (Gap 6). Every sub-resource here has no
// local Drift mirror; the screen fetches them live via AdminApiClient (see that class's own
// "Cantiere linked records (read-only)" section for why).
//
// CRITICAL: every test that pumps a screen watching a Drift stream MUST end with:
//   await tester.pumpWidget(const SizedBox.shrink());
//   await tester.pumpAndSettle();
// to avoid "A Timer is still pending" hangs from Drift's StreamQueryStore.

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/connectivity_provider.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart';
import 'package:tasktap_mobile/features/admin/admin_api_client.dart';
import 'package:tasktap_mobile/features/admin/cantieri/admin_cantiere_detail_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAdminApiClient extends AdminApiClient {
  _FakeAdminApiClient({
    Map<String, dynamic>? cantiereDetail,
    List<Map<String, dynamic>>? tickets,
    List<Map<String, dynamic>>? reports,
    List<Map<String, dynamic>>? workLogs,
    List<Map<String, dynamic>>? technicians,
    Map<String, dynamic>? commessa,
  }) : _cantiereDetail = cantiereDetail ?? {'contacts': [], 'assignments': []},
       _tickets = tickets ?? [],
       _reports = reports ?? [],
       _workLogs = workLogs ?? [],
       _technicians = technicians ?? [],
       _commessa = commessa,
       super(Dio());

  final Map<String, dynamic> _cantiereDetail;
  final List<Map<String, dynamic>> _tickets;
  final List<Map<String, dynamic>> _reports;
  final List<Map<String, dynamic>> _workLogs;
  final List<Map<String, dynamic>> _technicians;
  // Feature audit module #13, Gap 6 — GET /api/commesse/{id}, keyed by whatever single id the
  // test seeded onto the cantiere (no test here exercises more than one commessa at a time).
  final Map<String, dynamic>? _commessa;

  @override
  Future<Map<String, dynamic>?> fetchCommessaById(String id) async => _commessa;

  final List<String> deletedContactIds = [];
  final List<String> removedAssignmentIds = [];
  bool addContactCalled = false;
  bool addAssignmentCalled = false;

  @override
  Future<Map<String, dynamic>?> fetchCantiereDetail(String id) async => _cantiereDetail;

  @override
  Future<List<Map<String, dynamic>>> fetchCantiereTickets(String cantiereId) async => _tickets;

  @override
  Future<List<Map<String, dynamic>>> fetchReports({
    String? stato,
    String? cantiereId,
    int page = 1,
    int pageSize = 50,
  }) async => _reports;

  @override
  Future<List<Map<String, dynamic>>> fetchCantiereWorkLogs(String cantiereId) async => _workLogs;

  @override
  Future<List<Map<String, dynamic>>> fetchTechnicians() async => _technicians;

  @override
  Future<String> addCantiereContact(
    String cantiereId, {
    required String name,
    String? role,
    String? phone,
    String? email,
    String? notes,
  }) async {
    addContactCalled = true;
    return 'new-contact';
  }

  @override
  Future<void> deleteCantiereContact(String cantiereId, String contactId) async {
    deletedContactIds.add(contactId);
  }

  @override
  Future<String> addCantiereAssignment(
    String cantiereId, {
    required String userId,
    String? role,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    addAssignmentCalled = true;
    return 'new-assignment';
  }

  @override
  Future<void> removeCantiereAssignment(String cantiereId, String assignmentId) async {
    removedAssignmentIds.add(assignmentId);
  }

  /// When set, [deleteCantiere] throws a DioException carrying this status/body instead of
  /// succeeding — used to test that the backend's 409 message reaches the technician verbatim.
  int? deleteThrowsStatus;
  Object? deleteThrowsBody;

  @override
  Future<void> deleteCantiere(String id) async {
    if (deleteThrowsStatus != null) {
      throw DioException(
        requestOptions: RequestOptions(path: '/api/cantieri/$id'),
        response: Response(
          requestOptions: RequestOptions(path: '/api/cantieri/$id'),
          statusCode: deleteThrowsStatus,
          data: deleteThrowsBody,
        ),
      );
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

AppDatabase _makeDb() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  return AppDatabase(NativeDatabase.memory());
}

Widget _buildScreen({
  required AppDatabase db,
  required AdminApiClient api,
  String id = 'cant-1',
  // Every existing sub-resource fetch on this screen ignores connectivity and just attempts the
  // request (see the "Live sub-resource providers" comment in the screen itself), so this default
  // matches that: true, unlike ticket_detail_screen_test.dart's own harness which defaults to
  // false. Only the new commessa row (Gap 6) reads isOnlineProvider at all.
  bool isOnline = true,
}) {
  return ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      adminApiClientProvider.overrideWithValue(api),
      isOnlineProvider.overrideWithValue(isOnline),
    ],
    child: MaterialApp(home: AdminCantiereDetailScreen(cantiereId: id)),
  );
}

Future<void> _seedCantiere(AppDatabase db, {String id = 'cant-1', int status = 0}) async {
  await db
      .into(db.cantieri)
      .insert(
        CantieriCompanion.insert(
          id: id,
          tenantId: 'tenant-1',
          createdAt: DateTime.utc(2026, 1, 1),
          name: 'Cantiere Via Roma',
          status: Value(status),
        ),
      );
}

/// Pumps the detail screen on a tall surface — it stacks five sections (base info, contatti,
/// personale, ore, interventi, rapportini) in one CustomScrollView, taller than the default
/// 800×600 test surface, so content past the first section or two lays out below the fold and
/// `find.text` misses it. Mirrors the same `setSurfaceSize` convention
/// test/features/ticket/ticket_detail_screen_test.dart already uses for its own long scrolling
/// detail screen.
Future<void> _pumpScreen(
  WidgetTester tester, {
  required AppDatabase db,
  required AdminApiClient api,
  String id = 'cant-1',
  bool isOnline = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  await tester.pumpWidget(_buildScreen(db: db, api: api, id: id, isOnline: isOnline));
  await tester.pumpAndSettle();
}

Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.binding.setSurfaceSize(null);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await initializeDateFormatting('it', null);
  });

  late AppDatabase db;

  setUp(() => db = _makeDb());
  tearDown(() async => db.close());

  group('base info', () {
    testWidgets('shows Stato resolved from CantiereStatusEnum', (tester) async {
      await _seedCantiere(db, status: 1);
      await _pumpScreen(tester, db: db, api: _FakeAdminApiClient());

      expect(find.text('Completato'), findsOneWidget);
      await _teardown(tester);
    });
  });

  group('Elimina cantiere (Gap 3)', () {
    testWidgets('surfaces the backend 409 message directly, not a generic error', (tester) async {
      await _seedCantiere(db);
      final api = _FakeAdminApiClient()
        ..deleteThrowsStatus = 409
        ..deleteThrowsBody = {
          'message': 'Impossibile eliminare: il cantiere ha interventi, rapportini, ore o altri '
              'record collegati',
        };
      await _pumpScreen(tester, db: db, api: api);

      // HeaderIconBtn announces itself via Semantics(label:), not a Tooltip widget.
      await tester.tap(
        find.byWidgetPredicate((w) => w is HeaderIconBtn && w.label == 'Elimina cantiere'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Impossibile eliminare: il cantiere ha interventi, rapportini, ore o altri record '
          'collegati',
        ),
        findsOneWidget,
      );
      // Not the old generic message.
      expect(find.text('Impossibile eliminare. Riprova.'), findsNothing);
      await _teardown(tester);
    });
  });

  group('Contatti (Gap 1)', () {
    testWidgets('shows empty state when no contacts', (tester) async {
      await _seedCantiere(db);
      await _pumpScreen(tester, db: db, api: _FakeAdminApiClient());

      expect(find.text('Nessun contatto'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('lists contacts from the live GET /api/cantieri/{id} response', (tester) async {
      await _seedCantiere(db);
      final api = _FakeAdminApiClient(
        cantiereDetail: {
          'contacts': [
            {
              'id': 'contact-1',
              'name': 'Mario Rossi',
              'role': 'Titolare',
              'phone': '333123456',
            },
          ],
          'assignments': [],
        },
      );
      await _pumpScreen(tester, db: db, api: api);

      expect(find.text('Mario Rossi'), findsOneWidget);
      expect(find.textContaining('Titolare'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('deleting a contact confirms then calls deleteCantiereContact', (tester) async {
      await _seedCantiere(db);
      final api = _FakeAdminApiClient(
        cantiereDetail: {
          'contacts': [
            {'id': 'contact-1', 'name': 'Mario Rossi'},
          ],
          'assignments': [],
        },
      );
      await _pumpScreen(tester, db: db, api: api);

      await tester.tap(find.byTooltip('Elimina contatto'));
      await tester.pumpAndSettle();
      // Confirm dialog appears.
      expect(find.text('Eliminare il contatto?'), findsOneWidget);

      await tester.tap(find.text('Elimina'));
      await tester.pumpAndSettle();

      expect(api.deletedContactIds, ['contact-1']);
      await _teardown(tester);
    });
  });

  group('Personale (Gap 2)', () {
    testWidgets('shows empty state when no one is assigned', (tester) async {
      await _seedCantiere(db);
      await _pumpScreen(tester, db: db, api: _FakeAdminApiClient());

      expect(find.text('Nessuna persona assegnata'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('resolves an assigned userId to a name via the colleagues mirror', (tester) async {
      await _seedCantiere(db);
      await db
          .into(db.colleagues)
          .insert(const ColleaguesCompanion(id: Value('user-1'), displayName: Value('Luigi Bianchi')));
      final api = _FakeAdminApiClient(
        cantiereDetail: {
          'contacts': [],
          'assignments': [
            {'id': 'assign-1', 'userId': 'user-1', 'role': 'Elettricista'},
          ],
        },
      );
      await _pumpScreen(tester, db: db, api: api);

      expect(find.text('Luigi Bianchi'), findsOneWidget);
      expect(find.text('Elettricista'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('removing a crew member confirms then calls removeCantiereAssignment', (tester) async {
      await _seedCantiere(db);
      final api = _FakeAdminApiClient(
        cantiereDetail: {
          'contacts': [],
          'assignments': [
            {'id': 'assign-1', 'userId': 'user-1'},
          ],
        },
      );
      await _pumpScreen(tester, db: db, api: api);

      await tester.tap(find.byTooltip('Rimuovi dal cantiere'));
      await tester.pumpAndSettle();
      expect(find.text('Rimuovere dal cantiere?'), findsOneWidget);

      await tester.tap(find.text('Rimuovi'));
      await tester.pumpAndSettle();

      expect(api.removedAssignmentIds, ['assign-1']);
      await _teardown(tester);
    });
  });

  group('Ore / Interventi / Rapportini (Gap 6, read-only)', () {
    testWidgets('shows empty states for all three when nothing is linked', (tester) async {
      await _seedCantiere(db);
      await _pumpScreen(tester, db: db, api: _FakeAdminApiClient());

      expect(find.text('Nessuna ora registrata'), findsOneWidget);
      expect(find.text('Nessun intervento'), findsOneWidget);
      expect(find.text('Nessun rapportino'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('lists hours from GET /api/cantiereworklog?cantiereId=', (tester) async {
      await _seedCantiere(db);
      final api = _FakeAdminApiClient(
        workLogs: [
          {
            'id': 'wl-1',
            'workDate': '2026-08-20T00:00:00Z',
            'startTime': '08:00:00',
            'endTime': '12:00:00',
            'approvalStatus': 'Approved',
          },
        ],
      );
      await _pumpScreen(tester, db: db, api: api);

      expect(find.text('Completato'), findsWidgets); // stato pill, alongside cantiere Stato
      expect(find.textContaining('08:00'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('lists tickets from GET /api/tickets?cantiereId=', (tester) async {
      await _seedCantiere(db);
      final api = _FakeAdminApiClient(
        tickets: [
          {'id': 't-1', 'title': 'Guasto quadro elettrico', 'numero': '2026-00042', 'statusId': 1},
        ],
      );
      await _pumpScreen(tester, db: db, api: api);

      expect(find.text('Guasto quadro elettrico'), findsOneWidget);
      expect(find.text('2026-00042'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('lists reports from GET /api/reports?cantiereId=, decoding int stato', (tester) async {
      await _seedCantiere(db);
      final api = _FakeAdminApiClient(
        reports: [
          {
            'id': 'r-1',
            'title': 'Manutenzione impianto',
            'stato': 2,
            'createdAt': '2026-08-18T09:00:00Z',
          },
        ],
      );
      await _pumpScreen(tester, db: db, api: api);

      expect(find.text('Manutenzione impianto'), findsOneWidget);
      expect(find.text('Controllato'), findsOneWidget);
      await _teardown(tester);
    });
  });

  // Feature audit module #13, Gap 6 (not the same as the module-#8 "Gap 6" group above — the
  // numbering restarts per module): mobile already syncs `Cantiere.commessaId` locally but showed
  // it nowhere in the UI.
  group('Commessa (module 13, Gap 6)', () {
    testWidgets('shows no Commessa row when the cantiere has no commessa', (tester) async {
      await _seedCantiere(db);
      await _pumpScreen(tester, db: db, api: _FakeAdminApiClient());

      expect(find.text('COMMESSA'), findsNothing);
      await _teardown(tester);
    });

    testWidgets("shows the linked commessa's codice, resolved live", (tester) async {
      await _seedCantiere(db);
      await (db.update(db.cantieri)..where((c) => c.id.equals('cant-1'))).write(
        const CantieriCompanion(commessaId: Value('commessa-1')),
      );
      final api = _FakeAdminApiClient(commessa: {'id': 'commessa-1', 'codice': 'COM-001'});
      await _pumpScreen(tester, db: db, api: api);

      expect(find.text('COMMESSA'), findsOneWidget);
      expect(find.text('COM-001'), findsOneWidget);
      await _teardown(tester);
    });

    testWidgets('says plainly it is offline instead of showing a broken row', (tester) async {
      await _seedCantiere(db);
      await (db.update(db.cantieri)..where((c) => c.id.equals('cant-1'))).write(
        const CantieriCompanion(commessaId: Value('commessa-1')),
      );
      await _pumpScreen(tester, db: db, api: _FakeAdminApiClient(), isOnline: false);

      expect(find.text('Caricamento…'), findsNothing);
      expect(find.text('COMMESSA'), findsOneWidget);
      await _teardown(tester);
    });
  });
}
