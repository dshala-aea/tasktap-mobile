# Wave 0 — shared list shell and detail-shell additions

Task 0b of the Il Documento redesign swarm. Wave-1 list/detail agents treat these files as
read-only. Source of truth is `prototypes/list-screens.html` and `prototypes/other-details.html`.

## List shell — `lib/core/widgets/list/`

Import the barrel: `import '../../core/widgets/widgets.dart';` (the list widgets are re-exported
there).

| API | When to use | Replaces |
|---|---|---|
| `ListShell` | The whole list screen body: header (title, subtitle, `Nuovo`, extra header actions), search, chip row + `Filtri`, grouped rows, summary. Data-driven; keep your own providers/filters and hand it the resulting groups. | The hand-built `CustomScrollView` + `ScreenHeader` + `AppSearchBar` + per-screen row classes. |
| `ListHeaderAction` | A header text action (`Nuovo`). Pass `null` instead when the role cannot write (permission-denied hides it). | Ad-hoc `TextButton`s / red mono labels in headers. |
| `ListFilterRow` + `ListFilterChipData` | Quick single-facet presets. `onOpenFilters` renders the trailing red `Filtri` chip and must open the real sheet (Pianificazioni and any combinable-facet screen keep every facet there). | The Sept button-only filter and per-screen chip rows. |
| `ListGroupData` + `ListGroupHeader` | `ListShell.groups` entries. `title` is optional: pass `null` for a **flat list** (no heading, no rule, no count spacing); pass a title for a grouped list. `count` renders the mono count. | Faked groups / `SectionTitle` where a count is needed. |
| `ListDocumentRow` + `ListRowData` + `ListStatusTone` | One row: title / meta / secondary / stamp, 1px rule, chevron, leading slot, optional `rowKey`. Long strings clamp (title 2 lines, meta/secondary 1). `statusTone` overrides the stamp family for labels outside `statusFamilyOf`. | `_TicketRow` / `_RapportinoRow`-style private row widgets. |
| `ListSummaryFooter` + `ListSummaryData` | The two-part summary line under the last group. | Ad-hoc footer text. |
| `ListLoadingSkeleton` | `ListShellState.loading`; static bars, no spinner, reduced-motion safe. | `CircularProgressIndicator` as the whole list. |
| `ListShellState.unavailable` + `ListShell.unavailable` | Whole list cannot be read. Supply an `UnavailableState` with a retry action. | Bare error text. |
| `ListShell.empty` | Content is empty. Pass an `EmptyState` for an empty filter result or an `UnavailableState` for an empty catalogue — the two are different claims. | One generic empty message for both. |
| `ListShell.banner` | Offline/pending-sync banner slot above the header. Pass `const OfflineSyncBanner()`. | Stacking the banner over the list by hand. |

Notes:

- `ListShell` never reads a provider, route or repository. It also has no write-permission logic:
  omit `action` (and any header action) when the role cannot write.
- The status stamp tone is data, not string parsing: set `ListRowData.statusTone` when the label is
  not in `statusFamilyOf` (`Pianificato`, `In scadenza`, `Principale`, …). `StatusStamp` gained an
  optional `family` override for this; existing call sites are unchanged.
- `AppSearchBar` was restyled to the prototype (2px radius, 11px input, flat sheet, no inner
  decoration border). Its `controller`/`onChanged`/`margin` contract is unchanged.
- `ScreenHeader` gained `subtitleMaxLines` (default 1). `ListShell` uses 2 so a real list subtitle
  is not truncated.

## Detail shell additions — `lib/core/widgets/detail/`

| API | When to use | Replaces |
|---|---|---|
| `DetailHeroData.kind` + `DetailHeroVariant.summary` | The 10 master-data details. The summary layout puts the entity title and facts (`subtitle`) **inside** the hero card, with a rotated `StatusStamp` top-right and the primary action (`Modifica`, or `Apri PDF` for Report admin). Set `DetailStatus.tone` only for labels outside the `statusFamilyOf` vocabulary (`Attiva`, `In garanzia`, `6 sotto scorta`, `Oggi`, …); omitting it keeps the label-based mapping. | A per-screen hero rebuilt in each detail. |
| `DetailLinkRow` | A row in the prototype's section stack: bold name left, mono meta right, hairline, 44px target. Use for section links (`Relazioni`), date/scadenza facts and movement lines. | Per-screen `_SectionRow` copies. |

Existing pieces to reuse, not rebuild: `DetailScaffold` (frame, loading/unavailable, collapsed bar),
`DetailSection` (`isEmpty` hides it), `DetailFactsGrid`, `DetailActivityTimeline`,
`DetailAttachmentRow`, `GeoMapCard` (map-first sections), `ListRow` (member/person rows).

Rules already enforced by the shell: empty sections are hidden, and the hero's primary action and
`DetailScaffold.fab` are independent — do not pass a FAB when the hero already carries the action.
No fact should repeat between the hero and Sintesi; that is a data choice in the screen.
