# Detail screen proposals

Static visual: [`detail-layouts.html`](./detail-layouts.html)

## A — Hero + stack (chosen)

Identity header → one hero with status and the primary action → ordered sections:
Sintesi → Relazioni → Attività → Documenti & mappa. Operational screens put
Attività directly under the hero. The hero collapses into a 56px sticky
status/action bar on scroll.

## B — Overview board

Header → 2-column status/KPI grid → sticky action bar → facts and relations in
sheets. Fast to scan, but hides the day/activity behind taps and reads like a
dashboard rather than a document.

## C — Timeline first

Header → compact hero → the page is mainly a chronological activity feed; facts
in a bottom sheet. Best for ticket/cantiere/rapportino, weak for master data.

## Decision

A. It is the only layout that works for both operational and master-data
screens, and it is already proven on Cantiere and Ticket.

Full spec: `docs/superpowers/specs/2026-11-04-detail-shell-design.md`
Ticket plan: `docs/superpowers/plans/2026-11-04-detail-shell-ticket.md`
Rapportino plan: `docs/superpowers/plans/2026-11-04-rapportino-detail-shell.md`
