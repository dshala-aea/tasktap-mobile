# Ferie/Permessi Mobile Client — design

Status: **Draft, for review.**

## Context

The backend (`TaskTap` repo, merged to `master`) has a complete ferie/permesso/malattia
absence-request workflow: `AbsenceRequestsController` with create/list/get/cancel/approve/reject/
reassignment-candidates endpoints, a single flat approver model, no accrual tracking. Full design
at `docs/superpowers/specs/2026-08-30-ferie-permessi-design.md` (backend repo) — this document
does not repeat those decisions, only the mobile-specific ones.

Mobile's scope, per that spec: **self-service request creation and a status list of the
requester's own requests.** Approval, rejection, and the reassignment-candidates tool are
explicitly web-only — no approve/reject UI on mobile, matching the established
"mobile stays technician-persona, office/admin tooling is web-only" precedent already applied to
Users/Roles/Audit-log elsewhere in this app.

## Scope

**In scope:**
- `AbsenceListScreen` — the requester's own past/pending requests, filterable by status, with
  swipe-to-cancel on cancellable rows.
- `AbsenceFormScreen` — create a new request (Ferie/Permesso/Malattia, date range, optional
  partial-day time range for a same-day Permesso, optional reason).
- A thin Dio API client + DTOs mirroring the backend's `AbsenceRequestsController` shapes.
- A new entry point: a tile in Altro → Gestione grid (same location Agenda already uses).
- Two new `StatusPill` color mappings (`'approvato'`, and confirming `'in attesa'`/`'rifiutato'`/
  `'annullato'` already resolve correctly).

**Explicitly out of scope:**
- Approve/reject UI (web-only, per the backend spec).
- Reassignment-candidates UI (web-only).
- Office-filing-on-behalf-of-someone-else (the backend endpoint supports it for
  `PresenzeAbsenceApprove` holders, but mobile is technician-persona — no UI surfaces it here; if
  office ever needs this on mobile, that's a separate ask, not assumed).
- Offline queueing — see Decisions below.
- Balance/entitlement display ("you have N days left") — the backend doesn't track this either
  (explicit non-scope in the backend spec).

## Decisions

**Online-only, no offline queue.** Matches `lib/features/agenda/`'s precedent exactly (a
personal, desk-typed, planned-in-advance write, not a field-capture action like a ticket or
timbratura punch). Submit is gated by the existing `ensureOnlineOrWarn(context, ref)` helper — no
local Drift table, no sync queue, no offline-created-then-synced state to reconcile.

**Two screens, not one**, mirroring Agenda's `agenda_list_screen.dart` /
`agenda_form_screen.dart` split. The list is the landing screen (reached from the Gestione grid
tile); a FAB opens the form; successful submit pops back to the list and invalidates its provider
to refresh.

