// dart format width=100

/// Why the customer did not sign a ticket-linked report — `Il cliente non può firmare`.
///
/// Mirrors the backend's `CustomerSignatureAbsenceReason` enum. `System.Text.Json` serializes it as
/// its **integer** value (there is no `JsonStringEnumConverter` on it), so [wireValue] is the wire
/// contract: `Assente = 0`, `Rifiuta = 1`, `Altro = 2`. Never renumber them.
///
/// Mutually exclusive with a customer signature: a report carries either the signed allegato or
/// this reason, never both. The editor enforces that (`saveCustomerSignature` clears the reason)
/// and the submit payload refuses to emit both.
enum CustomerSignatureAbsenceReason {
  /// The customer was not there to sign.
  assente(0, 'Assente', 'Cliente assente'),

  /// The customer was there and refused to sign the report.
  rifiuta(1, 'Rifiuta il rapporto', 'Cliente rifiuta il rapporto'),

  /// Anything else; the free-text note says what.
  altro(2, 'Altro motivo', 'Altro motivo');

  const CustomerSignatureAbsenceReason(this.wireValue, this.chipLabel, this.summaryLabel);

  /// The value the server reads and writes.
  final int wireValue;

  /// Label on the reason choice in the entry dialog.
  final String chipLabel;

  /// Label shown in place of the empty signature block once a reason is recorded.
  final String summaryLabel;

  /// Wire int → enum, or null when absent/unknown.
  ///
  /// An unknown value (a newer server enum member on an older build) reads as null rather than
  /// throwing: losing the reason label must never fail a report import.
  static CustomerSignatureAbsenceReason? fromWire(Object? raw) {
    final value = raw is num ? raw.toInt() : null;
    if (value == null) return null;
    for (final reason in values) {
      if (reason.wireValue == value) return reason;
    }
    return null;
  }
}
