# Offline Engine + Real-Time Feel Design

## Overview

TaskTap mobile already has real, working offline infrastructure — a `SubmissionQueue`, per-domain
reconcilers/watchers for timbratura, ticket creation, and ticket attachments, all sitting on top of
a genuine OS-level connectivity signal (`connectivity_plus`, not a heuristic). What it lacks:

- **Zero UI visibility.** Nothing anywhere tells a technician they're offline, or that N actions
  are queued waiting to sync. The infrastructure works silently; the user has no idea it's there.
- **Uneven coverage.** Ticket creation, ticket attachments, and timbratura are offline-safe.
  Rapportino creation has no offline handling at all. Magazzino is unclear, in scope to determine
  during planning.
- **No real-time feel.** Everything is pull-based except one deliberate 1-minute poll on the
  dashboard's active-tracker strip. There is no push infrastructure anywhere, and no optimistic-UI
  pattern for the user's own actions.

This is genuinely three related but separable pieces of work, sequenced by leverage: visibility
first (cheapest, most immediately felt), then coverage expansion (extends an already-proven
pattern to two more flows), then real-time (the only piece requiring new infrastructure).

## Decisions

### 1. Visibility layer

- A persistent, app-shell-level **offline/sync indicator** — not a screen-by-screen ad hoc banner.
  Lives in the shell (`HomeShell`/wherever the bottom nav and header already live) so it's visible
  regardless of which screen the technician is on.
- Three states: online-and-synced (no chrome, the default — this app already treats absence of
  noise as correct, per the punch-clock/timbra design precedent elsewhere in this codebase),
  offline (a quiet, persistent indicator — not a modal, not a toast that disappears), and
  syncing-N-pending (a count, decrementing as the existing queues drain, driven by watching the
  existing `SubmissionQueue`/`TicketCreationQueue`/`TicketAttachmentUploadQueue`/reconciler state —
  no new queue-counting mechanism, just a UI layer reading what already exists).
- Uses the existing `ConnectivityNotifier` (`sync/connectivity_provider.dart`) as the
  online/offline signal — already real, already OS-level, no new detection mechanism.

### 2. Coverage expansion — RULED CLOSED, no plan written (amended 2026-09-04)

Investigated at plan-writing time, not just grounding time — both assumed gaps turned out not to
be gaps:

- **Rapportino creation is already fully offline-safe.** `create_draft.dart`'s draft creation is a
  pure local Drift write (no network call at all — nothing to fail offline). Submission already
  goes through the existing `SubmissionQueue` (`lib/data/sync/submission_queue.dart`), confirmed
  genuinely wired at app startup via `initSubmissionQueueWatcher` in `HomeShell` (not dead
  infrastructure). Nothing to build.
- **Magazzino's stock movements (carico/scarico) are offline-blocked by deliberate design, not by
  gap.** `ensureOnlineOrWarn` (`lib/core/utils/offline_guard.dart`) is used across every
  admin-style write in this app (customers, locations, schedules, contracts, squadre, prodotti,
  materiali, cantieri, magazzino movements) — its own doc comment states the reasoning explicitly:
  "queuing them was judged not worth the risk (a wrong queue is worse than an honest error)." This
  is a considered architectural stance already made in this exact codebase, not an oversight.
  Building a new offline queue for magazzino movements specifically would contradict that decision
  for no stated reason strong enough to override it.

**Ruling:** no coverage-expansion plan is written. If the `ensureOnlineOrWarn` design philosophy
itself should be revisited for some subset of these forms, that is a separate, explicit design
conversation — not something this plan silently does on the strength of an assumption that turned
out to be wrong. Cost if this ruling is wrong: low — nothing destructive happens by not building
this; a future request to make a specific admin flow offline-capable is a normal follow-up, not a
correction of damage done.

### 3. Real-time feel — hybrid, deliberately scoped

Two distinct things get worked on, not one:

