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

## Open, not yet asked

Carried from the backlog, in rough dependency order:

1. **Timbra page must not scroll** — responsive, fill the space, no overflow.
2. **System-UI overflow** on some screens.
3. **Navbar icon spacing** — too much space right of the icon.
4. **Calendar navigation** between days/weeks/months.
5. **Form/wizard buttons too large** — should draw attention without dominating.
6. **Animations** — modern feel across shell and transitions.
7. **Navigation and user flow** rework.
8. **GPS captured silently** when permission is granted, rather than prompting per report; and a
   coherent permission strategy (notifications, GPS) — ask at the moment of need or when the
   related setting is switched on.
9. **AI/STT** — embed speech-to-text in the app vs delegate responsibility to the user.
   `POST /api/ai/transcribe` exists; the blocker is an audio-recording dependency plus microphone
   permissions on both platforms, which is a platform change to weigh against the pilot date. The
   AI Act transparency angle belongs with decision 3.
10. **Further contract mismatches** — the response-shape guard covers `GET` bodies. Request bodies
    on POST/PUT are NOT yet checked against the snapshot; the sort-grammar bug shows query
    parameters are a third unchecked surface.
