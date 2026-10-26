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

import '../../core/router/app_router.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/ai/ai_api_client.dart';
import '../../data/local/app_database.dart' show Ticket;
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import '../../presentation/providers/report_editor_providers.dart'
    show draftReportRepositoryProvider, reportEditorProvider;
import 'ai_draft_feed.dart';
import 'ai_report/ai_describe_step.dart';
import 'ai_report/ai_review_step.dart';
import 'apply_confirmed_draft.dart';
import 'create_draft.dart';
import 'draft_for_ticket.dart';

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
// seeded draft at once with a provenance badge per value. Voice: the mic records, the recording is
// UPLOADED as-is (`VoiceCaptureController` + `AiApiClient.uploadVoiceCapture`, POST
// /api/ai/voice-captures) and posted as a `Voice` turn carrying only its `audioRef`, so the model
// hears the technician's own words — there is no transcription step on this path (ADR-0023). The
// turn keeps the recording's own Idempotency-Key, reused on every retry. On-device dictation
// (DictateButton, ADR-0017) stays as before and is the no-signal fallback. Leaving the screen never
// deletes the draft: it is durable and is resumed; only "Abbandona bozza" deletes it.
// ══════════════════════════════════════════════════════════════════════════════


class _ChatMessage {
  _ChatMessage({
    required this.isOperator,
    required this.text,
    this.source = AiTurnSource.typed,
    this.turnId,
    this.audioRef,
    this.durationSeconds,
  });
  final bool isOperator;

  /// What the operator typed, or the corrected text of a voice turn. EMPTY for a voice turn taken
  /// as recorded: the words are in the audio, never in a transcript this client produced.
  final String text;
  final AiTurnSource source;

  /// The server's id of this operator turn, once known (the POST response carries none, so it is
  /// read back from the conversation). A correction replaces this turn.
  String? turnId;

  /// Set when this turn's input was a recording the model listened to.
  final String? audioRef;

  /// Length of that recording, when this client uploaded it (a turn resumed from the server only
  /// says that it was spoken).
  final int? durationSeconds;

  /// What the bubble shows: the text, or the recording's own label when there is no text to show.
  String get displayText {
    if (isOperator && source == AiTurnSource.voice && text.trim().isEmpty) {
      final d = durationSeconds;
      return d == null ? 'Registrazione vocale' : 'Registrazione vocale · ${_mmss(d)}';
    }
    return text;
  }

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
  });

  /// Generated once. For a recording it derives from the recording's own persisted key, so it is
  /// stable across restarts of the upload.
  final String key;

  /// Set while the recording still has to be uploaded; [text] is null until then.
  final PendingRecording? recording;

  /// The recorder that produced [recording]; used for its (retried) upload.
  final VoiceCaptureController? voice;

  /// Empty (not null) once a recording became the input: the words travel in [audioRef].
  String? text;
  AiTurnSource source = AiTurnSource.typed;
  String? audioRef;
  int? durationSeconds;
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

/// Which of the two screens this route is showing. The third step — Firma — is its own route: it
/// acts on the local Report Confirm created, which does not exist until this screen is done.
enum _AiStep { describe, review }

