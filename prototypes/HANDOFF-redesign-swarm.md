# Handoff — TaskTap mobile "Il Documento" redesign, wave 2 (lists + master-data details)

For: an agent orchestrator running a swarm. Repo: `/mnt/d/AEA/Sviluppi/TaskTap/mobile` (Flutter, GitHub `dshala-aea/tasktap-mobile`, default branch `main`).
Written: 2026-11-04. Language of UI copy: Italian. Source of truth: the HTML prototypes in `prototypes/` — **not** any spec, plan or earlier implementation.

---

## 1. Goal

Make 23 existing screens look and behave like the prototypes: **13 existing list screens** (`prototypes/list-screens.html` has 14 list entries — Cantieri plus the "tredici" of its lede — but **Commesse has no list screen in the app**, so it is excluded, see 3.1) and **10 master-data detail screens** (`prototypes/other-details.html`). Wave 1 (ticket, rapportino view, cantiere detail) is already on `main`; the detail shell exists in `lib/core/widgets/detail/` (`detail_scaffold`, `detail_hero`, `detail_section`, `detail_facts_grid`, `detail_activity_timeline`, `detail_attachment_row`). Reuse it; do not fork it.

**Success** = a person opening the prototype phone and the real screen side by side sees the same screen: same hierarchy, typography, spacing, rules/borders, colours, copy, grouping, ordering, states. Behaviour, data sources, offline paths and deep links of every existing screen are preserved.

## 2. Why this handoff exists (lessons from wave 1 — read before dispatching)

Wave 1 shipped "layout moved, look not matched". Causes, and the rule that prevents each:

| What went wrong in wave 1 | Rule now |
|---|---|
| Plan said "wrap the existing section content". Old widgets (8-tile compartment grid, KeyVal cards) stayed, only hero/bar were new. | **Rebuild the visible UI from the prototype markup.** Reuse data/providers/behaviour, never the old visual widgets. |
| The written spec contradicted the mockup (title inside hero vs above it); the implementer followed the spec. | **Prototype wins over every doc.** If a doc/spec disagrees, follow the prototype and list the disagreement in the report. |
| Nobody looked at a rendered screen. Every wave-1 report said "not verified visually". | **Mandatory render-and-compare gate (section 5).** No screen is "done" without it. |
| Agents ran only their own feature tests. #201 merged with a red `main` (`app_palette_test.dart` guard: substring `AppBar(` banned in `lib/`). | Run the **full** `flutter test` + `flutter analyze` before opening a PR (section 7). |
| Eager providers added at page open (history/attachments) violated "no new network reads". | Section 4 rules on data. |
| Facts silently duplicated / dropped. | Prototype lists exactly which facts go where; follow it. |

## 3. Scope

### 3.1 Lists (13) — `prototypes/list-screens.html` (data-driven JS: read the `lists` array; each entry has `filters`, `groups`, `row`, `summary`, `cfg`)

Shared model per the prototype: app bar → screen title + subtitle → search → filter control → group headings with counts → rows (title, meta line, secondary line, status stamp) → summary line. "Cambiano filtri, gruppi e riga; non cambia il modello."

| Prototype list | Likely file (verify; some are tabs inside bigger screens) |
|---|---|
| Cantieri | `lib/features/cantiere/cantieri_list_screen.dart` |
| Ticket | `lib/features/ticket/ticket_list_screen.dart` |
| Rapportini | `lib/features/rapportino/rapportini_list_screen.dart` |
| Clienti | `lib/features/clienti/clienti_list_screen.dart` |
| Sedi | `lib/features/admin/locations/admin_location_list_screen.dart` |
| ~~Commesse~~ | **EXCLUDED — no list screen exists** (no `commesse_list_screen.dart`, no list route: `app_router.dart` declares only a permission at ~:291 and `commesse/:id` at ~:685; no local Drift mirror, data only via `admin_api_client.dart` ~:443). Building it = new route + new network read, which rules 3/4 forbid. Goes to PROPOSALS for the owner. The Commessa **detail** (3.2) is still in scope. |
| Contratti | `lib/features/admin/contracts/admin_contract_list_screen.dart` |
| Prodotti in assistenza | `lib/features/admin/prodotti/admin_prodotto_list_screen.dart` |
| Materiali | `lib/features/admin/materiali/admin_materiale_list_screen.dart` |
| Magazzini | `lib/features/admin/magazzini/admin_magazzino_list_screen.dart` |
| Squadre | `lib/features/admin/squadre/admin_squadra_list_screen.dart` |
| Pianificazioni | `lib/features/admin/schedules/admin_schedule_list_screen.dart` (has the existing filter bottom-sheet) |
| Report admin | `lib/features/admin/reports/admin_report_list_screen.dart` |
| Ferie | `lib/features/ferie/ferie_permessi_list_screen.dart` |

