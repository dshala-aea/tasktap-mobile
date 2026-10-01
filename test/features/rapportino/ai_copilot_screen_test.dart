// dart format width=100
// test/features/rapportino/ai_copilot_screen_test.dart
//
// Widget tests for AiCopilotScreen — the multi-turn AI copilot conversation entry point,
// distinct from AiDraftAction's single-shot "Bozza automatica" (see ai_draft_action_test.dart).
//
// Verifies: a session starts on mount, sending a turn appends both messages and updates the
// draft summary, Confirm is disabled while an open item is Ambiguous/Conflict, and a successful
// Confirm navigates to the created report's editor route.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/reports/server_report_api_client.dart';
import 'package:tasktap_mobile/data/reports/server_report_dto.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show SyncNotifier, SyncService, appDatabaseProvider, syncProvider;
import 'package:tasktap_mobile/features/rapportino/ai_copilot_screen.dart';
import 'package:tasktap_mobile/features/rapportino/steps/step_dettagli.dart';
import 'package:tasktap_mobile/presentation/providers/report_editor_providers.dart';
import 'package:tasktap_mobile/core/location/location_service.dart' show gpsPreferenceProvider;

import '../../data/reports/server_report_dto_test.dart' show backendFixture;

class _FakeAiApiClient extends AiApiClient {
  _FakeAiApiClient({
    this.turnResult,
    this.confirmResult,
    this.confirmError,
  }) : super(Dio());

  final AiConversationTurnResult? turnResult;
  final AiConversationConfirmResult? confirmResult;
  final Object? confirmError;

  final List<String> sentTurns = [];

  @override
  Future<AiQuotaDto> getQuota() async =>
      const AiQuotaDto(monthlyLimit: 20, used: 4, remaining: 16);

  @override
  Future<AiConversationSessionDto> startConversation({
    String? ticketId,
    String? cantiereId,
  }) async => AiConversationSessionDto(sessionId: 'sess-1', ticketId: ticketId);

  @override
  Future<AiConversationTurnResult> sendTurn(String sessionId, String text) async {
    sentTurns.add(text);
    return turnResult ??
        const AiConversationTurnResult(assistantReplyText: 'Ok.', draft: AiCopilotDraftDto.empty);
  }

  @override
  Future<AiConversationConfirmResult> confirmConversation(
    String sessionId, {
    required String idempotencyKey,
  }) async {
    if (confirmError != null) throw confirmError!;
    return confirmResult ?? const AiConversationConfirmResult(reportId: 'rpt-1', replayed: false);
  }

  @override
  Future<void> abandonConversation(String sessionId) async {}
}

/// Serves the backend-shaped fixture (re-keyed to the confirmed report id) or fails on demand.
class _FakeServerReportApi extends ServerReportApiClient {
  _FakeServerReportApi({this.fail = false, this.stato = 0}) : super(Dio());
  bool fail;
  final int stato;
  final fetched = <String>[];

  @override
  Future<ServerReportDto> fetchReport(String reportId) async {
    fetched.add(reportId);
    if (fail) throw DioException(requestOptions: RequestOptions(path: '/api/Reports/$reportId'));
    return ServerReportDto.fromJson({...backendFixture(), 'id': reportId, 'stato': stato});
  }
}

/// Keeps the post-import lookup sync off the network in widget tests.
class _NoopSync extends SyncNotifier {
  _NoopSync(AppDatabase db) : super(SyncService(db: db, dio: Dio()), db);
  @override
  Future<void> performSync() async {}
}