**Cancel is swipe-to-cancel on the list row**, `Dismissible` + `confirmDismiss`, reusing the
existing shared `confirmDeleteDialog` (`lib/core/widgets/confirm_delete_dialog.dart`) with
`confirmLabel: 'Annulla richiesta'` instead of its default `'Elimina'` — same dialog every other
destructive confirm in the app already uses, just relabeled. Only Pending and Approved rows offer
the swipe action (the backend's `CancelAsync` throws `already_decided` for Rejected/Cancelled);
Rejected/Cancelled rows render as a plain, non-dismissible `ListRow`.

**Form fields and their behavior:**
- **Type**: `DropdownButtonFormField` — Ferie / Permesso / Malattia. Changing type resets the
  time-range fields (switching away from Permesso, or to a multi-day range, clears any partial-day
  selection — see below).
- **Start date / End date**: two separate `showDatePicker` calls (no date-range-picker widget
  exists in this app yet — every existing form, including the closest analog,
  `admin_schedule_form_screen.dart`, uses two independent single-date pickers; not worth
  introducing a new range widget for one screen). `firstDate` for the picker is `DateTime.now()`
  when Type is Ferie or Permesso (matches the backend's `backdated_not_allowed` rule — reject the
  input before it round-trips to the server); `firstDate` has no lower bound (a fixed reasonable
  floor, e.g. one year back) when Type is Malattia, since the backend explicitly allows backdating
  sick leave. `lastDate` for the End Date picker is bounded by `startDate + 366 days` (matches the
  backend's `range_too_long` cap — same reasoning, catch it before the round-trip).
- **Partial-day toggle**: appears only when Type == Permesso AND start date == end date (a
  same-day request). Default **on** ("Tutto il giorno"). Toggling off reveals two
  `showTimePicker` fields (start time, end time), mirroring `admin_schedule_form_screen.dart`'s
  existing start-time/end-time picker pattern. Toggling Type away from Permesso, or changing the
  end date so it no longer equals the start date, clears any selected times and hides the toggle
  — the resulting request is a full-day request, matching what the backend would accept anyway
  (`StartTime`/`EndTime` both null).
- **Reason**: `AppTextField`, optional, multi-line, no character limit enforced client-side beyond
  the backend's `1000` char column (a `maxLength` on the field is a reasonable belt-and-suspenders
  addition, not load-bearing).
- **Submit**: `VetroButton` with `isLoading` bound to a local `_isSaving` flag, same shape as
  `agenda_form_screen.dart`'s `_save`. On success: `ref.invalidate` the list provider, `showAppToast`
  success, `context.pop(true)`. On failure: `showAppToast` error. The exact message shown on a
  `DomainRuleException`-shaped 400 (e.g. `end_before_start`, `partial_time_incomplete`) needs one
  concrete decision at plan-writing time: does the existing Dio/error-handling layer already
  extract a friendly `message` string from a `ProblemDetails`-shaped 400 body, or does every
  screen currently show the same generic "Errore, riprova" regardless of *why* the server refused?
  If the former, reuse it as-is (all four `DomainRuleException` codes already carry Italian
  messages server-side, per the backend's own code). If the latter, this screen doesn't need to
  invent per-code client-side messages either — showing the server's own message string (when the
  interceptor already surfaces it) is enough; do not build a code→string mapping table on mobile
  duplicating the server's own strings.

**Status list filter chips**: Tutte / In attesa / Approvate / Rifiutate, same `AppChip` +
single-select-active-state pattern as `notifiche_screen.dart`'s filter row. "Cancellate" is not a
separate filter tab — a cancelled request is a terminal, low-relevance state; it still shows under
"Tutte" but doesn't need its own tab (revisit if this turns out wrong in practice, not worth a
speculative tab now).

**Empty state**: reuse the `EmptyState` widget, same two-variant shape `notifiche_screen.dart`
already established (a distinct message for "no requests yet" vs. "couldn't load — check your
connection", not one generic empty state for both).

## Data model (mobile-side DTOs)

Mirrors the backend's wire shape exactly — no client-side reinterpretation of the enums beyond
the tolerant int-or-string decode pattern this app already uses everywhere a bare backend enum
crosses the wire (see `notification_api_client.dart`'s `_enumNameFromWire`, and the session's own
recent fix there — the same defensive decode is needed here since `AbsenceTypeEnum`/
`AbsenceRequestStatusEnum` carry no `[JsonConverter(JsonStringEnumConverter)]` server-side either,
confirmed by reading the backend entity directly before finalizing this document).

```
AbsenceRequestDto
  id, requestedByUserId, createdByUserId       String (GUID)
  type                                          String ("Ferie" | "Permesso" | "Malattia")
  startDate, endDate                            String (date-only, "yyyy-MM-dd")
  startTime, endTime                            String? ("HH:mm:ss", null = full day)
  reason                                        String?
  status                    String ("Pending" | "Approved" | "Rejected" | "Cancelled")
  decidedByUserId, decidedAt, decisionReason    nullable, read-only display fields
```

## Testing

- API client: `fromJson` round-trip tests, including the int-ordinal decode path for `type`/
  `status` (matching the regression-test shape already used for `NotificationDto`).
- Form screen: widget tests for the partial-day toggle's show/hide logic, the date-picker
  `firstDate` bound switching correctly per `Type`, and the submit/error/success toast paths
  (mirroring `agenda_form_screen_test.dart`'s existing coverage shape, if that file exists — verify
  during planning).
- List screen: widget tests for filter-chip switching, swipe-to-cancel only appearing on
  Pending/Approved rows, and the two empty-state variants.

## Open questions for review

1. Does the existing Dio interceptor/error-handling layer already surface a server's 400
   `ProblemDetails.detail` message to the UI, or does every screen currently collapse all failures
   to one generic string? Settles how much (if any) client-side error-message work this needs —
   flagged above, not blocking the rest of this design.
2. Confirm the `StatusPill` string-key convention (`'approvato'`, `'in attesa'`, `'rifiutato'`,
   `'annullato'`) is the right vocabulary to add to `status_colors.dart` — these are guesses at
   natural Italian labels, not copied from an existing precedent for this exact domain.
