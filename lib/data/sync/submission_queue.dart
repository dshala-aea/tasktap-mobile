// dart format width=100
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/error_message.dart';
import '../../domain/reports/strumenti_selection.dart';
import '../local/app_database.dart';
import '../reports/draft_report_repository.dart';
import '../reports/report_submit_api_client.dart';
import '../reports/submit_report_request.dart';
import 'draft_submission_state.dart';

export 'draft_submission_state.dart';

// ══════════════════════════════════════════════════════════════════════════════
// SubmissionQueue
//
// Processes local drafts that are marked readyToSubmit one-by-one.
//
// Design seam: the queue currently runs Strategy A (process on demand /
// on reconnect).  A future Strategy B (bulk/background) can replace
// _processAll() with a WorkManager job without touching the attachment-upload
// or submit logic.
//
// Invariants:
//   - A draft is NEVER deleted on failure; only its state is updated.
//   - The idempotency key is generated once and persisted; retries reuse it.
//   - Attachment upload (per allegato) is tracked individually so a partial
//     retry skips already-uploaded media.
//   - Signatures are staged through POST /attachments with a `kind`
//     (signature-customer | signature-technician): that endpoint works before the
//     report row exists. The server allegato ids are then referenced by /submit.
//   - Nothing is sent while offline: the row stays readyToSubmit (visible as pending).
//   - A no-response failure while the device cannot reach the network leaves the row
//     readyToSubmit and consumes NO retry attempt — being offline is never a failed send.
//     Only a server-answered transient (5xx/408/429/401) spends the [maxAutoRetries] budget.
//   - Rows stuck in uploadingMedia/submitting after an app kill are reset to
//     readyToSubmit on startup (recoverInterrupted) — safe because uploads are tracked
//     per allegato and submit is idempotent by key.
//   - A `failed` row with a TRANSIENT cause (transport, 5xx, 408, 429) is retried
//     automatically on every processAll (reconnect / resume / startup) up to
//     [maxAutoRetries]; permanent causes (other 4xx, missing local file) stay failed
//     until the technician taps "Riprova".
// ══════════════════════════════════════════════════════════════════════════════

/// What the technician reads when a submit is refused with a 409 (`concurrency_conflict`): the
/// report was edited in the office after this phone last saw it, so the `expectedVersion` this
/// send carried is stale.
///
/// Written to tell them the two things the generic send failure cannot: **why** this one is
/// different (someone else changed the rapportino — it is not a network glitch), and **not to
/// retry** — a retry carries the same stale version and will 409 again every time — but to call the
/// office. The last sentence reassures them the draft on the device (and their local edits) is
/// still there, because "Invio fallito" otherwise reads as "your signature just vanished".
///
/// There is deliberately no resolution flow yet: the draft stays on the phone, `failed`, intact. A
/// merge / re-import ("take the office's version" vs "keep mine") is a product decision, not
/// something to guess at here — guessing would discard someone's work in one direction or the other.
const String kStaleSubmitConflictMessage =
    'Questo rapportino è stato modificato in ufficio dopo che ne è stata scaricata una copia su '
    'questo telefono. Non riprovare a inviarlo: contatta l\'ufficio per farlo aggiornare. '
    'Quello che hai compilato è ancora salvato sul telefono.';

/// Whether [error] — a draft's persisted `submissionError` — is the stale-submit conflict text
/// above, so a reader can recognise the one failure a retry cannot fix (see the Riepilogo step's
/// failed-send branch, which hides its "Riprova invio" button for exactly this case) without
/// comparing message strings inline.
///
/// Comparing against the const itself is sound, not a shortcut: `_processDraft` writes this very
/// const into the column for a 409, and nothing else can produce that sentence — every other
/// failure path goes through `humanErrorMessage` or the fixed FileSystemException text, neither
/// of which contains it. If that ever stops being the single writer, this identity check is what
/// needs revisiting.
bool isStaleSubmitConflictMessage(String? error) => error == kStaleSubmitConflictMessage;

