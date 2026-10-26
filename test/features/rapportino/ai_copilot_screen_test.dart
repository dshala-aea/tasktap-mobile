// dart format width=100
// test/features/rapportino/ai_copilot_screen_test.dart
//
// Widget tests for AiCopilotScreen — the two-screen AI flow (Descrivi → Controlla) that replaced the
// single chat pane; the third screen, Firma, is its own route and is stubbed here so what these
// tests prove is what the flow itself does.
//
// Verifies: a session starts on mount and the first screen asks for a description, generating a
// turn moves to Controlla and shows what the assistant compiled, Confirm is disabled while an open
// item is Ambiguous/Conflict, a failed Confirm keeps the flow and its session, and a successful
// Confirm applies the resolved draft to a LOCAL rapportino (spec §5.5) then hands off to Firma.
// The confirm response resolves and persists nothing server-side (§5.4), so the last test in this
// file also proves no report is ever created over the network.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show SyncNotifier, SyncService, appDatabaseProvider, syncProvider;
import 'package:tasktap_mobile/features/rapportino/ai_copilot_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';
import 'package:tasktap_mobile/core/location/location_service.dart' show gpsPreferenceProvider;

/// The two footers' labels, asserted and tapped below. "Genera" sends the same turn the chat's
/// paper-plane used to; "Conferma" resolves the draft into a local Bozza and hands off to Firma.
const _generateLabel = 'Genera il rapporto';
const _confirmLabel = 'Conferma';

/// A realistic confirm response: a resolved draft, no reportId, and a null location — the exact
/// shape `POST /api/ai/conversations/{id}/confirm` returns (spec §5.4).
AiConversationConfirmResponse _resolvedDraft({String title = 'Pompa bloccata'}) =>
    AiConversationConfirmResponse(
      title: title,
      details: 'Sostituita pompa; verificata tenuta',
      ticketId: 'tkt-1',
      locationId: null,
      staff: const [AiResolvedStaff(userId: 'u-1', hoursWorked: 6.5, kmTraveled: 12)],
      materials: const [
        AiResolvedMaterial(
          freeTextName: 'Guarnizione',
          quantity: 2,
          notes: 'Da verificare: materiale non trovato a catalogo.',
        ),
      ],
      controlli: const [AiResolvedControl(ticketControlId: 'tc-1', boolValue: true)],
    );

