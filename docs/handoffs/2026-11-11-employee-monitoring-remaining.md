# Handoff — employee monitoring (GPS), remaining items

**To:** backend, office-web/admin, legal
**From:** mobile
**Date:** 2026-11-11
**ClickUp:** [P1][GDPR/IT] Employee monitoring (`12493t4qztq`)

## Shipped on mobile

- A `tenantGpsEnabledProvider` gate now sits in front of the location service. It defaults to
  true until the authenticated server setting is wired in; when false it disables capture even if
  the technician's device toggle is on.
- The Impostazioni “Geolocalizzazione” row is disabled and says “Disattivata dall'azienda” when the
  tenant switch is off.
- An in-app information notice states that position is recorded only at point events (clock-in,
  report, uploads), never continuously in the background, and that the tenant can disable it.

## Remaining

1. **Backend tenant setting.** Add a `GpsEnabled` (or equivalent) flag to `TenantSettings`, expose
   it in the mobile authenticated config (`/api/Auth/me` or a mobile config endpoint), and enforce
   it server-side: when false, ignore/clear GPS fields on work logs and reports rather than trusting
   the client. Add it to the admin/portal settings UI.
2. **Wire the mobile provider.** In `main.dart`, override `tenantGpsEnabledProvider` from that
   config and refresh it with the other authenticated settings.
3. **Legal templates.** Employee information notice (GDPR Art. 13; one-shot GPS, no continuous
   tracking, retention) and the customer-facing compliance note. The Statuto art. 4
   agreement/INL authorisation duties sit with the tenant; prepare guidance for customers.
4. **Legal review of the in-app notice.** Replace the current in-app copy with the approved wording
   when available.
