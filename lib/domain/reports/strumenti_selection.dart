// dart format width=100
import '../../data/reports/submit_report_request.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Strumenti selection rules (pure)
//
// Mirror of the web's `strumentiSelection.ts` / `expiry.ts`. The server recomputes expiry from the
// report's work date and wins; this is only the local hint that decides whether the technician must
// acknowledge an expired instrument, and what `expiredAcknowledged` the submit body carries.
// ══════════════════════════════════════════════════════════════════════════════

/// The civil work date of a report: the calendar day it started (device-local), falling back to the
/// day the draft was created. A DateTime would drift by a day across timezones if compared as an
/// instant, so everything below compares 'yyyy-MM-dd' strings.
String workDateLabel(DateTime? startedAt, DateTime createdAt) {
  final d = (startedAt ?? createdAt).toLocal();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Server rule: expired at use = expiry != null AND expiry < work date (valid THROUGH its expiry
/// day). Both arguments are 'yyyy-MM-dd' civil dates; anything unparseable is "not expired".
bool isStrumentoExpiredOn(String? calibrationExpiry, String workDate) {
  final e = _civil(calibrationExpiry);
  final w = _civil(workDate);
  if (e == null || w == null) return false;
  return e.compareTo(w) < 0;
}

final _civilRe = RegExp(r'^\d{4}-\d{2}-\d{2}');

String? _civil(String? v) {
  if (v == null) return null;
  final m = _civilRe.firstMatch(v);
  return m?.group(0);
}

/// The local row id of one instrument's selection on [reportId].
///
/// Deterministic on purpose: the editor's Strumenti step, the AI apply and the pre-fill all address
/// the same row, so a second selection for the same catalogue instrument can never appear as a
/// duplicate line in the submit body. The one place that spelling lives.
String strumentoRowId(String reportId, String strumentoId) => 'str-$reportId-$strumentoId';

/// One selected instrument as the submit builder sees it.
class StrumentoSelectionInput {
  const StrumentoSelectionInput({
    required this.strumentoId,
    required this.calibrationExpiry,
    required this.expiredAcknowledged,
    this.usageDescription,
    this.outcome,
  });

  final String strumentoId;
  final String? calibrationExpiry;
  final bool expiredAcknowledged;
  final String? usageDescription;
  final String? outcome;
}

/// The `strumenti` of the submit body. Never carries `expiredAtUse`; the acknowledgement is only
/// ever true for an instrument that is expired on [workDate] (a valid one with a true flag is a
/// 422). Duplicates collapse to the first occurrence.
List<SubmitReportStrumentoDto> buildStrumentiBody(
  Iterable<StrumentoSelectionInput> rows,
  String workDate,
) {
  final seen = <String>{};
  final out = <SubmitReportStrumentoDto>[];
  for (final r in rows) {
    if (!seen.add(r.strumentoId)) continue;
    final expired = isStrumentoExpiredOn(r.calibrationExpiry, workDate);
    out.add(
      SubmitReportStrumentoDto(
        strumentoId: r.strumentoId,
        expiredAcknowledged: expired ? r.expiredAcknowledged : false,
        usageDescription: r.usageDescription,
        outcome: r.outcome,
      ),
    );
  }
  return out;
}
