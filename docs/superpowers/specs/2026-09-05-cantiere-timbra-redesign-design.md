# Cantiere Timbra Screen Redesign

## Problem

`CantiereTimbraScreen` (`lib/features/timbra/cantiere_timbra_screen.dart`) grew feature-by-feature
— personal check-in/out, then caposquadra batch-start, then crew assignment, then cantiere-only
rapportino support — without its layout catching up. A prior area-by-area UI audit confirmed the
underlying state machine (not-checked-in → check-in body; checked-in → active-session body) and
its supporting logic (offline queue, batch-start, crew-lead detection, reconciliation) are all
correct — the problem is purely presentational:

- The check-in body's lead-vs-non-lead branching renders three stacked, visually equal buttons
  ("Solo io" / "Seleziona squadra" / "Tutta la squadra") for a caposquadra, reading like three
  independent primary actions instead of one action with a scope choice.
- There is no visibility into hours already logged on the cantiere today, even though the local
  event log (`todayCantiereEventsProvider`) already holds everything needed to compute it —
  nothing today surfaces it.
- General visual density/staleness relative to the app's current design language.

## Non-goals

- No change to the state machine, to any provider's existing behavior, to the offline event queue
  (`CantiereSessionRepository`), the sync push (`CantiereTimbraSyncService`), reconciliation
  (`CantiereWorkLogReconciler`), or the batch-start API contract.
- No crew-presence display ("who else is on site") — not requested.
- No surfacing of the cantiere's rapportini from this screen — that stays on
  `CantiereDetailScreen`, a sibling screen reached from the same parent.
- **Deferred:** a "Squadra · N persone" indicator on the active-session card (present in an early
  mockup during design) — no data source persists a batch-started session's crew count anywhere
  retrievable after the fact; the only crew-size field is the optional, rarely-filled manual
  "Dimensione squadra" in the check-in details form, which doesn't reflect actual batch-start
  selections. Adding this would need new plumbing (persisting crew count at batch-start time) and
  is out of scope here.

## New data: `cantiereTodayHoursProvider`

