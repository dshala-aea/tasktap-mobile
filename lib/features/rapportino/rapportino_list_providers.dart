// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/draft_submission_state.dart';
import '../../presentation/providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Rapportino list providers (D3b)
//
// Drives RapportiniListScreen and RapportinoViewScreen.
//
// The full server lifecycle (Inviato/Controllato/Fatturato/Respinto/Annullato) now syncs back to
// the device — see SyncService's `submittedReports` upsert (sync_service.dart) — so this reads
// every report the device knows about, not just still-local drafts. See
// `DraftReportRepository.watchAllReports` for why no `isLocalOnly` filter is needed here.
// ══════════════════════════════════════════════════════════════════════════════

/// Stream of every report this technician has locally — drafts and synced-down submitted
/// reports alike — newest first.
final rapportiniListProvider = StreamProvider.autoDispose<List<DraftReport>>((ref) {
  final repo = ref.watch(draftReportRepositoryProvider);
  return repo.watchAllReports();
});

/// Stream a single draft by id — for the view screen.
final rapportinoByIdProvider = StreamProvider.autoDispose.family<DraftReport?, String>((
  ref,
  reportId,
) {
  final repo = ref.watch(draftReportRepositoryProvider);
  return repo.watchDraft(reportId);
});

/// Stream staff rows for a given report.
final rapportinoStaffProvider = StreamProvider.autoDispose
    .family<List<ReportStaffTableData>, String>((ref, reportId) {
      final repo = ref.watch(draftReportRepositoryProvider);
      return repo.watchStaff(reportId);
    });

/// Stream materiali rows for a given report.
final rapportinoMaterialiProvider = StreamProvider.autoDispose
    .family<List<ReportMaterialiData>, String>((ref, reportId) {
      final repo = ref.watch(draftReportRepositoryProvider);
      return repo.watchMateriali(reportId);
    });

/// Stream every allegato (photos + signatures) for a given report — used by
/// RapportinoViewScreen to show what Step 6 attached and to resolve the customer signature's
/// actual image instead of a placeholder. `watchAllegati` filters by `entityId == reportId`
/// alone, so this list mixes photo and signature rows together; callers separate them by
/// matching id against `DraftReport.customerSignatureAllegatoId`.
final rapportinoAllegatiProvider = StreamProvider.autoDispose
    .family<List<ReportAllegatiData>, String>((ref, reportId) {
      final repo = ref.watch(draftReportRepositoryProvider);
      return repo.watchAllegati(reportId);
    });

/// Derived: total ore from staff rows for a given report.
/// Returns a formatted string like "3h 30min" or "—".
final rapportinoOreProvider = Provider.autoDispose.family<String, String>((ref, reportId) {
  final staffAsync = ref.watch(rapportinoStaffProvider(reportId));
  return staffAsync.when(
    loading: () => '—',
    error: (e, s) => '—',
    data: (rows) {
      final totalMinutes = rows.fold<double>(0, (acc, r) {
        if (r.startTime != null && r.endTime != null) {
          final worked = r.endTime!.difference(r.startTime!).inMinutes - r.pauseMinutes;
          return acc + worked;
        }
        return acc + ((r.hoursWorked ?? 0.0) * 60.0);
      });
      if (totalMinutes <= 0) return '—';
      final h = totalMinutes ~/ 60;
      final m = (totalMinutes % 60).round();
      if (m == 0) return '${h}h';
      return '${h}h ${m}min';
    },
  );
});

/// Combines staff count, materiali count, and the ore label for one report into a single
/// watch — see `_RapportinoRow.build` (rapportini_list_screen.dart), which used to `ref.watch`
/// [rapportinoStaffProvider], [rapportinoMaterialiProvider], and [rapportinoOreProvider]
/// separately per row. Purely additive: the three providers above are untouched, so
/// `RapportinoViewScreen` (which still watches them individually) is unaffected.
class RapportinoRowSummary {
  const RapportinoRowSummary({
    required this.staffCount,
    required this.materialiCount,
    required this.oreLabel,
  });

