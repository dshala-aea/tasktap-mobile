# TaskTap Mobile — Screens Implementation Plan (from "TaskTap Design System")

Build these screens in Flutter to match the design, **wired to the REAL data layer** (Drift cache, sync, submit, auth from M1–M5) — the design files use mock `M.*`; replace with the actual Riverpod providers. Use the components from `DESIGN-SPEC.md`. Italian copy. Apply ui-ux-pro-max a11y/touch/motion.

## Navigation (decided: design's 5-tab IA)
Floating pill BottomNav, 5 tabs: **Dashboard · Ticket · Timbra · Calendario · Altro**. Everything else (Rapportini, Clienti, Prodotti, Magazzino, Fatture, Team, Tag, Notifiche, Audit, Impostazioni) reached via the **Altro** hub or from Ticket detail. Replaces the built 4-tab (Oggi/Interventi/Rapportini/Profilo).

## Phase P2 — Shell + Dashboard + Timbra
- **Shell:** go_router StatefulShellRoute with the 5-tab pill BottomNav; safe-area aware; badge on Altro (notifiche unread).
- **Dashboard** (`Dashboard` tab): dark **Hero** (radial/linear gradient, bottom radius 30) — "Bentornato" + user name (yellow, Sora 26); top-right glass bell(badge)+user. **ActiveJobCard** (glass) per in-progress intervention: status badge, title, client, HH:MM:SS timer tiles, "Apri attività". **StatsGrid** 2×2 (Interventi oggi / in corso / completati / prossimi — from real data). **QuickActions** row (Storico, Nuova pianificazione, Nuovo ticket, Nuovo report). **"Prossimi interventi"** SectionTitle + UpcomingItem cards (intervento #, cliente, indirizzo, priorità badge, data/ora, "Naviga" dark btn). **Empty state** variant when no active jobs (glass "Nessuna attività" + EmptyState + "Cerca ticket aperti").
- **Timbra** (`Timbra` tab) — **NEW feature**: dark screen, big date + live clock (Sora 72 thin, yellow), giant circular punch button (radial yellow, play icon + "INIZIA TURNO"), "Sessioni di oggi" panel (Ingresso/Pausa/Ripresa/Ora attuale rows + total). ⚠️ Needs a timbratura/worklog clock-in backend endpoint — if absent, store locally + flag backend task. Wire to the real WorkLog model where possible.

## Phase P3 — Ticket + Rapportino flows (core workflow)
- **Ticket list** (`Ticket` tab): ScreenHeader (title + "N totali · M in corso" sub + filter btn), ListToolbar (SearchBar + chips Tutti/Aperti/In corso/In attesa/Completati), ListRow per ticket (ticket icon tile, num + priority dot, titolo, StatusPill + data meta), FAB (nuovo). Wire to cached tickets.
- **Ticket detail:** big num + titolo, StatusPill + priorità badge + tipo chip, KeyVal card (Cliente/Sede/Tecnico/Data/Ore), Descrizione card, Prodotto-in-assistenza card, **Tabs** (Report/Controllo/Pianificazioni/Allegati/Fabbisogno) with content or EmptyState, bottom actions (Cliente / **Crea rapportino**).
- **Rapportini list** (under Altro / from Ticket): like ticket list, chips Tutti/Bozza/Inviata/Pagata/Annullato, ListRow (file icon, num + firma icon, titolo + tecnico·ore·materiali, StatusPill + data). Wire to Drift draft_reports + submitted.
- **Rapportino 4-step form** (decided: design's 4-step look, KEEP all offline data): Stepper (Dettagli/Ore/Materiali/Riepilogo). Replaces the M4 7-step editor UI but reuses the M4 draft repository + validation + autosave.
  - **1 Dettagli:** ticket/sede context card; titolo, descrizione, "lavoro extra" toggle; + cliente/work-address + ticket-OR-cantiere pickers + **GPS capture** (folded in).
  - **2 Ore:** per-tech hours tiles (HH MM) + **km/travel + start/stop timer**; dark "Totale ore" summary.
  - **3 Materiali:** qty steppers (− / value / +), "Aggiungi materiale", "nessun materiale" toggle; + **controlli** + **foto/allegati** (folded in).
  - **4 Riepilogo:** KeyVal summary + **firma cliente + firma tecnico** signature pads (dashed → captured).
  - Sticky bottom: Indietro / Avanti(→ "Invia rapportino" on step 4). On submit → M5 submission queue.
- **Rapportino view** (read-only, submitted): white header card (StatusPill + date, titolo, KeyVal sede/tecnico/cliente/ore), Descrizione, Materiali (qty + price), Firma cliente (captured stroke + "Firmato il…"), download action.

## Phase P4 — Calendario + Altro hub + Impostazioni + Notifiche
- **Calendario** (`Calendario` tab): ScreenHeader + Tabs (Giorno/Settimana/Mese/Lista); week-day scroller (active = dark/yellow, event dots); Giorno = hour grid with colored event blocks; Settimana = 7-col grid; Mese = month grid w/ event dots; Lista = grouped-by-day ListRows. Wire to cached schedules.
- **Altro** (`Altro` tab): dark user card (name/role/squadra); **Gestione** 2-col grid of colored-tile cards (Interventi, Rapportini, Clienti, Prodotti, Magazzino, Fatture, Team, Tag) → each opens its list; **Sistema** list (Notifiche+badge, Audit log, Impostazioni, Ruoli e permessi); danger "Esci dall'account".
- **Impostazioni:** profile card; grouped sections (Notifiche / App / Account / Sistema) of toggle+chevron rows; version footer. Wire toggles to real prefs (push, geo, offline sync, etc.). Logout → auth signOut.
- **Notifiche:** filter chips; list of icon-tile + title/body/time rows, unread dot; mark-all-read. Wire to SignalR/notifications if available, else cached.

## Phase P5 — Anagrafiche & system (reached from Altro)
Standard list pattern (ScreenHeader + ListToolbar + ListRow + FAB), wired to cache where data exists:
- **Clienti** (avatar initials, città·sedi·prodotti, ticket count), **Prodotti** (package tile, matricola chip, prossima manutenzione), **Magazzino** (Tabs Magazzini/Articoli/Movimenti; dark valore-totale card; low-stock red), **Fatture** (fatturato-mese card + mini bar chart; status pills), **Team** (Lista/Squadre/Ruoli; online dot; avatar stacks), **Tag** (Tag/Tipi/Stati; color swatches; stato flow), **Audit log** (timeline w/ action-colored dots).
> Many of these are office-domain; on mobile show read-only where the tech has no write scope, and only if backend data is reachable. Prioritize Clienti/Prodotti/Magazzino (tech-relevant); the rest can be thin/deferred.

## Cross-cutting
- Re-skin the **M2 Login** screen to the design system (brand, yellow CTA).
- All screens wired to real Riverpod providers (Drift/sync/auth/submit), not mock `M.*`.
- `flutter analyze` clean + `flutter test` green after each phase; add widget tests per screen.
- Backend gaps to flag as tasks: **Timbra clock-in/out** endpoint; any list (Fatture/Team/Tag/Audit) whose mobile data isn't in `/api/sync/mobile` (most are office-only — keep thin/deferred).
