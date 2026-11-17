# Handoff — AI Act transparency, remaining items

**To:** legal/counsel, office-web
**From:** mobile
**Date:** 2026-11-11
**ClickUp:** [P2][AI Act] Transparency (Art. 50) (`12493t4qztu`)

## Shipped on mobile

- An **AI-assisted badge** (`AiAssistedBadge`, visible `AI`, accessible name “Assistito da AI”) on:
  - rapportini list rows where `DraftReport.isAiAssisted` is true;
  - the report view hero, next to the existing “Redazione: AI, poi rivista” fact.
- A permanent **AI/audio transparency notice** under the AI copilot header:
  “Stai interagendo con un assistente AI. I messaggi sono elaborati da un fornitore AI; le
  registrazioni vocali vengono inviate per la trascrizione.”
- The existing first-recording consent gate remains (`core/audio/voice_consent.dart`); its text is
  still marked **PLACEHOLDER — NOT FINAL LEGAL COPY** and uses SharedPreferences, not append-only
  consent history.

## Remaining

1. **Counsel — Art. 50(2) and the PDF marker.** ADR-0016 deliberately carries no AI marker on the
   customer-facing PDF because the signature is the authorship. Confirm this is the right reading
   for generated text, or decide the PDF needs a marker. No mobile change until that is settled.
2. **Office web consistency.** Web already shows “Assistito da AI”; align its exact wording/placement
   with the mobile badge and the report view fact.
3. **Legal copy for the voice consent.** Replace the placeholder `voiceConsentText` with approved
   wording, bump `voiceConsentKey`’s version, and coordinate with the GDPR consent task
   (`12493t4qztr`) for append-only consent history (actor/version/text hash/timestamp).
4. **Audio processor disclosure.** Confirm which processor/region receives the AI copilot recordings
   and whether the notice and privacy policy name it (ties into `12493t4qztx`).
