// dart format width=100
import 'package:drift/drift.dart' show Value;

import '../../core/time/business_time.dart' show formatDateOnly;
import '../../data/ai/ai_api_client.dart';
import '../../data/local/app_database.dart';
import '../../data/reports/draft_report_repository.dart';
import '../../domain/reports/strumenti_selection.dart' show strumentoRowId;

/// One instrument the copilot says was used, reduced to what persisting it needs — so the draft
/// turn path and the Confirm path share one writer instead of two copies of the same rules.
class AiStrumentoLine {
  const AiStrumentoLine({
    required this.strumentoId,
    required this.name,
    this.matricola,
    this.calibrationExpiry,
    this.expiredAtUse = false,
    this.expiredAcknowledged = false,
    this.usageDescription,
    this.outcome,
    this.knowsExpiry = false,
  });

  final String strumentoId;
  final String name;
  final String? matricola;
  final DateTime? calibrationExpiry;

  /// The server's verdict for the job's date. Display only — the submit body never carries it, and
  /// the editor recomputes expiry from the catalogue against the report's own work date.
  final bool expiredAtUse;
  final bool expiredAcknowledged;

  /// Whether this line carries the server's expiry verdict for the job's date. Only Confirm does:
  /// the draft has no work date to judge against. A line that does not know must leave the stored
  /// verdict and the technician's acknowledgement exactly as they are.
  final bool knowsExpiry;
  final String? usageDescription;
  final String? outcome;

  /// A resolved Confirm line: the id was checked against the tenant by the server and the expiry
  /// verdict was computed against the work date the preflight derived.
  factory AiStrumentoLine.fromResolved(AiResolvedStrumento s) => AiStrumentoLine(
    strumentoId: s.strumentoId,
    name: s.name,
    matricola: s.matricola,
    calibrationExpiry: s.calibrationExpiry,
    expiredAtUse: s.expiredAtUse,
    expiredAcknowledged: s.expiredAcknowledged,
    knowsExpiry: true,
    usageDescription: s.usageDescription,
    outcome: s.outcome,
  );

  /// A draft line, while the conversation is still running. `strumentoId` is empty unless the model
  /// obtained it from `search_strumenti`, and the draft carries no expiry: the local catalogue is
  /// what the editor reads expiry from anyway, so the line is written without one.
  ///
  /// A line still `needsConfirmation` (or ambiguous/conflicting) is not written: the same rule the
  /// feed applies to workers and materials — a proposal the technician has not accepted is not work
  /// that was done.
  static List<AiStrumentoLine> fromDraft(AiCopilotDraftDto draft) => [
    for (final s in draft.strumenti)
      if (s.strumentoId.isNotEmpty &&
          s.state != AiResolutionState.needsConfirmation &&
          s.state != AiResolutionState.ambiguous &&
          s.state != AiResolutionState.conflict)
        AiStrumentoLine(
          strumentoId: s.strumentoId,
          name: s.name,
          matricola: s.matricola,
          expiredAcknowledged: s.expiredAcknowledged,
          usageDescription: s.usageDescription,
          outcome: s.outcome,
        ),
  ];
}

/// Writes the copilot's instruments into [reportId] as this device's own selection.
///
/// This is the mobile half of the server's instruments slice: Confirm resolves each id against the
/// tenant and returns the calibration snapshot, and the report's instrument lines are the client's
/// to write (Confirm persists nothing). Rows land in `report_strumenti` with `isLocal` true and the
/// deterministic row id the editor's Strumenti step uses, so the step shows them as selected, the
/// technician can acknowledge/annotate them there, and the submit builder sends them.
///
/// What it deliberately does NOT do:
/// - insert a line whose `strumentoId` is empty: a dictated name no lookup resolved is the
///   technician's to pick in the step, and inventing an id is the one thing the copilot must never do;
/// - overwrite what the technician typed: an existing row keeps its `usageDescription` / `outcome`
///   when the line has none, and keeps an acknowledgement it already carries;
/// - remove a row: dropping an instrument is the technician's call, and a later turn saying nothing
///   about an instrument is not a statement that it was not used.
///
/// `strumentiPrefilled` is set with the write (one transaction), so the step's one-time kit pre-fill
/// cannot later add the whole kit over the selection the copilot just made.
///
/// An expired line is written with the server's verdict and whatever acknowledgement it carried. If
/// it carried none, the step's `unacknowledgedExpired` banner asks the technician to confirm, and
/// the server refuses the submit until they do — never silently dropped, never silently accepted.
Future<void> writeAiStrumenti(
  DraftReportRepository repo, {
  required String reportId,
  required Iterable<AiStrumentoLine> lines,
}) async {
  final existing = {
    for (final r in await repo.getLocalStrumenti(reportId))
      if (r.strumentoId != null) r.strumentoId!: r,
  };
  final seen = <String>{};
  final rows = <ReportStrumentiCompanion>[];
  for (final l in lines) {
    if (l.strumentoId.isEmpty || !seen.add(l.strumentoId)) continue;
    final old = existing[l.strumentoId];
    rows.add(
      ReportStrumentiCompanion.insert(
        id: old?.id ?? strumentoRowId(reportId, l.strumentoId),
        reportId: reportId,
        strumentoId: Value(l.strumentoId),
        name: l.name.trim().isEmpty ? (old?.name ?? '') : l.name,
        matricola: l.matricola ?? old?.matricola ?? '',
        // The draft path has no expiry (`null`), so the row keeps whatever the catalogue pre-fill
        // or an earlier Confirm already stored rather than blanking it.
        calibrationExpiry: Value(formatDateOnly(l.calibrationExpiry) ?? old?.calibrationExpiry),
        certificateReference: Value(old?.certificateReference),
        // A draft line does not know the work date, so it never overrides the pair an earlier
        // Confirm stored.
        expiredAtUse: Value(l.knowsExpiry ? l.expiredAtUse : (old?.expiredAtUse ?? false)),
        // A valid instrument never carries an acknowledgement (the submit is a 422 otherwise), and
        // the technician's acknowledgement of an expired one is never undone by a later turn.
        expiredAcknowledged: Value(
          l.knowsExpiry
              ? l.expiredAtUse && ((old?.expiredAcknowledged ?? false) || l.expiredAcknowledged)
              : (old?.expiredAcknowledged ?? false),
        ),
        isLocal: const Value(true),
        usageDescription: Value(_preferLine(l.usageDescription, old?.usageDescription)),
        outcome: Value(_preferLine(l.outcome, old?.outcome)),
      ),
    );
  }
  if (rows.isEmpty) return;
  await repo.seedLocalStrumenti(reportId, rows, markPrefilled: true);
}

/// The line's text, unless it says nothing — then what the row already holds.
String? _preferLine(String? line, String? stored) =>
    (line ?? '').trim().isEmpty ? stored : line;
