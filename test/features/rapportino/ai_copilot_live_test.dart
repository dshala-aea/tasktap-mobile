// dart format width=100
// test/features/rapportino/ai_copilot_live_test.dart
//
// Task 11 — the LIVE draft, driven through the two-step wizard (Descrivi → Controlla): resume/start
// from a ticket, voice turns (record -> upload -> turn carrying only its audioRef), the
// 409/429/422 handling around a turn, the banners, unsent recordings, consent and leave behaviour,
// and the live feed into the editor (Task 12).
// A fake AiApiClient and a fake VoiceCaptureController stand in for the network and the microphone.
//
// PORTED to the wizard. The chat pane this file used to drive is gone from lib/, so two tests were
// deleted outright rather than retargeted at a weaker assertion, their subject no longer existing:
//   - 'Correcting_a_voice_turn_posts_replacesTurnId' — correcting a previous turn (Correggi,
//     `replacesTurnId`, the "Invia correzione" dialog) was deleted from the screen; a report the
//     assistant got wrong is redone with "Descrivi di nuovo".
//   - 'Compila and Conferma are disabled while recording' — both actions now live only on Controlla,
//     which cannot be shown while the microphone is on (the mic exists only on Descrivi).
// Per-assertion losses inside surviving tests are marked `// GONE:` at the point they were dropped.

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
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
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:tasktap_mobile/core/location/location_service.dart' show gpsPreferenceProvider;
import 'package:tasktap_mobile/core/widgets/widgets.dart';
import 'package:tasktap_mobile/data/ai/ai_api_client.dart';
import 'package:tasktap_mobile/data/local/app_database.dart';
import 'package:tasktap_mobile/data/sync/sync_service.dart'
    show SyncNotifier, SyncService, appDatabaseProvider, syncProvider;
import 'package:tasktap_mobile/features/rapportino/ai_copilot_screen.dart';
import 'package:tasktap_mobile/features/rapportino/ai_draft_feed.dart';
import 'package:tasktap_mobile/features/rapportino/draft_provenance_badge.dart';
import 'package:tasktap_mobile/presentation/providers/auth_providers.dart';

class _Posted {
  _Posted(this.text, this.source, this.audioRef, this.replacesTurnId, this.key);
  final String text;
  final AiTurnSource source;
  final String? audioRef;
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

  /// `confirmedEdits` of each postTurn, parallel to [posted] (Task 12).
  final List<List<Map<String, dynamic>>?> postedEdits = [];
  final List<String> resumeCalls = [];
  final List<String> startCalls = [];
  final List<String> getCalls = [];
  final List<String> abandoned = [];

  /// Called on every getConversation after the first (so a test can change what a refetch returns).
  AiConversationDetailDto Function()? onRefetch;

  AiQuotaDto quota = const AiQuotaDto(monthlyLimit: 20, used: 1, remaining: 19);
  bool abandonOk = true;

  @override
  Future<AiQuotaDto> getQuota() async => quota;

  @override
  Future<bool> tryAbandonConversation(String sessionId) async {
    if (abandonOk) abandoned.add(sessionId);
    return abandonOk;
  }

