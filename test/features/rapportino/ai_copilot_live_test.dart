// dart format width=100
// test/features/rapportino/ai_copilot_live_test.dart
//
// Task 11 — the LIVE draft: resume/start from a ticket, the seeded draft with provenance badges,
// voice turns (record -> transcribe -> turn), correction, and the 409/429 handling around a turn.
// A fake AiApiClient and a fake VoiceCaptureController stand in for the network and the microphone.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tasktap_mobile/core/audio/audio_recorder_service.dart';
import 'package:tasktap_mobile/core/audio/pending_recording_store.dart';
import 'package:tasktap_mobile/core/audio/voice_capture_controller.dart';
import 'package:tasktap_mobile/core/audio/voice_capture_provider.dart';
import 'package:tasktap_mobile/core/location/location_service.dart' show gpsPreferenceProvider;
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show SyncNotifier, SyncService, appDatabaseProvider, syncProvider;
import 'package:tasktap_mobile/features/rapportino/ai_copilot_screen.dart';
import 'package:tasktap_mobile/features/rapportino/draft_provenance_badge.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _Posted {
  _Posted(this.text, this.source, this.audioRef, this.rawTranscript, this.replacesTurnId, this.key);
  final String text;
  final AiTurnSource source;
  final String? audioRef;
  final String? rawTranscript;
  final String? replacesTurnId;
  final String key;
}

class _FakeAi extends AiApiClient {
  _FakeAi({this.liveSessionId, AiConversationDetailDto? detail, this.startError})
    : detail = detail ?? _detail(),
      super(Dio());

  final String? liveSessionId;
  final Object? startError;
  AiConversationDetailDto detail;

  /// One entry consumed per postTurn: an exception is thrown, a result is returned.
  final Queue<Object> turnScript = Queue();

  /// When set, postTurn waits for it (to observe the in-flight state).
  Completer<void>? turnGate;
  final List<_Posted> posted = [];
  final List<String> resumeCalls = [];
  final List<String> startCalls = [];
  final List<String> getCalls = [];
  final List<String> abandoned = [];

  /// Called on every getConversation after the first (so a test can change what a refetch returns).
  AiConversationDetailDto Function()? onRefetch;

  @override
  Future<AiQuotaDto> getQuota() async => const AiQuotaDto(monthlyLimit: 20, used: 1, remaining: 19);

  @override
  Future<String?> resumeConversation(String ticketId) async {
    resumeCalls.add(ticketId);
    return liveSessionId;
  }

  @override
  Future<AiConversationSessionDto> startConversation({
    String? ticketId,
    String? cantiereId,
  }) async {
    if (startError != null) throw startError!;
    startCalls.add(ticketId ?? '');
    return AiConversationSessionDto(sessionId: 'sess-new', ticketId: ticketId);
  }

  @override
  Future<AiConversationDetailDto> getConversation(String sessionId) async {
    getCalls.add(sessionId);
    if (getCalls.length > 1 && onRefetch != null) detail = onRefetch!();
    return detail;
  }

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
    posted.add(_Posted(text, source, audioRef, rawTranscript, replacesTurnId, idempotencyKey));
    await turnGate?.future;
    final next = turnScript.isEmpty
        ? const AiConversationTurnResult(assistantReplyText: 'Ok.', draft: AiCopilotDraftDto.empty)
        : turnScript.removeFirst();
    if (next is AiConversationTurnResult) return next;
    throw next;
  }

  @override
  Future<void> abandonConversation(String sessionId) async => abandoned.add(sessionId);
}

class _ThrowingAbandonAi extends _FakeAi {
  _ThrowingAbandonAi({super.detail});
  int abandonAttempts = 0;
  @override
  Future<void> abandonConversation(String sessionId) async {
    abandonAttempts++;
    throw StateError('offline');
  }
}

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.status, this.body);
  final int status;
  final String body;
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _NoRecorder implements AudioRecorderService {
  @override
  Future<void> start() async {}
  @override
  Future<File> stop() async => File('x.m4a');
  @override
  Stream<Duration> get elapsed => const Stream.empty();
}

class _GrantedMic implements MicPermissionService {
  @override
  Future<MicPermission> request() async => MicPermission.granted;
}

class _FakeStore extends PendingRecordingStore {
  _FakeStore() : super(Directory.systemTemp);
  final List<String> deleted = [];
  @override
  Future<void> delete(PendingRecording r) async => deleted.add(r.id);
}

PendingRecording _rec(String n, {String? ticketId = 'tkt-1', String userId = 'user-1'}) =>
    PendingRecording(
      id: 'p-$n',
      file: File('p-$n.m4a'),
      idempotencyKey: 'pk-$n',
      createdAt: DateTime.now().toUtc(),
      userId: userId,
      ticketId: ticketId,
    );

class _FakeVoice extends VoiceCaptureController {
  _FakeVoice._(this.fakeStore)
    : super(
        recorder: _NoRecorder(),
        permissions: _GrantedMic(),
        store: fakeStore,
        consentAccepted: () async => true,
        currentUserId: () => 'user-1',
        upload: (f, k) async => throw StateError('unused'),
      );

  factory _FakeVoice() => _FakeVoice._(_FakeStore());

  final _FakeStore fakeStore;
  List<PendingRecording> pending = [];

  @override
  Future<List<PendingRecording>> pendingForCurrentUser() async => pending;