A new derived provider, scoped to one cantiere (matches the screen's own context — "how much have
I worked *here* today" — not a cross-cantiere daily total):

```dart
final cantiereTodayHoursProvider = Provider.autoDispose.family<Duration, String>((ref, cantiereId) {
  final events = ref.watch(todayCantiereEventsProvider).valueOrNull ?? [];
  // Fold today's events into closed (ingresso→uscita) intervals for this cantiere only, mirroring
  // deriveLocalActiveCantiereSession's own pairing logic. A still-open interval at the end is
  // deliberately NOT included here — see below.
  CantierePunche? opener;
  var total = Duration.zero;
  for (final e in events) {
    switch (e.eventType) {
      case 'ingresso':
        opener = e;
      case 'uscita':
        if (opener != null && opener.cantiereId == cantiereId) {
          total += e.eventTime.difference(opener.eventTime);
        }
        opener = null;
    }
  }
  return total;
});
```

This returns **closed-interval minutes only** — stable, no ticking, recomputes reactively whenever
local events change (a new punch, a sync-driven correction). It deliberately excludes the
currently-open interval (if any): that portion needs a live per-second tick, which a `Provider`
recomputed only on event-list changes can't give you smoothly. The UI combines this with a
separately-ticking "current session" duration (same `Ticker`-based pattern as
`rapportino/step_ore.dart`'s `_RunningTimerBadge`) to show the running total.

**Midnight edge case:** `todayCantiereEventsProvider`'s window is local-midnight-bounded
(`CantiereSessionRepository._todayBounds()`). A session that started before midnight and is still
open has no 'ingresso' row inside today's window at all — so the live elapsed-time widget must not
compute `now - session.startTime` (which could span back into yesterday) but
`now - max(session.startTime, todayLocalMidnightUtc)`, clamping to today's actual start. This
keeps "today" literal: only the since-midnight portion of an overnight session counts.

Displayed total on screen = `cantiereTodayHoursProvider(cantiereId)` + the live-ticking clamped
current-session elapsed (zero when not checked in).

## UI — Check-in body (not checked in)

Replaces the elevated-card-heavy layout with a flatter hierarchy — the audit's own finding was
"another card stacked on existing clutter" is the wrong direction:

```
OGGI
06h 42m
────────────────────────────
Cantiere
Via Roma 24

[      INIZIA TIMBRATURA     ]

Per: Me ▾                        ← lead only
```

- "OGGI" + total sits as a lightweight header block (plain text hierarchy, not an `AppCard`),
  above the existing cantiere picker/fixed-cantiere-card section (picker vs. fixed-card logic is
  unchanged — still gated on `widget.cantiereId == null`).
- One primary button, always "Inizia timbratura", **always performs the "solo me" single-person
  start directly on press** — no extra tap, for leads and non-leads alike. This is exactly
  today's non-lead single button, and today's "Solo io" button for a lead — unchanged behavior,
  just the one path every technician reaches immediately.
- **Lead-only scope menu**: a compact "Per: Me ▾" row directly below the button, visible only
  when `isLeadForCantiereProvider(cantiereId)` is true. This is *not* a persisted selection the
  main button later acts on — each of today's three buttons already fires its action immediately
  on tap ("Solo io" starts immediately; "Tutta la squadra" batch-starts everyone immediately;
  "Seleziona squadra" opens the teammate picker sheet, which itself fires on confirm), so the
  redesign collapses the two group-scoped choices into a menu behind "Per: Me ▾", each firing the
  *existing, unchanged* handler the instant it's picked:
  - "Squadra" → `_handleSelectSquadra` (opens `teammate_picker_sheet.dart`, unchanged)
  - "Me e squadra" → `_handleTuttaLaSquadra` (immediate batch-start for everyone, unchanged)

  "Solo me" is deliberately *not* one of the menu's options — it's what the main button already
  does, so repeating it in the menu would be a redundant path to the same action.
- **Non-leads see no menu at all** — the row is omitted entirely, not shown-disabled. Matches
  "don't make them interact with a concept they cannot use."
- The existing "Altri dettagli" progressive-disclosure trigger stays, unchanged behavior (now
  correctly clearing on session end, per the prior bug fix), placed as a low-emphasis text button
  below the selector/button.

## UI — Active-session body (checked in)

```
OGGI
06h 42m
────────────────────────────
TIMBRATURA ATTIVA          [pending-sync dot, if any]
Via Roma 24

        01h 18m

[       STOP TIMBRATURA      ]
```

- Same "OGGI" header block as the check-in body, for visual continuity between the two states.
- "TIMBRATURA ATTIVA" + cantiere name replaces the old hero card's status-dot-plus-KeyVal-rows
  layout with the flatter hierarchy; the existing pending-sync indicator dot stays (it's
  functional, not decorative — offline visibility the audit found no issue with) but moves inline
  next to the "TIMBRATURA ATTIVA" label rather than as a separate card element.
- Large centered live-ticking elapsed time for the *current session* (clamped to today's midnight
  bound per above) — visually secondary to the "OGGI" total above it, per the recommended
  hierarchy ("today's total wins").
- "Note di chiusura" progressive-disclosure trigger stays, low-emphasis, below the stop button.
- Ticket-link context (when the session is tied to a ticket) stays, shown between the cantiere
  name and the elapsed time — same information the old `KeyVal` row carried, restyled to match.

## Testing impact

- `test/features/timbra/cantiere_timbra_screen_test.dart`'s `'lead branching'` group (7 tests)
  directly asserts the old three-button UI ("Solo io" / "Seleziona squadra" / "Tutta la squadra"
  as separately tappable buttons) — these need rewriting against the new selector interaction,
  not just extending. The underlying assertions (batchStart called with correct userIds, failures
  surfaced by name, success-count toast) stay the same; only how the test reaches that action
  (selector → choice → button, instead of tapping one of three buttons) changes.
- New unit tests for `cantiereTodayHoursProvider`: sums closed intervals correctly, ignores other
  cantieri's events, excludes the still-open interval, and the midnight-clamping behavior for an
  overnight session (via a fake "now" or by constructing events that straddle the day boundary).
- New widget tests: "OGGI" total renders in both check-in and active-session states; the live
  current-session ticker updates; the "Per: Me ▾" menu is absent for a non-lead and present for a
  lead; the main button still starts solo for both roles with no extra tap; picking "Squadra" from
  the menu still opens the teammate picker and picking "Me e squadra" still batch-starts everyone
  (adapting the existing lead-branching test bodies — same assertions on `_handleSelectSquadra`/
  `_handleTuttaLaSquadra`'s outcomes, reached via the menu instead of a dedicated button).

## Implementation notes

No backend, queue, or reconciliation changes. This is confined to:
`lib/features/timbra/cantiere_timbra_screen.dart` (the `_CheckInBody` and `_ActiveSessionBody`
widgets, plus the new `cantiereTodayHoursProvider`), and its test file. `teammate_picker_sheet.dart`
and the batch-start/single-start handler methods in `_CantiereTimbraScreenState` are reused as-is.
