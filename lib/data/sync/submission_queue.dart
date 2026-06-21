// dart format width=100
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

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
// ══════════════════════════════════════════════════════════════════════════════

class SubmissionQueue {
  SubmissionQueue({
    required DraftReportRepository repo,
    required ReportSubmitApiClient apiClient,
  })  : _repo = repo,
        _apiClient = apiClient;

  final DraftReportRepository _repo;
  final ReportSubmitApiClient _apiClient;

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
    );
  }

  /// Process all readyToSubmit drafts (called on reconnect or manual trigger).
  /// Drafts are processed one at a time; a failure stops that draft but
  /// continues with others.
  Future<void> processAll() async {
    if (_running) return; // prevent re-entrant calls
    _running = true;
    try {
      final ready = await _repo.getDraftsReadyToSubmit();
      for (final draft in ready) {
        await _processDraft(draft);
      }
    } finally {
      _running = false;
    }
  }

  /// Retry a specific failed draft (failed → readyToSubmit, then process).
  Future<void> retry(String reportId) async {
    final draft = await _repo.getDraft(reportId);
    if (draft == null) return;
    if (DraftSubmissionState.fromString(draft.submissionState) !=
        DraftSubmissionState.failed) {
      return;
    }
    // Reuse the existing idempotency key so the server still deduplicates.
    await _repo.updateSubmissionState(
      reportId: reportId,
      state: DraftSubmissionState.readyToSubmit,
      error: null,
    );
    await processAll();
  }

  // ── Internal processing ────────────────────────────────────────────────────

  Future<void> _processDraft(DraftReport draft) async {
    try {
      // ── Step A: Upload pending allegati ──────────────────────────────────
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.uploadingMedia,
      );

      final pendingAllegati =
          await _repo.getPendingAllegati(draft.id);

      for (final allegato in pendingAllegati) {
        final uploaded = await _apiClient.uploadAttachment(
          reportId: draft.id,
          localPath: allegato.storagePath,
          fileName: allegato.fileName,
          contentType: allegato.contentType,
        );

        // Mark this allegato as uploaded and store the server id.
        await _repo.markAllegatoUploaded(
          localId: allegato.id,
          serverAllegatoId: uploaded.allegatoId,
        );

        // If this was a signature allegato, update the draft header too.
        final draftNow = await _repo.getDraft(draft.id);
        if (draftNow != null) {
          if (draftNow.customerSignatureAllegatoId == allegato.id) {
            await _repo.updateSignatureAllegatoId(
              reportId: draft.id,
              isCustomer: true,
              serverAllegatoId: uploaded.allegatoId,
            );
          } else if (draftNow.technicianSignatureAllegatoId == allegato.id) {
            await _repo.updateSignatureAllegatoId(
              reportId: draft.id,
              isCustomer: false,
              serverAllegatoId: uploaded.allegatoId,
            );
          }
        }
      }

      // ── Step B: Build SubmitReportRequest ─────────────────────────────────
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.submitting,
      );

      final freshDraft = await _repo.getDraft(draft.id);
      if (freshDraft == null) return; // shouldn't happen

      final request = await _buildRequest(freshDraft);
      final idempotencyKey =
          freshDraft.idempotencyKey ?? const Uuid().v4();

      // ── Step C: POST /api/reports/submit ──────────────────────────────────
      await _apiClient.submitReport(
        request: request,
        idempotencyKey: idempotencyKey,
      );

      // ── Step D: Mark submitted ────────────────────────────────────────────
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.submitted,
        error: null,
      );
      // Clear the isLocalOnly flag so the list no longer treats this as a local draft.
      await _repo.markSubmitted(draft.id);
    } catch (e) {
      // NEVER delete the draft on failure — keep it for retry.
      await _repo.updateSubmissionState(
        reportId: draft.id,
        state: DraftSubmissionState.failed,
        error: e.toString(),
      );
    }
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
        .where((a) =>
            !signatureIds.contains(a.id) && !a.isPendingUpload)
        .map((a) => a.id)
        .toList();

    return SubmitReportRequest(
      id: draft.id,
      scheduleId: draft.scheduleId,
      ticketId: draft.ticketId,
      locationId: draft.locationId,
      title: draft.title,
      details: draft.details,
      technicianNotes: draft.technicianNotes,
      startedAt: draft.startedAt,
      endedAt: draft.endedAt,
      customerSignatureAllegatoId: draft.customerSignatureAllegatoId,
      technicianSignatureAllegatoId: draft.technicianSignatureAllegatoId,
      customerSignoffText: draft.customerSignoffText,
      materialiNotRequired: draft.materialiNotRequired,
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
              notes: m.notes,
              magazzinoId: m.magazzinoId,
            ),
          )
          .toList(),
      controlli: controlli
          .map(
            (c) => SubmitReportControlloDto(
              controlId: c.controlId,
              stringValue: c.stringValue,
              boolValue: c.boolValue,
              dateValue: c.dateValue,
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
  throw UnimplementedError(
      'submissionQueueProvider must be overridden in ProviderScope');
});