class SubmissionQueue {
  SubmissionQueue({
    required DraftReportRepository repo,
    required ReportSubmitApiClient apiClient,
    bool Function()? isOnline,
    Future<bool> Function()? recheckOnline,
    Future<List<String>> Function(String cantiereId)? claimedCantiereWorkLogClientIds,
    this.maxAutoRetries = 5,
  }) : _repo = repo,
       _apiClient = apiClient,
       _isOnline = isOnline ?? (() => true),
       _recheckOnline = recheckOnline,
       _claimedCantiereWorkLogClientIds = claimedCantiereWorkLogClientIds;

  final DraftReportRepository _repo;
  final ReportSubmitApiClient _apiClient;
  final bool Function() _isOnline;

  /// Authoritative connectivity probe used when [_isOnline] (a cached provider value that is
  /// false until the first check resolves and is never re-polled) says offline, so a stale
  /// value cannot hold rows forever. Null = no probe: the cached value stands.
  final Future<bool> Function()? _recheckOnline;

  /// The device's own closed cantiere punches for a cantiere, as client ids (P2-6). Null = no
  /// source wired (tests, and any build without local punch storage): the submit then carries no
  /// claims, exactly the pre-P2-6 wire shape.
  final Future<List<String>> Function(String cantiereId)? _claimedCantiereWorkLogClientIds;

  /// Consecutive transient failures after which a `failed` row stops being retried unattended.
  final int maxAutoRetries;

  bool _running = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Mark a draft as ready-to-submit (draft → readyToSubmit).
  /// Idempotent: calling twice is a no-op if already readyToSubmit or beyond.
  Future<void> enqueue(String reportId) async {
    final draft = await _repo.getDraft(reportId);
    if (draft == null) return;

    final currentState = DraftSubmissionState.fromString(draft.submissionState);
    if (currentState == DraftSubmissionState.readyToSubmit ||
        currentState == DraftSubmissionState.uploadingMedia ||
        currentState == DraftSubmissionState.submitting ||
        currentState == DraftSubmissionState.submitted) {
      return; // already queued or done
    }

    // Generate and persist the idempotency key NOW so retries reuse it.
    final key = draft.idempotencyKey ?? const Uuid().v4();
    await _repo.updateSubmissionState(
      reportId: reportId,
      state: DraftSubmissionState.readyToSubmit,
      idempotencyKey: key,
      error: null,
      attempts: 0,
      errorTransient: false,
    );
  }

  /// Startup recovery: puts rows left in `uploadingMedia`/`submitting` by an app kill back to
  /// `readyToSubmit`. Call once, before the first [processAll]. A no-op while this queue is
  /// itself mid-send (e.g. the shell remounted), so it can never reset a live attempt.
  Future<void> recoverInterrupted() async {
    if (_running) return;
    await _repo.resetInterruptedSubmissions();
  }

  /// Process all readyToSubmit drafts plus `failed` drafts with a transient cause and retry
  /// budget left (called on reconnect, app resume, startup and manual trigger). Does nothing
  /// while offline: rows stay `readyToSubmit`. Drafts are processed one at a time; a failure
  /// stops that draft but continues with others.
  ///
  /// [force] is for a manual "Invia"/"Riprova": skip the connectivity gate and just attempt the
  /// network, so a real failure surfaces as a transient `failed` row with its Italian message
  /// instead of a silent no-op. A no-response failure with no reachable network is still not a
  /// failure — the row goes back to `readyToSubmit` (see [_processDraft]). Automatic flushes keep
  /// the gate, but confirm "offline" with a real probe before skipping.
  Future<void> processAll({bool force = false}) async {
    if (_running) return; // prevent re-entrant calls
    if (!force && !await _confirmedOnline()) return;
    if (_running) return; // another caller got in while probing
    _running = true;
    try {
      final ready = [
        ...await _repo.getDraftsReadyToSubmit(),
        ...await _repo.getRetryableFailedDrafts(maxAttempts: maxAutoRetries),
      ];
      for (final draft in ready) {
        await _processDraft(draft);
      }
    } finally {
      _running = false;
    }
  }

