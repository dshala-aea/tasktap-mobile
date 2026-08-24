// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// PendingTicketAttachmentState — persisted as a string in PendingTicketAttachments.state.
//
// State machine transitions:
//   pendingSync ──(request never sent: picked while offline)──► submitting
//   submitting  ──(POST /api/tickets/{id}/attachments 200)────► submitted
//   submitting  ──(error — server outcome now unknown)────────► failed
//
// `failed` is a dead end for automatic retry — see PendingTicketAttachments' own doc comment
// (no client-supplied idempotency key on the upload endpoint, unlike ticket creation's
// `clientId`, so a blind resend could attach the same photo twice). Only an explicit,
// user-initiated retry may move a `failed` row back to `submitting`.
// ══════════════════════════════════════════════════════════════════════════════

enum PendingTicketAttachmentState {
  pendingSync,
  submitting,
  submitted,
  failed;

  static PendingTicketAttachmentState fromString(String? s) {
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