  final Queue<Object> uploads = Queue();
  final List<String> uploadKeys = [];
  RecordingStartResult startResult = RecordingStartResult.started;
  bool _rec = false;
  int stopCalls = 0;
  int cancelCalls = 0;
  int _n = 0;

  @override
  bool get isRecording => _rec;

  /// Results for the next [start] calls, in order (falls back to [startResult]).
  final Queue<RecordingStartResult> startScript = Queue();

  /// When set, a [start] that starts recording only returns once this completes (a first-run
  /// permission prompt or a slow recorder): the microphone is already on while the caller waits.
  Completer<void>? startGate;
  int startCalls = 0;

  @override
  Future<RecordingStartResult> start({String? ticketId}) async {
    startCalls++;
    final result = startScript.isEmpty ? startResult : startScript.removeFirst();
    if (result == RecordingStartResult.started) {
      _rec = true;
      final gate = startGate;
      if (gate != null) await gate.future;
    }
    return result;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    _rec = false;
  }

  @override
  Future<PendingRecording> stop() async {
    stopCalls++;
    _rec = false;
    _n++;
    return PendingRecording(
      id: 'rec-$_n',
      file: File('rec-$_n.m4a'),
      idempotencyKey: 'rec-key-$_n',
      createdAt: DateTime.now().toUtc(),
      userId: 'user-1',
    );
  }

  @override
  Future<AiTranscription> transcribe(PendingRecording pending) async {
    uploadKeys.add(pending.idempotencyKey);
    final next = uploads.isEmpty
        ? const AiTranscription(transcript: 'Ho cambiato il filtro', audioRef: 'audio-1')
        : uploads.removeFirst();
    if (next is AiTranscription) return next;
    throw next;
  }
}

AiConversationDetailDto _detail({
  AiCopilotDraftDto draft = AiCopilotDraftDto.empty,
  List<AiConversationTurn> turns = const [],
  DateTime? expires,
}) => AiConversationDetailDto(
  sessionId: 'sess-new',
  ticketId: 'tkt-1',
  draft: draft,
  turns: turns,
  version: 3,
  expiresAtUtc: expires ?? DateTime.now().toUtc().add(const Duration(days: 20)),
  authorName: 'Marco Rossi',
);

AiCopilotDraftDto _seededDraft() => const AiCopilotDraftDto(
  workers: [
    AiDraftWorkerRef(
      userId: 'u-1',
      fullName: 'Luca Bianchi',
      state: AiResolutionState.needsConfirmation,
      source: AiFactSource.planned,
    ),
  ],
  materials: [
    AiDraftMaterialUsage(
      materialId: 'm-1',
      name: 'Filtro olio',
      quantity: 1,
      state: AiResolutionState.needsConfirmation,
      source: AiFactSource.planned,
    ),
  ],
  controlli: [],
  activities: [
    AiDraftActivity(
      description: 'Manutenzione compressore',
      hours: 3,
      state: AiResolutionState.resolvedBySystem,
      source: AiFactSource.ticketRecord,
    ),
  ],
  openItems: [],
);

class _NoopSync extends SyncNotifier {
  _NoopSync(AppDatabase db) : super(SyncService(db: db, dio: Dio()), db);
  @override
  Future<void> performSync() async {}
}

Widget _wrap(_FakeAi ai, _FakeVoice voice, {String? ticketId = 'tkt-1', bool pushed = false}) {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  final router = GoRouter(
    initialLocation: pushed ? '/home' : '/copilot',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => Scaffold(
          body: Column(
            children: [
              const Text('home-screen'),
              TextButton(onPressed: () => context.push('/copilot'), child: const Text('open')),
            ],
          ),
        ),
      ),
      GoRoute(
        path: '/copilot',
        builder: (context, state) =>
            AiCopilotScreen(ticketId: ticketId, turnRetryDelay: Duration.zero),
      ),
      GoRoute(
        path: '/altro/rapportini/editor/:reportId',
        builder: (context, state) => Text('editor:${state.pathParameters['reportId']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      aiApiClientProvider.overrideWithValue(ai),
      voiceCaptureControllerProvider.overrideWith((ref) async => voice),
      appDatabaseProvider.overrideWithValue(db),
      syncProvider.overrideWith((ref) => _NoopSync(db)),
      gpsPreferenceProvider.overrideWithValue(false),
      internalUserIdProvider.overrideWith((ref) async => 'internal-guid-2'),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _openPushed(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// Types [text] and sends it.
Future<void> _typeAndSend(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextFormField), text);
  await tester.tap(find.byTooltip('Invia'));
  await tester.pumpAndSettle();
}

Future<void> _failOneTypedTurn(_FakeAi ai, WidgetTester tester) async {
  ai.turnScript.add(const AiConversationException(null, 'Nessuna connessione.', offline: true));
  await _typeAndSend(tester, 'Primo aggiornamento');
}

bool _enabled(WidgetTester tester, String tooltip) =>
    tester
        .widget<IconButton>(
          find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)).first,
        )
        .onPressed !=
    null;

