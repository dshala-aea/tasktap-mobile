// dart format width=100
import '../../data/local/app_database.dart';

// ══════════════════════════════════════════════════════════════════════════════
// DraftValidation
//
// Mirrors the server-side ReportStateMachine rules.
// A draft is "pronto per invio" when ALL of:
//   1. title is non-empty
//   2. customerId is non-empty (either from picker or free-text captured in
//      customerFreeText via details JSON — we use customerId for cache-backed
//      OR customerFreeText for free-text)
//   3. ≥ 1 staff row
//   4. ≥ 1 materiale row OR materialiNotRequired == true
//   5. customerSignatureAllegatoId is non-null/non-empty
//   6. technicianSignatureAllegatoId is non-null/non-empty
// ══════════════════════════════════════════════════════════════════════════════

enum DraftValidationIssue {
  missingTitle,
  missingCustomer,
  noStaff,
  noMateriali, // only when materialiNotRequired == false
  missingCustomerSignature,
  missingTechnicianSignature,
}

class DraftValidationResult {
  const DraftValidationResult({required this.issues});

  final List<DraftValidationIssue> issues;

  bool get isValid => issues.isEmpty;

  bool get isReadyToSubmit => isValid;

  /// Returns human-readable Italian strings for each issue.
  List<String> get italianMessages {
    return issues.map((i) {
      switch (i) {
        case DraftValidationIssue.missingTitle:
          return 'Titolo mancante';
        case DraftValidationIssue.missingCustomer:
          return 'Cliente non specificato';
        case DraftValidationIssue.noStaff:
          return 'Nessun tecnico aggiunto';
        case DraftValidationIssue.noMateriali:
          return 'Nessun materiale aggiunto (o flag "nessun materiale" non attivo)';
        case DraftValidationIssue.missingCustomerSignature:
          return 'Firma cliente mancante';
        case DraftValidationIssue.missingTechnicianSignature:
          return 'Firma tecnico mancante';
      }
    }).toList();
  }
}

/// Validate a draft against the ReadyToSubmit rules.
///
/// [staffCount] and [materialiCount] are the child row counts from Drift.
/// [customerFreeText] is the free-text customer name (stored in details JSON)
/// used when no cached customerId is available.
DraftValidationResult validateDraft({
  required DraftReport draft,
  required int staffCount,
  required int materialiCount,
  String? customerFreeText,
}) {
  final issues = <DraftValidationIssue>[];

  final title = draft.title.trim();
  if (title.isEmpty) {
    issues.add(DraftValidationIssue.missingTitle);
  }

  // Customer: either a cached id or a free-text fallback
  final hasCustomer = (draft.customerId?.isNotEmpty ?? false) ||
      (customerFreeText?.isNotEmpty ?? false);
  if (!hasCustomer) {
    issues.add(DraftValidationIssue.missingCustomer);
  }

  if (staffCount == 0) {
    issues.add(DraftValidationIssue.noStaff);
  }

  if (!draft.materialiNotRequired && materialiCount == 0) {
    issues.add(DraftValidationIssue.noMateriali);
  }

  if (draft.customerSignatureAllegatoId == null ||
      draft.customerSignatureAllegatoId!.isEmpty) {
    issues.add(DraftValidationIssue.missingCustomerSignature);
  }

  if (draft.technicianSignatureAllegatoId == null ||
      draft.technicianSignatureAllegatoId!.isEmpty) {
    issues.add(DraftValidationIssue.missingTechnicianSignature);
  }

  return DraftValidationResult(issues: issues);
}