/// `0:42` / `2:07` — the length of a recording, as the operator's bubble shows it.
String _mmss(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

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

class _AiCopilotScreenState extends ConsumerState<AiCopilotScreen> with WidgetsBindingObserver {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _messages = <_ChatMessage>[];

  String? _sessionId;
  AiCopilotDraftDto _draft = AiCopilotDraftDto.empty;
  bool _starting = true;
  bool _sending = false;
  bool _confirming = false;

  /// Which screen of the flow is showing. The flow replaces the old single chat pane: the technician
  /// describes on one screen and checks the compiled report on the next, as the client asked.
  _AiStep _step = _AiStep.describe;

  /// The technician chose to write the description instead of speaking it.
  bool _writing = false;

  /// The ticket's number, shown under the title. Fetched once; null when unknown (cantiere flow).
  String? _ticketNumber;

  String? _startError;
  String? _confirmKey;
  int _thinkingStage = 0;
  final _thinkingTimers = <Timer>[];

  DateTime? _expiresAt;
  bool _expiryDismissed = false;

  /// The server said voice capture is off for this company (404 on the capture upload): no mic.
  bool _voiceDisabled = false;
  bool _recording = false;

  /// "Abbandona e ricomincia" is running: a second tap would start a second session.
  bool _abandoning = false;
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

  /// A feed apply is writing the linked report.
  bool _applying = false;

  /// This session's draft already went into a rapportino that was signed, queued or sent (or the
  /// feed refused to write it for that reason). Re-seeding a new report from it would file the
  /// same materials and hours twice: Compila and Conferma stay blocked until the technician
  /// abandons it and starts again.
  String? _usedDraftMessage;

  /// Only the MICROPHONE is unavailable (transcription refused for credits): typed turns and
  /// on-device dictation go on.
  String? _micBlockedMessage;

  /// The failed turn was refused for its length: offer to shorten it.
  bool _failedTooLong = false;

  /// Set when leaving the app stopped a recording; told to the technician on return.
  String? _backgroundNote;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadTicketNumber());
    _start();
  }

  /// The header's subtitle. Read from the local mirror, not the server: it is already there for any
  /// ticket the technician can open this screen from, and a failure here must never block the flow.
  Future<void> _loadTicketNumber() async {
    final id = widget.ticketId;
    if (id == null) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final row = await (db.select(db.tickets)..where((t) => t.id.equals(id))).getSingleOrNull();
      final numero = row?.numero?.trim();
      if (!mounted || numero == null || numero.isEmpty) return;
      setState(() => _ticketNumber = numero);
    } catch (_) {
      // A missing row (or an unreadable mirror) costs the subtitle, nothing else.
    }
  }

  /// Leaving the app (screen off, another app, the home button) never keeps the microphone hot:
  /// a ticket-bound recording is stopped and KEPT (offered again), a ticketless one is cancelled.
  /// Nothing is uploaded until the technician is back and chooses to send it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused || state == AppLifecycleState.inactive) && _recording) {
      _backgroundNote = widget.ticketId != null
          ? 'La registrazione è stata fermata quando hai lasciato l\'app ed è salvata sul telefono: '
                'puoi inviarla o scartarla.'
          : 'La registrazione è stata annullata quando hai lasciato l\'app.';
      _releaseMicrophone();
      unawaited(_interruptSub?.cancel());
      _interruptSub = null;
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _backgroundNote != null && mounted) {
      final note = _backgroundNote!;
      _backgroundNote = null;
      showAppToast(context, message: note, tone: ToastTone.warning);
      unawaited(_loadPending());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
      unawaited(_refreshLinked().then((_) => _checkLinkedReport(apply: detail != null)));
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
          'La dettatura sul telefono funziona anche offline: puoi compilare il rapporto di lavoro '
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
  ///
  /// Afterwards the editor's provider is invalidated: an editor hydrated before this write would
  /// otherwise hold the old row, and its next whole-row save would turn the stale values into
  /// "hand edits" sent to the server as confirmed.
  Future<void> _feedApply() async {
    final id = _sessionId;
    final reportId = _linkedReportId;
    if (id == null || reportId == null) return;
    if (mounted) setState(() => _applying = true);
    try {
      await ref.read(aiDraftFeedProvider).apply(id, _draft);
      if (mounted) ref.invalidate(reportEditorProvider(reportId));
    } on AiFeedReportLockedException catch (e) {
      // The report was signed, queued or sent meanwhile: the feed let go of it.
      if (mounted) setState(() => _markDraftUsed(e.message));
    } on AiFeedSessionGoneException catch (e) {
      if (mounted) setState(() => _linkedReportId = null);
      if (mounted) showAppToast(context, message: e.message, tone: ToastTone.warning);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _markDraftUsed(String reason) {
    _linkedReportId = null;
    _usedDraftMessage =
        'Questa bozza è già stata usata per un rapporto di lavoro inviato. $reason '
        'Per un nuovo rapporto di lavoro abbandonala e ricomincia.';
  }

  /// On entry (and before Compila): a linked report that is no longer an editable draft means
  /// this draft was already used. It is never re-seeded silently into a new report.
  Future<void> _checkLinkedReport({required bool apply}) async {
    final sessionId = _sessionId;
    final reportId = _linkedReportId;
    if (sessionId == null || reportId == null) return;
    try {
      final existing = await ref.read(draftReportRepositoryProvider).getDraft(reportId);
      if (existing == null) {
        // The report was deleted from the phone: nothing was filed from it; the link just goes.
        await ref.read(aiDraftFeedStoreProvider).unlink(sessionId);
        if (mounted) setState(() => _linkedReportId = null);
        return;
      }
      final refusal = feedWriteRefusal(existing);
      if (refusal != null) {
        // Stays linked: the link is the durable "this session was used" record.
        if (mounted) setState(() => _markDraftUsed(refusal));
        return;
      }
    } catch (_) {
      return;
    }
    if (apply) await _feedApply();
  }

  /// "Abbandona e ricomincia": deletes the used session on the server, then starts a fresh one.
  Future<void> _abandonAndRestart() async {
    final sessionId = _sessionId;
    if (sessionId == null || _abandoning || _recording) return;
    setState(() => _abandoning = true);
    final bool ok;
    try {
      ok = await ref.read(aiApiClientProvider).tryAbandonConversation(sessionId);
    } catch (_) {
      if (mounted) setState(() => _abandoning = false);
      rethrow;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _abandoning = false);
      showAppToast(
        context,
        message: 'Non sono riuscito ad abbandonare la bozza. Controlla la connessione e riprova.',
        tone: ToastTone.error,
      );
      return;
    }
    await _quiet(ref.read(aiDraftFeedStoreProvider).unlink(sessionId));
    if (!mounted) return;
    setState(() {
      _abandoning = false;
      _sessionId = null;
      _usedDraftMessage = null;
      _linkedReportId = null;
      _messages.clear();
      _draft = AiCopilotDraftDto.empty;
      _confirmKey = null;
    });
    await _start();
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
        if (existing == null) {
          reportId = null; // deleted from the phone: a fresh report is linked below
        } else if (feedWriteRefusal(existing) case final refusal?) {
          // Signed, queued or sent: this draft was used. Never re-seed it into a new report.
          if (mounted) setState(() => _markDraftUsed(refusal));
          return;
        }
      }
      if (reportId == null) {
        reportId = await _createManualDraft();
        if (reportId == null) {
          if (mounted) {
            showAppToast(
              context,
              message: 'Accedi per creare un rapporto di lavoro.',
              tone: ToastTone.warning,
            );
          }
          return;
        }
        await store.link(sessionId: sessionId, reportId: reportId);
      }
      await ref.read(aiDraftFeedProvider).apply(sessionId, _draft);
      if (!mounted) return;
      setState(() => _linkedReportId = reportId);
      unawaited(context.push(AppRoutes.rapportiniEditor(reportId)));
    } on AiFeedReportLockedException catch (e) {
      if (mounted) setState(() => _markDraftUsed(e.message));
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
    } on AiFeedSessionGoneException catch (e) {
      if (mounted) setState(() => _linkedReportId = null);
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

  /// Does this draft have anything for the technician to check? A turn that only asked a question
  /// resolves nothing, and moving to the review screen then would show an empty report.
  static bool _draftHasContent(AiCopilotDraftDto d) =>
      d.activities.isNotEmpty ||
      d.workers.isNotEmpty ||
      d.materials.isNotEmpty ||
      d.controlli.isNotEmpty ||
      d.strumenti.isNotEmpty ||
      d.openItems.isNotEmpty ||
      (d.customerSignoffText?.isNotEmpty ?? false);

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

  /// Runs one outgoing turn to the end: upload the recording if it is audio, show it, post it (with
  /// the bounded 409 handling), apply the draft. Every failure leaves [o] intact for "Riprova invio".
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
        // `capture` stores the recording under its OWN key and keeps the local files: the turn
        // carries only its `audioRef`, so the model hears the operator rather than a transcript.
        final AiVoiceCapture capture;
        try {
          capture = await voice.capture(o.recording!);
        } on AiQuotaExhaustedException {
          // The upload is billed at the TURN, not here, so a 429 at this point means a server that
          // still charges for the capture. Either way only the MICROPHONE stops: the recording
          // stays on the phone; typed turns and on-device dictation go on.
          if (!mounted) return;
          _cancelThinkingTimers();
          setState(() {
            _sending = false;
            _micBlockedMessage =
                'Crediti AI esauriti: la registrazione vocale non è disponibile. Puoi scrivere '
                'o dettare sul telefono; la registrazione resta salvata.';
            if (o.recording != null && !_pendingRecs.any((r) => r.id == o.recording!.id)) {
              _pendingRecs = [..._pendingRecs, o.recording!];
            }
          });
          return;
        }
        // A voice turn IS its audio: empty text, which the server accepts whenever `audioRef` is set
        // (`AiConversationTurnRequestValidator`). No transcript is produced or sent.
        o.text = '';
        o.audioRef = capture.audioRef;
        o.durationSeconds = capture.durationSeconds;
        o.source = AiTurnSource.voice;
      }
      if (o.audioRef == null && o.text!.trim().isEmpty) {
        // Nothing to send: a turn with neither text nor audio, which the server would refuse as
        // `turn_empty`. The screens never build one — this is the guard against a future caller.
        unawaited(_discardRecording(o));
        _finishRun();
        if (mounted) {
          showAppToast(
            context,
            message: 'Non c\'è niente da inviare.',
            tone: ToastTone.warning,
          );
        }
        return;
      }
      if (o.text!.length > maxTurnCharacters) {
        // Over the server's per-turn cap: refused before it is sent, and the technician can
        // shorten it instead of losing the recording.
        _cancelThinkingTimers();
        setState(() => _sending = false);
        _fail(
          o,
          'Il testo è troppo lungo per un solo aggiornamento (massimo $maxTurnCharacters '
          'caratteri): accorcialo e invialo di nuovo.',
          tooLong: true,
        );
        return;
      }
      if (o.message == null) {
        final m = _ChatMessage(
          isOperator: true,
          text: o.text!,
          source: o.source,
          audioRef: o.audioRef,
          durationSeconds: o.durationSeconds,
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
        o.message?.accepted = true;
        if (o.recording != null) _pendingRecs.removeWhere((r) => r.id == o.recording!.id);
        _messages.add(_ChatMessage(isOperator: false, text: result.assistantReplyText));
        _draft = result.draft;
        _sending = false;
        // A turn that compiled something takes the technician to the result. A turn that only asked
        // a question leaves the draft empty and must not: there is nothing to check yet, and the
        // description the technician just gave is still on screen to refine.
        if (_draftHasContent(result.draft)) {
          _step = _AiStep.review;
          _writing = false;
        }
      });
      if (o.edits!.isNotEmpty) {
        unawaited(_quiet(ref.read(aiEditSyncerProvider).acknowledge(sessionId, o.edits!)));
      }
      unawaited(_feedApply());
      _scrollToEnd();
      // The turn is accepted: only now is the local recording no longer needed.
      unawaited(_discardRecording(o));
      unawaited(_learnTurnIds());
    } on AiVoiceUploadException catch (e) {
      if (!mounted) return;
      _cancelThinkingTimers();
      if (e.error == AiVoiceUploadError.voiceDisabled) {
        // Retrying cannot help and the mic must not keep offering what the server refuses; the
        // file is deleted rather than offered again for a week.
        unawaited(_discardRecording(o));
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
        _fail(o, e.message, tooLong: e.isTextTooLong);
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

  void _fail(_Outgoing o, String message, {bool tooLong = false}) {
    setState(() {
      _failed = o;
      _failureMessage = message;
      _failedTooLong = tooLong;
    });
  }

  /// "Accorcia il testo": the over-long update is edited and re-sent (same key: a refused turn
  /// claimed nothing on the server). The unedited transcript is kept beside it.
  Future<void> _shortenFailed() async {
    final o = _failed;
    if (o == null || o.text == null) return;
    final edited = await showDialog<String>(
      context: context,
      builder: (ctx) =>
          _CorrectionDialog(initial: o.text!, title: 'Accorcia il testo', action: 'Invia'),
    );
    if (edited == null || edited.trim().isEmpty || !mounted) return;
    setState(() {
      if (o.message != null) _messages.remove(o.message);
      o.message = null;
      o.text = edited.trim();
      _failedTooLong = false;
    });
    await _retryFailed();
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

  /// Sends the held recordings one by one: upload (the server replays the stored key) and post
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
        if ((e.statusCode == 400 || e.statusCode == 422) &&
            !e.isTextTooLong &&
            (o.edits?.isNotEmpty ?? false)) {
          // The server refused the turn: one of the hand edits riding in it, most likely. The
          // spoken/typed update must still go through: the edits are sent edits-only, where a
          // refused one is isolated, whatever is still undelivered is recorded as refused (shown
          // on the editor card, never riding again), and the turn is re-sent WITHOUT them under
          // the same key (a refused turn claims nothing server-side).
          final syncer = ref.read(aiEditSyncerProvider);
          try {
            await syncer.sync(sessionId);
          } catch (_) {}
          try {
            await syncer.refuseTurnEdits(sessionId, o.edits!, e.code ?? 'turn_refused');
          } catch (_) {}
          if (!mounted) rethrow;
          o.edits = const [];
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
      if (localLast.isOperator &&
          localLast.turnId == null &&
          localLast.accepted &&
          localLast.text == lastServer.text) {
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
        // The 5-minute hard stop or another app taking the microphone ends the recording without a tap.
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
      final String? localId;
      try {
        localId = await applyConfirmedDraft(
          ref,
          response: response,
          ticketId: widget.ticketId,
          cantiereId: widget.cantiereId,
          sessionId: _linkedReportId != null ? sessionId : null,
        );
      } on AiFeedReportLockedException catch (e) {
        // The linked report was signed, queued or sent: Confirm never writes into it.
        if (!mounted) return;
        setState(() {
          _confirming = false;
          _markDraftUsed(e.message);
        });
        return;
      }
      if (!mounted) return;

      if (localId == null) {
        // The same refusal createLocalDraft makes: no signed-in internal user id, so there is
        // nobody to attribute a rapportino to. Retrying the same button is the whole recovery.
        setState(() => _confirming = false);
        showAppToast(
          context,
          message: 'Non riesco a creare il rapporto di lavoro su questo telefono. Riprova.',
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
      // The report exists locally now, so the flow's last screen is the signing one: the customer
      // signs, the technician sends, and only then does the office have a report. Anything still to
      // change goes through "Modifica" on the Controlla screen, which opens the full editor.
      context.go(AppRoutes.aiSign(localId));
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
    // Same guard as the ticket screen: leaving the copilot for the manual editor must not mint a
    // second Bozza for a ticket that already has one.
    final ticketId = widget.ticketId;
    if (ticketId != null) {
      final existing = await editableDraftsForTicket(ref.read(appDatabaseProvider), ticketId);
      if (!mounted) return;
      if (existing.isNotEmpty) {
        // Built here rather than inline in the switch: this is the only use of `context`, and it now
        // happens strictly before the await, so the mounted check above covers it.
        final asking = askAboutExistingDraft(context, drafts: existing);
        switch (await asking) {
          case ExistingDraftChoice.openExisting:
            if (!mounted) return;
            await openEditableDraft(context, ref, existing.first);
            return;
          case ExistingDraftChoice.createNew:
            break;
          case ExistingDraftChoice.cancelled:
            return;
        }
      }
    }
    final id = await _createManualDraft();
    if (!mounted) return;
    if (id == null) {
      showAppToast(
        context,
        message: 'Accedi per creare un rapporto di lavoro.',
        tone: ToastTone.warning,
      );
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
      title: ticket != null ? 'Rapporto di lavoro — ${ticket.title}' : 'Nuovo rapporto di lavoro',
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
            ScreenHeader(
              title: 'Rapporto di intervento',
              subtitle: _ticketNumber,
              showBack: true,
              onBack: _leave,
            ),
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
              Expanded(
                child: _step == _AiStep.review
                    ? AiReviewStep(
                        draft: _draft,
                        busy: _sending || _editing || _applying || _confirming,
                        onAccept: _accept,
                        onResolveHeld: (item, {required bool reAdd}) =>
                            _resolveHeld(item, reAdd: reAdd),
                      )
                    : AiDescribeStep(
                        recording: _recording,
                        busy: _sending,
                        thinkingLabel: _thinkingStageMessages[_thinkingStage],
                        failureMessage: _failureMessage,
                        micBlockedMessage: _micBlockedMessage,
                        voiceDisabled: _voiceDisabled,
                        controller: _inputCtrl,
                        writing: _writing,
                        onToggleWriting: () => setState(() => _writing = !_writing),
                        onMic: _toggleMic,
                        onShorten: _shortenFailed,
                        onTextChanged: () => setState(() {}),
                      ),
              ),
              _buildFooter(context),
            ],
          ],
        ),
      ),
      ),
    );
  }

  /// The one action of each screen, pinned under it.
  ///
  /// "Genera il rapporto" sends exactly what the field or the recording holds — the same `_send` the
  /// chat's paper-plane called. "Conferma" is the same guarded `_confirm` as before: it stays disabled
  /// while an open item is ambiguous or conflicting, so the assistant's own uncertainty can never be
  /// confirmed away by a tap.
  Widget _buildFooter(BuildContext context) {
    final pad = const EdgeInsets.fromLTRB(
      AppSpacing.pagePadding,
      AppSpacing.sm,
      AppSpacing.pagePadding,
      AppSpacing.base,
    );

    if (_step == _AiStep.review) {
      final busy = _sending || _confirming || _editing || _applying || _recording;
      return Padding(
        padding: pad,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const ValueKey('ai-describe-again'),
              // The description is kept: a report the assistant got wrong costs a sentence, not a
              // re-recording.
              onPressed: busy || _usedDraftMessage != null
                  ? null
                  : () => setState(() => _step = _AiStep.describe),
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Text(
                'Descrivi di nuovo',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.red),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  // "Modifica" opens the ordinary report editor on this draft — every card
                  // editable, the same editor the technician already knows — and keeps the session
                  // alive, so what they change by hand survives the next turn. "Descrivi di nuovo"
                  // (the link above) is the cheaper route when the assistant got the story wrong.
                  child: AppButton.secondary(
                    label: 'Modifica',
                    isLoading: _opening,
                    onPressed: busy || _opening || _usedDraftMessage != null
                        ? null
                        : _openInEditor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: AppButton(
                    label: _confirming ? 'Preparo il rapporto…' : 'Conferma',
                    isLoading: _confirming,
                    onPressed: _sessionId == null ||
                            _draft.hasBlockingOpenItems ||
                            _confirming ||
                            _sending ||
                            _editing ||
                            _recording ||
                            _usedDraftMessage != null ||
                            _failed != null
                        ? null
                        : _confirm,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final hasText = _inputCtrl.text.trim().isNotEmpty;
    return Padding(
      padding: pad,
      child: AppButton(
        label: _sending ? 'Generazione in corso…' : 'Genera il rapporto',
        isLoading: _sending,
        onPressed: _sessionId == null ||
                !hasText ||
                _sending ||
                _recording ||
                _aiBlocked ||
                _failed != null
            ? null
            : _send,
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
      if (_usedDraftMessage != null)
        banner(context.colors.amber, _usedDraftMessage!, [
          TextButton(
            key: const ValueKey('abandon-and-restart'),
            onPressed: _sending || _recording || _abandoning ? null : _abandonAndRestart,
            child: const Text('Abbandona e ricomincia'),
          ),
        ]),
      if (_sessionId != null && (ref.watch(aiQuotaProvider).valueOrNull?.exhausted ?? false))
        banner(
          context.colors.amber,
          'Crediti AI esauriti: puoi finire questa bozza, per nuove bozze servono crediti.',
          const [],
        ),
      if (_micBlockedMessage != null) banner(context.colors.amber, _micBlockedMessage!, const []),
      if (_backgroundNote != null && !_recording)
        banner(context.colors.amber, _backgroundNote!, const []),
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
          if (_failedTooLong)
            TextButton(
              key: const ValueKey('shorten-failed'),
              onPressed: _sending ? null : _shortenFailed,
              child: const Text('Accorcia il testo'),
            )
          else
            TextButton(
                onPressed: _sending ? null : _retryFailed, child: const Text('Riprova invio')),
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
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({
    required this.initial,
    this.title = 'Correggi la trascrizione',
    this.action = 'Invia correzione',
  });
  final String initial;
  final String title;
  final String action;

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
      title: Text(widget.title),
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
          child: Text(widget.action),
        ),
      ],
    );
  }
}
