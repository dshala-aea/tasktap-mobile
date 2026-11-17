# Rapportini in navbar, Interventi in Altro — design

Status: **Draft, for review.**

ClickUp: [CHANGE] Replace tickets from navbar with reports (`12493t4vybw`).

## Intent

The technician's primary daily artifact is the rapportino, but the bottom nav's first
operational tab is **Ticket**. Move **Rapportini** into that slot and keep tickets one tap away
under **Altro › Interventi**, which already exists.

## Goals

- Tab 1 (index 1) of the floating bottom nav becomes **Reports** (`RapportiniListScreen`).
- Every existing `/ticket` path keeps working: detail deep links, notification taps, and the
  `TicketOverdueDigest` route.
- Tickets remain reachable from **Altro › Interventi**, with a working back affordance.
- The duplicate **Rapportini** tile in the Altro hub is removed (it is now a main tab).

## Non-goals

- No change to the ticket list/detail screens themselves.
- No change to rapportini list/editor behavior or its `/altro/rapportini/...` paths.
- No new backend work.

## Approaches

1. **Swap places (chosen).** Branch 1 hosts `/altro/rapportini`; `/ticket` moves to a root-level
   full-screen route reached with `push` from Altro › Interventi. Smallest diff; all paths and
   deep links stay valid.
2. Keep `/ticket` as a hidden 6th shell branch — fragile `currentIndex`/branch mapping; rejected.
3. Relabel the Ticket tab without changing its destination — does not meet the request; rejected.

## Decisions

- **Branch 1 = `/altro/rapportini`.** Move the existing `GoRoute` (with its nested editor/view
  routes) out of the Altro branch into branch 1. Paths stay unchanged, so the
  `/altro/rapportini` route requirement and notification deep links are untouched.
- **`/ticket` becomes a top-level route** (`parentNavigatorKey: rootNavigatorKey`) containing the
  existing `TicketListScreen` and its nested detail/assets routes. The detail routes are already
  root-level in effect (`parentNavigatorKey: rootNavigatorKey`), so only the list wrapper moves.
- **Altro › Interventi uses `context.push(AppRoutes.ticket)`** instead of `go`, since the ticket
  list is no longer a shell branch. System back (and iOS swipe) returns to Altro. A visible back
  button is added only if the ticket list header does not already provide one — verified at
  implementation time.
- **Nav item:** `AppBottomNavIcons.ticket` stays (ticket icon is still used elsewhere); add a
  `reports` icon (`LucideIcons.fileText`, matching the Altro tile) and change tab 1's label to
  `Reports`.
- **Remove the "Rapportini" tile** from `altro_hub_screen.dart`'s Gestione tiles; keep
  "Interventi".

## Testing

- `bottom_nav_test.dart`: tab 1 label is `Reports`, icon is the reports icon; the other four
  tabs are unchanged.
- `app_shell_test.dart`: tapping tab 1 opens the Rapportini list; Altro › Interventi still opens
  the ticket list.
- Existing notification/deep-link tests continue to pass unchanged (`/ticket`, `/ticket/:id`,
  `/altro/rapportini/...`).
- `flutter analyze` + targeted `flutter test` for router, home shell, bottom nav, Altro hub.

## Open questions

None.
