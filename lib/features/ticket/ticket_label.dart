// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// How a ticket names itself
//
// Five screens rendered `ticket.id.substring(0, 8)` — eight hex characters of a
// GUID — as the thing that identifies a job. The ticket detail screen used it as
// the *page title*, demoting the ticket's actual title to a subtitle, so the
// most prominent text on the screen was `#3f2a1c8e`.
//
// The number existed the whole time. `Ticket.Numero` is a per-tenant display
// number on the server, mobile sync returns the ticket entity itself, and this
// client simply never read the field. Schema 12 adds the column; this decides
// what to show once it is there.
//
// The rule, which is the same one the rapportino wizard already follows: an
// identifier a human cannot recognise is worse than no identifier. A ticket with
// no number is named by its title alone — nothing is invented, and nothing
// reaches for the id.
// ══════════════════════════════════════════════════════════════════════════════

/// The reference a technician can read out over the phone, or null when there
/// isn't one.
///
/// Tickets created before numbering existed have no `numero`, and that is a real
/// and permanent state rather than a loading one — the caller renders nothing,
/// not a placeholder.
String? ticketReference(String? numero) {
  final trimmed = numero?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  // The server stores the bare number; the `#` is presentation, and doubling it
  // when a tenant's format already carries one reads as a typo.
  return trimmed.startsWith('#') ? trimmed : '#$trimmed';
}