  final int staffCount;
  final int materialiCount;
  final String oreLabel;
}

final rapportinoRowSummaryProvider = Provider.autoDispose.family<RapportinoRowSummary, String>((
  ref,
  reportId,
) {
  final staffAsync = ref.watch(rapportinoStaffProvider(reportId));
  final materialiAsync = ref.watch(rapportinoMaterialiProvider(reportId));
  final oreLabel = ref.watch(rapportinoOreProvider(reportId));
  return RapportinoRowSummary(
    staffCount: staffAsync.valueOrNull?.length ?? 0,
    materialiCount: materialiAsync.valueOrNull?.length ?? 0,
    oreLabel: oreLabel,
  );
});

// ══════════════════════════════════════════════════════════════════════════════
// Status-name resolver
//
// Maps submissionState + stato → Italian label for the StatusPill.
// uploadingMedia/submitting → "Invio…" (local, in-flight — no server stato yet)
// stato == Respinto         → "Respinta"
// stato == Controllato      → "Controllato"
// stato == Fatturato        → "Pagata"
// stato == Annullato        → "Annullato"
// submissionState==submitted OR stato==Inviato → "Inviata"
// everything else           → "Bozza"
//
// `stato` is checked first for the four states past "submitted" because it — not the local
// `submissionState` — is the field SyncService's `submittedReports` upsert keeps current: a
// report this device never itself submitted (or one the office has since moved further along —
// rejected, checked, invoiced) needs the right label regardless of what `submissionState` this
// device last recorded for it. "Inviata" falls back to `submissionState == submitted` alongside
// `stato == Inviato` because the two are set together by `markSubmitted` on this device but a
// sync only ever touches `stato`, never `submissionState` (see SyncService._upsertDraftReports) —
// requiring both would make a report this device submitted, and that has not been touched by the
// office since, momentarily read as "Bozza" between submit and the next sync.
// ══════════════════════════════════════════════════════════════════════════════

/// Returns the Italian status label shown in the StatusPill for a draft.
String rapportinoStatusLabel(DraftReport draft) {
  final sub = DraftSubmissionState.fromString(draft.submissionState);
  if (sub == DraftSubmissionState.uploadingMedia || sub == DraftSubmissionState.submitting) {
    return 'Invio…';
  }
  switch (draft.stato) {
    case 'Respinto':
      return 'Respinta';
    case 'Controllato':
      return 'Controllato';
    case 'Fatturato':
      return 'Pagata';
    case 'Annullato':
      return 'Annullato';
  }
  if (sub == DraftSubmissionState.submitted || draft.stato == 'Inviato') {
    return 'Inviata';
  }
  return 'Bozza';
}

/// Returns true once the report has left the draft state — either this device submitted it
/// (`submissionState == submitted`) or a sync learned it left `Bozza` some other way — so the
/// list should route to the read-only view instead of the editor.
bool rapportinoIsSubmitted(DraftReport draft) {
  if (DraftSubmissionState.fromString(draft.submissionState) == DraftSubmissionState.submitted) {
    return true;
  }
  return draft.stato != 'Bozza';
}

/// Returns true when the draft is in-flight (uploading or submitting).
bool rapportinoIsInFlight(DraftReport draft) {
  final sub = DraftSubmissionState.fromString(draft.submissionState);
  return sub == DraftSubmissionState.uploadingMedia || sub == DraftSubmissionState.submitting;
}

/// Returns true when the office rejected this report (`Inviato → Respinto`) — the case that
/// needs a rework affordance rather than a plain read-only view. See `createReworkDraft`
/// (create_draft.dart) and RapportinoViewScreen's rejection banner.
bool rapportinoIsRejected(DraftReport draft) => draft.stato == 'Respinto';