**A. Optimistic UI — DROPPED (amended 2026-09-04).** Investigated at plan-writing time: the most
obvious candidate (ticket/cantiere worklog timer start/stop) turned out to be deliberately
non-optimistic by existing, documented design — `_TicketTimerBar`'s own code comment: "these writes
have no idempotent upsert to queue against, so there is nothing to promise here" (starting/stopping
a server-authoritative timer twice, or racing a stop against an optimistically-shown start, would
produce genuinely wrong elapsed-time data — not a UI polish problem, a correctness one). This is
the second deliberate "already decided against this" finding while writing these plans (the first
was magazzino's `ensureOnlineOrWarn`, see the Coverage section above) — ruled out rather than
overridden. No optimistic-UI plan is written. If a genuinely safe, idempotent candidate for
optimistic UI is identified later, that is a separate, narrowly-scoped follow-up, not something
forced into existence here on the strength of the original spec's blanket assumption.

**B. A deliberately small-scope SignalR hub (other users' actions appear without a manual
refresh).** Not "replace polling everywhere" — a targeted set of events, tenant/permission-scoped:
`TicketUpdated`, `TicketWorkLogStarted`/`Stopped`, `CantiereStatusChanged`, `MaterialeUpdated`,
`RapportinoSubmitted`. The database write is always the source of truth, committed before any
SignalR notification goes out — if the push fails or a client is disconnected, existing
reconciliation/polling on screen-focus is the recovery path, not a second source of truth to keep
consistent. A technician holds one persistent connection regardless of how many screens/tickets
they have open (not one connection per open ticket) — connection count is trivial (hundreds, not
tens of thousands) for this app's real user population, so no backplane/scaling infrastructure is
needed at this stage; a single ASP.NET SignalR hub instance is sufficient today, and scaling
options exist later only if the tenant/user count grows into a range that needs them (this is
explicitly deferred, not designed for now — no premature scaling architecture).
- Backend: one new SignalR hub in the existing ASP.NET API, auth/tenant-scoped groups (a
  connection joins its tenant's group on connect, per this codebase's existing tenant-isolation
  conventions — RLS-equivalent scoping for realtime, not a new isolation model).
- Mobile: a SignalR client (`signalr_netcore` or the maintained Dart/Flutter SignalR client — pick
  during planning after checking pub.dev for current maintenance status) with reconnect/backoff
  handling, invalidating the relevant Riverpod provider(s) on each event rather than pushing raw
  data into local state directly (keeps the existing Drift-backed `StreamProvider` pattern as the
  single rendering source of truth — a SignalR event triggers "go re-fetch/re-sync this specific
  thing," it doesn't become a second data path).
- Existing polling (the dashboard's 1-minute tracker poll) stays as a fallback/reconciliation tick,
  not removed — SignalR is an optimization on top of a system that already tolerates missed
  updates, not a hard dependency.

## Architecture

Three genuinely separable sub-projects, in dependency/leverage order:

1. **Visibility** (shell-level indicator + queue-state watching) — no backend changes, mobile-only,
   lowest risk, ships first.
2. **Coverage** (rapportino offline queue + magazzino determination) — mobile-only, mirrors an
   already-proven pattern, ships second.
3. **Real-time** (optimistic UI + SignalR hub) — the only piece touching the backend, the only
   piece needing new infrastructure, ships last and is itself two halves (optimistic UI can ship
   independently of and before the SignalR half, since it needs no backend change at all).

Each of these should become its own implementation plan (matching this session's established
pattern of one plan per coherent, independently-shippable unit of work) rather than one giant plan
— sequenced 1→2→3a→3b.

## Testing

- Visibility: widget tests asserting the indicator renders correctly for each of the three states,
  driven by mocked `ConnectivityNotifier`/queue-state providers — matching this codebase's existing
  test-harness pattern (`ProviderContainer` overrides, as used throughout the widget-layer restyle
  work this session).
- Coverage: mirrors `TicketCreationQueue`'s existing test suite shape for the new rapportino queue.
- Optimistic UI: a widget test asserting the UI updates before the underlying async call resolves
  (pump once, assert the optimistic state, then let the future complete, assert final state).
- SignalR: backend hub tests for tenant-scoping (a connection in tenant A's group never receives a
  tenant B event) and the "DB write commits even if the notify step throws" guarantee; mobile
  client tests for reconnect behavior and provider-invalidation-on-event, using a fake hub
  connection rather than a real network socket.

## Out of scope

- Any change to how `SubmissionQueue`/reconcilers/watchers actually work internally — they're
  correct and proven; this project builds a visibility layer and extends coverage using their
  existing shape, not redesigning the queue mechanism itself.
- A SignalR backplane/multi-instance scaling setup — explicitly deferred until real usage numbers
  justify it, per the Decisions section above.
- Extending SignalR events beyond the five named above — if more prove necessary during
  implementation or after shipping, that's a follow-up, not silently expanded scope here.
