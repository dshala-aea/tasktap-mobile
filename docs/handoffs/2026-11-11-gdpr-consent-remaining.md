# Handoff — GDPR consent, remaining items

**To:** backend, office-web/frontend, legal
**From:** mobile
**Date:** 2026-11-11
**ClickUp:** [P1][GDPR] Consent (`12493t4qztr`)

## Shipped on mobile

- Voice-recording consent is now **append-only** locally: every acceptance writes a record with
  `version`, SHA-256 `textHash`, UTC `acceptedAtUtc`, and `actorId` (the signed-in auth user id).
- The gate checks the latest record for the signed-in actor: a different actor, a changed text, or
  a bumped version all require a fresh consent.
- The old boolean key (`voice_recording_consent_v1`) is ignored rather than migrated: it has no
  actor or timestamp, so migrating it would fabricate an audit entry. Users re-consent once.
- Storage is `SharedPreferences` key `voice_recording_consents_v1`; records are only appended.
- The consent dialog and the AI copilot gate both use the same record.

## Remaining

1. **Backend — append-only history.** The current consent upsert overwrites its own history. Add a
   consent record store (version, text hash, timestamp, actor, source) and an endpoint for the
   mobile voice-consent records. Decide the authoritative actor id: mobile currently uses the
   Zitadel `sub`; the backend may want the internal user id, so agree on the mapping.
2. **Frontend — signup links / ePrivacy.** The SignupWizard already has the terms/privacy
   checkboxes and versions (`tos-2026-05`, `privacy-2026-05`) but no links; add links to the actual
   documents. Review the web cookie/ePrivacy banner.
3. **Legal — final voice-consent copy.** Replace the **PLACEHOLDER** `voiceConsentText`, bump
   `voiceConsentVersion`, and update the privacy policy with the AI processor/region.
4. **Mobile follow-up.** Once the backend endpoint exists, push the local append-only records and
   reconcile with the server (the server becomes authoritative). Keep the local list as the offline
   queue; do not prune it before the server acknowledges.
5. **Legacy key.** Remove or explicitly document `voice_recording_consent_v1` after a release; today
   it is deliberately ignored.
