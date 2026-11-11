# Dashboard: Prossimi 7 giorni counter + Storico — design

Status: **Draft, for review.**

ClickUp: [CHANGE] dashboard: make the prossimi eventi counter more visible; add history (`12493t4vybq`).

## Intent

The dashboard already computes `upcomingCount` (next 7 days) but never shows it, and there is no
way from the dashboard to look at schedules that already happened. Surface the counter prominently
and add a direct entry to a past-schedules history.

## Goals

- Show a third hero readout: **PROSSIMI 7 GIORNI** with `DashboardStats.upcomingCount`.
- Add a **Storico** action to the dashboard that opens a full-screen past-schedules list.
- Storico lists locally synced schedules before today, newest first, grouped by day; tapping a row
  with a ticket opens that ticket.
- In the dashboard work queue, an all-day row always says **Tutto il giorno** instead of showing no
  time at all, and a non-today all-day row also names its day (e.g. **Gio 13 · Tutto il giorno**).
  A multi-day plan is one row per covered day on this branch, so each row naming its own day is
  what makes a multi-day run readable.
- Keep the existing work queue and Calendario behaviour unchanged.

## Non-goals

- No changes to the five work-queue tiers, their ranking, or `PROGRAMMATO`'s contents.
- No date-range picker, search, pagination, or "load more" in Storico for this pass.
- No multi-day schema or grouping work: this branch has no `isBlockOccupied`; the multi-day plan
  arrives as one ordinary schedule row per day, and that is what the label change reads.
- No backend/API changes: history is whatever the local Drift mirror holds.
- No change to Calendario's views or routes.

## Approaches

1. **Hero counter + Storico section action (chosen).** Third `_Readout` in the hero and a `Storico`
   text action on the "Oggi" `SectionTitle`, opening a new `StoricoScreen`. Most visible, one new
   screen, no duplication of `PROGRAMMATO`.
2. Dedicated "Prossimi eventi" card between hero and Oggi — duplicates the queue and costs height.
3. Counter as plain text in the Oggi header only — not meaningfully "more visible".

## Decisions

- **Counter label is `PROSSIMI 7 GIORNI`**, not a bare number: it states its own window, matching
  the provider (`today+1 .. today+8`). It is a quiet readout (`accent: false`) — it is information,
  not a call to action. It counts non-cancelled schedules only, so it always agrees with the
  `PROGRAMMATO` list under it.
- **Storico scope = all locally synced schedules with `activityDate < today`**, newest first. No
  arbitrary 30/90-day cutoff: sync retention already bounds what exists, and a cut-off without a
  range control would be a hidden rule.
- **New root-level route** `AppRoutes.storico = '/storico'` (full-screen, pushes over the shell)
  with `ScreenHeader(title: 'Storico', showBack: true)`. It is deliberately **not** added to
  `_routeRequirements`: it exposes the same local schedule mirror the Dashboard and `/calendario`
  already expose ungated, and gating it on `interventi` would hide schedule history from a tenant
  that has schedules but not tickets.
- **Hero readouts use a `Wrap`** (two per run at normal scale, flowing to a second run at large
  accessibility text sizes) so adding the third readout cannot overflow a narrow phone.
- **New provider** `pastSchedulesProvider` in `dashboard_providers.dart`: same UTC-midnight
  convention as the existing providers, `orderBy(activityDate desc, timeStartMinutes desc)`.
- **Reuse `ListaView`** instead of duplicating its grouped row rendering. Add three optional,
  backward-compatible parameters: `reverseDays` (default `false`), `emptyTitle`/`emptyBody`
  (defaults keep today's copy), and `bottomPadding` (defaults to `context.navClearance`). Storico
  passes `reverseDays: true`, history copy, and `context.fabSafeBottom`.
- **Entry point is the Oggi section header**: `SectionTitle(title: 'Oggi', trailing: ..., action:
  TextButton('Storico'))`. The trailing completed-count stays.
- **The work queue's day label becomes one function**: today + timed → `HH:MM`; today + all-day →
  `Tutto il giorno`; other day + timed → `Gio 13, HH:MM`; other day + all-day →
  `Gio 13 · Tutto il giorno`. No `00:00` ever appears for an all-day row.

## Testing

- `dashboard_providers_test.dart`: `pastSchedulesProvider` includes yesterday and earlier, excludes
  today and future, newest first.
- `dashboard_screen_test.dart`: hero renders `PROSSIMI 7 GIORNI` and the upcoming count; tapping
  `Storico` pushes `/storico`.
- New `storico_screen_test.dart`: groups past schedules newest-first, empty state, row tap with a
  ticket pushes the ticket detail path.
- `work_queue_section_test.dart`: an all-day row renders `Tutto il giorno` (no `00:00`); a
  future all-day row renders its day + `Tutto il giorno`; two consecutive future all-day rows
  render two distinct day labels (multi-day run is distinguishable).
- `app_router_route_requirement_redirect_test.dart`: `/storico` resolves to `StoricoScreen`
  regardless of module entitlement, matching `/calendario`.
- `flutter analyze` + targeted `flutter test`; no golden baselines cover the dashboard today.

## Open questions

None.
