// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// PendingTicketState — persisted as a string in PendingTickets.state.
//
// State machine transitions:
//   pendingSync ──(request never sent: created while offline)──► submitting
//   submitting  ──(POST /api/Tickets 200)───────────────────────► submitted
//   submitting  ──(error — server outcome now unknown)──────────► failed
//
// `failed` is a dead end for automatic retry: see TicketCreationQueue for why
// (no client-supplied idempotency key on ticket creation, so a blind resend
// could create a duplicate). Only an explicit, user-initiated retry may move
// a `failed` row back to `submitting`.
// ══════════════════════════════════════════════════════════════════════════════

enum PendingTicketState {
  pendingSync,
  submitting,
  submitted,
  failed;

  static PendingTicketState fromString(String? s) {
    switch (s) {
      case 'submitting':
        return submitting;
      case 'submitted':
        return submitted;
      case 'failed':
        return failed;
      default:
        return pendingSync;
    }
  }

  String toPersistedString() => name;
}
