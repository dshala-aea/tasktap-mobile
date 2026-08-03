# TaskTap Mobile — completion design

Wire and implement every screen, form and feature of the Flutter app against the
real backend, on the design system in `design-reference/`.

Domain invariants live in the backend repo's `docs/adr/0006-operational-execution-layer.md`.
The backend contract this app builds against is specified in
`docs/superpowers/specs/2026-08-03-w8-operational-execution-layer-design.md` (backend
repo). This document owns the mobile side only.

## 1. Starting state

HEAD is `e34eb0c` (2026-06-23) with **37 uncommitted files** that nobody has
compiled, run or tested:

- Zitadel auth migration — `supabase_auth_repository.dart` deleted,
  `zitadel_auth_repository.dart` added, `auth_providers`, `login_screen`, `main.dart`,
  `dio_client`, `env` all modified.
- `lib/features/admin/` — nine domains × list/detail/form (customers, locations,
  cantieri, schedules, materiali, prodotti, contracts, reports, squadre), ~28 screens,
  already imported by `app_router.dart`.
- Push notifications — `lib/core/notifications/`, `lib/data/notifications/`.
- `new_ticket_form_screen` + steps + `ticket_api_client`.
- `codemagic.yaml`, proguard rules, Android/iOS manifest changes.

Committed and working: D1–D5 (shell, dashboard, timbra, ticket list/detail,
rapportino 4-step, calendario, altro hub, impostazioni, notifiche, clienti,
magazzino) and D6b (cantiere timbra, worklog API client, sync watcher), 442 tests.

**Design source of truth:** `design-reference/DESIGN-SPEC.md` (tokens, components)
and `design-reference/DESIGN-SCREENS.md` (per-screen layout). There is no Figma file;
these documents are the spec.

## 2. Audience and scope

One app, two personas, one shell. A manager is a technician with more to review —
not a user of a different application.

| Surface | Screens | Data mode |
|---|---|---|
| Technician core | Dashboard · Ticket list/detail/create · Timbra (attendance) · Cantiere presence · ticket timer · Rapportino 4-step · Rapportino read-only · Calendario | Offline-first |
| Manager | Operations Inbox · segment and report review · assign and schedule · team presence | **Reads cached, writes online** |
| Anagrafiche | nine domains × list/detail/form | Online-only |
| Sistema | Notifiche · Impostazioni · Audit · profilo | Online, cached where data exists |

Offline split: technician writes queue and sync on reconnect. Manager and anagrafiche
**writes** require connectivity and say so before the user starts typing, not at sync
time. Manager **reads** — the inbox, a report from yesterday — are cached, because
managers work in bad signal too.

## 3. Information architecture

The design's five-tab shell stands: **Dashboard · Ticket · Timbra · Calendario ·
Altro**. Tabs represent primary workflows every technician uses; role-specific task
lists do not become tabs, or the shell grows a tab per role as dispatcher, warehouse
manager and supervisor appear.

- **Operations Inbox** is a permission-gated Dashboard card with a badge when action
  is needed, opening the full inbox. Not a sixth tab.
- **Cantiere** is a first-class contextual object reached from Altro and from a
  linked ticket — list → detail → presence clock → that site's tickets. Not a tab.

**Permission gating** consumes `/auth/me` `permissions[]` through a shared
abstraction. **No permission name strings in widgets** — one `Can`/`ModuleGate`
equivalent, coarse read/write/admin as the backend actually implements it. No
per-domain permission model: the web app shipped that fiction once and it had to be
removed.

## 4. Workstreams

### M-A — Truth pass *(runs first, in parallel with backend T0/T1; blocks on nothing)*

Audit the 37 uncommitted files: `flutter analyze` clean, `flutter test` green, and
every client route checked against the real backend route inventory. The W7a lesson
is that mocks hide capability gaps — 28 admin screens were written against endpoints
nobody confirmed exist.

**Release gate, applied to every screen from here on.** A screen does not graduate
from prototype until:

1. its endpoint exists and has been called against a real backend,
2. its permission requirement is verified,
3. its error state is implemented,
4. its unavailable state is implemented.

Output: a verified baseline commit plus a written gap list. Anything calling a
non-existent endpoint gets an explicit unavailable state, never a silent mock.

### M-B — Fast-form kit (`lib/core/forms/`)

Every form in the app is built on it.

**`FormContext`** is the single place a form asks for defaults:

```
FormContext
├── NavigationContext   (the object you came from)
├── SessionContext      (active cantiere, running timer, today)
├── UserContext         (profile defaults)
├── RecentValues        (per-field, per-user recency in Drift)
└── FeatureFlags
```

Precedence is deterministic: navigation context → operational context → user profile
→ recent values → empty. **Only one source supplies a default; a lower-precedence
source never overwrites a higher one** — recency must not override the customer of
the ticket you are standing in. A field with no honest default stays empty rather
than guessing.

**Autosave.** Every form is a Drift-backed draft, debounce-persisted, resumable after
a kill or crash, with a resume banner. **Draft identity is separate from business
identity** (draft id ≠ ticket/report id) so two drafts against one ticket never
collide. Generalises the M4 draft repository that today only rapportini use.

**Scanners are input providers, not business logic.** Barcode, QR, and later NFC or
OCR all produce one thing: a *suggested field value*. The form still owns validation.
GPS capture and inline photo attach follow the same rule.

