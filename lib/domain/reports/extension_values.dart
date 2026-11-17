// dart format width=100
import '../../data/extension_fields/extension_fields_api_client.dart'
    show ExtensionFieldDefinitionDto;

// ══════════════════════════════════════════════════════════════════════════════
// Extension-field values of a rapportino draft ("Altri campi")
//
// A draft lives on the phone until it is submitted, so its custom-field values are local state:
// they are stored in `draft_reports.extension_values`, shown/edited by the wizard, checked before
// "Invia" and carried by the submit itself (`SubmitReportRequest.extensionValues`). There is no
// server row to read or PUT them against beforehand.
//
// These functions are the single definition of "what value does this field effectively hold", so
// the form, the pre-submit check and the submit payload can never disagree.
// ══════════════════════════════════════════════════════════════════════════════

/// The value each active definition effectively holds: what the technician stored, else the
/// definition's default, else empty. Keys with no definition (a field the office has since
/// deactivated) are dropped.
Map<String, String> effectiveExtensionValues(
  List<ExtensionFieldDefinitionDto> definitions,
  Map<String, String> stored,
) {
  return {for (final d in definitions) d.key: stored[d.key] ?? d.defaultValue ?? ''};
}

/// Labels of the required fields whose effective value is blank, in the office's field order.
List<String> missingRequiredExtensionLabels(
  List<ExtensionFieldDefinitionDto> definitions,
  Map<String, String> stored,
) {
  final effective = effectiveExtensionValues(definitions, stored);
  final ordered = [...definitions]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  return [
    for (final d in ordered)
      if (d.isRequired && (effective[d.key] ?? '').trim().isEmpty) d.label,
  ];
}