  Future<bool> _confirmedOnline() async {
    if (_isOnline()) return true;
    final probe = _recheckOnline;
    if (probe == null) return false;
    try {
      return await probe();
    } catch (_) {
      return false;
    }
  }

  /// Whether the device can actually reach the network, asked authoritatively of the probe.
  ///
  /// Deliberately does NOT trust [_isOnline] first the way [_confirmedOnline] does: that value is
  /// "the interface is up", which is true on a captive portal, a dead Wi-Fi and a radio with no
  /// data. This is the question that decides whether a no-response failure was the device being
  /// offline or the server genuinely not answering, so the cached value is only the fallback when
  /// no probe is wired at all.
  Future<bool> _networkReachable() async {
    final probe = _recheckOnline;
    if (probe == null) return _isOnline();
    try {
      return await probe();
    } catch (_) {
      return false;
    }
  }

  /// Retry a specific failed draft (failed → readyToSubmit, then process).
  Future<void> retry(String reportId) async {
    final draft = await _repo.getDraft(reportId);
    if (draft == null) return;
    if (DraftSubmissionState.fromString(draft.submissionState) != DraftSubmissionState.failed) {
      return;
    }
    // Reuse the existing idempotency key so the server still deduplicates.
    // A manual retry gets a fresh attempt budget.
    await _repo.updateSubmissionState(
      reportId: reportId,
      state: DraftSubmissionState.readyToSubmit,
      error: null,
      attempts: 0,
      errorTransient: false,
    );
    await processAll(force: true);
  }

  // ── Internal processing ────────────────────────────────────────────────────

