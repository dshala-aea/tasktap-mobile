// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/audio/pending_recording_store.dart';
import '../../core/audio/voice_capture_controller.dart';
import '../../core/audio/voice_capture_provider.dart';
import '../../core/audio/voice_consent.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/dictation/dictate_button.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai/ai_api_client.dart';
import '../../data/local/app_database.dart' show Ticket;
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../presentation/providers/report_editor_providers.dart'
    show draftReportRepositoryProvider;
import 'ai_draft_feed.dart';
import 'apply_confirmed_draft.dart';
import 'create_draft.dart';
import 'draft_provenance_badge.dart';

// ══════════════════════════════════════════════════════════════════════════════
// AiCopilotScreen — the multi-turn AI copilot (distinct from step_dettagli.dart's
// single-shot "Genera con AI" action).
//
// The operator talks (typed, or dictated on-device per ADR-0017 — text only, never uploaded
// audio), the assistant calls TaskTap tools to verify people/hours/materials/checklist items
// against real data, and a structured draft builds up as the conversation progresses. Confermare
// is blocked while any open item is Ambiguous/Conflict, mirroring the backend's own gate. It calls
// POST .../confirm (idempotency-keyed), which RESOLVES the draft and persists nothing (spec §5.4):
// the phone then applies the response to its own Drift draft (`applyConfirmedDraft`, spec §5.5)
// and opens the ordinary editor on it. Nothing is created server-side, so there is no server object
// to download and no import to retry.
//
// LIVE DRAFT (AI report builder MVP). Entered from a ticket, the screen RESUMES the technician's
// durable server-side draft for that ticket (GET ?ticketId=) or starts one (POST), then shows the
// seeded draft at once with a provenance badge per value. Voice: the mic records, the server
// transcribes (`VoiceCaptureController` + `AiApiClient.transcribe`), the transcript appears next to
// the draft and is posted as a `Voice` turn with a per-recording Idempotency-Key that is reused on
// every retry. On-device dictation (DictateButton, ADR-0017) stays as before and is the no-signal
// fallback. Leaving the screen never deletes the draft: it is durable and is resumed; only
// "Abbandona bozza" deletes it.
// ══════════════════════════════════════════════════════════════════════════════


class _ChatMessage {
  _ChatMessage({
    required this.isOperator,
    required this.text,
    this.source = AiTurnSource.typed,
    this.turnId,
    this.audioRef,
    this.rawTranscript,
  });
  final bool isOperator;
  final String text;
  final AiTurnSource source;

  /// The server's id of this operator turn, once known (the POST response carries none, so it is
  /// read back from the conversation). A correction replaces this turn.
  String? turnId;
  final String? audioRef;
  final String? rawTranscript;

  /// Replaced by a later correction: shown struck through.
  bool superseded = false;

  /// False for an operator message the server has not accepted yet (in flight, failed, or held
  /// back): rendered as NOT sent so it never looks delivered.
  bool accepted = true;
}

/// One turn on its way to the server, kept whole until it succeeds so a retry re-sends exactly the
/// same thing under exactly the same Idempotency-Key.
class _Outgoing {
  _Outgoing({
    required this.key,
    this.recording,
    this.voice,
    this.text,
    this.source = AiTurnSource.typed,
    this.audioRef,
    this.rawTranscript,
    this.replacesTurnId,
    this.supersedes,
  });

  /// Generated once. For a recording it derives from the recording's own persisted key, so it is
  /// stable across restarts of the upload.
  final String key;

  /// Set while the audio still has to be transcribed; [text] is null until then.
  final PendingRecording? recording;

  /// The recorder that produced [recording]; used for its (retried) upload.
  final VoiceCaptureController? voice;
  String? text;
  AiTurnSource source;
  String? audioRef;
  String? rawTranscript;
  final String? replacesTurnId;

  /// The message a correction replaces (to strike it through once the correction lands).
  final _ChatMessage? supersedes;
  _ChatMessage? message;

  /// The technician's hand edits from the editor that ride in this turn (Task 12). Frozen on the
  /// first attempt so every retry sends the same body under the same key; acknowledged only once
  /// the turn is accepted.
  List<AiConfirmedEdit>? edits;
}

// A turn can legitimately take up to the server's ~45s wall-clock ceiling — a single static
// "elaborando" label for that whole span reads as frozen, not working. Purely a client-side
// staged message swap + spinner, no backend streaming involved.
const _thinkingStageMessages = [
  'Il copilot sta elaborando…',
  'Sto verificando i dati con TaskTap…',
  'Quasi fatto…',
];
const _thinkingStageDelays = [Duration.zero, Duration(seconds: 4), Duration(seconds: 12)];

/// How many times a 409 `turn_in_progress` is retried (same key) before the technician is asked.
const _maxTurnInProgressRetries = 5;

/// A draft with less than this left before deletion shows the expiry warning.
const _expiryWarningWindow = Duration(days: 3);

class AiCopilotScreen extends ConsumerStatefulWidget {
  const AiCopilotScreen({
    super.key,
    this.ticketId,
    this.cantiereId,
    @visibleForTesting this.turnRetryDelay = const Duration(seconds: 2),
  });

  final String? ticketId;
  final String? cantiereId;

  /// Pause before re-sending a turn the server reports as still in progress.
  final Duration turnRetryDelay;

  @override
  ConsumerState<AiCopilotScreen> createState() => _AiCopilotScreenState();
}