/// A turn that compiled something, so the flow advances to Controlla. A turn that only asks a
/// question leaves the draft empty and must NOT advance — that case is asserted on its own.
const _compiledDraft = AiConversationTurnResult(
  assistantReplyText: 'Ho preparato il rapporto.',
  draft: AiCopilotDraftDto(
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
);

/// A turn that only asked a question: nothing to check yet.
const _questionOnlyDraft = AiConversationTurnResult(
  assistantReplyText: 'Quante ore hai lavorato?',
  draft: AiCopilotDraftDto(
    workers: [],
    materials: [],
    controlli: [],
    activities: [],
    openItems: [],
  ),
);

class _FakeAiApiClient extends AiApiClient {
  _FakeAiApiClient({
    this.turnResult,
    this.confirmResult,
    this.confirmError,
  }) : super(Dio());

  final AiConversationTurnResult? turnResult;
  final AiConversationConfirmResponse? confirmResult;
  final Object? confirmError;

  final List<String> sentTurns = [];

  /// Every session id `abandonConversation` was called with, so the release-after-persist order is
  /// assertable rather than assumed.
  final List<String> abandoned = [];

  @override
  Future<AiQuotaDto> getQuota() async =>
      const AiQuotaDto(monthlyLimit: 20, used: 4, remaining: 16);

  @override
  Future<AiConversationSessionDto> startConversation({
    String? ticketId,
    String? cantiereId,
  }) async => AiConversationSessionDto(
    sessionId: 'sess-1',
    ticketId: ticketId,
    cantiereId: cantiereId,
  );

  @override
  Future<AiConversationDetailDto> getConversation(String sessionId) async => AiConversationDetailDto(
    sessionId: sessionId,
    draft: AiCopilotDraftDto.empty,
    turns: const [],
    version: 1,
    expiresAtUtc: DateTime.utc(9999),
  );

  /// Task 11: entering from a ticket first asks for a live session; none exists here.
  @override
  Future<String?> resumeConversation(String ticketId) async => null;

  @override
  Future<AiConversationTurnResult> postTurn(
    String sessionId, {
    required String text,
    AiTurnSource source = AiTurnSource.typed,
    String? audioRef,
    String? rawTranscript,
    String? replacesTurnId,
    List<Map<String, dynamic>>? confirmedEdits,
    required String idempotencyKey,
  }) async {
    sentTurns.add(text);
    return turnResult ??
        const AiConversationTurnResult(assistantReplyText: 'Ok.', draft: AiCopilotDraftDto.empty);
  }

  @override
  Future<AiConversationConfirmResponse> confirmConversation(
    String sessionId, {
    required String idempotencyKey,
  }) async {
    if (confirmError != null) throw confirmError!;
    return confirmResult ?? _resolvedDraft();
  }

  @override
  Future<void> abandonConversation(String sessionId) async {
    abandoned.add(sessionId);
  }
}

/// A real `AiApiClient` over an adapter that records every request and answers with real wire
/// shapes. The positive control the negative test below needs: a fake that overrides the methods
/// outright never reaches Dio, so an empty list of observed calls would prove nothing.
class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.paths);

  final List<RequestOptions> paths;
  static const _sessionId = 'sess-1';

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options);
    final body = _bodyFor(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Object _bodyFor(RequestOptions options) {
    if (options.path == '/api/ai/quota') {
      return {'monthlyLimit': 20, 'used': 4, 'remaining': 16};
    }
    if (options.path.contains('/turns')) {
      return {
        'assistantReplyText': 'Fatto.',
        'draft': {
          'workers': [],
          'materials': [],
          'controlli': [],
          'activities': [
            {'description': 'Sostituita pompa', 'hours': 2, 'state': 2, 'source': 1},
          ],
          'openItems': [],
        },
      };
    }
    if (options.path.contains('/confirm')) {
      return {
        'title': 'Pompa bloccata',
        'details': 'Sostituita pompa',
        'materialiNotRequired': false,
        'customerSignoffText': null,
        'ticketId': 'tkt-1',
        'cantiereId': null,
        'locationId': null,
        'staff': [],
        'materials': [],
        'controlli': [],
        'warnings': [],
      };
    }
    // Conversation start (and anything else this path might grow) — an empty session.
    return {'sessionId': _sessionId, 'ticketId': 'tkt-1'};
  }
}

/// Keeps the post-import lookup sync off the network in widget tests.
class _NoopSync extends SyncNotifier {
  _NoopSync(AppDatabase db) : super(SyncService(db: db, dio: Dio()), db);
  @override
  Future<void> performSync() async {}
}

