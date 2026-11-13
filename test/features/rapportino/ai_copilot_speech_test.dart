// dart format width=100
// test/features/rapportino/ai_copilot_speech_test.dart
//
// Task 9 — the copilot's optional spoken replies. Text stays the source of truth: an assistant
// reply is always shown, the speaker action is the only way to hear it (no autoplay), and a new
// turn or leaving the screen stops playback. The device preference is off by default and persists.

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/core/audio/speech_output.dart';
import 'package:tasktap_mobile/core/location/location_service.dart' show gpsPreferenceProvider;
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show SyncNotifier, SyncService, appDatabaseProvider, syncProvider;
import 'package:tasktap_mobile/features/rapportino/ai_copilot_screen.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _FakeEngine implements SpeechEngine {
  final List<String> spoken = [];
  int stops = 0;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stops++;
}

class _FakeAi extends AiApiClient {
  _FakeAi() : super(Dio());

  final List<String> sentTurns = [];

  @override
  Future<AiQuotaDto> getQuota() async => const AiQuotaDto(monthlyLimit: 20, used: 1, remaining: 19);

  @override
  Future<String?> resumeConversation(String ticketId) async => null;

  @override
  Future<AiConversationSessionDto> startConversation({
    String? ticketId,
    String? cantiereId,
  }) async => AiConversationSessionDto(sessionId: 'sess-1', ticketId: ticketId);

  @override
  Future<AiConversationDetailDto> getConversation(String sessionId) async =>
      AiConversationDetailDto(
        sessionId: sessionId,
        draft: AiCopilotDraftDto.empty,
        turns: const [],
        version: 1,
        expiresAtUtc: DateTime.utc(9999),
      );

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
    return const AiConversationTurnResult(
      assistantReplyText: 'Quante ore hai lavorato?',
      draft: AiCopilotDraftDto.empty,
    );
  }
}

class _NoopSync extends SyncNotifier {
  _NoopSync(AppDatabase db) : super(SyncService(db: db, dio: Dio()), db);
  @override
  Future<void> performSync() async {}
}

Widget _wrap(AppDatabase db, AiApiClient ai, SpeechOutput speech) {
  final router = GoRouter(
    initialLocation: '/copilot',
    routes: [
      GoRoute(
        path: '/copilot',
        builder: (context, state) =>
            const AiCopilotScreen(ticketId: 'tkt-1', turnRetryDelay: Duration.zero),
      ),
    ],
  );
  return ProviderScope(retry: (_, _) => null, 
    overrides: [
      aiApiClientProvider.overrideWithValue(ai),
      speechOutputProvider.overrideWith((ref) async => speech),
      appDatabaseProvider.overrideWithValue(db),
      syncProvider.overrideWith((ref) => _NoopSync(db)),
      gpsPreferenceProvider.overrideWithValue(false),
      internalUserIdProvider.overrideWith((ref) async => 'internal-guid-2'),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _describeAndGenerate(WidgetTester tester, [String text = 'Ho fatto il lavoro']) async {
  if (find.byKey(const ValueKey('ai-describe-again')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('ai-describe-again')));
    await tester.pumpAndSettle();
  }
  final toggle = find.byKey(const ValueKey('ai-toggle-writing'));
  if (toggle.evaluate().isEmpty) {
    await tester.dragUntilVisible(toggle, find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  // Write mode survives a question-only turn, so only tap the toggle when the field is hidden.
  if (find.text('Preferisci scrivere?').evaluate().isNotEmpty) {
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
  final field = find.byKey(const ValueKey('ai-description-field'));
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  await tester.enterText(field, text);
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('ai-generate')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('assistant reply is shown but never autoplays', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = _FakeEngine();
    final speech = SpeechOutput(engine: engine);
    await speech.load();

    await tester.pumpWidget(_wrap(db, _FakeAi(), speech));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester);

    expect(find.text('Quante ore hai lavorato?'), findsOneWidget);
    expect(engine.spoken, isEmpty, reason: 'no autoplay without an explicit tap');
    expect(speech.enabled, isFalse);

    await tester.tap(find.byKey(const ValueKey('ai-speak-reply')));
    await tester.pumpAndSettle();

    expect(engine.spoken, ['Quante ore hai lavorato?']);
    expect(speech.enabled, isTrue, reason: 'the explicit tap opts the device in');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('tasktap.ai.tts.enabled'), isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('speaker toggle persists the device preference', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = _FakeEngine();
    final speech = SpeechOutput(engine: engine);
    await speech.load();

    await tester.pumpWidget(_wrap(db, _FakeAi(), speech));
    await tester.pumpAndSettle();

    expect(speech.enabled, isFalse);
    final toggle = find.byKey(const ValueKey('ai-tts-toggle'));
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(speech.enabled, isTrue);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(speech.enabled, isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a new turn stops playback', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = _FakeEngine();
    final speech = SpeechOutput(engine: engine);
    await speech.load();

    await tester.pumpWidget(_wrap(db, _FakeAi(), speech));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester, 'Primo aggiornamento');

    await tester.tap(find.byKey(const ValueKey('ai-speak-reply')));
    await tester.pumpAndSettle();
    expect(engine.spoken, hasLength(1));

    await _describeAndGenerate(tester, 'Secondo aggiornamento');

    expect(engine.stops, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('leaving the screen stops playback', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final engine = _FakeEngine();
    final speech = SpeechOutput(engine: engine);
    await speech.load();

    await tester.pumpWidget(_wrap(db, _FakeAi(), speech));
    await tester.pumpAndSettle();
    await _describeAndGenerate(tester);

    await tester.tap(find.byKey(const ValueKey('ai-speak-reply')));
    await tester.pumpAndSettle();
    expect(engine.spoken, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(engine.stops, greaterThanOrEqualTo(1));
  });
}
