// dart format width=100

// ══════════════════════════════════════════════════════════════════════════════
// DraftSubmissionState — persisted as a string in DraftReports.submissionState.
//
// State machine transitions:
//   draft  ──(enqueue)──────────────────────►  readyToSubmit
//   readyToSubmit ──(queue picks up)────────►  uploadingMedia
//   uploadingMedia ──(all allegati uploaded)►  submitting
//   submitting ──(POST /submit 200)──────────►  submitted
//   uploadingMedia|submitting ──(error)──────►  failed
//   failed ──(retry)─────────────────────────►  readyToSubmit
// ══════════════════════════════════════════════════════════════════════════════

enum DraftSubmissionState {
  draft,
  readyToSubmit,
  uploadingMedia,
  submitting,
  submitted,
  failed;

  static DraftSubmissionState fromString(String? s) {
    switch (s) {
      case 'readyToSubmit':
        return readyToSubmit;
      case 'uploadingMedia':
        return uploadingMedia;
      case 'submitting':
        return submitting;
      case 'submitted':
        return submitted;
      case 'failed':
        return failed;
      default:
        return draft;
    }
  }

  String toPersistedString() => name;
}