  Future<void> _processDraft(DraftReport draft) async {
    try {
      // ── Step A: Upload pending allegati ──────────────────────────────────
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.uploadingMedia,
      );

      final pendingAllegati = await _repo.getPendingAllegati(draft.id);

      for (final allegato in pendingAllegati) {
        // A signature-role allegato is identified by comparing its local id against the
        // draft header's own customer/technician signature FK — set once, at capture time,
        // by DraftReportRepository.saveSignature — rather than matching on its file name.
        // Every other pending allegato (photos) is a plain upload.
        final isCustomerSignature = draft.customerSignatureAllegatoId == allegato.id;
        final isTechnicianSignature = draft.technicianSignatureAllegatoId == allegato.id;

        // Signatures ride the generic attachments endpoint with a `kind` (works before the
        // report exists; server stores them as SystemArtifact, out of the Foto list). Photos
        // carry no kind.
        final uploaded = await _apiClient.uploadAttachment(
          reportId: draft.id,
          localPath: allegato.storagePath,
          fileName: allegato.fileName,
          contentType: allegato.contentType,
          kind: isCustomerSignature
              ? 'signature-customer'
              : isTechnicianSignature
              ? 'signature-technician'
              : null,
          capturedLatitude: allegato.capturedLatitude,
          capturedLongitude: allegato.capturedLongitude,
          // Normalize to UTC: drift's default (non-text) DateTime storage round-trips the same
          // instant but drops the UTC flag, which would otherwise make this value's `==`
          // disagree with the UTC value it started as.
          capturedAt: allegato.capturedAt?.toUtc(),
        );
        final serverAllegatoId = uploaded.allegatoId;

        // Mark this allegato as uploaded and store the server id.
        await _repo.markAllegatoUploaded(localId: allegato.id, serverAllegatoId: serverAllegatoId);

        // If this was a signature allegato, update the draft header too.
        if (isCustomerSignature) {
          await _repo.updateSignatureAllegatoId(
            reportId: draft.id,
            isCustomer: true,
            serverAllegatoId: serverAllegatoId,
          );
        } else if (isTechnicianSignature) {
          await _repo.updateSignatureAllegatoId(
            reportId: draft.id,
            isCustomer: false,
            serverAllegatoId: serverAllegatoId,
          );
        }
      }

      // ── Step B: Build SubmitReportRequest ─────────────────────────────────
      await _repo.updateSubmissionState(reportId: draft.id, state: DraftSubmissionState.submitting);

      final freshDraft = await _repo.getDraft(draft.id);
      if (freshDraft == null) return; // shouldn't happen

      final request = await _buildRequest(freshDraft);
      final idempotencyKey = freshDraft.idempotencyKey ?? const Uuid().v4();

      // ── Step C: POST /api/reports/submit ──────────────────────────────────
      await _apiClient.submitReport(request: request, idempotencyKey: idempotencyKey);

      // ── Step D: Mark submitted ────────────────────────────────────────────
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.submitted,
        error: null,
      );
      // Clear the isLocalOnly flag so the list no longer treats this as a local draft.
      await _repo.markSubmitted(draft.id);
    } catch (e) {
      // ── Offline is not a failed send ──────────────────────────────────────
      //
      // A no-response failure (radio down, DNS, timeout — nothing answered at all) while the
      // device has no reachable network is the ordinary state of a technician in a basement, not
      // a rejection. The rapportino is intact and simply has not left the phone yet, so the row
      // goes straight back to `readyToSubmit`: it keeps its place in the queue, keeps its whole
      // retry budget, and shows the calm "In attesa di connessione" state instead of "Invio
      // fallito". Before this, a manual Invia tapped five times in airplane mode burned all five
      // auto-retries and stranded a signed rapportino behind a manual "Riprova".
      //
      // Only a failure the server actually ANSWERED with a retryable status (5xx/408/429/401) is
      // allowed to consume the budget — see [_isServerAnsweredTransient].
      if (_hasNoResponse(e) && !await _networkReachable()) {
        await _repo.updateSubmissionState(
          reportId: draft.id,
          state: DraftSubmissionState.readyToSubmit,
          error: null,
          errorTransient: false,
          attempts: draft.submissionAttempts,
        );
        return;
      }

      final transient = _isTransient(e);
      // NEVER delete the draft on failure — keep it for retry.
      //
      // Humanised here rather than at the point it is drawn, because this column is the *only*
      // thing the Riepilogo step has to explain a failed send: it is read back long after the
      // exception is gone, sometimes on a different day. It used to store `e.toString()`, so the
      // subtitle under "Invio fallito" — the sentence a technician reads when a signed rapportino
      // did not leave the phone — was a Dio stack.
      //
      // A 409 (the stale-submit guard) is special-cased BEFORE humanErrorMessage, not through it:
      // the backend's own `detail` for it is an English "The resource was modified by another
      // process. Please retry.", which humanErrorMessage's _serverSentence would prefer — and
      // "Please retry" is exactly wrong here, since a retry resends the same stale version and is
      // guaranteed to 409 again. See kStaleSubmitConflictMessage.
      final message = e is FileSystemException
          ? 'File non trovato sul dispositivo: una foto o una firma non è più disponibile. '
                'Rimuovila dal rapportino e riprova.'
          : _isStaleSubmitConflict(e)
          ? kStaleSubmitConflictMessage
          : humanErrorMessage(e, azione: 'inviare il rapportino');
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.failed,
        error: message,
        errorTransient: transient,
        // Only a server-answered transient consumes the auto-retry budget; a permanent failure is
        // never auto-retried, and a no-response one the server never answered must not be able to
        // spend a technician's retries either (see [_isServerAnsweredTransient]).
        attempts: _isServerAnsweredTransient(e)
            ? draft.submissionAttempts + 1
            : draft.submissionAttempts,
      );
    }
  }

  /// Whether retrying the same request unattended could plausibly succeed: no response at all
  /// (radio/timeout), a server fault (5xx), or explicit back-pressure (408/429). Everything else
  /// — other 4xx, a missing local file, a programming error — needs the technician.
  /// 401 counts as transient: the auth interceptor's silent refresh can leave the original 401
  /// surfacing when the refresh failed for a non-definitive reason; the retry cap bounds it.
  static bool _isTransient(Object e) {
    if (e is! DioException) return false;
    final status = e.response?.statusCode;
    if (status == null) return e.type != DioExceptionType.badResponse;
    return status >= 500 || status == 401 || status == 408 || status == 429;
  }

  /// A failure with no HTTP response at all: the request never reached a server that answered.
  /// That covers connectionError, connection/send/receive timeouts and a cancelled request — the
  /// shapes a device with no usable network produces.
  static bool _hasNoResponse(Object e) =>
      e is DioException && e.response?.statusCode == null;

  /// A transient the SERVER answered: a fault (5xx), back-pressure (408/429), or a 401 whose
  /// silent refresh may not have taken. This is the only class that spends the retry budget —
  /// the server is reachable, so "five attempts" is a real signal, not a measure of how often the
  /// radio flapped.
  static bool _isServerAnsweredTransient(Object e) {
    if (e is! DioException) return false;
    final status = e.response?.statusCode;
    if (status == null) return false;
    return status >= 500 || status == 401 || status == 408 || status == 429;
  }

  /// Whether [e] is the stale-submit `409 concurrency_conflict`: the report was edited (in the
  /// office, or on another device) after this phone last saw its version, so the `expectedVersion`
  /// this submit carried no longer matches. Permanent (see [_isTransient]), never auto-retried.
  ///
  /// ASSUMPTION, to revisit rather than to trust: this keys on the status code alone, which is
  /// only correct while the conflict is the *only* 409 this flow can get. That holds today — a
  /// rejection for any other reason (already Inviato, wrong state) is a 400 — but a future 409
  /// from another step (an attachment upload, say) would be mislabelled as the stale-submit
  /// conflict and handed [kStaleSubmitConflictMessage], which tells the technician not to retry
  /// something an unattended retry would in fact have fixed. If a second 409 source is ever
  /// added, discriminate on the response body's `code` (`concurrency_conflict`), not the status.
  static bool _isStaleSubmitConflict(Object e) =>
      e is DioException && e.response?.statusCode == HttpStatus.conflict;

  Future<SubmitReportRequest> _buildRequest(DraftReport draft) async {
    final staff = await _repo.getStaff(draft.id);
    final materiali = await _repo.getMateriali(draft.id);
    final controlli = await _repo.getControlli(draft.id);
    final allegati = await _repo.getAllegati(draft.id);

    // Instruments: only the selection authored on this device. A draft whose Strumenti step was
    // never opened has none, and an empty list tells the server to keep the rows it holds. The
    // calibration expiry is the catalogue's (fresher than the snapshot saved on the row); it is
    // used ONLY to decide expiredAcknowledged, `expiredAtUse` is never sent.
    final localStrumenti = await _repo.getLocalStrumenti(draft.id);
    final catalogue = {for (final s in await _repo.getStrumentiCatalogue()) s.id: s};
    final strumenti = buildStrumentiBody([
      for (final r in localStrumenti)
        if (r.strumentoId != null)
          StrumentoSelectionInput(
            strumentoId: r.strumentoId!,
            calibrationExpiry: catalogue.containsKey(r.strumentoId)
                ? catalogue[r.strumentoId]!.calibrationExpiry
                : r.calibrationExpiry,
            expiredAcknowledged: r.expiredAcknowledged,
            usageDescription: r.usageDescription,
            outcome: r.outcome,
          ),
    ], workDateLabel(draft.startedAt, draft.createdAt));

    // Photo allegati (non-signature, non-pending)
    final signatureIds = {
      draft.customerSignatureAllegatoId,
      draft.technicianSignatureAllegatoId,
    }.whereType<String>().toSet();

    final photoIds = allegati
        .where((a) => !signatureIds.contains(a.id) && !a.isPendingUpload)
        .map((a) => a.id)
        .toList();

    // P2-6: a rapportino drafted from a cantiere carries that cantiere, and claims the phone's own
    // closed punches for it so the server can mark those hours consumed instead of letting the next
    // cantiere-originated rapportino count them a second time. Best-effort: a local read failure
    // must never block a submit — the server treats an empty claim list as "nothing to claim".
    var claimedCantierePunchIds = const <String>[];
    final claimSource = _claimedCantiereWorkLogClientIds;
    if (draft.cantiereId != null && claimSource != null) {
      try {
        claimedCantierePunchIds = await claimSource(draft.cantiereId!);
      } catch (_) {
        // Fall through with no claims; the submit itself is what matters.
      }
    }

    return SubmitReportRequest(
      id: draft.id,
      cantiereId: draft.cantiereId,
      consumedCantiereWorkLogClientIds: claimedCantierePunchIds,
      // The version captured when this device last SAW the server's copy (import / cantiere-create),
      // read straight off the persisted draft. Read here, never fetched: a version fetched at submit
      // time would always match the row being compared and the guard would be inert. Null for a
      // draft that has never been on the server → the request omits it and the server skips the check.
      expectedVersion: draft.expectedVersion,
      scheduleId: draft.scheduleId,
      ticketId: draft.ticketId,
      locationId: draft.locationId,
      title: draft.title,
      details: draft.details,
      diagnosi: draft.diagnosi,
      soluzione: draft.soluzione,
      technicianNotes: draft.technicianNotes,
      startedAt: draft.startedAt,
      endedAt: draft.endedAt,
      customerSignatureAllegatoId: draft.customerSignatureAllegatoId,
      technicianSignatureAllegatoId: draft.technicianSignatureAllegatoId,
      customerSignoffText: draft.customerSignoffText,
      materialiNotRequired: draft.materialiNotRequired,
      aiAssisted: draft.isAiAssisted,
      richiedeSecondoIntervento: draft.richiedeSecondoIntervento,
      photoAllegatoIds: photoIds,
      strumenti: strumenti,
      staff: staff
          .map(
            (s) => SubmitReportStaffDto(
              userId: s.userId,
              hoursWorked: s.hoursWorked,
              kmTraveled: s.kmTraveled,
              vehicle: s.vehicle,
              costPerKm: s.costPerKm,
              notes: s.notes,
              startTime: s.startTime,
              endTime: s.endTime,
              pauseMinutes: s.pauseMinutes,
            ),
          )
          .toList(),
      materiali: materiali
          .map(
            (m) => SubmitReportMaterialeDto(
              materialeId: m.materialeId,
              freeTextName: m.freeTextName,
              quantity: m.quantity,
              unitOfMeasure: m.unitOfMeasure,
              // Backend ReportSubmitService builds each ReportMateriale with `UnitPrice =
              // m.UnitPrice` from this request, and submit REPLACES the materials: omitting it
              // would null a price the server (or an import) already holds. The editor never
              // edits it, so the local value is the server's.
              unitPrice: m.unitPrice,
              notes: m.notes,
              magazzinoId: m.magazzinoId,
            ),
          )
          .toList(),
      controlli: controlli
          .map(
            (c) => SubmitReportControlloDto(
              ticketControlId: c.controlId,
              stringValue: c.stringValue,
              boolValue: c.boolValue,
              dateValue: c.dateValue,
              numberValue: c.numberValue,
            ),
          )
          .toList(),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Riverpod provider
// ══════════════════════════════════════════════════════════════════════════════

final submissionQueueProvider = Provider<SubmissionQueue>((ref) {
  throw UnimplementedError('submissionQueueProvider must be overridden in ProviderScope');
});
