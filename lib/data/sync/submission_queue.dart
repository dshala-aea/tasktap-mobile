// dart format width=100
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/error_message.dart';
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
//   - Rows stuck in uploadingMedia/submitting after an app kill are reset to
//     readyToSubmit on startup (recoverInterrupted) — safe because uploads are tracked
//     per allegato and submit is idempotent by key.
//   - A `failed` row with a TRANSIENT cause (transport, 5xx, 408, 429) is retried
//     automatically on every processAll (reconnect / resume / startup) up to
//     [maxAutoRetries]; permanent causes (other 4xx, missing local file) stay failed
//     until the technician taps "Riprova".
// ══════════════════════════════════════════════════════════════════════════════

class SubmissionQueue {
  SubmissionQueue({
    required DraftReportRepository repo,
    required ReportSubmitApiClient apiClient,
    bool Function()? isOnline,
    Future<bool> Function()? recheckOnline,
    this.maxAutoRetries = 5,
  }) : _repo = repo,
       _apiClient = apiClient,
       _isOnline = isOnline ?? (() => true),
       _recheckOnline = recheckOnline;

  final DraftReportRepository _repo;
  final ReportSubmitApiClient _apiClient;
  final bool Function() _isOnline;

  /// Authoritative connectivity probe used when [_isOnline] (a cached provider value that is
  /// false until the first check resolves and is never re-polled) says offline, so a stale
  /// value cannot hold rows forever. Null = no probe: the cached value stands.
  final Future<bool> Function()? _recheckOnline;

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
  /// instead of a silent no-op. Automatic flushes keep the gate, but confirm "offline" with a
  /// real probe before skipping.
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
      final transient = _isTransient(e);
      // NEVER delete the draft on failure — keep it for retry.
      //
      // Humanised here rather than at the point it is drawn, because this column is the *only*
      // thing the Riepilogo step has to explain a failed send: it is read back long after the
      // exception is gone, sometimes on a different day. It used to store `e.toString()`, so the
      // subtitle under "Invio fallito" — the sentence a technician reads when a signed rapportino
      // did not leave the phone — was a Dio stack.
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.failed,
        error: e is FileSystemException
            ? 'File non trovato sul dispositivo: una foto o una firma non è più disponibile. '
                  'Rimuovila dal rapportino e riprova.'
            : humanErrorMessage(e, azione: 'inviare il rapportino'),
        errorTransient: transient,
        // Only transient failures consume the auto-retry budget; permanent ones are never
        // auto-retried, so their counter is irrelevant.
        attempts: transient ? draft.submissionAttempts + 1 : draft.submissionAttempts,
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

  Future<SubmitReportRequest> _buildRequest(DraftReport draft) async {
    final staff = await _repo.getStaff(draft.id);
    final materiali = await _repo.getMateriali(draft.id);
    final controlli = await _repo.getControlli(draft.id);
    final allegati = await _repo.getAllegati(draft.id);

    // Photo allegati (non-signature, non-pending)
    final signatureIds = {
      draft.customerSignatureAllegatoId,
      draft.technicianSignatureAllegatoId,
    }.whereType<String>().toSet();

    final photoIds = allegati
        .where((a) => !signatureIds.contains(a.id) && !a.isPendingUpload)
        .map((a) => a.id)
        .toList();

    return SubmitReportRequest(
      id: draft.id,
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