Count check: 13 in-scope lists = Cantieri (technician), Ticket, Rapportini, Clienti, Sedi, Contratti, Prodotti, Materiali, Magazzini, Squadre, Pianificazioni, Report admin, Ferie. Read the whole `lists` array in `list-screens.html` (entries span ~lines 148-242; Squadre/Pianificazioni/Report admin/Ferie are at the end).

Scope clarifications (owner can overrule):
- **Cantieri = the technician list** (`cantieri_list_screen.dart`, groups "Da seguire oggi / Altri attivi / Pianificati"). The **admin** Cantieri list (`lib/features/admin/cantieri/admin_cantiere_list_screen.dart`, route `/altro/cantieri`) is a different screen and **stays as-is** in this swarm (my call; cheap to add later as a 14th list once the shell exists).
- **Materiali = `admin_materiale_list_screen.dart` only.** `MagazzinoScreen` (`lib/features/magazzino/magazzino_screen.dart`) with its own Articoli / Giacenze tabs and category chips is a separate screen the prototype does not show: **out of scope** (don't touch it; PROPOSAL if the owner wants it aligned).
- **Filters:** the prototype's filter control is the **chip row plus a red "Filtri" chip that opens the filter bottom-sheet** (`list-screens.html` ~:314 renders the chips + Filtri; ~:304 renders the sheet design). This **supersedes** the Sept spec (`docs/superpowers/specs/2026-09-07-list-search-filter-redesign-design.md`), which deliberately standardised a button-only, **non-two-tier** filter everywhere; the owner must sign off on bringing the chip row back. **Keep the sheet**: screens with combinable facets (Pianificazioni, and any other that has them today) keep all their facets reachable through "Filtri"; the chips are the quick single-facet presets from the prototype. The prototype's "Filtri" chip has **no JS click handler** and the sheet is a static side-panel demo — wire the chip to the real sheet and keep its `Applica`/`Azzera` behaviour; do not ship a dead control.
- **Materiali header actions (preserve):** the existing Materiali list (titled "Magazzino") has header actions "Giacenze e movimenti" (`/altro/magazzino/giacenze`) and "Magazzini" (`/altro/magazzino/magazzini`) at `lib/features/admin/materiali/admin_materiale_list_screen.dart:131-144`, plus the show/hide-inactive toggle. The prototype does not show them, but they are the **only** entry points to those screens: keep them (restyled to match the prototype header) and list them under KNOWN DEVIATIONS. Do not drop them while rebuilding the header.

### 3.2 Master-data details (10) — `prototypes/other-details.html` (data-driven `screens` array)

All use the existing shell with **SummaryHero + primary `Modifica`** (Report admin: `Apri PDF`). Section order differs per subject ("first section" choice) — copy it exactly; empty sections are hidden; no fact repeated between hero and Sintesi; no FAB when the hero has the action.

| Detail | File | First section (prototype choice) |
|---|---|---|
| Cliente | `lib/features/admin/customers/admin_customer_detail_screen.dart` | Relazioni |
| Sede | `.../admin/locations/admin_location_detail_screen.dart` | Documenti & mappa |
| Commessa | `.../admin/commesse/admin_commessa_detail_screen.dart` | Relazioni (cantieri) |
| Contratto | `.../admin/contracts/admin_contract_detail_screen.dart` | Sintesi (scadenze) |
| Prodotto in assistenza | `.../admin/prodotti/admin_prodotto_detail_screen.dart` | Attività (storico) |
| Materiale | `.../admin/materiali/admin_materiale_detail_screen.dart` | Movimenti |
| Magazzino | `.../admin/magazzini/admin_magazzino_detail_screen.dart` | Sintesi (sotto scorta) |
| Squadra | `.../admin/squadre/admin_squadra_detail_screen.dart` | Relazioni (membri) |
| Pianificazione | `.../admin/schedules/admin_schedule_detail_screen.dart` | Sintesi (impegno) |
| Report admin | `.../admin/reports/admin_report_detail_screen.dart` | Documenti (PDF) |

### 3.3 Out of scope
Forms/wizards, navigation/bottom bar, dashboard, timbra, login/onboarding, dark mode work beyond tokens that already exist, anything under `lib/features/ticket|cantiere/…detail` and `rapportino_view` (done in wave 1 — don't regress them).

## 4. Rules (hard)

1. **Prototype is the spec.** Open the HTML, read its CSS (`:root` tokens, sizes, letter-spacing, radii 2px, 1px rules, no shadows, mono labels uppercase, stamps rotated -3deg with double border) and the markup/JS for the screen. Match type scale (Archivo Narrow display / Archivo body / IBM Plex Mono for refs, times, counts), spacing, borders, colours, copy.
2. **Tokens, not hex.** Use `lib/core/theme/app_palette.dart`, `app_text_styles.dart`, `app_spacing.dart`. If a prototype colour has no token, report it (wave 1: prototype green `#248A3D` vs token `palette.green` — flag, don't hardcode).
3. **Rebuild visuals; keep logic.** Providers, repositories, routing, permissions (`CapabilityGate`), offline/sync behaviour, deep links stay. Old visual widgets (cards, KeyVal rows, accordion/compartment tiles, ListRow icon tiles) are replaced wherever the prototype shows something different.
4. **Data / network.** No new HTTP calls, endpoints, tables, migrations or packages. Read only what the screen already read (local mirror/providers). Never add providers that fire requests at page open; heavy/optional data loads on demand (tap/open sheet). A fact with no data source is **dropped** from the screen (list it in the report), not invented.
5. **Additions are allowed — within limits.** The product owner allows adding features when the logic needs them or they are clearly useful to the user (e.g. a derived count/label, an empty state, a disabled-with-reason action, a quick link). Allowed if it (a) uses only data already available locally, (b) does not change existing behaviour, (c) is listed in the report under **ADDITIONS** with a one-line why. Anything that needs a backend/API/DB change or a product decision → do **not** build; list under **PROPOSALS**.
6. **Prototype ≠ real data.** Mockup strings are placeholders ("Rossi Srl"). Real strings may be longer/missing: apply ellipsis/clamp rules, test with real Italian strings, handle null/empty/loading/error/offline/pending-sync states per the shell's state matrix (loading skeleton, `UnavailableState` with retry, offline banner kept, permission-denied hides write actions).
7. **Accessibility.** 44–48px touch targets without changing visuals (add tap padding), semantic labels on icon-only controls, stamps carry text, reduced-motion respected.
8. **Conflicts between prototype and existing app conventions** → **follow the prototype** and report the conflict; never silently pick. (The filter case is decided in 3.1: chips + "Filtri" sheet. That supersedes the Sept spec's button-only, non-two-tier decision, so it needs explicit owner sign-off before wave 1.)

## 5. Mandatory verification gate — render and compare

A screen is **not done** until its report contains a side-by-side comparison. Tooling already on the box:

- **Prototype screenshots:** headless Chromium is installed (Playwright cache `~/.cache/ms-playwright/chromium*`; node/npx available — verify with `npx playwright --version`; fall back to the chromium binary's `--headless --screenshot`). Screenshot just the phone element for the subject (list: select the list via the prototype's tab/JS, 390×844 viewport; details: the `.screen-card` for the subject). Wave 0 provides a script `tool/prototype_shot.mjs <html> <selector|listId> <out.png>`.
- **App screenshots:** Flutter golden tests (the repo already has `alchemist` + `test/golden/`, bundled fonts). Wave 0 provides a harness `test/golden/redesign/` that pumps a screen with fixture/provider overrides at 390×844, DPR 2–3, real bundled fonts, and writes `build/redesign/<screen>.png`. Goldens are **review artifacts, not committed baselines** unless the owner asks (platform font drift; the repo keeps only `bottom_nav_tabs` goldens).
- **Compare** by opening both PNGs (the Read tool displays images), then write a per-screen table: `element | prototype | app | match? | note`. Cover at least: app bar, title/kicker/subtitle, hero or search+filters, each section/group heading, row/cell anatomy, stamps, rules, spacing rhythm, empty/loading state.
- Fix every mismatch you can; list the rest as **KNOWN DEVIATIONS** with reason. "Looks right from reading the CSS" is **not** acceptable evidence (that is exactly what failed in wave 1).
- If rendering a screen needs fixtures that don't exist, create minimal fakes under `test/support/` (reuse existing ones first). If a screen genuinely can't be rendered headlessly, say so and why; don't skip silently.

## 6. Orchestration plan

Parallelism is safe only when agents don't share files. Therefore waves:

**Wave 0 — foundation (two agents, 0a and 0b run in parallel; both block wave 1).** 0a owns `tool/` and `test/golden/redesign/`; 0b owns `lib/core/widgets/**` and, if a token/style addition is truly needed, `lib/core/theme/**`. They touch disjoint files. 0b's own render-and-compare gate needs 0a's harness, so 0b writes the widgets first and runs its comparison once 0a lands the harness (0a lands it early on `feat/redesign-wave0-harness`; 0b works on `feat/redesign-wave0-shell`; 0c merges both into `feat/redesign-wave0`).
- 0a *Harness*: `tool/prototype_shot.mjs` + golden screenshot harness (section 5) + a README snippet in the handoff folder showing the two commands. Prove it on a wave-1 screen (cantiere detail) and attach the comparison.
- 0b *Shared list shell* (new, from `list-screens.html`): widgets for list page frame (title + subtitle + action `Nuovo`), search field styling (wrap/restyle `AppSearchBar`), filter row (chips per prototype, plus the existing filter-sheet entry for screens that have combinable facets), group header (title + mono count), document row (title / meta / secondary line / stamp, 1px rules, no card chrome unless prototype shows it), summary footer line, empty/loading/error states. Names are the agent's call but must be documented in a short `docs/` note. Also check `DetailHero` summary variant, `Movimenti`/specialist section support, and any gap the 10 details need (e.g. map-first section, scadenze row, membri row) — **add generic pieces here, not per screen**.
- 0c Merge 0a+0b into `feat/redesign-wave0`, open **one** PR (base `main`), CI green, **merge before wave 1 starts**. If stacking instead, wave-1 agents branch from the wave-0 branch and PRs merge in order; pick this or the merge-first mode for the whole run.

**Wave 1 — lists + details, 3–4 concurrent agents at a time (not 8).** The box has 16 cores but ~7 GiB RAM (~4 GiB free); parallel worktrees each running `build_runner` plus the full `flutter test` will thrash or OOM at 8. Run a queue with concurrency 3–4. One agent per screen (23 screens: 13 lists + 10 details), or per tight pair that truly shares a file; the Pianificazioni list+detail pair makes 22 agents. Each agent: own git worktree off the wave-0 result (once wave 0 is merged: `origin/main`; if the orchestrator stacks PRs: the wave-0 branch — see section 7), own branch `feat/redesign-<screen>`, touches only its screen's files (+ its tests). **Shared files (`lib/core/widgets/**`, theme, routes, `pubspec`) are read-only in wave 1**; if a shared widget needs a change, the agent stops and sends the orchestrator a request (small PR to wave-0 branch) rather than editing it. Suggested queue order (13 lists + 10 details = 23 agents): A) lists Ticket, Rapportini, Cantieri, Clienti; B) lists Sedi, Contratti, Prodotti, Materiali; C) lists Magazzini, Squadre, Pianificazioni, Report admin, Ferie; D) details Cliente, Sede, Commessa, Contratto, Prodotto; E) details Materiale, Magazzino, Squadra, Pianificazione, Report admin. Feed the queue so at most 3–4 run at once; lists first (they depend only on the list shell), then details. Pianificazioni list and detail share `admin_schedule_*` code and its filter sheet — give them to one agent.

**Wave 2 — integration.** One agent merges/rebases, runs the full suite, regenerates all comparison PNGs for a single review sheet (one image per screen: prototype | app), and checks cross-screen consistency (same header, same group heading, same stamp usage).

## 7. Engineering requirements (every PR)

- Worktrees: **branch base rule** — after wave 0 is merged, base is `origin/main`: `git worktree add -b <branch> .worktrees/<name> origin/main`. If the orchestrator chooses stacked PRs instead, base is the wave-0 branch (`origin/feat/redesign-wave0`) and PRs must be merged in order, wave 0 first. Pick one mode for the whole run and say so in the dispatch. The post-checkout hook runs build_runner and is **slow (minutes)** — wait for it; don't kill it. `dart pub` failing in the hook on `alchemist` is noise; use `flutter pub get`/`fvm flutter`.
- Before opening a PR: `flutter analyze` (whole project, no new issues) and **full `flutter test`** (CI runs ~4100 tests incl. repo guards, e.g. `test/core/theme/app_palette_test.dart` bans the substring `AppBar(` anywhere in `lib/` except two signature screens, and a ban on device-zone midnights; widget names like `_FooAppBar` trip it — use `TopBar`/`Header`). CI also runs three device-time-zone jobs (Europe/Rome, America/Los_Angeles, Pacific/Auckland).
- Update existing tests to the new UI instead of deleting expectations; add widget tests for new widgets (placement, ellipsis, states). Use `find.byKey`/semantics rather than brittle text where the same text now appears twice.
- Commits: conventional (`feat(<area>): …`/`fix(...)`), no attribution tricks, **do not push to `main`, do not merge PRs yourself**. Push branch + open PR (base `main`, or stack on wave-0 branch), body = the per-screen report (section 8) including the comparison table and PNG paths. Mention CI status honestly; if CI is red for reasons outside your change, say which.
- Never touch the main checkout `/mnt/d/AEA/Sviluppi/TaskTap/mobile` working tree; it may hold the owner's unrelated uncommitted work. Never use bare `git stash`.
- Backend/web repos are out of scope for this swarm. (If a screen needs a field the API doesn't provide, that is a PROPOSAL.)

## 8. Per-screen report (required format)

```
SCREEN: <name>  BRANCH: <branch>  PR: <url>
RESULT: matches prototype / matches with deviations
COMPARISON: <table: element | prototype | app | match | note>  + PNG paths (prototype, app)
DEVIATIONS (known, with reason):
ADDITIONS (features/logic added beyond the prototype, with why):
PROPOSALS (needs backend/product decision, NOT built):
DROPPED FACTS (in prototype, no data source):
BEHAVIOUR PRESERVED: <offline / permissions / deep links / actions — what was checked>
TESTS: analyze <result>; full flutter test <N passed / N failed>; new tests <list>
NOT VERIFIED:
```

## 9. Definition of done (per screen)
1. Rendered side-by-side comparison attached; no unexplained mismatch.
2. Full analyze + full test suite green locally.
3. No new network read at open; no new packages/tables/endpoints.
4. Behaviour/permissions/offline/deep links preserved (spot-checked and stated).
5. Report in the format above; PR open, not merged.

## 10. Orchestrator notes / judgement calls already made (change if wrong)
- I split into waves because the 13 lists share a model and the 10 details share the shell; building the shared list shell first avoids 13 divergent implementations (the wave-1 failure mode in reverse).
- Prototype colour/size values are the target; where a token differs slightly the token wins and the difference is reported.
- Goldens are throwaway review images, not committed baselines (my call; the owner may want them committed later).
- Concurrency 3–4 (machine: 16 cores, ~7 GiB RAM, ~4 GiB free); each worktree runs `build_runner` and the full suite. Goldens are review artifacts only and are **not CI-enforced** — the PR comparison image is the only visual gate.
- Open owner decisions: Commesse list (new screen, needs new route/network read — excluded); admin Cantieri list (left as-is; no UI links to it); `MagazzinoScreen` tabs (left as-is; keep the Materiali header action that reaches it); owner must sign off on chips + "Filtri" sheet, which supersedes the Sept button-only spec.
- ClickUp/backlog linkage was not part of this handoff; the orchestrator may create one task per screen if desired.