/// Tap the mic twice (start, then stop) and let the upload + turn run.
Future<void> _recordOnce(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Ferma la registrazione'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('parsing', () {
    test('Unknown_enum_strings_parse_to_safe_defaults', () {
      final draft = AiCopilotDraftDto.fromJson({
        'futureTopLevelField': {'a': 1},
        'workers': [
          {
            'userId': 'u1',
            'fullName': 'Pianificato',
            'state': 'NeedsConfirmation',
            'source': 'Planned',
            'brandNewField': true,
          },
          {'userId': 'u2', 'fullName': 'Dal ticket', 'state': 'ResolvedBySystem', 'source': 'TicketRecord'},
          {'userId': 'u3', 'fullName': 'Futuro', 'state': 'SomethingInvented', 'source': 'FromTheFuture'},
        ],
        'activities': [
          {'description': 'x', 'state': 'Whatever', 'source': 'Whatever'},
        ],
        'materials': [
          {'materialId': 'm', 'name': 'n', 'quantity': 1, 'state': 7, 'source': null},
        ],
        'openItems': [
          {'field': 'f', 'state': 'AlsoInvented', 'provenance': {'sourceType': 'Nope'}},
        ],
      });

      expect(draft.workers[0].state, AiResolutionState.needsConfirmation);
      expect(draft.workers[0].source, AiFactSource.planned);
      expect(draft.workers[1].source, AiFactSource.ticketRecord);
      expect(draft.workers[2].state, AiResolutionState.unresolved);
      expect(draft.workers[2].source, AiFactSource.operatorInput);
      expect(draft.activities.single.state, AiResolutionState.unresolved);
      expect(draft.activities.single.source, AiFactSource.operatorInput);
      expect(draft.materials.single.state, AiResolutionState.unresolved);
      expect(draft.materials.single.source, AiFactSource.operatorInput);
      expect(draft.openItems.single.state, AiResolutionState.unresolved);
      expect(draft.openItems.single.source, AiFactSource.operatorInput);
    });

    test('a conversation detail with unknown turn sources and extra fields parses', () {
      final d = AiConversationDetailDto.fromJson({
        'sessionId': 's',
        'ticketId': 't',
        'draft': {'workers': []},
        'turns': [
          {'turnId': 'a', 'role': 'Operator', 'text': 'ciao', 'source': 'Voice', 'at': '2026-10-20T10:00:00Z'},
          {'turnId': 'b', 'role': 'Assistant', 'text': 'ok', 'source': 'Telepathy', 'at': 'not-a-date', 'x': 1},
        ],
        'version': 4,
        'expiresAtUtc': '2026-11-01T00:00:00Z',
        'author': {'userId': 'u', 'fullName': 'Marco'},
        'extra': 1,
      });
      expect(d.turns[0].source, AiTurnSource.voice);
      expect(d.turns[1].source, AiTurnSource.typed);
      expect(d.authorName, 'Marco');
      expect(d.expiresAtUtc.year, 2026);
    });
  });

  group('entering from a ticket', () {
    testWidgets('Resumes_existing_session_for_the_ticket', (tester) async {
      final ai = _FakeAi(
        liveSessionId: 'sess-live',
        detail: _detail(
          draft: _seededDraft(),
          turns: [
            AiConversationTurn(
              turnId: 't1',
              role: 'Operator',
              text: 'Sono arrivato in sede',
              source: AiTurnSource.typed,
              at: DateTime.utc(2026, 10, 20, 9),
            ),
            AiConversationTurn(
              turnId: 't2',
              role: 'Assistant',
              text: 'Annotato.',
              source: AiTurnSource.typed,
              at: DateTime.utc(2026, 10, 20, 9, 1),
            ),
          ],
        ),
      );
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(ai.resumeCalls, ['tkt-1']);
      expect(ai.startCalls, isEmpty, reason: 'a live session exists: nothing new is started');
      expect(ai.getCalls, ['sess-live']);
      expect(find.text('Sono arrivato in sede'), findsOneWidget);
      expect(find.text('Annotato.'), findsOneWidget);
      expect(find.textContaining('Luca Bianchi'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('starts a session when none is live and shows the seeded draft at once', (
      tester,
    ) async {
      final ai = _FakeAi(detail: _detail(draft: _seededDraft()));
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(ai.startCalls, ['tkt-1']);
      expect(find.textContaining('Manutenzione compressore'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Seeded_draft_shows_planned_items_marked_planned', (tester) async {
      final ai = _FakeAi(detail: _detail(draft: _seededDraft()));
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      // Two planned entries (worker + material), each with the "not confirmed" badge.
      expect(find.text('Pianificato: conferma'), findsNWidgets(2));
      expect(
        find.byWidgetPredicate(
          (w) => w.key is ValueKey && '${(w.key! as ValueKey).value}'.startsWith('planned-unconfirmed-row'),
        ),
        findsNWidgets(2),
      );
      // The ticket's own hours are labelled as coming from the ticket, not as work reported.
      expect(find.text('Dal ticket'), findsOneWidget);
      expect(find.byType(DraftProvenanceBadge), findsNWidgets(3));
      await _unmount(tester);
    });
  });

  group('provenance label', () {
    test('built from source and state', () {
      String? l(AiFactSource s, AiResolutionState st) => provenanceLabel(s, st);
      expect(l(AiFactSource.planned, AiResolutionState.needsConfirmation), 'Pianificato: conferma');
      expect(l(AiFactSource.planned, AiResolutionState.resolvedBySystem), 'Pianificato: conferma');
      expect(l(AiFactSource.ticketRecord, AiResolutionState.resolvedBySystem), 'Dal ticket');
      expect(l(AiFactSource.ticketRecord, AiResolutionState.needsConfirmation), 'Dal ticket: conferma');
      expect(l(AiFactSource.ticketRecord, AiResolutionState.unresolved), 'Dal ticket: conferma');
      expect(l(AiFactSource.operatorInput, AiResolutionState.resolvedBySystem), 'Riferito');
      expect(l(AiFactSource.operatorInput, AiResolutionState.operatorConfirmed), 'Riferito');
      expect(l(AiFactSource.operatorInput, AiResolutionState.unresolved), 'Riferito');
      expect(l(AiFactSource.operatorInput, AiResolutionState.needsConfirmation), 'Da confermare');
      expect(l(AiFactSource.operatorInput, AiResolutionState.ambiguous), 'Da chiarire');
      expect(l(AiFactSource.planned, AiResolutionState.conflict), 'In conflitto');
      expect(l(AiFactSource.taskTapTool, AiResolutionState.unresolved), 'Non verificato');
    });

    test('planned and ticket values are unconfirmed proposals unless the technician confirmed', () {
      bool u(AiFactSource s, AiResolutionState st) => isUnconfirmedProposal(s, st);
      expect(u(AiFactSource.planned, AiResolutionState.needsConfirmation), isTrue);
      expect(u(AiFactSource.planned, AiResolutionState.resolvedBySystem), isTrue);
      expect(u(AiFactSource.planned, AiResolutionState.unresolved), isTrue, reason: 'unknown future state');
      expect(u(AiFactSource.ticketRecord, AiResolutionState.resolvedBySystem), isFalse, reason: 'ticket data is authoritative');
      expect(u(AiFactSource.ticketRecord, AiResolutionState.unresolved), isTrue);
      expect(u(AiFactSource.ticketRecord, AiResolutionState.needsConfirmation), isTrue);
      expect(u(AiFactSource.planned, AiResolutionState.operatorConfirmed), isFalse);
      expect(u(AiFactSource.operatorInput, AiResolutionState.resolvedBySystem), isFalse);
      expect(u(AiFactSource.operatorInput, AiResolutionState.needsConfirmation), isTrue);
      expect(u(AiFactSource.planned, AiResolutionState.ambiguous), isFalse);
    });
  });

  group('voice turns', () {
    testWidgets('a recording is transcribed, shown, and posted as a Voice turn', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await _recordOnce(tester);

      expect(voice.uploadKeys, ['rec-key-1']);
      expect(ai.posted, hasLength(1));
      final p = ai.posted.single;
      expect(p.text, 'Ho cambiato il filtro');
      expect(p.source, AiTurnSource.voice);
      expect(p.audioRef, 'audio-1');
      expect(p.rawTranscript, 'Ho cambiato il filtro');
      expect(p.replacesTurnId, isNull);
      expect(find.text('Ho cambiato il filtro'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Retry_after_lost_response_reuses_the_idempotency_key', (tester) async {
      final ai = _FakeAi()
        ..turnScript.add(const AiConversationException(null, 'Nessuna connessione.', offline: true));
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await _recordOnce(tester);
      expect(ai.posted, hasLength(1), reason: 'the response was lost: not retried silently');
      expect(find.text('Riprova invio'), findsOneWidget);

      await tester.tap(find.text('Riprova invio'));
      await tester.pumpAndSettle();

      expect(ai.posted, hasLength(2));
      expect(ai.posted[1].key, ai.posted[0].key, reason: 'same key: the server replays, never double-applies');
      expect(ai.posted[1].text, ai.posted[0].text);
      expect(ai.posted[1].audioRef, 'audio-1');
      expect(voice.uploadKeys, ['rec-key-1'], reason: 'already transcribed: the audio is not uploaded twice');
      expect(find.text('Riprova invio'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a failed transcribe keeps the recording and retries it with the SAME key', (
      tester,
    ) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()
        ..uploads.add(
          const AiTranscribeException(AiTranscribeError.offline, 'Nessuna connessione.'),
        );
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await _recordOnce(tester);
      expect(ai.posted, isEmpty);
      await tester.tap(find.text('Riprova invio'));
      await tester.pumpAndSettle();

      expect(voice.uploadKeys, ['rec-key-1', 'rec-key-1']);
      expect(ai.posted, hasLength(1));
      await _unmount(tester);
    });

    testWidgets('Correcting_the_transcript_posts_replacesTurnId', (tester) async {
      final ai = _FakeAi();
      // After the voice turn the server's turn list names the operator turn: that id is what a
      // correction replaces (the POST response carries no turn id).
      ai.onRefetch = () => _detail(
        turns: [
          AiConversationTurn(
            turnId: 'turn-7',
            role: 'Operator',
            text: 'Ho cambiato il filtro',
            source: AiTurnSource.voice,
            at: DateTime.utc(2026, 10, 20, 9),
          ),
        ],
      );
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _recordOnce(tester);

      await tester.tap(find.text('Correggi'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('correction-field')), 'Ho cambiato il filtro olio');
      await tester.tap(find.text('Invia correzione'));
      await tester.pumpAndSettle();

      expect(ai.posted, hasLength(2));
      final c = ai.posted[1];
      expect(c.replacesTurnId, 'turn-7');
      expect(c.text, 'Ho cambiato il filtro olio');
      expect(c.rawTranscript, 'Ho cambiato il filtro', reason: 'the unedited STT output is kept');
      expect(c.audioRef, 'audio-1');
      expect(c.key, isNot(ai.posted[0].key), reason: 'a correction is a new turn: its own key');
      await _unmount(tester);
    });

    testWidgets('Voice_disabled_404_hides_the_mic', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()
        ..uploads.add(
          const AiTranscribeException(
            AiTranscribeError.voiceDisabled,
            'La trascrizione vocale non è attiva per questa azienda.',
          ),
        );
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Registra un aggiornamento vocale'), findsOneWidget);

      await _recordOnce(tester);

      expect(find.byTooltip('Registra un aggiornamento vocale'), findsNothing);
      expect(find.textContaining('registrazione vocale non è attiva'), findsOneWidget);
      // Typing (and on-device dictation) is untouched.
      expect(find.byTooltip('Invia'), findsOneWidget);
      expect(find.text('Riprova invio'), findsNothing, reason: 'retrying cannot help');
      await _unmount(tester);
    });

    testWidgets('the consent gate is shown before the first recording', (tester) async {
      final voice = _FakeVoice()..startResult = RecordingStartResult.consentRequired;
      await tester.pumpWidget(_wrap(_FakeAi(), voice));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pumpAndSettle();

      expect(find.textContaining('l\'audio viene inviato al server di TaskTap'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('turn errors', () {
    testWidgets('Turn_in_progress_retries_with_the_same_key', (tester) async {
      final ai = _FakeAi()
        ..turnScript.addAll([
          const AiConversationException(409, 'in corso', code: 'turn_in_progress'),
          const AiConversationException(409, 'in corso', code: 'turn_in_progress'),
          const AiConversationTurnResult(
            assistantReplyText: 'Fatto.',
            draft: AiCopilotDraftDto(
              workers: [],
              materials: [],
              controlli: [],
              activities: [
                AiDraftActivity(description: 'Cambio filtro', state: AiResolutionState.resolvedBySystem),
              ],
              openItems: [],
            ),
          ),
        ]);
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Cambio filtro');
      await tester.tap(find.byTooltip('Invia'));
      await tester.pumpAndSettle();

      expect(ai.posted, hasLength(3));
      expect(ai.posted.map((p) => p.key).toSet(), hasLength(1));
      expect(find.textContaining('Cambio filtro'), findsWidgets);
      expect(find.text('Fatto.'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Turn_in_progress_gives_up_after_a_bounded_number_of_retries', (tester) async {
      final ai = _FakeAi();
      for (var i = 0; i < 20; i++) {
        ai.turnScript.add(const AiConversationException(409, 'in corso', code: 'turn_in_progress'));
      }
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Cambio filtro');
      await tester.tap(find.byTooltip('Invia'));
      await tester.pumpAndSettle();

      expect(ai.posted.length, lessThanOrEqualTo(8));
      expect(ai.posted.map((p) => p.key).toSet(), hasLength(1));
      expect(find.text('Riprova invio'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Concurrent_update_refetches_then_retries_once', (tester) async {
      final ai = _FakeAi()
        ..turnScript.add(
          const AiConversationException(409, 'cambiata', code: 'concurrent_update'),
        );
      ai.onRefetch = () => _detail(draft: _seededDraft());
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      expect(ai.getCalls, hasLength(1));

      await tester.enterText(find.byType(TextFormField), 'Cambio filtro');
      await tester.tap(find.byTooltip('Invia'));
      await tester.pumpAndSettle();

      expect(ai.posted, hasLength(2));
      expect(ai.posted[1].key, ai.posted[0].key);
      // One refetch because of the 409 (plus, at most, the turn-id lookup after success).
      expect(ai.getCalls.length, greaterThanOrEqualTo(2));
      expect(find.text('Riprova invio'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a second concurrent_update is not retried again', (tester) async {
      final ai = _FakeAi()
        ..turnScript.addAll([
          const AiConversationException(409, 'cambiata', code: 'concurrent_update'),
          const AiConversationException(409, 'cambiata', code: 'concurrent_update'),
        ]);
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Cambio filtro');
      await tester.tap(find.byTooltip('Invia'));
      await tester.pumpAndSettle();

      expect(ai.posted, hasLength(2));
      expect(find.text('Riprova invio'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Quota_exhausted_keeps_draft_and_offers_manual_path', (tester) async {
      final ai = _FakeAi(detail: _detail(draft: _seededDraft()))
        ..turnScript.add(const AiQuotaExhaustedException());
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Cambio filtro');
      await tester.tap(find.byTooltip('Invia'));
      await tester.pumpAndSettle();

      // The draft is still there and readable.
      expect(find.textContaining('Luca Bianchi'), findsOneWidget);
      expect(find.textContaining('Manutenzione compressore'), findsOneWidget);
      // The manual path is offered, and sending more to the AI is not.
      expect(find.text('Continua senza AI'), findsOneWidget);
      expect(find.text('Riprova invio'), findsNothing);

      await tester.tap(find.text('Continua senza AI'));
      await tester.pumpAndSettle();
      expect(find.textContaining('editor:'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a quota refusal when STARTING offers the manual path', (tester) async {
      final ai = _FakeAi(startError: const AiQuotaExhaustedException());
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(find.text('Continua senza AI'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('offline at entry says the draft needs a connection and dictation still works', (
      tester,
    ) async {
      final ai = _FakeAi(
        startError: const AiConversationException(null, 'Nessuna connessione.', offline: true),
      );
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(find.textContaining('richiede la connessione'), findsOneWidget);
      expect(find.textContaining('dettatura'), findsOneWidget);
      expect(find.text('Continua senza AI'), findsOneWidget);
      await _unmount(tester);
    });
  });

  group('lifecycle and open items', () {
    testWidgets('Expiry_within_three_days_shows_warning', (tester) async {
      final ai = _FakeAi(
        detail: _detail(expires: DateTime.now().toUtc().add(const Duration(days: 2))),
      );
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(find.textContaining('scade'), findsOneWidget);
      expect(find.text('Riprendi'), findsOneWidget);
      expect(find.text('Abbandona bozza'), findsOneWidget);

      await tester.tap(find.text('Riprendi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('scade'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Abbandona bozza deletes the session', (tester) async {
      final ai = _FakeAi(
        detail: _detail(expires: DateTime.now().toUtc().add(const Duration(days: 1))),
      );
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abbandona bozza'));
      await tester.pumpAndSettle();

      expect(ai.abandoned, ['sess-new']);
      await _unmount(tester);
    });

    testWidgets('no expiry warning when the draft has plenty of time left', (tester) async {
      await tester.pumpWidget(_wrap(_FakeAi(), _FakeVoice()));
      await tester.pumpAndSettle();
      expect(find.textContaining('scade'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('leaving the screen does NOT delete a live draft', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      await _unmount(tester);
      expect(ai.abandoned, isEmpty, reason: 'the draft is durable: it is resumed, not discarded');
    });

    testWidgets('Held_removed_item_is_rendered', (tester) async {
      final ai = _FakeAi(
        detail: _detail(
          draft: const AiCopilotDraftDto(
            workers: [],
            materials: [],
            controlli: [],
            activities: [],
            openItems: [
              AiCandidateFact(
                field: 'removed.materials.id:abc',
                state: AiResolutionState.conflict,
                conflictOperatorValue: 'Filtro olio',
              ),
              AiCandidateFact(field: 'workers[0].hours', state: AiResolutionState.ambiguous),
            ],
          ),
        ),
      );
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Filtro olio'), findsOneWidget);
      expect(find.textContaining('rimosso'), findsWidgets);
      expect(find.textContaining('2 punti da chiarire'), findsOneWidget);
      // Both block Confirm, mirroring the server.
      final confirm = tester.widget<AppButton>(
        find.widgetWithText(AppButton, 'Conferma e apri il rapportino'),
      );
      expect(confirm.onPressed, isNull);
      await _unmount(tester);
    });
  });

  group('a turn that did not go through (Important 1)', () {
    testWidgets('Next_send_is_blocked_while_a_turn_has_failed', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _failOneTypedTurn(ai, tester);
      expect(ai.posted, hasLength(1));

      await tester.enterText(find.byType(TextFormField), 'Secondo');
      expect(_enabled(tester, 'Invia'), isFalse);
      expect(_enabled(tester, 'Registra un aggiornamento vocale'), isFalse);
      expect(find.text('Riprova invio'), findsOneWidget);
      expect(find.text('Scarta'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Discard_reenables_sending_and_removes_the_bubble', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _failOneTypedTurn(ai, tester);

      await tester.tap(find.text('Scarta'));
      await tester.pumpAndSettle();
      expect(find.text('Primo aggiornamento'), findsNothing);
      expect(find.text('Riprova invio'), findsNothing);

      await _typeAndSend(tester, 'Secondo');
      expect(ai.posted, hasLength(2));
      expect(ai.posted[1].text, 'Secondo');
      await _unmount(tester);
    });

    testWidgets('Discarding_a_failed_voice_turn_deletes_its_recording', (tester) async {
      final ai = _FakeAi()
        ..turnScript.add(const AiConversationException(null, 'Nessuna connessione.', offline: true));
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _recordOnce(tester);
      expect(voice.fakeStore.deleted, isEmpty, reason: 'kept until the turn is accepted');

      await tester.tap(find.text('Scarta'));
      await tester.pumpAndSettle();
      expect(voice.fakeStore.deleted, ['rec-1']);
      await _unmount(tester);
    });

    testWidgets('A_failed_bubble_is_marked_not_sent_until_accepted', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _failOneTypedTurn(ai, tester);
      expect(find.text('Non inviato'), findsOneWidget);

      await tester.tap(find.text('Riprova invio'));
      await tester.pumpAndSettle();
      expect(find.text('Non inviato'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Confirm_is_disabled_while_failed_or_sending', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      // One accepted turn so Confirm is otherwise available.
      await _typeAndSend(tester, 'Uno');
      bool confirmOn() => tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Conferma e apri il rapportino'))
          .onPressed != null;
      expect(confirmOn(), isTrue);

      ai.turnGate = Completer<void>();
      await tester.enterText(find.byType(TextFormField), 'Due');
      await tester.tap(find.byTooltip('Invia'));
      await tester.pump();
      await tester.pump();
      expect(confirmOn(), isFalse, reason: 'a turn is in flight');
      ai.turnGate!.complete();
      await tester.pumpAndSettle();
      expect(confirmOn(), isTrue);

      await _failOneTypedTurn(ai, tester);
      expect(confirmOn(), isFalse, reason: 'a turn has failed');
      await _unmount(tester);
    });

    testWidgets('typed send is blocked while recording', (tester) async {
      await tester.pumpWidget(_wrap(_FakeAi(), _FakeVoice()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pumpAndSettle();
      expect(_enabled(tester, 'Invia'), isFalse);
      await _unmount(tester);
    });
  });

  group('unsent recordings survive (Important 2)', () {
    testWidgets('Pending_recording_is_kept_until_the_turn_is_accepted', (tester) async {
      final ai = _FakeAi()
        ..turnScript.add(const AiConversationException(null, 'Nessuna connessione.', offline: true));
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _recordOnce(tester);
      expect(voice.fakeStore.deleted, isEmpty);

      await tester.tap(find.text('Riprova invio'));
      await tester.pumpAndSettle();
      expect(voice.fakeStore.deleted, ['rec-1'], reason: 'deleted only after the turn is accepted');
      await _unmount(tester);
    });

    test('transcribe keeps the files; upload (legacy) still deletes them', () async {
      final dir = await Directory.systemTemp.createTemp('pending_voice_test');
      addTearDown(() => dir.delete(recursive: true));
      final store = PendingRecordingStore(dir);
      final src = File('${dir.path}/src.m4a')..writeAsBytesSync([1, 2, 3]);
      final c = VoiceCaptureController(
        recorder: _NoRecorder(),
        permissions: _GrantedMic(),
        store: store,
        consentAccepted: () async => true,
        currentUserId: () => 'user-1',
        upload: (f, k) async => const AiTranscription(transcript: 't', audioRef: 'a'),
      );
      final rec = await store.add(src, userId: 'user-1', ticketId: 'tkt-1');
      await c.transcribe(rec);
      expect(rec.file.existsSync(), isTrue);
      await c.upload(rec);
      expect(rec.file.existsSync(), isFalse);
    });

    test('pendingForCurrentUser never returns another user\'s recordings', () async {
      final dir = await Directory.systemTemp.createTemp('pending_voice_test2');
      addTearDown(() => dir.delete(recursive: true));
      final store = PendingRecordingStore(dir);
      await store.add(File('${dir.path}/a.m4a')..writeAsBytesSync([1]), userId: 'user-1', ticketId: 't');
      await store.add(File('${dir.path}/b.m4a')..writeAsBytesSync([1]), userId: 'user-2', ticketId: 't');
      final c = VoiceCaptureController(
        recorder: _NoRecorder(),
        permissions: _GrantedMic(),
        store: store,
        consentAccepted: () async => true,
        currentUserId: () => 'user-1',
        upload: (f, k) async => throw StateError('unused'),
      );
      final mine = await c.pendingForCurrentUser();
      expect(mine.map((r) => r.userId).toSet(), {'user-1'});
    });

    testWidgets('Entering_offers_pending_recordings_of_this_ticket_only', (tester) async {
      final voice = _FakeVoice()
        ..pending = [_rec('a'), _rec('b'), _rec('c', ticketId: 'other-ticket'), _rec('d', ticketId: null)];
      await tester.pumpWidget(_wrap(_FakeAi(), voice));
      await tester.pumpAndSettle();
      expect(find.text('Hai 2 registrazioni non inviate'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('no offer when nothing is pending', (tester) async {
      await tester.pumpWidget(_wrap(_FakeAi(), _FakeVoice()));
      await tester.pumpAndSettle();
      expect(find.textContaining('non inviate'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Sending_pending_recordings_reuses_the_same_keys', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()..pending = [_rec('a'), _rec('b')];
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invia'));
      await tester.pumpAndSettle();

      expect(voice.uploadKeys, ['pk-a', 'pk-b']);
      expect(ai.posted.map((p) => p.key), ['pk-a:turn', 'pk-b:turn']);
      expect(voice.fakeStore.deleted, ['p-a', 'p-b']);
      expect(find.textContaining('non inviate'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Discarding_pending_recordings_deletes_them_after_confirmation', (tester) async {
      final voice = _FakeVoice()..pending = [_rec('a'), _rec('b')];
      await tester.pumpWidget(_wrap(_FakeAi(), voice));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scarta'));
      await tester.pumpAndSettle();
      expect(voice.fakeStore.deleted, isEmpty, reason: 'asks first');
      await tester.tap(find.text('Scarta').last);
      await tester.pumpAndSettle();

      expect(voice.fakeStore.deleted, ['p-a', 'p-b']);
      expect(find.textContaining('non inviate'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Leaving_with_a_failed_turn_asks_for_confirmation', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), pushed: true));
      await _openPushed(tester);
      await _failOneTypedTurn(ai, tester);

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.textContaining('non inviato'), findsWidgets);
      await tester.tap(find.text('Resta qui'));
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsNothing);

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esci comunque'));
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsOneWidget);
      expect(ai.abandoned, isEmpty, reason: 'ticket-bound drafts are durable');
      await _unmount(tester);
    });
  });

  group('sessions without a ticket (Important 3)', () {
    testWidgets('Context_free_session_is_abandoned_on_leave', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), ticketId: null, pushed: true));
      await _openPushed(tester);

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();

      expect(find.text('home-screen'), findsOneWidget);
      expect(ai.abandoned, ['sess-new']);
      await _unmount(tester);
    });

    testWidgets('Ticket_bound_session_is_kept_on_leave', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), pushed: true));
      await _openPushed(tester);

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();

      expect(find.text('home-screen'), findsOneWidget);
      expect(ai.abandoned, isEmpty);
      await _unmount(tester);
    });
  });

  group('folded minors', () {
    testWidgets('a failing DELETE on Abbandona bozza keeps the session and says so', (tester) async {
      final ai = _ThrowingAbandonAi(detail: _detail(expires: DateTime.now().toUtc().add(const Duration(days: 1))));
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbandona bozza'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Non sono riuscito'), findsOneWidget);
      // Still usable: a second attempt reaches the server again.
      await tester.tap(find.text('Abbandona bozza'));
      await tester.pumpAndSettle();
      expect(ai.abandonAttempts, 2);
      await _unmount(tester);
    });

    test('a non-string 409 code does not throw a TypeError', () async {
      final dio = Dio();
      dio.httpClientAdapter = _StubAdapter(409, '{"code": 5, "error": {"x": 1}}');
      await expectLater(
        () => AiApiClient(dio).postTurn('s', text: 't', idempotencyKey: 'k'),
        throwsA(isA<AiConversationException>().having((e) => e.code, 'code', isNull)),
      );
    });
  });

  group('fix round 2', () {
    testWidgets('Ticketless_leave_says_the_update_is_lost_and_does_not_save_the_recording', (
      tester,
    ) async {
      final ai = _FakeAi();
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice, ticketId: null, pushed: true));
      await _openPushed(tester);
      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.textContaining('andrà perso'), findsOneWidget);
      expect(find.textContaining('riproporremo'), findsNothing);
      expect(find.textContaining('potrai inviarla'), findsNothing);
      await tester.tap(find.text('Esci comunque'));
      await tester.pumpAndSettle();

      expect(find.text('home-screen'), findsOneWidget);
      expect(voice.cancelCalls, 1, reason: 'the microphone is released and nothing is saved');
      expect(voice.stopCalls, 0, reason: 'a recording that can never be offered again is not saved');
      expect(ai.abandoned, ['sess-new']);
      await _unmount(tester);
    });

    testWidgets('Ticket_bound_leave_while_recording_saves_it_and_says_so', (tester) async {
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(_FakeAi(), voice, pushed: true));
      await _openPushed(tester);
      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      expect(find.textContaining('riproporremo'), findsOneWidget);
      await tester.tap(find.text('Esci comunque'));
      await tester.pumpAndSettle();
      expect(voice.stopCalls, 1);
      expect(voice.cancelCalls, 0);
      await _unmount(tester);
    });

    testWidgets('Empty_transcript_of_a_pending_recording_is_removed_with_a_message', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()
        ..pending = [_rec('a')]
        ..uploads.add(const AiTranscription(transcript: '  ', audioRef: 'a-1'));
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invia'));
      await tester.pumpAndSettle();

      expect(ai.posted, isEmpty);
      expect(voice.fakeStore.deleted, ['p-a']);
      expect(find.textContaining('non inviate'), findsNothing);
      expect(find.textContaining('Non ho sentito nulla'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Dispose_while_recording_releases_the_microphone_ticketless', (tester) async {
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(_FakeAi(), voice, ticketId: null));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pumpAndSettle();

      await _unmount(tester);
      expect(voice.cancelCalls, 1);
      expect(voice.isRecording, isFalse);
    });

    testWidgets('Dispose_while_recording_keeps_a_ticket_bound_recording', (tester) async {
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(_FakeAi(), voice));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pumpAndSettle();

      await _unmount(tester);
      expect(voice.stopCalls, 1);
      expect(voice.cancelCalls, 0);
    });

    // A start still in flight when the screen goes away (first-run permission or consent dialog,
    // slow recorder): the controller ends up recording with no screen to release it.
    Future<_FakeVoice> leaveDuringStart(
      WidgetTester tester, {
      String? ticketId,
      bool consent = false,
    }) async {
      final voice = _FakeVoice()..startGate = Completer<void>();
      if (consent) voice.startScript.add(RecordingStartResult.consentRequired);
      await tester.pumpWidget(_wrap(_FakeAi(), voice, ticketId: ticketId));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pump();
      if (consent) {
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accetto'));
        await tester.pump();
        await tester.pump();
      }
      expect(voice.startCalls, consent ? 2 : 1);
      expect(voice.isRecording, isTrue, reason: 'the microphone is on, start() has not returned');

      await _unmount(tester);
      voice.startGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return voice;
    }

    testWidgets('Leaving_during_start_releases_the_microphone_ticketless', (tester) async {
      final voice = await leaveDuringStart(tester, ticketId: null);
      expect(voice.isRecording, isFalse, reason: 'no screen is left to stop it');
      expect(voice.cancelCalls, 1, reason: 'a ticketless recording can never be offered again');
      expect(voice.stopCalls, 0, reason: 'nothing is saved: no file is left behind');
    });

    testWidgets('Leaving_during_start_keeps_a_ticket_bound_recording', (tester) async {
      final voice = await leaveDuringStart(tester, ticketId: 'tkt-1');
      expect(voice.isRecording, isFalse);
      expect(voice.stopCalls, 1, reason: 'stopped and kept: offered on the next entry');
      expect(voice.cancelCalls, 0);
    });

    testWidgets('Leaving_during_the_consent_restart_releases_the_microphone_ticketless', (
      tester,
    ) async {
      final voice = await leaveDuringStart(tester, ticketId: null, consent: true);
      expect(voice.isRecording, isFalse);
      expect(voice.cancelCalls, 1);
      expect(voice.stopCalls, 0);
    });

    testWidgets('Leaving_during_the_consent_restart_keeps_a_ticket_bound_recording', (
      tester,
    ) async {
      final voice = await leaveDuringStart(tester, ticketId: 'tkt-1', consent: true);
      expect(voice.isRecording, isFalse);
      expect(voice.stopCalls, 1);
      expect(voice.cancelCalls, 0);
    });

    testWidgets('after leaving, no double release on dispose', (tester) async {
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(_FakeAi(), voice, ticketId: null, pushed: true));
      await _openPushed(tester);
      await tester.tap(find.byTooltip('Registra un aggiornamento vocale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esci'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Esci comunque'));
      await tester.pumpAndSettle();
      await _unmount(tester);
      expect(voice.cancelCalls, 1);
    });
  });
}