Widget _wrap(AiApiClient client, {String? ticketId, String? cantiereId, AppDatabase? db}) {
  final database = db ?? AppDatabase(NativeDatabase.memory());
  if (db == null) addTearDown(database.close);
  final router = GoRouter(
    initialLocation: '/copilot',
    routes: [
      GoRoute(
        path: '/copilot',
        builder: (context, state) => AiCopilotScreen(ticketId: ticketId, cantiereId: cantiereId),
      ),
      // The flow's third screen. Stubbed so these tests prove the hand-off and, alongside the Drift
      // assertions, that the id it carries is the LOCAL report Confirm wrote. What Firma itself does
      // is its own screen's business.
      GoRoute(
        path: '/altro/rapportini/firma/:reportId',
        builder: (context, state) =>
            Scaffold(body: Text('firma:${state.pathParameters['reportId']}')),
      ),
      GoRoute(
        path: '/altro/rapportini/editor/:reportId',
        builder: (context, state) =>
            Scaffold(body: Text('editor:${state.pathParameters['reportId']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      aiApiClientProvider.overrideWithValue(client),
      appDatabaseProvider.overrideWithValue(database),
      syncProvider.overrideWith((ref) => _NoopSync(database)),
      gpsPreferenceProvider.overrideWithValue(false),
      // `applyConfirmedDraft` refuses without a signed-in author (same refusal createLocalDraft
      // makes), so the confirm path needs one resolved, exactly as a real signed-in session has.
      internalUserIdProvider.overrideWith((ref) async => 'internal-guid-2'),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Tear the tree down and let drift's stream-cleanup timers fire before the test ends.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Step 1 → step 2: switch to writing, type the description, generate.
Future<void> _describeAndGenerate(
  WidgetTester tester, [
  String text = 'Ho fatto il lavoro',
]) async {
  // The toggle is the last thing on step 1, below the mic orb, in a lazily-built list: on the
  // 800x600 surface the tests run on its centre is past the bottom of the viewport, so a bare `tap`
  // lands on the pinned footer's "Genera il rapporto" instead — and if a banner has pushed it
  // further down it is not in the tree at all, so `ensureVisible` throws. Drag it into reach the way
  // a thumb would, then ensure it is fully visible.
  final toggle = find.byKey(const ValueKey('ai-toggle-writing'));
  if (toggle.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      toggle,
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('ai-description-field')), text);
  await tester.pump();
  await tester.tap(find.widgetWithText(AppButton, _generateLabel));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts a conversation on mount and asks for a description', (tester) async {
    await tester.pumpWidget(_wrap(_FakeAiApiClient(), ticketId: 'tkt-1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Descrivi le attività svolte'), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-toggle-writing')), findsOneWidget);
    // Nothing to generate from yet, so the one action of the screen is disabled.
    final generate = tester.widget<AppButton>(find.widgetWithText(AppButton, _generateLabel));
    expect(generate.onPressed, isNull);
  });

  testWidgets('a compiled turn moves to Controlla and shows what the assistant produced', (
    tester,
  ) async {
    final client = _FakeAiApiClient(turnResult: _compiledDraft);

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester, 'Ho sostituito la valvola');

    expect(client.sentTurns, ['Ho sostituito la valvola']);
    // Step 2 is up: the compile provenance band, the work description, the hours.
    expect(find.textContaining('Compilato dall\'assistente AI'), findsOneWidget);
    expect(find.text('Sostituzione valvola'), findsOneWidget);
    expect(find.text('6,5 h'), findsOneWidget);
    expect(find.widgetWithText(AppButton, _confirmLabel), findsOneWidget);
  });

  testWidgets('a turn that only asks a question stays on Descrivi', (tester) async {
    final client = _FakeAiApiClient(turnResult: _questionOnlyDraft);

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester, 'Ho fatto il lavoro');

    // There is nothing to check yet, and the description is still on screen to refine.
    expect(find.byKey(const ValueKey('ai-description-field')), findsOneWidget);
    expect(find.widgetWithText(AppButton, _confirmLabel), findsNothing);
  });

  testWidgets('Descrivi di nuovo returns to step 1 with the description kept', (tester) async {
    final client = _FakeAiApiClient(turnResult: _compiledDraft);

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester, 'Ho sostituito la valvola');

    await tester.tap(find.byKey(const ValueKey('ai-describe-again')));
    await tester.pumpAndSettle();

    // Step 1 rebuilds, so its list starts at the top again and the field — the last child — has to
    // be scrolled back into existence before it can be read.
    final fieldFinder = find.byKey(const ValueKey('ai-description-field'));
    if (fieldFinder.evaluate().isEmpty) {
      await tester.dragUntilVisible(
        fieldFinder,
        find.byType(Scrollable).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
    }
    final field = tester.widget<TextField>(fieldFinder);
    expect(field.controller?.text, 'Ho sostituito la valvola');
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
    await _describeAndGenerate(tester, 'Ho usato una vite');

    final confirmButton = tester.widget<AppButton>(find.widgetWithText(AppButton, _confirmLabel));
    expect(confirmButton.onPressed, isNull);
  });

  testWidgets('a failed Confirm shows the error and keeps the flow and its session', (
    tester,
  ) async {
    final client = _FakeAiApiClient(
      turnResult: _compiledDraft,
      confirmError: const AiConversationException(409, 'La bozza è cambiata, riprova.'),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester);

    await tester.tap(find.widgetWithText(AppButton, _confirmLabel));
    await tester.pumpAndSettle();

    expect(find.textContaining('La bozza è cambiata'), findsOneWidget);
    // Still on Controlla with the same Conferma button to retry — one state, not two, now that there
    // is no half-created server object to reconcile.
    expect(find.widgetWithText(AppButton, _confirmLabel), findsOneWidget);
    // Nothing was released: the draft was never persisted, so the session must survive the failure.
    expect(client.abandoned, isEmpty);
  });

  testWidgets('Confirm applies the resolved draft to a local rapportino and opens Firma', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final client = _FakeAiApiClient(turnResult: _compiledDraft, confirmResult: _resolvedDraft());

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1', db: db));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester);
    await tester.tap(find.widgetWithText(AppButton, _confirmLabel));
    await tester.pumpAndSettle();

    // The signing screen opened on a LOCAL id, not a server one — nothing was created server-side.
    final row = await db.select(db.draftReports).getSingle();
    expect(find.text('firma:${row.id}'), findsOneWidget);
    expect(row.title, 'Pompa bloccata');
    expect(row.isLocalOnly, isTrue);
    expect(row.stato, 'Bozza');
    expect(row.isAiAssisted, isTrue, reason: "provenance is the client's to set");
    expect(row.locationId, '', reason: 'the null location stayed empty and is the editor\'s to fill');
    expect(
      await db.select(db.reportStaffTable).get(),
      hasLength(1),
      reason: 'the resolved staff line reached the local draft',
    );
    expect(await db.select(db.reportMateriali).get(), hasLength(1));
    expect(await db.select(db.reportControlli).get(), hasLength(1));
    expect(
      client.abandoned,
      ['sess-1'],
      reason: 'the session is released after the draft is persisted',
    );
    await _unmount(tester);
  });

  testWidgets('a cantiere-bound copilot keeps its cantiereId on the applied draft', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    // The response carries no cantiereId (the server echoes the session's binding only when it has
    // one); the screen's own cantiereId is what must survive onto the local draft.
    final client = _FakeAiApiClient(
      turnResult: _compiledDraft,
      confirmResult: const AiConversationConfirmResponse(
        title: 'Manutenzione',
        details: 'Fatto',
        locationId: null,
      ),
    );

    await tester.pumpWidget(_wrap(client, cantiereId: 'cant-7', db: db));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester);
    await tester.tap(find.widgetWithText(AppButton, _confirmLabel));
    await tester.pumpAndSettle();

    final row = await db.select(db.draftReports).getSingle();
    expect(row.cantiereId, 'cant-7');
    await _unmount(tester);
  });

  testWidgets('confirming never writes to the server — the report is the phone\'s until submit', (
    tester,
  ) async {
    final paths = <RequestOptions>[];
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter(paths);
    // The copilot must reach the network through THIS client, not through a method-overriding fake.
    // Overriding aiApiClientProvider with a real `AiApiClient(dio)` is what makes `paths` mean
    // anything; with the fake in place every assertion below would pass on an empty list.
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await tester.pumpWidget(_wrap(AiApiClient(dio), ticketId: 'tkt-1', db: db));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester);
    await tester.tap(find.widgetWithText(AppButton, _confirmLabel));
    await tester.pumpAndSettle();

    expect(
      paths.map((o) => '${o.method} ${o.path}').where((p) => p.startsWith('POST /api/Reports')),
      isEmpty,
      reason:
          'mobile does not create a report on confirm (spec §5.5). Routing this through '
          'POST /api/Reports + children would also make a retried material write deplete stock '
          'twice, which no client-side state machine can detect.',
    );
    expect(
      paths.where(
        (o) =>
            o.path.contains('/staff') ||
            o.path.contains('/materiali') ||
            o.path.contains('/observations'),
      ),
      isEmpty,
    );
    // The positive half — the test must be able to fail on a wrong design, not only on a right one:
    expect(
      paths.map((o) => o.path),
      contains('/api/ai/conversations/sess-1/confirm'),
      reason:
          'if this is empty the adapter is not wired to the copilot and every other '
          'assertion here is vacuous',
    );
    await _unmount(tester);
  });
}