**Ergonomics.** Numeric steppers over keyboards, bottom-anchored sticky actions in
thumb reach, ≥44pt targets everywhere including where the 393pt design draws smaller,
one concern per step, destructive actions never at thumb rest.

**Known backend constraint, not worked around here:** `ProdottoAssistenza.SerialNumber`
is a scalar, so one product carries at most one serial. Multi-serial inventory
requires backend evolution before richer matricole UX can exist.

### M-C — Technician core

The loop, end to end:

open app → attendance clock-in (Timbra) → open ticket → *"sei al cantiere X — timbra
l'ingresso?"* when a foreground fix supports it → ticket timer → **Start / Pause /
Resume / Stop in the UI**, stored as immutable segments (a pause is two segments; the
technician never sees the word) → stop last segment → *"crea rapportino?"* →
4-step form pre-filled with tracked hours, declared hours editable with a mandatory
reason on variance → signatures → queued → synced.

Survives app kill: the running timer is reconstructed from its persisted start
instant.

### M-D — Manager mode

Operations Inbox over the aggregated read model: attendance, its segments, the
rapportini filed from them, anomalies inline. Approve at the level chosen; bulk
approval for clean items; anomalies require explicit review. Plus assign and
schedule, and team presence at a glance.

Technicians see anomaly information **only** when synchronisation was affected or
action is required, in neutral language — never "your device clock differed by
7 minutes".

### M-E — Anagrafiche, sistema and notifications

Nine anagrafiche domains as list/detail/form, online-only, each passing the M-A
release gate. Notifiche, Impostazioni, Audit. The remaining ComingSoon stubs are
removed — a screen either works or states plainly that it is unavailable and why.

**Notification strategy** (plumbing partly exists in the uncommitted pile; backend has
`NotificationsController` and `DevicesController`):

- Technician — ticket assigned, report approved or rejected, changes requested.
- Manager — approvals pending, reports submitted, sync completed with anomalies.

### M-F — Voice capture and AI

Dictate → **editable transcript** (the durable input) → structure into suggested
fields → technician reviews and accepts. Nothing auto-applied. Degrades to typing
when the recogniser is unavailable, which in a plant room it often will be; the
transcript queues for structuring on reconnect.

The action is labelled for intent — *Compila campi* — not for technology. The user's
goal is filling the report, not running a model.

Speech goes through a provider interface so the platform recogniser can later be
replaced by an offline on-device model or an enterprise service without touching the
rapportino flow.

## 5. Offline machinery

**One outbox, not per-feature queues.** Per-feature queues duplicate retry logic,
diverge in conflict handling, and destroy observability.

A single durable Drift queue: `clientUuid` · `schemaVersion` · `sequenceNumber` ·
`deviceBootSessionId` · payload · attempts · `lastError` · state · `createdAt` ·
`updatedAt`.

**Invariant: the outbox contains immutable operations, never mutable object
snapshots.** Replay is then predictable.

Per-entity FIFO ordering, exponential backoff, idempotency by construction (the
server upserts on the client UUID). Permanently-failed items surface in a
"da sincronizzare" screen where a human retries or discards — never silently dropped.

**Timers:** a monotonic clock drives the **running display only**. The persisted
segment is always reconstructed as explicit UTC start and end instants before upload,
so the ADR's capture-versus-truth invariant holds and a mid-shift device clock change
cannot corrupt a segment.

**Cache, two kinds with different invalidation:**

- *Reference data* — customers, locations, tickets, schedules, cantieri (now with
  coordinates and ticket links), materiali, ticket statuses and types, teams.
  Refreshed on sync.
- *View cache* — inbox contents, viewed reports. Cached on view, short-lived.

## 6. Verification

- Contract tests mobile ↔ OpenAPI, mirroring the web app's `CONTRACT_CASES` harness.
- **Outbox integration tests** — enqueue offline, restart the app, reconnect,
  duplicate retry, server conflict, successful replay. These are the highest-risk
  behaviours in the application.
- Drift schema-migration tests.
- Widget tests observing the known teardown discipline: a screen watching a Drift
  stream must be unmounted before teardown (`pumpWidget(SizedBox.shrink())` +
  `pumpAndSettle()`) or the suite hangs on a leaked `StreamQueryStore` timer.

## 7. Dependencies and order

```
M-A ──────────────────────────────► (parallel with backend T0/T1)
        │
        ├── M-B ── M-C   (needs backend T2, T4, T5, T6)
        ├──────── M-D    (needs backend T7)
        ├──────── M-E
        └──────── M-F    (needs backend T8)
```

## 8. Environment constraints

Flutter lives Windows-side (`/mnt/c/.../flutter/bin/flutter`); WSL has no Android
SDK. Agents write code and run `flutter analyze` and `flutter test` headless. Device
builds, emulator runs, `flutter build apk`, integration tests on hardware and
airplane-mode field testing are user-run on Windows — and they are the phase no
amount of agent velocity shortens.

## 9. Schedule

Full scope, no cut. The September pilot date stays and is allowed to slip rather
than be met by shipping a partial technician loop. Manager mode, anagrafiche and
voice are pilot scope, not post-pilot.

## 10. Out of scope

Background location and geofencing, multi-serial inventory UX, merging the three
approval workflows, and any offline queueing of manager or anagrafiche writes.