class _AiCopilotScreenState extends ConsumerState<AiCopilotScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_ChatMessage>[];

  String? _sessionId;
  AiCopilotDraftDto _draft = AiCopilotDraftDto.empty;
  bool _starting = true;
  bool _sending = false;
  bool _confirming = false;

  String? _startError;
  String? _confirmKey;
  int _thinkingStage = 0;
  final _thinkingTimers = <Timer>[];

  DateTime? _expiresAt;
  bool _expiryDismissed = false;

  /// The server said voice capture is off for this company (404 on transcribe): no mic.
  bool _voiceDisabled = false;
  bool _recording = false;
  StreamSubscription<PendingRecording>? _interruptSub;
  bool _stopping = false;
  VoiceCaptureController? _voiceCtl;

  /// Recordings of this user and ticket the phone still holds (not yet accepted as a turn).
  List<PendingRecording> _pendingRecs = [];

  /// Set once the technician decided to leave (or the draft was abandoned): no more confirmation.
  bool _forceLeave = false;

  /// The turn that has not gone through yet (offered as "Riprova invio"), and why.
  _Outgoing? _failed;
  String? _failureMessage;

  /// AI is unusable for this draft (no credits, caps reached): the draft stays readable and the
  /// technician is offered the manual path.
  String? _aiBlockedMessage;

  /// The local rapportino this session feeds (Task 12), once the technician opened it.
  String? _linkedReportId;

  /// An edits-only request (accept a proposal, settle a held removal) is in flight.
  bool _editing = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _releaseMicrophone();
    _cancelThinkingTimers();
    _interruptSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _cancelThinkingTimers() {
    for (final timer in _thinkingTimers) {
      timer.cancel();
    }
    _thinkingTimers.clear();
  }

  void _startThinkingTimers() {
    _cancelThinkingTimers();
    _thinkingStage = 0;
    for (var i = 1; i < _thinkingStageDelays.length; i++) {
      _thinkingTimers.add(
        Timer(_thinkingStageDelays[i], () {
          if (!mounted) return;
          setState(() => _thinkingStage = i);
        }),
      );
    }
  }

  // ── entry: resume or start ────────────────────────────────────────────────────

  /// From a ticket: the live session for (user, ticket) if the server has one, else a new one.
  /// Either way the draft (seeded from the ticket on a new session) and the earlier turns are read
  /// back with GET so the technician sees them immediately.
  Future<void> _start() async {
    setState(() {
      _starting = true;
      _startError = null;
    });
    final client = ref.read(aiApiClientProvider);
    try {
      String? id;
      if (widget.ticketId != null) id = await client.resumeConversation(widget.ticketId!);
      final resumed = id != null;
      id ??= (await client.startConversation(
        ticketId: widget.ticketId,
        cantiereId: widget.cantiereId,
      )).sessionId;

      AiConversationDetailDto? detail;
      try {
        detail = await client.getConversation(id);
      } catch (_) {
        // A resumed draft that cannot be read is an error (an empty screen would look like data
        // loss); a freshly started one just has nothing worth showing yet.
        if (resumed) rethrow;
      }
      if (!mounted) return;
      setState(() {
        _sessionId = id;
        _starting = false;
        if (detail != null) _adopt(detail, withTurns: true);
      });
      _scrollToEnd();
      unawaited(_loadPending());
      unawaited(_refreshLinked().then((_) => detail != null ? _feedApply() : null));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = _startFailureText(e);
        if (e is AiQuotaExhaustedException) {
          _aiBlockedMessage = _startError;
        }
      });
    }
  }

  String _startFailureText(Object e) {
    if (e is AiQuotaExhaustedException) {
      return 'I crediti AI dell\'azienda sono esauriti: non posso avviare una nuova bozza AI.';
    }
    if (e is AiConversationException && e.offline) {
      return 'La bozza AI richiede la connessione e ora non c\'è segnale. '
          'La dettatura sul telefono funziona anche offline: puoi compilare il rapportino '
          'a mano e dettare nei campi.';
    }
    return e.toString();
  }

  /// Takes what the server holds as the truth for the draft, the expiry and (on entry) the
  /// conversation so far.
  void _adopt(AiConversationDetailDto d, {required bool withTurns}) {
    _draft = d.draft;
    _expiresAt = d.expiresAtUtc;
    if (withTurns) {
      _messages
        ..clear()
        ..addAll(
          d.turns.map(
            (t) => _ChatMessage(
              isOperator: t.isOperator,
              text: t.text,
              source: t.source,
              turnId: t.isOperator ? t.turnId : null,
            ),
          ),
        );
    }
  }

  // ── live feed into the editor (Task 12) ──────────────────────────────────────

  static Future<void> _quiet(Future<void> f) => f.then((_) {}, onError: (Object _) {});

  /// Reads which local report (if any) this session already feeds.
  Future<void> _refreshLinked() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final linked = (await ref.read(aiDraftFeedStoreProvider).load(id))?.reportId;
      if (mounted && linked != _linkedReportId) setState(() => _linkedReportId = linked);
    } catch (_) {
      // No readable feed state: the session feeds nothing yet.
    }
  }

  /// Writes the confirmed subset of the current draft into the linked report. A no-op when the
  /// draft was never opened in the editor. Never throws: the feed is a convenience over the
  /// server draft, which stays the source of truth.
  Future<void> _feedApply() async {
    final id = _sessionId;
    if (id == null || _linkedReportId == null) return;
    try {
      await ref.read(aiDraftFeedProvider).apply(id, _draft);
    } catch (_) {}
  }

  Future<List<AiConfirmedEdit>> _editsForTurn(String sessionId) async {
    try {
      return await ref.read(aiEditSyncerProvider).editsForTurn(sessionId);
    } catch (_) {
      return const [];
    }
  }

  /// "Compila nel rapportino": the draft goes into the ordinary editor and keeps feeding it. The
  /// session is NOT confirmed or released: the technician can come back, keep talking, and every
  /// later turn updates the same rapportino without touching what they changed by hand.
  Future<void> _openInEditor() async {
    final sessionId = _sessionId;
    if (sessionId == null || _opening) return;
    setState(() => _opening = true);
    try {
      final store = ref.read(aiDraftFeedStoreProvider);
      var reportId = (await store.load(sessionId))?.reportId;
      if (reportId != null) {
        final existing = await ref.read(draftReportRepositoryProvider).getDraft(reportId);
        // Only a Bozza still on this phone can be fed; a sent one is the office's now.
        if (existing == null || existing.stato != 'Bozza') reportId = null;
      }
      if (reportId == null) {
        reportId = await _createManualDraft();
        if (reportId == null) {
          if (mounted) {
            showAppToast(context, message: 'Accedi per creare un rapportino.', tone: ToastTone.warning);
          }
          return;
        }
        await store.link(sessionId: sessionId, reportId: reportId);
      }
      await ref.read(aiDraftFeedProvider).apply(sessionId, _draft);
      if (!mounted) return;
      setState(() => _linkedReportId = reportId);
      unawaited(context.push(AppRoutes.rapportiniEditor(reportId)));
    } catch (e) {
      if (mounted) showAppToast(context, message: e.toString(), tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// An explicit edit action (accept a proposal, settle a held removal), sent edits-only: no
  /// model call, no charge. The returned draft is adopted and fed into the linked report.
  Future<void> _runEdits(
    Future<AiCopilotDraftDto?> Function(AiEditSyncer syncer, String sessionId) op,
  ) async {
    final sessionId = _sessionId;
    if (sessionId == null || _sending || _editing) return;
    setState(() {
      _editing = true;
      // The draft's Version moves on: a pending confirm key is stale.
      _confirmKey = null;
    });
    try {
      final draft = await op(ref.read(aiEditSyncerProvider), sessionId);
      if (!mounted) return;
      if (draft != null) setState(() => _draft = draft);
      unawaited(_feedApply());
    } on AiEditSyncBlockedException catch (e) {
      if (mounted) showAppToast(context, message: e.message, tone: ToastTone.warning);
    } catch (e) {
      if (mounted) showAppToast(context, message: e.toString(), tone: ToastTone.error);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  void _accept(AiConfirmedEdit edit) => _runEdits((s, id) => s.sync(id, extra: [edit]));

  void _resolveHeld(AiCandidateFact item, {required bool reAdd}) =>
      _runEdits((s, id) => s.resolveHeldRemoval(id, item, reAdd: reAdd));

  // ── sending ──────────────────────────────────────────────────────────────────

  bool get _aiBlocked => _aiBlockedMessage != null;

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty || _sessionId == null || _sending || _aiBlocked || _recording) return;
    if (_failed != null) return; // the unsent update must be retried or discarded first
    _inputCtrl.clear();
    await _run(_Outgoing(key: const Uuid().v4(), text: text));
  }

  Future<void> _retryFailed() async {
    final o = _failed;
    if (o == null || _sending) return;
    await _run(o);
  }

  /// Runs one outgoing turn to the end: transcribe if it is audio, show it, post it (with the
  /// bounded 409 handling), apply the draft. Every failure leaves [o] intact for "Riprova invio".
  Future<void> _run(_Outgoing o) async {
    final sessionId = _sessionId;
    if (sessionId == null || _sending) return;
    setState(() {
      _sending = true;
      _failed = null;
      _failureMessage = null;
      // A new turn moves the draft's Version on — any pending confirm key is now stale.
      _confirmKey = null;
    });
    _startThinkingTimers();

    try {
      if (o.text == null) {
        final voice = o.voice!;
        // `upload` reuses the recording's OWN key and deletes the local files only on success.
        final t = await voice.transcribe(o.recording!);
        o.text = t.transcript;
        o.audioRef = t.audioRef;
        o.rawTranscript = t.transcript;
        o.source = AiTurnSource.voice;
      }
      if (o.text!.trim().isEmpty) {
        // Nothing to send: the recording holds no speech, so it must not linger in the pending list.
        unawaited(_discardRecording(o));
        _finishRun();
        if (mounted) {
          showAppToast(
            context,
            message: 'Non ho sentito nulla nella registrazione. Riprova.',
            tone: ToastTone.warning,
          );
        }
        return;
      }
      if (o.message == null) {
        final m = _ChatMessage(
          isOperator: true,
          text: o.text!,
          source: o.source,
          audioRef: o.audioRef,
          rawTranscript: o.rawTranscript,
        )..accepted = false;
        o.message = m;
        if (mounted) setState(() => _messages.add(m));
        _scrollToEnd();
      }

      // Hand edits made in the editor since the last sync ride in this turn, folded as confirmed
      // BEFORE the model reads it (Task 12).
      // Only a session that feeds a report has hand edits; an unlinked one never touches the store.
      o.edits ??= _linkedReportId == null ? const [] : await _editsForTurn(sessionId);
      final result = await _postWithRetry(sessionId, o);
      if (!mounted) return;
      _cancelThinkingTimers();
      setState(() {
        o.supersedes?.superseded = true;
        o.message?.accepted = true;
        if (o.recording != null) _pendingRecs.removeWhere((r) => r.id == o.recording!.id);
        _messages.add(_ChatMessage(isOperator: false, text: result.assistantReplyText));
        _draft = result.draft;
        _sending = false;
      });
      if (o.edits!.isNotEmpty) {
        unawaited(_quiet(ref.read(aiEditSyncerProvider).acknowledge(sessionId, o.edits!)));
      }
      unawaited(_feedApply());
      _scrollToEnd();
      // The turn is accepted: only now is the local recording no longer needed.
      unawaited(_discardRecording(o));
      unawaited(_learnTurnIds());
    } on AiTranscribeException catch (e) {
      if (!mounted) return;
      _cancelThinkingTimers();
      if (e.error == AiTranscribeError.voiceDisabled) {
        // Retrying cannot help and the mic must not keep offering what the server refuses.
        setState(() {
          _voiceDisabled = true;
          _sending = false;
        });
        return;
      }
      setState(() => _sending = false);
      if (e.retryable) {
        _fail(o, e.message);
      } else {
        // The audio itself is unusable: drop it rather than offer a retry that cannot work.
        unawaited(_discardRecording(o));
        showAppToast(context, message: e.message, tone: ToastTone.error);
      }
    } on AiQuotaExhaustedException {
      if (!mounted) return;
      _cancelThinkingTimers();
      setState(() {
        _sending = false;
        _aiBlockedMessage =
            'I crediti AI dell\'azienda sono esauriti. La bozza resta qui, leggibile: '
            'puoi continuare senza AI.';
      });
    } on AiConversationException catch (e) {
      if (!mounted) return;
      _cancelThinkingTimers();
      setState(() => _sending = false);
      if (e.isDraftTooLarge || e.isTurnLimitExceeded) {
        setState(() => _aiBlockedMessage = e.message);
      } else {
        _fail(o, e.message);
      }
    } catch (e) {
      if (!mounted) return;
      _cancelThinkingTimers();
      setState(() => _sending = false);
      _fail(o, e.toString());
    }
  }

  void _finishRun() {
    _cancelThinkingTimers();
    if (mounted) setState(() => _sending = false);
  }

  void _fail(_Outgoing o, String message) {
    setState(() {
      _failed = o;
      _failureMessage = message;
    });
  }

  /// Explicit "Scarta": drops the unsent update (its bubble, and for audio its recording).
  void _discardFailed() {
    final o = _failed;
    if (o == null) return;
    setState(() {
      if (o.message != null) _messages.remove(o.message);
      _failed = null;
      _failureMessage = null;
    });
    unawaited(_discardRecording(o));
  }

  Future<void> _loadPending() async {
    final ticketId = widget.ticketId;
    if (ticketId == null) return;
    try {
      final voice = await ref.read(voiceCaptureControllerProvider.future);
      final all = await voice.pendingForCurrentUser();
      if (!mounted) return;
      setState(() {
        _voiceCtl = voice;
        _pendingRecs = all.where((r) => r.ticketId == ticketId).toList();
      });
    } catch (_) {
      // No recorder on this device (or the store is unreadable): nothing to offer.
    }
  }

  /// Sends the held recordings one by one: transcribe (the server replays the stored key) and post
  /// with the key derived from the recording's own, so nothing can apply twice.
  Future<void> _sendPending() async {
    final voice = _voiceCtl;
    if (voice == null || _sending || _failed != null || _recording) return;
    for (final rec in List.of(_pendingRecs)) {
      await _run(_Outgoing(key: '${rec.idempotencyKey}:turn', recording: rec, voice: voice));
      if (!mounted || _failed != null || _aiBlocked) break;
    }
  }

  Future<void> _discardPending() async {
    final voice = _voiceCtl;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scartare le registrazioni?'),
        content: const Text('Le registrazioni non inviate verranno cancellate dal telefono.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Scarta')),
        ],
      ),
    );
    if (ok != true || voice == null || !mounted) return;
    final recs = List.of(_pendingRecs);
    setState(() => _pendingRecs = []);
    for (final r in recs) {
      try {
        await voice.store.delete(r);
      } catch (_) {}
    }
  }

  Future<void> _discardRecording(_Outgoing o) async {
    final r = o.recording;
    if (r == null) return;
    _pendingRecs.removeWhere((p) => p.id == r.id);
    try {
      await o.voice?.store.delete(r);
    } catch (_) {
      // The 7-day sweep of the pending store collects it anyway.
    }
  }

  /// Posts [o] with the SAME key every time. 409 `turn_in_progress`: the server is still on it,
  /// wait and re-send (bounded). 409 `concurrent_update`: refetch the draft, then re-send ONCE.
  Future<AiConversationTurnResult> _postWithRetry(String sessionId, _Outgoing o) async {
    final client = ref.read(aiApiClientProvider);
    var inProgress = 0;
    var refetched = false;
    while (true) {
      try {
        return await client.postTurn(
          sessionId,
          text: o.text!,
          source: o.source,
          audioRef: o.audioRef,
          rawTranscript: o.rawTranscript,
          replacesTurnId: o.replacesTurnId,
          confirmedEdits: (o.edits == null || o.edits!.isEmpty)
              ? null
              : [for (final e in o.edits!) e.toJson()],
          idempotencyKey: o.key,
        );
      } on AiConversationException catch (e) {
        if (e.isTurnInProgress && inProgress < _maxTurnInProgressRetries) {
          inProgress++;
          await Future<void>.delayed(widget.turnRetryDelay);
          if (!mounted) rethrow;
          continue;
        }
        if (e.isConcurrentUpdate && !refetched) {
          refetched = true;
          final d = await client.getConversation(sessionId);
          if (!mounted) rethrow;
          setState(() => _adopt(d, withTurns: false));
          continue;
        }
        rethrow;
      }
    }
  }

  /// The turn response names no turn id, so the id a correction must replace is read back from the
  /// conversation: the latest operator turn, if it is the text we just sent.
  Future<void> _learnTurnIds() async {
    final id = _sessionId;
    if (id == null) return;
    try {
      final d = await ref.read(aiApiClientProvider).getConversation(id);
      if (!mounted) return;
      final lastServer = d.turns.lastWhere(
        (t) => t.isOperator,
        orElse: () => const AiConversationTurn(
          turnId: '',
          role: '',
          text: '',
          source: AiTurnSource.typed,
        ),
      );
      if (lastServer.turnId.isEmpty) return;
      final localLast = _messages.lastWhere(
        (m) => m.isOperator && !m.superseded,
        orElse: () => _ChatMessage(isOperator: false, text: ''),
      );
      if (localLast.isOperator && localLast.turnId == null && localLast.text == lastServer.text) {
        setState(() {
          localLast.turnId = lastServer.turnId;
          _expiresAt = d.expiresAtUtc;
        });
      }
    } catch (_) {
      // Best effort: "Correggi" looks the id up again when it is tapped.
    }
  }

  // ── correction ───────────────────────────────────────────────────────────────

  Future<void> _correct(_ChatMessage m) async {
    if (_sending || _sessionId == null) return;
    if (m.turnId == null) await _learnTurnIds();
    if (!mounted) return;
    final replaces = m.turnId;
    if (replaces == null) {
      showAppToast(
        context,
        message: 'Non riesco a correggere questo messaggio adesso. Riprova tra poco.',
        tone: ToastTone.warning,
      );
      return;
    }
    final corrected = await showDialog<String>(
      context: context,
      builder: (ctx) => _CorrectionDialog(initial: m.text),
    );
    if (corrected == null || corrected.trim().isEmpty || corrected.trim() == m.text.trim()) return;
    await _run(
      _Outgoing(
        key: const Uuid().v4(),
        text: corrected.trim(),
        // Keeps the audio and the unedited transcript beside the corrected text.
        source: m.audioRef != null ? AiTurnSource.voice : AiTurnSource.typed,
        audioRef: m.audioRef,
        rawTranscript: m.rawTranscript ?? (m.audioRef != null ? m.text : null),
        replacesTurnId: replaces,
        supersedes: m,
      ),
    );
  }

  // ── voice ────────────────────────────────────────────────────────────────────

  Future<void> _toggleMic() async {
    if (_sending) return;
    VoiceCaptureController voice;
    try {
      voice = await ref.read(voiceCaptureControllerProvider.future);
    } catch (_) {
      if (mounted) {
        showAppToast(
          context,
          message: 'La registrazione non è disponibile su questo telefono.',
          tone: ToastTone.error,
        );
      }
      return;
    }
    if (!mounted) return;

    if (_recording) {
      await _stopRecording(voice);
      return;
    }

    var result = await voice.start(ticketId: widget.ticketId);
    if (!mounted) return _releaseOrphanedStart(voice, result);
    if (result == RecordingStartResult.consentRequired) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Registrazione vocale'),
          content: const Text(voiceConsentText),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accetto')),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
      await acceptVoiceConsent();
      result = await voice.start(ticketId: widget.ticketId);
      if (!mounted) return _releaseOrphanedStart(voice, result);
    }
    switch (result) {
      case RecordingStartResult.started:
        setState(() => _recording = true);
        // The 9:30 hard stop or another app taking the microphone ends the recording without a tap.
        _interruptSub?.cancel();
        _voiceCtl = voice;
        _interruptSub = voice.completed.listen(
          (rec) => _onRecordingEnded(voice, rec),
          onError: (Object e) {
            if (!mounted) return;
            setState(() => _recording = false);
            showAppToast(
              context,
              message: 'La registrazione si è interrotta e non è stata salvata.',
              tone: ToastTone.error,
            );
          },
        );
      case RecordingStartResult.consentRequired:
        break;
      case RecordingStartResult.notSignedIn:
        showAppToast(context, message: 'Accedi per registrare un aggiornamento.', tone: ToastTone.warning);
      case RecordingStartResult.permissionDenied:
        showAppToast(
          context,
          message: 'Serve il permesso del microfono per registrare.',
          tone: ToastTone.warning,
        );
      case RecordingStartResult.permissionPermanentlyDenied:
        showAppToast(
          context,
          message: 'Il microfono è bloccato: abilitalo dalle impostazioni del telefono.',
          tone: ToastTone.warning,
        );
    }
  }

  Future<void> _stopRecording(VoiceCaptureController voice) async {
    if (_stopping) return;
    _stopping = true;
    try {
      final rec = await voice.stop();
      // Not awaited: nothing depends on the cancel completing.
      unawaited(_interruptSub?.cancel());
      _interruptSub = null;
      if (!mounted) return;
      setState(() => _recording = false);
      await _run(_Outgoing(key: '${rec.idempotencyKey}:turn', recording: rec, voice: voice));
    } catch (e) {
      if (!mounted) return;
      setState(() => _recording = false);
      showAppToast(context, message: 'Registrazione non riuscita: $e', tone: ToastTone.error);
    } finally {
      _stopping = false;
    }
  }

  void _onRecordingEnded(VoiceCaptureController voice, PendingRecording rec) {
    if (!mounted || !_recording) return;
    setState(() => _recording = false);
    unawaited(_run(_Outgoing(key: '${rec.idempotencyKey}:turn', recording: rec, voice: voice)));
  }

  // ── lifecycle: confirm, leave, abandon, manual path ──────────────────────────

  Future<void> _confirm() async {
    final sessionId = _sessionId;
    if (sessionId == null || _confirming) return;

    setState(() => _confirming = true);

    // Hand edits made in the editor reach the server before it resolves the draft, so Confirm
    // returns the technician's values. Best effort: offline, they still win locally (the confirm
    // apply never overwrites a hand-edited field).
    if (_linkedReportId != null) {
      try {
        if (await ref.read(aiEditSyncerProvider).sync(sessionId) != null) _confirmKey = null;
      } catch (_) {}
      if (!mounted) return;
    }
    _confirmKey ??= const Uuid().v4();

    try {
      final response = await ref
          .read(aiApiClientProvider)
          .confirmConversation(sessionId, idempotencyKey: _confirmKey!);
      if (!mounted) return;

      // Spec §5.5: mobile applies the resolved draft to its own report and then uses the existing
      // save/submit path. Nothing is created server-side — Confirm resolves, it does not create
      // (§5.4) — so there is no server object to download, no import to retry, and no state that
      // can move on underneath us between the two calls.
      // A session already feeding a report confirms INTO it (matched by identity: no duplicate
      // lines); otherwise a new local report is created, as before.
      final localId = await applyConfirmedDraft(
        ref,
        response: response,
        ticketId: widget.ticketId,
        cantiereId: widget.cantiereId,
        sessionId: _linkedReportId != null ? sessionId : null,
      );
      if (!mounted) return;

      if (localId == null) {
        // The same refusal createLocalDraft makes: no signed-in internal user id, so there is
        // nobody to attribute a rapportino to. Retrying the same button is the whole recovery.
        setState(() => _confirming = false);
        showAppToast(
          context,
          message: 'Non riesco a creare il rapportino su questo telefono. Riprova.',
          tone: ToastTone.error,
        );
        return;
      }

      // What the server could not resolve is operator-facing and belongs on screen before the
      // technician leaves the conversation — this is the only place those sentences are visible.
      if (response.warnings.isNotEmpty) {
        showAppToast(context, message: response.warnings.join('\n'), tone: ToastTone.warning);
      }

      // The draft is in Drift, provenance included — applyConfirmedDraft wrote isAiAssisted in the
      // same companion. The session has now done its job and is released (the controller's own
      // rule). Clearing _sessionId first keeps the leave handler (which releases a ticket-less
      // session) from firing a second DELETE at an id the server has already forgotten.
      //
      // Do NOT call reportEditorProvider(localId).notifier.markAiAssisted() here. That provider has
      // just been constructed, its `state` is still the blank placeholder, and _hydrate() has not
      // resolved — its autosave would write blanks over everything applyConfirmedDraft just saved.
      // See the markAiAssisted constraint in the plan's Global Constraints; the flag is already set.
      _sessionId = null;
      unawaited(ref.read(aiApiClientProvider).abandonConversation(sessionId));
      // The report no longer has a live draft behind it.
      if (_linkedReportId != null) {
        unawaited(_quiet(ref.read(aiDraftFeedStoreProvider).unlink(sessionId)));
      }

      if (!mounted) return;
      context.go(AppRoutes.rapportiniEditor(localId));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _confirming = false;
        // A stale-version 409 means the draft moved on since this key was minted — the next
        // attempt must not replay it.
        if (e is AiConversationException && e.isStaleVersionConflict) _confirmKey = null;
      });
      showAppToast(context, message: e.toString(), tone: ToastTone.error);
    }
  }

  /// Leaves the screen. A TICKET-bound live draft is durable: it is resumed next time, never
  /// deleted here. A session without a ticket has no resume route (Start makes a new one every
  /// time), so leaving releases it (see [_releaseContextFree]).
  void _leave() {
    if (mounted) Navigator.of(context).maybePop();
  }

  bool get _needsLeaveConfirm =>
      !_forceLeave && (_recording || _failed != null || _messages.any((m) => !m.accepted));

  /// Leaving (or being torn down) while recording must always release the microphone. Ticket-bound:
  /// stop and keep the file (offered again on the next entry). Ticketless: it could never be
  /// offered again, so cancel and delete it.
  void _releaseMicrophone() {
    if (!_recording) return;
    _recording = false;
    final voice = _voiceCtl;
    if (voice != null) _releaseVoice(voice);
  }

  void _releaseVoice(VoiceCaptureController voice) {
    if (widget.ticketId != null) {
      unawaited(voice.stop().then((_) {}, onError: (_) {}));
    } else {
      unawaited(voice.cancel());
    }
  }

  /// The screen went away while [VoiceCaptureController.start] was in flight (a first-run
  /// permission or consent dialog, a slow recorder). [dispose] ran before `_recording` was set, so
  /// [_releaseMicrophone] had nothing to release: if the start succeeded the microphone is on with
  /// no screen. Release it by the same rule as [_releaseMicrophone].
  void _releaseOrphanedStart(VoiceCaptureController voice, RecordingStartResult result) {
    if (result == RecordingStartResult.started) _releaseVoice(voice);
  }

  void _releaseContextFree() {
    final id = _sessionId;
    if (widget.ticketId == null && id != null) {
      _sessionId = null;
      unawaited(ref.read(aiApiClientProvider).abandonConversation(id));
    }
  }

  Future<void> _onPopBlocked() async {
    if (_forceLeave) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final canResume = widget.ticketId != null;
    final voiceUpdate = _recording || _failed?.recording != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Uscire?'),
        content: Text(
          _recording
              ? (canResume
                    ? 'Stai registrando. Se esci la registrazione viene salvata sul telefono e te la '
                          'riproporremo la prossima volta.'
                    : 'Stai registrando. Questa conversazione non è legata a un ticket e non si può '
                          'riprendere: uscendo l\'aggiornamento andrà perso.')
              : 'Hai un aggiornamento non inviato. ${voiceUpdate && canResume ? 'La registrazione resta salvata sul telefono e potrai inviarla la prossima volta.' : 'Se esci andrà perso.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Resta qui')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Esci comunque')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _forceLeave = true;
    _releaseMicrophone();
    Navigator.of(context).pop();
  }

  /// The explicit, destructive act: delete the server-side draft, then leave.
  Future<void> _abandonDraft() async {
    final sessionId = _sessionId;
    if (sessionId != null) {
      try {
        await ref.read(aiApiClientProvider).abandonConversation(sessionId);
      } catch (_) {
        if (mounted) {
          showAppToast(
            context,
            message: 'Non sono riuscito ad abbandonare la bozza. Controlla la connessione e riprova.',
            tone: ToastTone.error,
          );
        }
        return;
      }
      _sessionId = null;
    }
    _forceLeave = true;
    if (mounted) Navigator.of(context).maybePop();
  }

  /// "Continua senza AI": the ordinary manual editor, prefilled from the ticket exactly like the
  /// ticket screen's own "Crea rapportino". The AI draft (if any) stays on the server untouched.
  Future<void> _continueWithoutAi() async {
    final id = await _createManualDraft();
    if (!mounted) return;
    if (id == null) {
      showAppToast(context, message: 'Accedi per creare un rapportino.', tone: ToastTone.warning);
      return;
    }
    context.go(AppRoutes.rapportiniEditor(id));
  }

  /// A local Bozza prefilled from the ticket exactly like the ticket screen's own "Crea
  /// rapportino"; null when nobody is signed in.
  Future<String?> _createManualDraft() async {
    Ticket? ticket;
    final ticketId = widget.ticketId;
    if (ticketId != null) {
      try {
        final db = ref.read(appDatabaseProvider);
        ticket = await (db.select(db.tickets)..where((t) => t.id.equals(ticketId))).getSingleOrNull();
      } catch (_) {
        ticket = null; // an unreadable mirror just means no prefill
      }
    }
    final id = await createLocalDraft(
      ref,
      title: ticket != null ? 'Rapportino — ${ticket.title}' : 'Nuovo rapportino',
      locationId: ticket?.locationId ?? '',
      ticketId: ticketId,
      cantiereId: widget.cantiereId,
      customerId: ticket?.customerId,
      tenantId: ticket?.tenantId,
    );
    return id;
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  // ── build ────────────────────────────────────────────────────────────────────

  bool get _expiringSoon {
    final e = _expiresAt;
    if (e == null || _expiryDismissed) return false;
    return e.difference(DateTime.now().toUtc()) <= _expiryWarningWindow;
  }

  @override
  Widget build(BuildContext context) {
    final quota = ref.watch(aiQuotaProvider);
    final quotaExhausted = quota.valueOrNull?.exhausted ?? false;
    final blocked = _draft.hasBlockingOpenItems;
    final sessionReady = _sessionId != null;

    return PopScope(
      canPop: !_needsLeaveConfirm,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _releaseContextFree();
        } else {
          unawaited(_onPopBlocked());
        }
      },
      child: Scaffold(
      backgroundColor: context.colors.bg2,
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: 'Rapportino con AI Copilot', showBack: true, onBack: _leave),
            if (_starting) const Expanded(child: Center(child: CircularProgressIndicator())),
            if (_startError != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.pagePadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_startError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        if (!_aiBlocked) AppButton.secondary(label: 'Riprova', onPressed: _start),
                        if (!_aiBlocked) const SizedBox(height: 8),
                        AppButton(label: 'Continua senza AI', onPressed: _continueWithoutAi),
                      ],
                    ),
                  ),
                ),
              ),
            if (!_starting && _startError == null) ...[
              ..._buildBanners(context),
              Expanded(child: _buildChat(context)),
              if (_draft.activities.isNotEmpty ||
                  _draft.workers.isNotEmpty ||
                  _draft.materials.isNotEmpty ||
                  _draft.controlli.isNotEmpty ||
                  _draft.diagnosi != null ||
                  _draft.soluzione != null ||
                  _draft.customerSignoffText != null ||
                  _draft.openItems.isNotEmpty)
                _buildDraftSummary(context),
              if (_voiceDisabled)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.pagePadding,
                    vertical: 4,
                  ),
                  child: Text(
                    'La registrazione vocale non è attiva per questa azienda: scrivi o detta '
                    'con la tastiera.',
                    style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
                  ),
                ),
              _buildInputRow(context, sessionReady, quotaExhausted),
              // The live feed (Task 12): the confirmed part of the draft goes into the ordinary
              // rapportino and keeps updating it after every later turn.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  0,
                ),
                child: AppButton.secondary(
                  label: _linkedReportId != null
                      ? 'Apri il rapportino collegato'
                      : 'Compila nel rapportino',
                  isLoading: _opening,
                  onPressed: !sessionReady || _opening || _confirming ? null : _openInEditor,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pagePadding,
                  AppSpacing.sm,
                  AppSpacing.pagePadding,
                  AppSpacing.base,
                ),
                child: Row(
                  children: [
                    Expanded(child: AppButton.secondary(label: 'Esci', onPressed: _leave)),
                    const SizedBox(width: 12),
                    Expanded(
                      // The label says "apri", not "crea": Confirm no longer creates anything
                      // server-side, and the technician lands on a local Bozza that is not yet
                      // sent. Copy that said "crea" would be the one place in the app where a
                      // rapportino looks filed and is not.
                      child: AppButton(
                        label: _confirming ? 'Preparo il rapportino…' : 'Conferma e apri il rapportino',
                        onPressed: !sessionReady ||
                                _messages.isEmpty ||
                                blocked ||
                                _confirming ||
                                _sending ||
                                _editing ||
                                _failed != null
                            ? null
                            : _confirm,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  List<Widget> _buildBanners(BuildContext context) {
    Widget banner(Color color, String text, List<Widget> actions) => Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(AppSpacing.pagePadding, 4, AppSpacing.pagePadding, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(color: context.colors.ink, fontSize: 13)),
          if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
        ],
      ),
    );

    return [
      if (_expiringSoon)
        banner(context.colors.amber, _expiryText(), [
          TextButton(
            onPressed: () => setState(() => _expiryDismissed = true),
            child: const Text('Riprendi'),
          ),
          TextButton(onPressed: _abandonDraft, child: const Text('Abbandona bozza')),
        ]),
      if (_aiBlockedMessage != null)
        banner(context.colors.red, _aiBlockedMessage!, [
          TextButton(onPressed: _continueWithoutAi, child: const Text('Continua senza AI')),
        ]),
      if (_failed != null && _failureMessage != null)
        banner(context.colors.red, '$_failureMessage\nL\'aggiornamento non è stato inviato.', [
          TextButton(onPressed: _sending ? null : _retryFailed, child: const Text('Riprova invio')),
          TextButton(onPressed: _sending ? null : _discardFailed, child: const Text('Scarta')),
        ]),
      if (_pendingRecs.isNotEmpty && _failed == null)
        banner(
          context.colors.amber,
          _pendingRecs.length == 1
              ? 'Hai 1 registrazione non inviata'
              : 'Hai ${_pendingRecs.length} registrazioni non inviate',
          [
            TextButton(onPressed: _sending || _recording ? null : _sendPending, child: const Text('Invia')),
            TextButton(onPressed: _sending ? null : _discardPending, child: const Text('Scarta')),
          ],
        ),
    ];
  }

  String _expiryText() {
    final e = _expiresAt!.toLocal();
    final d = '${e.day.toString().padLeft(2, '0')}/${e.month.toString().padLeft(2, '0')}';
    return 'Questa bozza scade il $d se non la riprendi. Puoi continuarla o abbandonarla.';
  }

  Widget _buildChat(BuildContext context) {
    if (_messages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Center(
          child: Text(
            'Racconta cosa hai fatto, a voce o per iscritto — il copilot verifica persone, ore, '
            'materiali e checklist con i dati reali di TaskTap prima di proporre una bozza.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.inkMuted),
          ),
        ),
      );
    }

    // Only the latest, still-valid voice message of the operator can be corrected.
    final lastCorrectable = _messages.lastIndexWhere((m) => m.isOperator && !m.superseded);

    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding,
        vertical: AppSpacing.sm,
      ),
      itemCount: _messages.length + (_sending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == _messages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colors.inkMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _thinkingStageMessages[_thinkingStage],
                    style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }
        final m = _messages[i];
        final notSent = !m.accepted && !_sending;
        final canCorrect =
            i == lastCorrectable &&
            m.source == AiTurnSource.voice &&
            m.accepted &&
            !_sending &&
            _failed == null &&
            !_aiBlocked;
        return Align(
          alignment: m.isOperator ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: m.isOperator ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: notSent
                      ? context.colors.bg3
                      : (m.isOperator ? AppColors.Y : context.colors.surface),
                  borderRadius: BorderRadius.circular(12),
                  border: notSent ? Border.all(color: context.colors.red) : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (m.isOperator && m.source == AiTurnSource.voice) ...[
                      Icon(
                        LucideIcons.mic,
                        size: 14,
                        color: notSent ? context.colors.ink : Colors.white,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        m.text,
                        style: TextStyle(
                          color: m.isOperator && !notSent ? Colors.white : context.colors.ink,
                          decoration: m.superseded ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (notSent)
                Text(
                  'Non inviato',
                  style: TextStyle(color: context.colors.red, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              if (canCorrect)
                TextButton(
                  onPressed: () => _correct(m),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Correggi'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDraftSummary(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.borderMedium),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_draft.diagnosi != null) _draftLine('Diagnosi', _draft.diagnosi!),
            if (_draft.soluzione != null) _draftLine('Soluzione', _draft.soluzione!),
            if (_draft.customerSignoffText != null)
              _draftLine('Accettazione cliente', _draft.customerSignoffText!),
            // What becomes the rapportino's Title/Description on Confirm (Confirm builds both
            // directly from these) — shown before workers/materials so the technician can verify
            // it, not just the line items.
            for (final a in _draft.activities)
              _draftRow(
                '${a.description.isEmpty ? '—' : a.description}${a.hours != null ? ' · ${a.hours}h' : ''}',
                a.state,
                a.source,
              ),
            // A planned/assigned entry stays out of the rapportino until the technician accepts
            // it here (a property-less confirmed edit): assignment is not participation.
            for (final w in _draft.workers)
              _draftRow(
                '${w.fullName.isEmpty ? '—' : w.fullName}${w.hours != null ? ' · ${w.hours}h' : ''}',
                w.state,
                w.source,
                accept: w.state == AiResolutionState.needsConfirmation && w.userId.isNotEmpty
                    ? AiEditSyncer.acceptWorker(w)
                    : null,
              ),
            for (final m in _draft.materials)
              _draftRow(
                '${m.name.isEmpty ? '—' : m.name} × ${m.quantity}',
                m.state,
                m.source,
                accept: m.state == AiResolutionState.needsConfirmation
                    ? AiEditSyncer.acceptMaterial(m)
                    : null,
              ),
            for (final c in _draft.controlli)
              _draftRow(c.describe(), c.state, AiFactSource.operatorInput),
            if (_draft.openItems.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_draft.openItems.length} punti da chiarire'
                  '${_draft.hasBlockingOpenItems ? ' — risolvi prima di confermare' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _draft.hasBlockingOpenItems ? context.colors.red : context.colors.inkMuted,
                  ),
                ),
              ),
              for (final item in _draft.openItems) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    describeOpenItem(item),
                    style: TextStyle(
                      fontSize: 12,
                      color: item.state == AiResolutionState.conflict
                          ? context.colors.red
                          : context.colors.ink,
                    ),
                  ),
                ),
                // A held removal is settled by the technician, never by the AI.
                if (item.isHeldRemoval)
                  Wrap(
                    spacing: 8,
                    children: [
                      if (AiEditSyncer.heldRemovalEdit(item, reAdd: true) != null)
                        TextButton(
                          onPressed: _sending || _editing
                              ? null
                              : () => _resolveHeld(item, reAdd: true),
                          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                          child: const Text('Reinserisci'),
                        ),
                      if (AiEditSyncer.heldRemovalEdit(item, reAdd: false) != null)
                        TextButton(
                          onPressed: _sending || _editing
                              ? null
                              : () => _resolveHeld(item, reAdd: false),
                          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                          child: const Text('Mantieni rimosso'),
                        ),
                    ],
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _draftLine(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    // Text.rich, not a bare RichText: it picks up the ambient DefaultTextStyle and — unlike
    // RichText — is what find.text/find.textContaining actually look at in widget tests.
    child: Text.rich(
      TextSpan(
        style: TextStyle(color: context.colors.ink, fontSize: 12),
        children: [
          TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: value),
        ],
      ),
    ),
  );

  /// One value of the draft with its provenance badge. A planned / ticket-recorded value the
  /// technician has not confirmed is muted and italic: it must never read as work that was done.
  Widget _draftRow(
    String label,
    AiResolutionState state,
    AiFactSource source, {
    AiConfirmedEdit? accept,
  }) {
    final unconfirmed = isUnconfirmedProposal(source, state);
    return Padding(
      key: unconfirmed ? ValueKey('planned-unconfirmed-row:$label') : null,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontStyle: unconfirmed ? FontStyle.italic : FontStyle.normal,
                color: unconfirmed ? context.colors.inkMuted : context.colors.ink,
              ),
            ),
          ),
          DraftProvenanceBadge(source: source, state: state),
          if (accept != null)
            TextButton(
              key: ValueKey('accept-proposal:$label'),
              onPressed: _sending || _editing ? null : () => _accept(accept),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: const Text('Accetta'),
            ),
        ],
      ),
    );
  }

  Widget _buildInputRow(BuildContext context, bool sessionReady, bool quotaExhausted) {
    final enabled = sessionReady && !quotaExhausted && !_aiBlocked;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.sm,
        AppSpacing.pagePadding,
        0,
      ),
      child: AppTextField.multiline(
        label: 'Scrivi cosa hai fatto…',
        controller: _inputCtrl,
        maxLines: 3,
        enabled: enabled,
        onChanged: (_) {},
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_voiceDisabled)
              IconButton(
                icon: Icon(
                  _recording ? LucideIcons.square : LucideIcons.mic,
                  size: 18,
                  color: _recording ? context.colors.red : context.colors.ink,
                ),
                tooltip: _recording ? 'Ferma la registrazione' : 'Registra un aggiornamento vocale',
                onPressed: enabled && _failed == null && (!_sending || _recording) ? _toggleMic : null,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            DictateButton(controller: _inputCtrl, onChanged: (_) {}, explainWhenUnavailable: false),
            IconButton(
              icon: Icon(LucideIcons.send, size: 18, color: context.colors.ink),
              tooltip: 'Invia',
              onPressed: enabled && !_sending && !_recording && _failed == null ? _send : null,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
          ],
        ),
      ),
    );
  }
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({required this.initial});
  final String initial;

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Correggi la trascrizione'),
      content: TextField(
        key: const ValueKey('correction-field'),
        controller: _ctrl,
        maxLines: 5,
        minLines: 2,
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Invia correzione'),
        ),
      ],
    );
  }
}
