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
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/features/rapportino/ai_copilot_screen.dart';

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

Widget _wrap(AiApiClient client, {String? ticketId}) {
  final router = GoRouter(
    initialLocation: '/copilot',
    routes: [
      GoRoute(
        path: '/copilot',
        builder: (context, state) => AiCopilotScreen(ticketId: ticketId),
      ),
      GoRoute(
        path: '/altro/rapportini/editor/:reportId',
        builder: (context, state) =>
            Scaffold(body: Text('editor:${state.pathParameters['reportId']}')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [aiApiClientProvider.overrideWithValue(client)],
    child: MaterialApp.router(routerConfig: router),
  );
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
  });

  testWidgets('Confirm is disabled while an open item is Ambiguous', (tester) async {
    final client = _FakeAiApiClient(
      turnResult: const AiConversationTurnResult(
        assistantReplyText: 'Serve una scelta.',
        draft: AiCopilotDraftDto(
          workers: [],
          materials: [],
          controlli: [],
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

  testWidgets('a successful Confirm navigates to the created report editor', (tester) async {
    final client = _FakeAiApiClient(
      turnResult: const AiConversationTurnResult(
        assistantReplyText: 'Fatto.',
        draft: AiCopilotDraftDto(workers: [], materials: [], controlli: [], openItems: []),
      ),
      confirmResult: const AiConversationConfirmResult(reportId: 'rpt-1', replayed: false),
    );

    await tester.pumpWidget(_wrap(client, ticketId: 'tkt-1'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Ho fatto il lavoro');
    await tester.tap(find.byTooltip('Invia'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, 'Conferma e crea rapportino'));
    await tester.pumpAndSettle();

    expect(find.text('editor:rpt-1'), findsOneWidget);
  });

  testWidgets('a failed Confirm shows the error and stays on the screen', (tester) async {
    final client = _FakeAiApiClient(
      turnResult: const AiConversationTurnResult(
        assistantReplyText: 'Fatto.',
        draft: AiCopilotDraftDto(workers: [], materials: [], controlli: [], openItems: []),
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
}