Widget _wrap(
  AiApiClient client, {
  String? ticketId,
  AppDatabase? db,
  ServerReportApiClient? serverApi,
}) {
  final database = db ?? AppDatabase(NativeDatabase.memory());
  if (db == null) addTearDown(database.close);
  final router = GoRouter(
    initialLocation: '/copilot',
    routes: [
      GoRoute(
        path: '/copilot',
        builder: (context, state) => AiCopilotScreen(ticketId: ticketId),
      ),
      GoRoute(
        path: '/altro/rapportini/editor/:reportId',
        // The real Dettagli step stands in for the editor: it reads ONLY from Drift, exactly like
        // the real editor, so what it shows is what the import wrote.
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              Text('editor:${state.pathParameters['reportId']}'),
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final id = state.pathParameters['reportId']!;
                    // Like the real form screen: build the step only once hydration finished.
                    if (ref.watch(reportEditorProvider(id)).isLoading) return const SizedBox();
                    return StepDettagli(reportId: id);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      aiApiClientProvider.overrideWithValue(client),
      appDatabaseProvider.overrideWithValue(database),
      syncProvider.overrideWith((ref) => _NoopSync(database)),
      serverReportApiClientProvider.overrideWithValue(serverApi ?? _FakeServerReportApi()),
      gpsPreferenceProvider.overrideWithValue(false),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Tear the tree down and let drift's stream-cleanup timers fire before the test ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('starts a conversation on mount and shows the empty-state hint', (tester) async {
    await tester.pumpWidget(_wrap(_FakeAiApiClient(), ticketId: 'tkt-1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Racconta cosa hai fatto'), findsOneWidget);
  });

  testWidgets('sending a turn appends messages and updates the draft summary', (tester) async {
    final client = _FakeAiApiClient(
      turnResult: const AiConversationTurnResult(
        assistantReplyText: 'Ho aggiornato la bozza.',
        draft: AiCopilotDraftDto(
          diagnosi: 'Valvola bloccata',
          workers: [
            AiDraftWorkerRef(
              userId: 'u1',
              fullName: 'Marco Rossi',
              hours: 6.5,
              state: AiResolutionState.resolvedBySystem,
            ),
          ],
          materials: [],
          controlli: [],
          activities: [
            AiDraftActivity(
              description: 'Sostituzione valvola',
              hours: 2,
              state: AiResolutionState.resolvedBySystem,
            ),
          ],
          openItems: [],
        ),
      ),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Ho sostituito la valvola');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();

    expect(client.sentTurns, ['Ho sostituito la valvola']);
    expect(find.text('Ho sostituito la valvola'), findsOneWidget);
    expect(find.text('Ho aggiornato la bozza.'), findsOneWidget);
    expect(find.textContaining('Valvola bloccata'), findsOneWidget);
    expect(find.textContaining('Marco Rossi'), findsOneWidget);
    // Bug (2026-09-23): activities[] — what Confirm builds the created Report's Title/Description
    // from — used to be silently dropped, so the technician had no way to verify it before
    // confirming.
    expect(find.textContaining('Sostituzione valvola'), findsOneWidget);
  });

  testWidgets('Confirm is disabled while an open item is Ambiguous', (tester) async {
    final client = _FakeAiApiClient(
      turnResult: const AiConversationTurnResult(
        assistantReplyText: 'Serve una scelta.',
        draft: AiCopilotDraftDto(
          workers: [],
          materials: [],
          controlli: [],
          activities: [],
          openItems: [
            AiCandidateFact(field: 'materials[0].materialId', state: AiResolutionState.ambiguous),
          ],
        ),
      ),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Ho usato una vite');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();

    final confirmButton = tester.widget<AppButton>(
      find.widgetWithText(AppButton, 'Conferma e crea rapportino'),
    );
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('a failed Confirm shows the error and stays on the screen', (tester) async {
    final client = _FakeAiApiClient(
      turnResult: const AiConversationTurnResult(
        assistantReplyText: 'Fatto.',
        draft: AiCopilotDraftDto(workers: [], materials: [], controlli: [], activities: [], openItems: []),
      ),
      confirmError: const AiConversationException(409, 'La bozza è cambiata, riprova.'),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Ho fatto il lavoro');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Conferma e crea rapportino'));
    await tester.pumpAndSettle();

    expect(find.textContaining('La bozza è cambiata'), findsOneWidget);
    expect(find.text('editor:rpt-1'), findsNothing);
  });

  Future<void> confirmFlow(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField), 'Ho fatto il lavoro');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(AppButton, 'Conferma e crea rapportino'));
    await tester.pumpAndSettle();
  }

  const emptyDraft = AiConversationTurnResult(
    assistantReplyText: 'Fatto.',
    draft: AiCopilotDraftDto(workers: [], materials: [], controlli: [], activities: [], openItems: []),
  );

  testWidgets('Confirm imports the server report into Drift before opening the editor', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final serverApi = _FakeServerReportApi();
    final client = _FakeAiApiClient(
      turnResult: emptyDraft,
      confirmResult: const AiConversationConfirmResult(reportId: 'rpt-1', replayed: false),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1', db: db, serverApi: serverApi));
    await tester.pumpAndSettle();
    await confirmFlow(tester);

    expect(serverApi.fetched, ['rpt-1']);
    expect(find.text('editor:rpt-1'), findsOneWidget);
    // The editor shows the confirmed values, not a blank form.
    expect(find.text('Sostituita pompa; verificata tenuta'), findsOneWidget);
    expect(find.text('Pompa bloccata'), findsOneWidget);
    expect(find.text('Sostituita'), findsOneWidget);
    expect(await db.select(db.reportStaffTable).get(), hasLength(1));
    expect(await db.select(db.reportMateriali).get(), hasLength(2));
    final row = await (db.select(db.draftReports)..where((r) => r.id.equals('rpt-1'))).getSingle();
    expect(row.tenantId, '22222222-2222-2222-2222-222222222222');
    await _unmount(tester);
  });

  testWidgets('a cantiere-bound copilot keeps its cantiereId on the imported report', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final router = GoRouter(
      initialLocation: '/copilot',
      routes: [
        GoRoute(path: '/copilot', builder: (_, _) => const AiCopilotScreen(cantiereId: 'cant-7')),
        GoRoute(
          path: '/altro/rapportini/editor/:reportId',
          builder: (_, state) => Scaffold(body: Text('editor:${state.pathParameters['reportId']}')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiApiClientProvider.overrideWithValue(
            _FakeAiApiClient(
              turnResult: emptyDraft,
              confirmResult: const AiConversationConfirmResult(reportId: 'rpt-1', replayed: false),
            ),
          ),
          appDatabaseProvider.overrideWithValue(db),
          syncProvider.overrideWith((ref) => _NoopSync(db)),
          serverReportApiClientProvider.overrideWithValue(_FakeServerReportApi()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await confirmFlow(tester);

    final row = await (db.select(db.draftReports)..where((r) => r.id.equals('rpt-1'))).getSingle();
    expect(row.cantiereId, 'cant-7');
  });

  testWidgets('a failed import keeps the session, shows an error and does NOT open the editor', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final serverApi = _FakeServerReportApi(fail: true);
    final client = _FakeAiApiClient(
      turnResult: emptyDraft,
      confirmResult: const AiConversationConfirmResult(reportId: 'rpt-1', replayed: false),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1', db: db, serverApi: serverApi));
    await tester.pumpAndSettle();
    await confirmFlow(tester);

    expect(find.textContaining('non è stato possibile scaricarlo'), findsWidgets);
    expect(find.text('editor:rpt-1'), findsNothing);
    expect(find.text('Fatto.'), findsOneWidget); // conversation still on screen
    expect(await db.select(db.draftReports).get(), isEmpty);

    // Retry re-runs only the import (Confirm is not repeated) and then opens the editor.
    serverApi.fail = false;
    await tester.tap(find.widgetWithText(AppButton, 'Riprova'));
    await tester.pumpAndSettle();

    expect(serverApi.fetched, ['rpt-1', 'rpt-1']);
    expect(find.text('editor:rpt-1'), findsOneWidget);
    expect(find.text('Pompa bloccata'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('a report no longer Bozza shows the not-editable message with Chiudi, no retry loop', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final serverApi = _FakeServerReportApi(stato: 1);
    final client = _FakeAiApiClient(
      turnResult: emptyDraft,
      confirmResult: const AiConversationConfirmResult(reportId: 'rpt-1', replayed: false),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1', db: db, serverApi: serverApi));
    await tester.pumpAndSettle();
    await confirmFlow(tester);

    expect(find.text('Questo rapportino non è più modificabile.'), findsWidgets);
    expect(find.textContaining('Controlla la connessione'), findsNothing);
    expect(find.widgetWithText(AppButton, 'Chiudi'), findsOneWidget);
    expect(find.widgetWithText(AppButton, 'Riprova'), findsNothing);
    expect(find.text('editor:rpt-1'), findsNothing);
    await _unmount(tester);
  });
}