  @override
  Future<String?> resumeConversation(String ticketId) async {
    resumeCalls.add(ticketId);
    return abandoned.contains(liveSessionId) ? null : liveSessionId;
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
    posted.add(_Posted(text, source, audioRef, replacesTurnId, idempotencyKey));
    postedEdits.add(confirmedEdits);
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
  Future<AiVoiceCapture> capture(PendingRecording pending) async {
    uploadKeys.add(pending.idempotencyKey);
    final next = uploads.isEmpty
        ? const AiVoiceCapture(audioRef: 'audio-1', durationSeconds: 12)
        : uploads.removeFirst();
    if (next is AiVoiceCapture) return next;
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
      unit: 'pz',
      // Deliberately fractional: the row must print an Italian decimal comma, the same
      // convention Ore already uses a few pixels to its right.
      quantity: 1.5,
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

/// A draft with something on it, so a turn carrying it moves the flow to Controlla and the review
/// screen has a value to show.
AiCopilotDraftDto _reviewableDraft() => const AiCopilotDraftDto(
  workers: [
    AiDraftWorkerRef(
      userId: 'me-1',
      fullName: 'Marco Rossi',
      hours: 3,
      state: AiResolutionState.resolvedBySystem,
      source: AiFactSource.ticketRecord,
    ),
  ],
  materials: [],
  controlli: [],
  activities: [],
  openItems: [],
);

class _NoopSync extends SyncNotifier {
  _NoopSync(AppDatabase db) : super(SyncService(db: db, dio: Dio()), db);
  @override
  Future<void> performSync() async {}
}

Widget _wrap(
  _FakeAi ai,
  _FakeVoice voice, {
  String? ticketId = 'tkt-1',
  bool pushed = false,
  AppDatabase? database,
}) {
  final db = database ?? AppDatabase(NativeDatabase.memory());
  if (database == null) addTearDown(db.close);
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

/// The step-1 microphone orb. It carries no tooltip and no visible label any more — it is a 120 pt
/// disc drawn inside a `GestureDetector` — so its icon is the only stable handle, and that icon
/// flips from the microphone to a stop square while a recording runs.
Finder get _micIdle => find.byIcon(LucideIcons.mic);
Finder get _micRecording => find.byIcon(LucideIcons.square);

/// Is the orb taking taps? The step disables it by handing `_MicOrb` a null callback rather than by
/// replacing the widget, so the gesture detector is where "enabled" lives.
bool _micEnabled(WidgetTester tester) =>
    tester
        .widget<GestureDetector>(
          find.ancestor(of: _micIdle, matching: find.byType(GestureDetector)).first,
        )
        .onTap !=
    null;

/// The one action of step 1: the same `_send` the chat's paper-plane called. Found by key, not by
/// label — the label changes with the state ("Generazione in corso…", "Genera di nuovo il rapporto"
/// once a draft exists) while the action does not.
AppButton _generateButton(WidgetTester tester) =>
    tester.widget<AppButton>(find.byKey(const ValueKey('ai-generate')));

/// Taps the orb to start a recording. Nothing may `pumpAndSettle` again until the recording ends:
/// the orb's halos animate for as long as `recording` is true, so the settle loop would spin until
/// it timed out. Two plain frames are enough for the controller's `start()` and the rebuild.
Future<void> _startRecording(WidgetTester tester) async {
  // The orb may have been scrolled out of view by a previous `_reveal` (the toggle sits below it);
  // a tap on an off-screen widget is delivered to whatever is at that offset instead.
  await _reveal(tester, _micIdle);
  await tester.tap(_micIdle);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// Starts and stops one recording and lets the upload + turn run.
Future<void> _recordOnce(WidgetTester tester) async {
  await _startRecording(tester);
  await tester.tap(_micRecording);
  // Recording is off again, so the halos have stopped and settling is safe.
  await tester.pumpAndSettle();
}

/// The header's back control. It is an icon with a screen-reader label now ("Indietro"), so the
/// chevron glyph is the handle. The fixed pumps let a confirmation dialog finish opening even while
/// a recording keeps the orb pulsing (which rules out `pumpAndSettle`).
Future<void> _tapBack(WidgetTester tester) async {
  await tester.tap(find.byIcon(LucideIcons.chevronLeft));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// Brings [finder] into view, building it first if the list has not reached it yet.
///
/// Two things on step 1 are true at once. Its `ListView` only instantiates the children near the
/// viewport, so a control pushed below the fold by a banner (a used-draft notice, "Continua senza
/// AI") is not in the tree at all — `ensureVisible` needs an element and throws `No element`. And
/// one that *is* built can still have its centre outside the viewport, which makes `tap` derive an
/// offset that hit-tests to the pinned footer instead. Dragging the list the way a thumb would,
/// then ensuring it is fully in view, covers both.
Future<void> _reveal(WidgetTester tester, Finder finder, {bool settle = true}) async {
  if (finder.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      finder,
      find.byType(Scrollable).first,
      const Offset(0, -120),
    );
  }
  if (settle) {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  } else {
    // While a recording is running the orb's halos animate forever, so `pumpAndSettle` would spin
    // until it timed out; a couple of fixed frames let the scroll land instead.
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Taps "Preferisci scrivere?" and reveals the description field.
Future<void> _tapToggleWriting(WidgetTester tester) async {
  final toggle = find.byKey(const ValueKey('ai-toggle-writing'));
  await _reveal(tester, toggle);
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

/// Switches step 1 to the keyboard, types [text] and generates the report. Descrivi is the only
/// screen with an input, so a second update first goes back through "Descrivi di nuovo" — exactly
/// what the technician does.
Future<void> _typeAndGenerate(WidgetTester tester, String text) async {
  if (find.byKey(const ValueKey('ai-describe-again')).evaluate().isNotEmpty) {
    await tester.tap(find.byKey(const ValueKey('ai-describe-again')));
    await tester.pumpAndSettle();
  }
  // Whether the keyboard mode is on is read from the toggle's own label, not from the field being
  // absent: the list builds lazily, so an absent field means "not built yet" just as often as
  // "mode off", and tapping the toggle in the second case would switch it off again. Reveal the
  // toggle first — a banner above the list can leave it unbuilt — and only then read its label.
  final toggle = find.byKey(const ValueKey('ai-toggle-writing'));
  await _reveal(tester, toggle);
  if (find.text('Preferisci scrivere?').evaluate().isNotEmpty) {
    await tester.tap(toggle);
    await tester.pumpAndSettle();
  }
  final field = find.byKey(const ValueKey('ai-description-field'));
  await _reveal(tester, field);
  await tester.enterText(field, text);
  // The footer's button only enables once the parent has heard about the text.
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('ai-generate')));
  await tester.pumpAndSettle();
}

/// Puts the flow on Controlla showing [draft]. Step 2 is only reached through a turn that compiled
/// something, and the screen renders THAT turn's draft — the resumed one has no surface until then —
/// so a test that wants a particular draft on step 2 has to have the server return it from a turn.
Future<void> _compile(WidgetTester tester, _FakeAi ai, AiCopilotDraftDto draft) async {
  ai.turnScript.add(AiConversationTurnResult(assistantReplyText: 'Ok.', draft: draft));
  await _typeAndGenerate(tester, 'Ho finito il lavoro');
}

Future<void> _failOneTypedTurn(_FakeAi ai, WidgetTester tester) async {
  ai.turnScript.add(const AiConversationException(null, 'Nessuna connessione.', offline: true));
  await _typeAndGenerate(tester, 'Primo aggiornamento');
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
      // GONE: the two turn texts and the worker's name. The turns were chat bubbles, and Controlla
      // renders neither them nor the worker lines. What resuming still has to prove is that the
      // draft was adopted and the flow opened on a usable Descrivi screen.
      expect(find.byKey(const ValueKey('ai-toggle-writing')), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('starts a session when none is live', (tester) async {
      final ai = _FakeAi(detail: _detail(draft: _seededDraft()));
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(ai.startCalls, ['tkt-1']);
      // GONE: 'the seeded draft is shown at once'. The draft has no surface before the first
      // compiled turn — Controlla is only reached through one — so entry lands on Descrivi.
      expect(find.textContaining('Descrivi le attività svolte'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Seeded_draft_shows_planned_items_as_proposals', (tester) async {
      final ai = _FakeAi(detail: _detail(draft: _seededDraft()));
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _compile(tester, ai, _seededDraft());

      // A planned value the technician has not confirmed is offered to accept, never drawn as
      // stock already used — the same rule `isUnconfirmedProposal` encodes for the badges.
      // GONE: the chat summary's two 'Pianificato: conferma' badges and their
      // `planned-unconfirmed-row` keys. Controlla renders only the material row (worker lines have
      // no card), and its needsConfirmation state turns the badge into the 'Accetta' action below.
      expect(find.text('Filtro olio'), findsOneWidget);
      expect(find.text('Accetta'), findsOneWidget);
      // Italian decimal comma: the row used to print the raw double ('1.5 pz') while the Ore line
      // right below it already read '1,5 h'.
      expect(find.text('1,5 pz'), findsOneWidget);
      // The ticket's own activity is shown with the 3 h the ticket already had, beside its text.
      expect(find.text('Manutenzione compressore · 3 h'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('coming back to Descrivi over an existing draft offers to regenerate it', (
      tester,
    ) async {
      final ai = _FakeAi(detail: _detail(draft: _seededDraft()));
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _compile(tester, ai, _seededDraft());

      await tester.tap(find.byKey(const ValueKey('ai-describe-again')));
      await tester.pumpAndSettle();

      // The label says this is a second attempt: the draft is still there, and the screen must not
      // read as a fresh start on top of it.
      expect(find.text('Genera di nuovo il rapporto'), findsOneWidget);
      expect(find.text('Genera il rapporto'), findsNothing);
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
    testWidgets('a recording is uploaded and posted as a Voice turn with no transcript', (
      tester,
    ) async {
      final ai = _FakeAi();
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await _recordOnce(tester);

      expect(voice.uploadKeys, ['rec-key-1']);
      expect(ai.posted, hasLength(1));
      final p = ai.posted.single;
      expect(p.text, isEmpty, reason: 'the words are in the audio, not in a transcript');
      expect(p.source, AiTurnSource.voice);
      expect(p.audioRef, 'audio-1');
      expect(p.replacesTurnId, isNull);
      // GONE: the 'Registrazione vocale · 0:12' bubble. This turn compiled nothing, so the flow
      // stays on Descrivi and is ready for the next description — which is what is asserted here.
      expect(find.text('TOCCA PER INIZIARE'), findsOneWidget);
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
      expect(find.byKey(const ValueKey('ai-retry')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai-retry')));
      await tester.pumpAndSettle();

      expect(ai.posted, hasLength(2));
      expect(ai.posted[1].key, ai.posted[0].key, reason: 'same key: the server replays, never double-applies');
      expect(ai.posted[1].text, ai.posted[0].text);
      expect(ai.posted[1].audioRef, 'audio-1');
      expect(voice.uploadKeys, ['rec-key-1'], reason: 'already uploaded: the audio is not uploaded twice');
      expect(find.byKey(const ValueKey('ai-retry')), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a failed upload keeps the recording and retries it with the SAME key', (
      tester,
    ) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()
        ..uploads.add(
          const AiVoiceUploadException(AiVoiceUploadError.offline, 'Nessuna connessione.'),
        );
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await _recordOnce(tester);
      expect(ai.posted, isEmpty);
      await tester.tap(find.byKey(const ValueKey('ai-retry')));
      await tester.pumpAndSettle();

      expect(voice.uploadKeys, ['rec-key-1', 'rec-key-1']);
      expect(ai.posted, hasLength(1));
      await _unmount(tester);
    });

    // DELETED: 'Correcting_a_voice_turn_posts_replacesTurnId'. The correction path (Correggi, the
    // `correction-field` dialog, `replacesTurnId`) no longer exists in lib/ — a wrong report is
    // redone from Descrivi.

    testWidgets('Voice_disabled_404_says_so_and_leaves_writing', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()
        ..uploads.add(
          const AiVoiceUploadException(
            AiVoiceUploadError.voiceDisabled,
            'La trascrizione vocale non è attiva per questa azienda.',
          ),
        );
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      expect(_micIdle, findsOneWidget);

      await _recordOnce(tester);

      // The orb is not hidden any more: the screen says voice is off for the company and leaves the
      // description to the keyboard. Retrying cannot help, so no retry is offered…
      expect(find.textContaining('registrazione vocale non è attiva'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-retry')), findsNothing, reason: 'retrying cannot help');
      // …and typing (and on-device dictation) is untouched: the turn still goes through.
      await _typeAndGenerate(tester, 'Ho cambiato il filtro olio');
      expect(ai.posted.single.text, 'Ho cambiato il filtro olio');
      await _unmount(tester);
    });

    testWidgets('the consent gate is shown before the first recording', (tester) async {
      final voice = _FakeVoice()..startResult = RecordingStartResult.consentRequired;
      await tester.pumpWidget(_wrap(_FakeAi(), voice));
      await tester.pumpAndSettle();

      await tester.tap(_micIdle);
      await tester.pumpAndSettle();

      expect(find.textContaining('l\'audio viene inviato al server di TaskTap'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('a denied microphone says so on screen and offers Settings', (tester) async {
      final voice = _FakeVoice()
        ..startResult = RecordingStartResult.permissionPermanentlyDenied;
      await tester.pumpWidget(_wrap(_FakeAi(), voice));
      await tester.pumpAndSettle();

      await _reveal(tester, _micIdle);
      await tester.tap(_micIdle);
      await tester.pumpAndSettle();

      // Once the OS stops asking, a toast is gone before the technician can act on it: the state
      // stays on screen and carries the one action that can undo it.
      expect(find.textContaining('serve il microfono'), findsOneWidget);
      expect(find.text('Apri impostazioni'), findsOneWidget);
      expect(find.byKey(const ValueKey('mic-open-settings')), findsOneWidget);
      // Writing is untouched — the banner says so and the toggle is still there.
      expect(find.byKey(const ValueKey('ai-toggle-writing')), findsOneWidget);
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

      await _typeAndGenerate(tester, 'Cambio filtro');

      expect(ai.posted, hasLength(3));
      expect(ai.posted.map((p) => p.key).toSet(), hasLength(1));
      // The compiled activity is on Controlla: the retried turn landed and its draft is shown.
      expect(find.textContaining('Cambio filtro'), findsWidgets);
      // GONE: the assistant's 'Fatto.' reply — a chat bubble the wizard never renders.
      await _unmount(tester);
    });

    testWidgets('Turn_in_progress_gives_up_after_a_bounded_number_of_retries', (tester) async {
      final ai = _FakeAi();
      for (var i = 0; i < 20; i++) {
        ai.turnScript.add(const AiConversationException(409, 'in corso', code: 'turn_in_progress'));
      }
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      await _typeAndGenerate(tester, 'Cambio filtro');

      expect(ai.posted.length, lessThanOrEqualTo(8));
      expect(ai.posted.map((p) => p.key).toSet(), hasLength(1));
      expect(find.byKey(const ValueKey('ai-retry')), findsOneWidget);
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

      await _typeAndGenerate(tester, 'Cambio filtro');

      expect(ai.posted, hasLength(2));
      expect(ai.posted[1].key, ai.posted[0].key);
      // One refetch because of the 409 (plus, at most, the turn-id lookup after success).
      expect(ai.getCalls.length, greaterThanOrEqualTo(2));
      expect(find.byKey(const ValueKey('ai-retry')), findsNothing);
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

      await _typeAndGenerate(tester, 'Cambio filtro');

      expect(ai.posted, hasLength(2));
      expect(find.byKey(const ValueKey('ai-retry')), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Quota_exhausted_keeps_draft_and_offers_manual_path', (tester) async {
      final ai = _FakeAi(detail: _detail(draft: _seededDraft()))
        ..turnScript.add(const AiQuotaExhaustedException());
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      await _typeAndGenerate(tester, 'Cambio filtro');

      // GONE: 'the draft is still there and readable' (the worker's name and the activity text).
      // The refused turn leaves the flow on Descrivi, and Controlla — the only screen that renders
      // the draft — is not shown there. The coverage that remains is the manual path below.
      // The manual path is offered, and sending more to the AI is not.
      expect(find.text('Continua senza AI'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-retry')), findsNothing);
      // The refusal banner above the field pushes it below the fold; reveal it before typing.
      await _reveal(tester, find.byKey(const ValueKey('ai-description-field')));
      await tester.enterText(find.byKey(const ValueKey('ai-description-field')), 'Ancora');
      await tester.pump();
      expect(
        _generateButton(tester).onPressed,
        isNull,
        reason: 'no credits: the only way forward is the manual report',
      );

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
      // Pushed, so the back control really leaves: on the initial route there is nowhere to pop to
      // and the assertion below would hold whether or not the screen released anything.
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), pushed: true));
      await _openPushed(tester);
      await _tapBack(tester);
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsOneWidget);
      await _unmount(tester);
      expect(ai.abandoned, isEmpty, reason: 'the draft is durable: it is resumed, not discarded');
    });

    testWidgets('Held_removed_item_is_rendered', (tester) async {
      final ai = _FakeAi(detail: _detail(draft: AiCopilotDraftDto.empty));
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _compile(
        tester,
        ai,
        const AiCopilotDraftDto(
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
      );

      expect(find.textContaining('Filtro olio'), findsOneWidget);
      expect(find.textContaining('rimosso'), findsWidgets);
      // GONE: the '2 punti da chiarire' count — Controlla has no count line. What it does say is
      // that the open items block the confirm, which is the fact that count was standing for.
      expect(find.text('DA CHIARIRE PRIMA DI CONFERMARE'), findsOneWidget);
      // Both block Confirm, mirroring the server.
      final confirm = tester.widget<AppButton>(find.widgetWithText(AppButton, 'Conferma'));
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

      // The failure banner above the field pushes it below the fold; reveal it before typing.
      await _reveal(tester, find.byKey(const ValueKey('ai-description-field')));
      await tester.enterText(find.byKey(const ValueKey('ai-description-field')), 'Secondo');
      await tester.pump();
      // The unsent turn is the footer's one action, so the next send is not merely disabled — it is
      // not offered at all until the turn goes through or is discarded.
      expect(find.byKey(const ValueKey('ai-generate')), findsNothing);
      expect(tester.widget<AppButton>(find.byKey(const ValueKey('ai-retry'))).onPressed, isNotNull);
      // GONE: 'the microphone is disabled too'. `AiDescribeStep` receives only the 404
      // `voiceDisabled` flag; a failed turn does not stop the orb taking taps.
      expect(find.text('Scarta'), findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('Discard_reenables_sending', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _failOneTypedTurn(ai, tester);

      await tester.tap(find.text('Scarta'));
      await tester.pumpAndSettle();
      // GONE: 'the failed bubble is gone' — there is no bubble, so its absence would prove nothing.
      expect(find.byKey(const ValueKey('ai-retry')), findsNothing);

      await _typeAndGenerate(tester, 'Secondo');
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

    testWidgets('A_failed_update_is_marked_not_sent_until_accepted', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _failOneTypedTurn(ai, tester);
      // The failed bubble's 'Non inviato' badge is now the banner's own sentence.
      expect(find.textContaining('L\'aggiornamento non è stato inviato'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('ai-retry')));
      await tester.pumpAndSettle();
      expect(find.textContaining('L\'aggiornamento non è stato inviato'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Confirm_is_disabled_while_failed_or_sending', (tester) async {
      final ai = _FakeAi(detail: _detail(draft: _reviewableDraft()));
      // Controlla has no input, so the only way to have a turn in flight while it is up is the
      // pending-recordings banner: the footer's guard is what this asserts.
      final voice = _FakeVoice()..pending = [_rec('a')];
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _compile(tester, ai, _reviewableDraft());
      bool confirmOn() => tester
          .widget<AppButton>(find.widgetWithText(AppButton, 'Conferma'))
          .onPressed !=
          null;
      expect(confirmOn(), isTrue);

      ai.turnGate = Completer<void>();
      ai.turnScript
          .add(const AiConversationException(null, 'Nessuna connessione.', offline: true));
      await tester.tap(find.text('Invia'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(confirmOn(), isFalse, reason: 'a turn is in flight');

      ai.turnGate!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-retry')), findsOneWidget);
      expect(confirmOn(), isFalse, reason: 'a turn has failed');

      // Retrying the failed turn clears it, and Conferma comes back.
      await tester.tap(find.byKey(const ValueKey('ai-retry')));
      await tester.pumpAndSettle();
      expect(confirmOn(), isTrue);
      await _unmount(tester);
    });

    testWidgets('typed send is blocked while recording', (tester) async {
      await tester.pumpWidget(_wrap(_FakeAi(), _FakeVoice()));
      await tester.pumpAndSettle();
      await _tapToggleWriting(tester);
      await tester.enterText(find.byKey(const ValueKey('ai-description-field')), 'Ho iniziato');
      await tester.pump();
      // Generation is available up to the moment the microphone opens, so the assertion below is
      // about the recording and not about an empty field.
      expect(_generateButton(tester).onPressed, isNotNull);

      await _startRecording(tester);

      expect(_generateButton(tester).onPressed, isNull);
      // Revealing the orb scrolled the list back up, so the toggle may no longer be built; bring it
      // back with fixed pumps, since the running recording never settles.
      final toggle = find.byKey(const ValueKey('ai-toggle-writing'));
      await _reveal(tester, toggle, settle: false);
      expect(
        tester.widget<TextButton>(toggle).onPressed,
        isNull,
        reason: 'the description cannot be swapped mid-recording either',
      );
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

      await tester.tap(find.byKey(const ValueKey('ai-retry')));
      await tester.pumpAndSettle();
      expect(voice.fakeStore.deleted, ['rec-1'], reason: 'deleted only after the turn is accepted');
      await _unmount(tester);
    });

    test('capture keeps the files; upload (one-shot) still deletes them', () async {
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
        upload: (f, k) async => const AiVoiceCapture(audioRef: 'a', durationSeconds: 2),
      );
      final rec = await store.add(src, userId: 'user-1', ticketId: 'tkt-1');
      await c.capture(rec);
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

      await _tapBack(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('non inviato'), findsWidgets);
      await tester.tap(find.text('Resta qui'));
      await tester.pumpAndSettle();
      expect(find.text('home-screen'), findsNothing);

      await _tapBack(tester);
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

      await _tapBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('home-screen'), findsOneWidget);
      expect(ai.abandoned, ['sess-new']);
      await _unmount(tester);
    });

    testWidgets('Ticket_bound_session_is_kept_on_leave', (tester) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), pushed: true));
      await _openPushed(tester);

      await _tapBack(tester);
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
      await _startRecording(tester);

      await _tapBack(tester);
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
      await _startRecording(tester);

      await _tapBack(tester);
      expect(find.textContaining('riproporremo'), findsOneWidget);
      await tester.tap(find.text('Esci comunque'));
      await tester.pumpAndSettle();
      expect(voice.stopCalls, 1);
      expect(voice.cancelCalls, 0);
      await _unmount(tester);
    });

    testWidgets('A_pending_recording_is_sent_as_a_voice_turn_even_if_it_holds_no_words', (
      tester,
    ) async {
      // There is no transcript to be empty any more: the recording IS the turn, and the server's
      // model decides what was said (and asks, if nothing was).
      final ai = _FakeAi();
      final voice = _FakeVoice()..pending = [_rec('a')];
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Invia'));
      await tester.pumpAndSettle();

      expect(ai.posted, hasLength(1));
      expect(ai.posted.single.audioRef, 'audio-1');
      expect(ai.posted.single.text, isEmpty);
      expect(voice.fakeStore.deleted, ['p-a'], reason: 'accepted: the local copy goes');
      expect(find.textContaining('Non ho sentito nulla'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Dispose_while_recording_releases_the_microphone_ticketless', (tester) async {
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(_FakeAi(), voice, ticketId: null));
      await tester.pumpAndSettle();
      await _startRecording(tester);

      await _unmount(tester);
      expect(voice.cancelCalls, 1);
      expect(voice.isRecording, isFalse);
    });

    testWidgets('Dispose_while_recording_keeps_a_ticket_bound_recording', (tester) async {
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(_FakeAi(), voice));
      await tester.pumpAndSettle();
      await _startRecording(tester);

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
      await tester.tap(_micIdle);
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
      await _startRecording(tester);
      await _tapBack(tester);
      await tester.tap(find.text('Esci comunque'));
      await tester.pumpAndSettle();
      await _unmount(tester);
      expect(voice.cancelCalls, 1);
    });
  });

  group('live feed into the editor (Task 12)', () {
    AiCopilotDraftDto liveDraft() => const AiCopilotDraftDto(
      workers: [
        AiDraftWorkerRef(
          userId: 'me-1',
          fullName: 'Marco Rossi',
          hours: 3,
          state: AiResolutionState.resolvedBySystem,
          source: AiFactSource.ticketRecord,
        ),
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
      activities: [],
      openItems: [],
    );

    testWidgets('Accetta on a planned entry sends a property-less edits-only request', (
      tester,
    ) async {
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _compile(tester, ai, _seededDraft());

      // One per planned MATERIAL. A planned worker has no inline accept any more: Controlla draws
      // workers only as their total hours, so the material row is the one entry that can be
      // accepted on its own.
      expect(find.text('Accetta'), findsOneWidget, reason: 'one per planned material entry');
      await tester.tap(find.text('Accetta'));
      await tester.pumpAndSettle();

      expect(ai.posted.last.text, '', reason: 'edits-only: no model call, no charge');
      expect(ai.postedEdits.last, [
        {'kind': 'material', 'id': 'm-1', 'remove': false},
      ]);
      await _unmount(tester);
    });

    testWidgets('Modifica writes only the confirmed subset into the editor; a hand edit then rides '
        'in the next turn', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      await _compile(tester, ai, liveDraft());
      ai.turnScript.add(AiConversationTurnResult(assistantReplyText: 'Ok.', draft: liveDraft()));

      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      expect(find.textContaining('editor:'), findsOneWidget);

      final staff = await db.select(db.reportStaffTable).get();
      expect(staff.map((s) => (s.userId, s.hoursWorked)), [('me-1', 3.0)]);
      expect(await db.select(db.reportMateriali).get(), isEmpty, reason: 'planned stays out');

      // The technician corrects the hours in the editor, then comes back and talks.
      await (db.update(db.reportStaffTable)..where((r) => r.id.equals(staff.single.id))).write(
        const ReportStaffTableCompanion(hoursWorked: Value(5)),
      );
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
      // GONE: the "Apri il rapporto di intervento collegato" banner the chat drew after returning from
      // the editor. The wizard has no chat pane to hang it on; what still holds is that Controlla
      // stayed put, with every action available again.
      expect(find.widgetWithText(AppButton, 'Modifica'), findsOneWidget);
      await _typeAndGenerate(tester, 'Ho finito');

      expect(ai.postedEdits.last, [
        {'kind': 'worker', 'id': 'me-1', 'property': 'hours', 'value': 5.0, 'remove': false},
      ]);
      // The turn's draft (3 h again) never overwrites the hand edit.
      final after = await db.select(db.reportStaffTable).get();
      expect(after.single.hoursWorked, 5);
      await _unmount(tester);
    });

    testWidgets('a 400 on a turn carrying hand edits resends the turn without them; the bad edit '
        'is isolated and never sent again', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      await _compile(tester, ai, liveDraft());
      await tester.tap(find.text('Modifica'));
      await tester.pumpAndSettle();
      final staff = await db.select(db.reportStaffTable).get();
      await (db.update(db.reportStaffTable)..where((r) => r.id.equals(staff.single.id))).write(
        const ReportStaffTableCompanion(hoursWorked: Value(5)),
      );
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();

      const refused = AiConversationException(400, 'edit_value_invalid', code: 'edit_value_invalid');
      ai.turnScript
        ..add(refused) // the turn with the edit
        ..add(refused) // the edit alone, edits-only: isolated and dropped
        ..add(AiConversationTurnResult(assistantReplyText: 'Annotato.', draft: liveDraft()));
      await _typeAndGenerate(tester, 'Ho finito');

      const edit = {'kind': 'worker', 'id': 'me-1', 'property': 'hours', 'value': 5.0, 'remove': false};
      expect(ai.posted.map((p) => p.text).toList(), [
        'Ho finito il lavoro', // the turn that compiled the draft on Controlla
        'Ho finito',
        '',
        'Ho finito',
      ]);
      expect(ai.postedEdits, [
        null,
        [edit],
        [edit],
        null,
      ], reason: 'the spoken update goes through without the refused edit');
      // GONE: `find.text('Annotato.')` — the assistant's reply line is not rendered anywhere in the
      // wizard, which shows the compiled draft on Controlla and nothing of the conversation.
      await _typeAndGenerate(tester, 'Altro');
      expect(ai.postedEdits.last, isNull, reason: 'a refused edit never wedges later turns');
      await _unmount(tester);
    });

    testWidgets('Modifica is disabled while a turn is in flight (no editor hydrated under a '
        'pending apply)', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()..pending = [_rec('a')];
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _compile(tester, ai, liveDraft());

      AppButton modifica() =>
          tester.widget<AppButton>(find.widgetWithText(AppButton, 'Modifica'));
      expect(modifica().onPressed, isNotNull);

      // A turn in flight while Controlla is up: the pending-recording banner's "Invia" is the one
      // send reachable from this screen.
      ai.turnGate = Completer<void>();
      await tester.tap(find.text('Invia'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(modifica().onPressed, isNull, reason: 'a turn is in flight');

      ai.turnGate!.complete();
      await tester.pumpAndSettle();
      expect(modifica().onPressed, isNotNull);
      await _unmount(tester);
    });

    testWidgets('Held_removal_can_be_re_added_or_kept_removed (copilot actions)', (tester) async {
      const held = AiCandidateFact(
        field: 'removed.materials.id:m-1',
        state: AiResolutionState.conflict,
        conflictOperatorValue: 'Filtro olio',
      );
      const draftWithHeld = AiCopilotDraftDto(
        workers: [],
        materials: [],
        controlli: [],
        activities: [],
        openItems: [held],
      );
      final ai = _FakeAi();
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _compile(tester, ai, draftWithHeld);

      expect(find.text('Reinserisci'), findsOneWidget);
      await tester.tap(find.text('Mantieni rimosso'));
      await tester.pumpAndSettle();
      expect(ai.posted.last.text, '');
      expect(ai.postedEdits.last, [
        {'kind': 'material', 'id': 'm-1', 'remove': true},
      ]);
      await _unmount(tester);
    });
  });

  group('final review fixes (mobile)', () {
    const sess = 'sess-new';
    const reportId = 'rep-linked';

    AiCopilotDraftDto liveDraft({bool withCable = false}) => AiCopilotDraftDto(
      workers: const [
        AiDraftWorkerRef(
          userId: 'me-1',
          fullName: 'Marco Rossi',
          hours: 3,
          state: AiResolutionState.resolvedBySystem,
          source: AiFactSource.ticketRecord,
        ),
      ],
      materials: [
        if (withCable)
          const AiDraftMaterialUsage(
            materialId: 'm-2',
            name: 'Cavo',
            quantity: 2,
            state: AiResolutionState.operatorConfirmed,
            source: AiFactSource.operatorInput,
          ),
      ],
      controlli: const [],
      activities: const [],
      openItems: const [],
    );

    Future<AppDatabase> dbWithLinkedReport({String submission = 'draft', String stato = 'Bozza'}) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.draftReports).insert(
        DraftReportsCompanion.insert(
          id: reportId,
          tenantId: 'ten-1',
          createdAt: DateTime.utc(2026, 10, 20),
          title: 'Rapportino',
          insertedUserId: 'internal-guid-2',
          locationId: 'loc-1',
          stato: Value(stato),
          submissionState: Value(submission),
        ),
      );
      await AiDraftFeedStore().link(sessionId: sess, reportId: reportId);
      return db;
    }

    AppButton button(WidgetTester tester, String label) => tester.widget<AppButton>(
      find.ancestor(of: find.text(label), matching: find.byType(AppButton)),
    );

    // ── MUST FIX 5 ─────────────────────────────────────────────────────────────
    // 'Compila and Conferma are disabled while recording' was deleted: both actions live only on
    // Controlla, and Controlla cannot be reached while the microphone is on (the mic is on Descrivi
    // and generating is refused while recording). The behaviour has no reachable state to assert.

    // ── SHOULD FIX (a): backgrounding ──────────────────────────────────────────
    testWidgets('backgrounding while recording stops and keeps a ticket-bound recording', (
      tester,
    ) async {
      final ai = _FakeAi();
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _startRecording(tester);

      for (final st in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pumpAndSettle();
      expect(voice.stopCalls, 1);
      expect(voice.cancelCalls, 0);
      expect(voice.uploadKeys, isEmpty, reason: 'nothing is uploaded behind the technician');

      for (final st in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pumpAndSettle();
      expect(find.textContaining('hai lasciato l\'app'), findsWidgets);
      await _unmount(tester);
    });

    testWidgets('backgrounding while recording cancels a ticketless recording', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice, ticketId: null));
      await tester.pumpAndSettle();
      await _startRecording(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(voice.cancelCalls, 1);
      expect(voice.stopCalls, 0);
      await _unmount(tester);
    });

    // ── MUST FIX 4: credits ────────────────────────────────────────────────────
    testWidgets('an exhausted balance never locks a live session (typing and mic stay on)', (
      tester,
    ) async {
      final ai = _FakeAi()
        ..quota = const AiQuotaDto(monthlyLimit: 20, used: 20, remaining: 0);
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Crediti AI esauriti: puoi finire questa bozza'), findsOneWidget);
      expect(_micEnabled(tester), isTrue);
      await _typeAndGenerate(tester, 'Ho finito');
      expect(ai.posted.single.text, 'Ho finito');
      await _unmount(tester);
    });

    testWidgets('an upload refused for credits says the microphone is unavailable; typed turns '
        'continue', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()..uploads.add(const AiQuotaExhaustedException());
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();

      await _recordOnce(tester);

      expect(find.textContaining('registrazione vocale non è disponibile'), findsOneWidget);
      expect(find.text('Continua senza AI'), findsNothing, reason: 'the session is not blocked');
      // The orb goes dim and stops taking taps: AI credits are gone for the month, so a second tap
      // could only earn the same refusal. A *failed* turn deliberately leaves it enabled — the
      // network comes back and speaking again is a legitimate retry.
      expect(_micEnabled(tester), isFalse);
      // GONE: the draft-readable assertion looked for the worker names ("Luca"/"Marco"); Controlla
      // renders workers as their total hours, never by name.
      await _typeAndGenerate(tester, 'Scrivo a mano');
      expect(ai.posted.last.text, 'Scrivo a mano');
      await _unmount(tester);
    });

    // ── SHOULD FIX (d): voice disabled deletes the file ────────────────────────
    testWidgets('a 404 on the capture upload deletes the pending file instead of re-offering it', (tester) async {
      final ai = _FakeAi();
      final voice = _FakeVoice()
        ..uploads.add(
          const AiVoiceUploadException(AiVoiceUploadError.voiceDisabled, 'La registrazione non è attiva.'),
        );
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _recordOnce(tester);
      expect(voice.fakeStore.deleted, ['rec-1']);
      await _unmount(tester);
    });

    // ── SHOULD FIX (c): long text ──────────────────────────────────────────────
    testWidgets('a 422 text-too-long offers to shorten and re-sends the shortened text', (
      tester,
    ) async {
      final ai = _FakeAi()
        ..turnScript.add(
          const AiConversationException(
            422,
            'Il testo è troppo lungo',
            code: AiConversationException.textTooLongCode,
          ),
        );
      await tester.pumpWidget(_wrap(ai, _FakeVoice()));
      await tester.pumpAndSettle();
      await _typeAndGenerate(tester, 'Testo lunghissimo');

      expect(find.text('Accorcia il testo'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-retry')), findsOneWidget, reason: 'the same footer action, relabelled');
      await tester.tap(find.text('Accorcia il testo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('correction-field')), 'Testo corto');
      await tester.tap(find.text('Invia'));
      await tester.pumpAndSettle();

      expect(ai.posted.map((p) => p.text).toList(), ['Testo lunghissimo', 'Testo corto']);
      expect(find.text('Accorcia il testo'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a transcript over the server cap is never posted and can be shortened', (
      tester,
    ) async {
      final ai = _FakeAi();
      final voice = _FakeVoice();
      await tester.pumpWidget(_wrap(ai, voice));
      await tester.pumpAndSettle();
      await _typeAndGenerate(tester, 'a' * (maxTurnCharacters + 1));

      expect(ai.posted, isEmpty, reason: 'refused locally, no doomed request');
      expect(find.text('Accorcia il testo'), findsOneWidget);
      await tester.tap(find.text('Accorcia il testo'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('correction-field')), 'Riassunto');
      await tester.tap(find.text('Invia'));
      await tester.pumpAndSettle();
      expect(ai.posted.single.text, 'Riassunto');
      await _unmount(tester);
    });

    // ── MUST FIX 1: refused edits-only never jams ──────────────────────────────
    testWidgets('a 404 on an Accetta unlinks the feed and tells the technician', (tester) async {
      final db = await dbWithLinkedReport();
      final ai = _FakeAi(liveSessionId: sess);
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      await _compile(tester, ai, _seededDraft());
      // GONE: the "Apri il rapporto di intervento collegato" banner — the wizard gives the link no
      // surface, so the feed's presence is asserted through its effect below (it is released).
      ai.turnScript.add(const AiConversationException(404, 'gone'));

      // Only the planned material carries an inline accept on Controlla.
      await tester.tap(find.text('Accetta'));
      await tester.pumpAndSettle();

      expect(find.textContaining('non esiste più sul server'), findsOneWidget);
      expect(
        find.widgetWithText(AppButton, 'Modifica'),
        findsOneWidget,
        reason: 'the flow is still usable and the feed was released',
      );
      expect(await AiDraftFeedStore().sessionForReport(reportId), isNull);
      await _unmount(tester);
    });

    // ── MUST FIX 2 + 3: a used report is never rewritten or re-seeded ──────────
    for (final submission in ['readyToSubmit', 'failed', 'submitted', 'uploadingMedia']) {
      testWidgets('resuming a draft whose report is $submission blocks Modifica and Conferma', (
        tester,
      ) async {
        final db = await dbWithLinkedReport(submission: submission);
        final ai = _FakeAi(liveSessionId: sess);
        await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
        await tester.pumpAndSettle();
        // Controlla is the only screen with these two actions, and it is only reached through a
        // turn: the block has to hold there.
        await _compile(tester, ai, liveDraft(withCable: true));

        expect(
          find.textContaining('già stata usata per un rapporto di intervento inviato'),
          findsOneWidget,
        );
        expect(button(tester, 'Modifica').onPressed, isNull);
        expect(button(tester, 'Conferma').onPressed, isNull);
        expect(db.select(db.reportMateriali).get(), completion(isEmpty), reason: 'not rewritten');
        // The AI draft itself stays readable.
        expect(find.textContaining('Cavo'), findsWidgets);
        await _unmount(tester);
      });
    }

    testWidgets('Abbandona e ricomincia deletes the used session and starts a fresh one', (
      tester,
    ) async {
      final db = await dbWithLinkedReport(submission: 'submitted');
      final ai = _FakeAi(liveSessionId: sess);
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      await _compile(tester, ai, liveDraft(withCable: true));

      await tester.tap(find.text('Abbandona e ricomincia'));
      await tester.pumpAndSettle();

      expect(ai.abandoned, [sess]);
      expect(ai.startCalls, hasLength(1));
      expect(find.textContaining('già stata usata'), findsNothing);
      expect(button(tester, 'Modifica').onPressed, isNotNull);
      await _unmount(tester);
    });

    testWidgets('re-entering after a refusal, without abandoning, still shows the used banner and '
        'blocks Modifica and Conferma', (tester) async {
      final db = await dbWithLinkedReport(submission: 'submitted');
      final ai = _FakeAi(liveSessionId: sess);
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('già stata usata per un rapporto di intervento inviato'),
        findsOneWidget,
      );
      await _unmount(tester); // back, WITHOUT 'Abbandona e ricomincia'

      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      await _compile(tester, ai, liveDraft(withCable: true));

      expect(
        find.textContaining('già stata usata per un rapporto di intervento inviato'),
        findsOneWidget,
      );
      expect(button(tester, 'Modifica').onPressed, isNull);
      expect(button(tester, 'Conferma').onPressed, isNull);
      expect(await db.select(db.reportMateriali).get(), isEmpty);
      expect(await db.select(db.reportStaffTable).get(), isEmpty);
      expect(await db.select(db.draftReports).get(), hasLength(1), reason: 'no new report');
      expect(await AiDraftFeedStore().sessionForReport(reportId), sess, reason: 'the used link stays');
      await _unmount(tester);
    });

    testWidgets('Abbandona e ricomincia clears the used state: the fresh session is unlinked', (
      tester,
    ) async {
      final db = await dbWithLinkedReport(submission: 'submitted');
      final ai = _FakeAi(liveSessionId: sess, detail: _detail(draft: liveDraft(withCable: true)));
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abbandona e ricomincia'));
      await tester.pumpAndSettle();

      expect(await AiDraftFeedStore().sessionForReport(reportId), isNull);
      expect(await AiDraftFeedStore().load(sess), isNull);
      expect(await AiDraftFeedStore().load('sess-new'), isNull);
      expect(find.textContaining('già stata usata'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Abbandona e ricomincia is disabled while recording', (tester) async {
      final db = await dbWithLinkedReport(submission: 'submitted');
      final ai = _FakeAi(liveSessionId: sess, detail: _detail(draft: liveDraft(withCable: true)));
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      await _startRecording(tester);

      final restart = tester.widget<TextButton>(find.byKey(const ValueKey('abandon-and-restart')));
      expect(restart.onPressed, isNull);
      await _unmount(tester);
    });

    testWidgets('a double tap on Abbandona e ricomincia starts exactly one session', (tester) async {
      final db = await dbWithLinkedReport(submission: 'submitted');
      final ai = _FakeAi(liveSessionId: sess, detail: _detail(draft: liveDraft(withCable: true)));
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();

      final finder = find.byKey(const ValueKey('abandon-and-restart'));
      await tester.tap(finder);
      await tester.tap(finder, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(ai.abandoned, [sess]);
      expect(ai.startCalls, hasLength(1));
      await _unmount(tester);
    });

    testWidgets('a report submitted while the copilot is open refuses the next turn apply and '
        'the open-in-editor path creates no new report', (tester) async {
      final db = await dbWithLinkedReport();
      final ai = _FakeAi(liveSessionId: sess);
      ai.turnScript.add(
        AiConversationTurnResult(
          assistantReplyText: 'Aggiunto il cavo.',
          draft: liveDraft(withCable: true),
        ),
      );
      await tester.pumpWidget(_wrap(ai, _FakeVoice(), database: db));
      await tester.pumpAndSettle();
      // Signed and queued on weak signal from the editor, then back to the copilot.
      await (db.update(db.draftReports)..where((r) => r.id.equals(reportId))).write(
        const DraftReportsCompanion(submissionState: Value('readyToSubmit')),
      );

      await _typeAndGenerate(tester, 'ho usato anche 2 m di cavo');

      expect(await db.select(db.reportMateriali).get(), isEmpty, reason: 'the queued report is untouched');
      expect(
        find.textContaining('già stata usata per un rapporto di intervento inviato'),
        findsOneWidget,
      );
      expect(find.textContaining('Cavo'), findsWidgets, reason: 'the draft stays readable');
      expect(await db.select(db.draftReports).get(), hasLength(1), reason: 'no second report');
      await _unmount(tester);
    });
  });
}
