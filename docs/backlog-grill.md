# Backlog grill — 2026-08-15

Outcome of stress-testing the 14-item backlog raised from real-device use. Decisions are the
user's; diagnoses are verified against the code and the frozen contract, not recalled.

Nothing below is built yet except the four items marked **FIXED**.

---

## Decided

### 1. Customer confidentiality outranks convenience

A technician must not be able to enumerate the customer's client book — the stated risk is a
technician selling those contacts to a competitor.

The line the user drew: **a picker returns the customer you are standing at; a browse screen
enumerates the book with details.** Lookup is fine, enumeration is not.

- **Clienti screen (`/altro/clienti`)** — must NOT be a browsable full book with details for a
  Technician. It lives under Altro, which PRODUCT.md defines as the office surface.
- **Pickers (ticket wizard cliente/sede, rapportino)** — keep search plus locations. Operationally
  required: without them a technician cannot file a ticket or a report at all.

> Whatever is built, the control belongs on the server. A client-side restriction is not a
> restriction — the app's own token can call the API directly.

### 2. Picker behaviour: local first, server search on demand

The mirror's customers appear instantly and work offline; a search action queries the server when
there is signal. Same pattern for the Clienti list and the ticket wizard, so it is one piece of
work rather than two.

### 3a. Compliance driver: pilot hardening, not a conformance claim

Fix what is provably broken before the September pilot; defer anything needing legal input. This
is deliberately **not** a claim of conformance — a privacy policy, a DPA with the AI provider, a
record of processing and an accessibility statement are documents, not code, and no amount of
engineering closes them.

### 3b. Client-book control: permission-gated list, narrow search, rate limited

- `GET /api/Customers` browse/paging requires an office-level permission.
- A separate **narrow search** stays open to Technicians: minimum query length, capped results, no
  paging — enough to find the customer you are standing at, not enough to harvest the book.
- Search is **rate-limited per user**, with alerting on unusual volume.
- Both paths audit-logged.

Note the honest limit: rate limiting raises the cost of slow harvesting, it does not prevent it,
and the alert threshold will be wrong at first.

### 3. EU compliance: audit first, then plan

Across backend, frontend and mobile, against GDPR + AI Act + EAA, reporting gaps per surface with
severity — then scope from evidence. Plus the confidentiality requirement above, which is a
commercial concern rather than a regulatory one but lands in the same audit.

**Already provable:** the backend serves `/api/Gdpr/consent`, `/api/Gdpr/export` and
`DELETE /api/Gdpr/account`, and **mobile exposes none of them** — zero references in `lib/`. No
privacy notice either, and GPS/notification permissions are taken without a stated purpose.

---

## Diagnosed, root cause known

### The sync scope is the cause of three reported "bugs"

`MobileUserSyncService.GetDeltaAsync` scopes the payload to:

```
schedules assigned to me, activityDate ∈ [today, today + SyncWindowDays]
  → their locations → their tickets → those customers
```

Forward-looking only. So a technician with no upcoming scheduled work syncs **zero customers**, and
anyone they worked for last month drops out. That single fact explains:

- "clienti not visible on mobile whereas on web they are"
- "ticket wizard selects are not working" — `step_cliente_sede` reads the same mirror and, unlike
  the rapportino wizard, has **no empty-state and no free-text fallback**; it renders a dead picker
- any report/ticket flow that needs a customer outside the window

Note this is also, accidentally, the only thing currently enforcing decision 1.

### FIXED this session

- **Cantiere clock 400 on every dashboard poll** (`60a67d0`) — the backend's sort grammar is a
  leading minus; the client sent `sort: 'createdAt desc'`, which is read as a column name, misses
  the allowlist and raises `invalid_sort`. A technician clocked into a site never saw that clock.
  Guarded: any sort value containing a space now fails a test.
- **Six paginated-envelope mismatches** (`08611f2`) — including both technician pickers.
- **Buttons under the nav** (`08611f2`, `8dd2d6c`) — clearance token; 17 FABs, 36 paddings.
- **Fonts fetched at runtime** (`87fe3df`) — Sora/Manrope now bundled; 18 call sites had been
  rendering as system sans on every device.

---

## Closed since (2026-08-16/17)

- **8. GPS/notification permission strategy** — done. `askPermissionPurpose`
  (`lib/core/widgets/permission_purpose_sheet.dart`) states the purpose *and what still works
  without it* before the OS dialog. The notification request moved out of `runTaskTapApp()` — it
  was the first thing on screen at first launch — and now fires when the technician turns the
  setting on. `pushAbilitate` defaults to true, so it is also reconciled against the real OS
  answer at load, or a fresh install would show the switch on with permission never asked.
  Location asks at both call sites; the cantiere one asks *before* the spinner.
- **9. AI/STT** — done earlier (`dedafd6`, `c6962ed`): on-device only, capability-gated,
  Impostazioni reports what the handset can do. `POST /api/ai/transcribe` stays unwired.
- **10. Further contract mismatches** — done. `test/contract/request_body_contract_test.dart`
  drives the real client methods through a capturing Dio adapter and checks body keys, query
  parameter names and the sort grammar for all 36 write routes. A new POST fails the build until
  someone writes a case or records why it cannot be checked.
- **GDPR (decision 3)** — mobile now exposes consent and export read-only under Altro → Sistema
  → *I miei dati*. Deletion is deliberately absent, and the screen says so and says who to ask.
  Consent is read-only until the `consentType` catalogue is pinned down.

> **A warning worth carrying.** Two checks in that contract file exist only to stop it passing
> while proving nothing, and one of them caught a real mistake in its own scanner: the regex
> matched type arguments with `[^>]*`, which cannot match `.post<Map<String, dynamic>>(`. It found
> 23 of 36 routes and the coverage test passed anyway. **A coverage check's failure mode is that
> it goes quiet, never that it goes loud.** Floor the counts.

## Open, not yet asked

Carried from the backlog, in rough dependency order:

1. **Timbra page must not scroll** — responsive, fill the space, no overflow.
2. **System-UI overflow** on some screens.
3. **Navbar icon spacing** — too much space right of the icon.
4. **Calendar navigation** between days/weeks/months.
5. **Form/wizard buttons too large** — should draw attention without dominating.
6. **Animations** — modern feel across shell and transitions.
7. **Navigation and user flow** rework.
8. ~~GPS/permission strategy~~ — see *Closed since*.
9. ~~AI/STT~~ — see *Closed since*.
10. ~~Further contract mismatches~~ — see *Closed since*.
11. **Client-book confidentiality is still enforced only by accident.** Decision 1 above is not
    built. The only thing stopping enumeration today is the forward-looking sync window, which is
    a side effect, not a control — and the app's own token can call `GET /api/Customers`
    directly. Decision 3b (permission-gated browse, narrow rate-limited search, both audited) is
    server work and has not started.
12. **Real settings** — `GET/PUT /api/NotificationSettings` is wired; `PUT /api/Users/me/preferences`
    and `PUT /api/Auth/profile` are not, so several Impostazioni toggles still write local prefs
    the server never sees.
