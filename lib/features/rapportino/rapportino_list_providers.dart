// dart format width=100
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/sync/draft_submission_state.dart';
import '../../presentation/providers/report_editor_providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Rapportino list providers (D3b)
//
// Drives RapportiniListScreen and RapportinoViewScreen.
// Only local DraftReports are cached; server lifecycle (Pagata/Annullato) is
// not synced back to the device yet.
// ══════════════════════════════════════════════════════════════════════════════

/// Stream of all local drafts (isLocalOnly == true), newest first.
final rapportiniListProvider =
    StreamProvider.autoDispose<List<DraftReport>>((ref) {
  final repo = ref.watch(draftReportRepositoryProvider);
  return repo.watchLocalDrafts();
});

/// Stream a single draft by id — for the view screen.
final rapportinoByIdProvider =
    StreamProvider.autoDispose.family<DraftReport?, String>((ref, reportId) {
  final repo = ref.watch(draftReportRepositoryProvider);
  return repo.watchDraft(reportId);
});

/// Stream staff rows for a given report.
final rapportinoStaffProvider =
    StreamProvider.autoDispose.family<List<ReportStaffTableData>, String>(
  (ref, reportId) {
    final repo = ref.watch(draftReportRepositoryProvider);
    return repo.watchStaff(reportId);
  },
);

/// Stream materiali rows for a given report.
final rapportinoMaterialiProvider =
    StreamProvider.autoDispose.family<List<ReportMaterialiData>, String>(
  (ref, reportId) {
    final repo = ref.watch(draftReportRepositoryProvider);
    return repo.watchMateriali(reportId);
  },
);

/// Derived: total ore from staff rows for a given report.
/// Returns a formatted string like "3h 30min" or "—".
final rapportinoOreProvider =
    Provider.autoDispose.family<String, String>((ref, reportId) {
  final staffAsync = ref.watch(rapportinoStaffProvider(reportId));
  return staffAsync.when(
    loading: () => '—',
    error: (e, s) => '—',
    data: (rows) {
      final totalMinutes = rows.fold<double>(
        0,
        (acc, r) {
          if (r.startTime != null && r.endTime != null) {
            final worked =
                r.endTime!.difference(r.startTime!).inMinutes - r.pauseMinutes;
            return acc + worked;
          }
          return acc + ((r.hoursWorked ?? 0.0) * 60.0);
        },
      );
      if (totalMinutes <= 0) return '—';
      final h = totalMinutes ~/ 60;
      final m = (totalMinutes % 60).round();
      if (m == 0) return '${h}h';
      return '${h}h ${m}min';
    },
  );
});

// ══════════════════════════════════════════════════════════════════════════════
// Status-name resolver
//
// Maps submissionState + stato → Italian label for the StatusPill.
// submitted  → "Inviata"
// draft/readyToSubmit/failed  → "Bozza"
// uploadingMedia/submitting   → "Invio…"
// ══════════════════════════════════════════════════════════════════════════════

/// Returns the Italian status label shown in the StatusPill for a draft.
String rapportinoStatusLabel(DraftReport draft) {
  final sub = DraftSubmissionState.fromString(draft.submissionState);
  return switch (sub) {
    DraftSubmissionState.submitted => 'Inviata',
    DraftSubmissionState.uploadingMedia => 'Invio…',
    DraftSubmissionState.submitting => 'Invio…',
    _ => 'Bozza',
  };
}

/// Returns true when the draft is submitted (read-only view mode).
bool rapportinoIsSubmitted(DraftReport draft) {
  return DraftSubmissionState.fromString(draft.submissionState) ==
      DraftSubmissionState.submitted;
}

/// Returns true when the draft is in-flight (uploading or submitting).
bool rapportinoIsInFlight(DraftReport draft) {
  final sub = DraftSubmissionState.fromString(draft.submissionState);
  return sub == DraftSubmissionState.uploadingMedia ||
      sub == DraftSubmissionState.submitting;
}
