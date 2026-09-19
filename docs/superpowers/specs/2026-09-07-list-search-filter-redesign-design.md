# List Search & Filter Redesign (Phase 1)

## Problem

Every searchable list screen in this app uses the same `AppSearchBar` (consistent, solid — not
touched by this work). Filtering, however, is three unrelated, hand-rolled idioms with no shared
widget:

1. **No filters** — Clienti, admin Squadre/Prodotti/Contracts: search only.
2. **Single-select `AppChip` row** — Ticket (`ticket_list_screen.dart:163-193`), Rapportini
   (`rapportini_list_screen.dart:164-193`), Magazzino Articoli tab's category chips and Giacenze
   tab's "Tutte / Sotto scorta" 2-chip toggle (`magazzino_screen.dart:190-230`, `279-303`), admin
   Materiali/Locations/Reports. Each screen reimplements the padding/spacing/mapping by hand;
   never combinable with a second facet.
3. **Filter button + badge → bottom sheet, "Rimuovi filtri" recap link** — admin Schedules only
   (`admin_schedule_list_screen.dart:290-337, 385-429`), for its 5 combinable facets (date range,
   status, technician, squadra). The richest, most scalable pattern that exists — and it's used
   exactly once.

Two dead-control comments already on record (`ticket_list_screen.dart:146-148`,
`rapportini_list_screen.dart:158-160`, both about a decorative filter icon that used to do
nothing) show this inconsistency has already cost user trust once.

## Decision (confirmed with the user)

Standardize on pattern 3 (filter button + badge + bottom sheet) **everywhere**, not a two-tier
system. Extract Schedules' already-shipped, working implementation into shared widgets rather than
designing fresh. Accepted, explicit tradeoff: screens that filter in one tap today via a chip
(Ticket, Rapportini, Magazzino) become two taps (open sheet → pick → Applica) — the cost of one
consistent idiom app-wide.

## Non-goals (this phase)

- No per-chip-removable "active filters" recap row (Gmail-style). Schedules' existing recap is a
  single combined "Rimuovi filtri (N)" link, not individually removable chips — the extracted
  widget matches that exact, already-proven shape. Per-chip removal is a plausible future
  enhancement, not built here (YAGNI — nothing today asks for it).
- No generic/config-driven facet system (e.g. a `List<FilterFacet>` descriptor model). Each
  screen's filter fields are different shapes (date range vs. dropdown vs. boolean toggle) and
  three screens is not enough repetition to justify abstracting the facet definitions themselves —
  only the sheet's outer chrome and the button/recap-link are shared. Each screen keeps its own
  small immutable `XFilters` class (`isEmpty`/`activeCount`/`copyWith`), matching
  `AdminScheduleFilters`'s existing convention.
- No migration of the remaining ~11 screens (admin Materiali/Locations/Reports/Squadre/Clienti/
  Contracts/Prodotti) — a follow-up phase once this proves out in Ticket/Rapportini/Magazzino.
- No change to Schedules' actual filter *fields*, backend queries, or any provider's behavior —
  presentation-layer extraction only.

## New shared widgets (`lib/core/widgets/`)

### `AppFilterButton`

Straight lift of `admin_schedule_list_screen.dart`'s `_FilterButton` (lines 385-429) — already
screen-agnostic, takes only `activeCount`/`onTap`. No behavior change, just relocated and made
public.

```dart
class AppFilterButton extends StatelessWidget {
  const AppFilterButton({super.key, required this.activeCount, required this.onTap});

  final int activeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    final tint = AppColors.Y;
    final activeFg = tint.computeLuminance() > 0.3 ? Colors.black : Colors.white;
    return AppTappable(
      onTap: onTap,
      color: active ? tint : context.colors.surface,
      border: Border.all(color: active ? tint : context.colors.borderMedium),
      borderRadius: AppRack.insetShape,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      semanticLabel: 'Filtri${active ? ' ($activeCount attivi)' : ''}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.filter, size: 16, color: active ? activeFg : context.colors.ink),
          if (active) ...[
            const SizedBox(width: 6),
            Text(
              '$activeCount',
              style: AppTextStyles.labelMedium.copyWith(color: activeFg, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }
}
```

### `AppActiveFiltersLink`

Straight lift of Schedules' "Rimuovi filtri (N)" row (lines 311-337).

```dart
class AppActiveFiltersLink extends StatelessWidget {
  const AppActiveFiltersLink({super.key, required this.activeCount, required this.onClear});

  final int activeCount;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppSpacing.pagePadding,
        right: AppSpacing.pagePadding,
        bottom: AppSpacing.sm,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AppTappable(
          onTap: onClear,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.x, size: 12, color: context.colors.inkMuted),
              const SizedBox(width: 4),
              Text(
                'Rimuovi filtri ($activeCount)',
                style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### `AppFilterSheetScaffold`

Extracted chrome from Schedules' `_FilterSheet` (lines 546-660): the padding, scroll behavior, and
Azzera/Applica footer. The facet fields themselves are the caller's `child`. `onApply` receives no
value — the caller reads its own in-sheet-built state (each screen's filter sheet content is a
`StatefulWidget`/`ConsumerStatefulWidget` holding local field state, same as `_FilterSheetState`
today) and calls `Navigator.pop(context, <its own Filters value>)` itself; `AppFilterSheetScaffold`
only renders the two buttons and wires their taps.

```dart
class AppFilterSheetScaffold extends StatelessWidget {
  const AppFilterSheetScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onReset,
    required this.onApply,
    this.resetLabel = 'Azzera',
    this.applyLabel = 'Applica',
  });

  final String title;
  final Widget child;
  final VoidCallback onReset;
  final VoidCallback onApply;
  final String resetLabel;
  final String applyLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom + 19,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            child,
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: onReset, child: Text(resetLabel))),
                const SizedBox(width: 12),
                Expanded(child: AppButton(label: applyLabel, onPressed: onApply)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

Callers open it the same way Schedules already does:

```dart
void _openFilterSheet() async {
  final result = await showModalBottomSheet<XFilters>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => _XFilterSheetContent(initial: _filters),
  );
  if (result != null) setState(() => _filters = result);
}
```

where `_XFilterSheetContent` is the screen's own small `StatefulWidget` wrapping
`AppFilterSheetScaffold` with its facet fields as `child` — same shape as `_FilterSheet` today,
just delegating its chrome to the shared scaffold instead of duplicating it.

## Migration: Schedules (dogfood the extraction)

`admin_schedule_list_screen.dart`'s `_FilterButton`, the recap link block (lines 311-337), and
`_FilterSheet`'s chrome are deleted and replaced with the three shared widgets above; its 5 facet
fields (date range, status, technician, squadra dropdowns) become `AppFilterSheetScaffold`'s
`child`. `AdminScheduleFilters` (the state model) is untouched — this is a pure presentation-layer swap,
zero behavior change, verified by `test/features/admin/schedules/admin_schedule_list_screen_test.dart`
(already exists, already exercises the squadra-filter pre-apply and the "clear filters" recap —
see Testing below for what must keep passing).

## Migration: Ticket (`ticket_list_screen.dart`)

Today: `_TicketFilter` enum (`tutti`/`aperti`/`inCorso`/`inAttesa`/`completati`) rendered as an
`AppChip` row (lines 163-193), single-select via `_filter` state.

After: `_TicketFilter` becomes the sheet's one facet (a radio-style list or `DropdownButtonFormField`
inside `AppFilterSheetScaffold`, mirroring Schedules' `AppFieldShell` + `DropdownButtonFormField`
pattern for a single-select facet). `_filter`'s `activeCount` is `0` when `tutti`, `1` otherwise
(no separate `Filters` class needed for a single field — `_filter` state stays exactly as it is,
`AppFilterButton(activeCount: filter == _TicketFilter.tutti ? 0 : 1, ...)`). The chip row
(lines 175-193) is deleted; the search row becomes `Row(children: [Expanded(AppSearchBar), SizedBox(width: 8), AppFilterButton(...)])`.
`AppActiveFiltersLink` shown when `filter != _TicketFilter.tutti`, clearing back to `tutti`.

## Migration: Rapportini (`rapportini_list_screen.dart`)

Same shape as Ticket (confirmed identical structure by the earlier codebase survey, lines
164-193) — single status-filter enum, chip row replaced by filter button + sheet with one
dropdown facet, same as above.

## Migration: Magazzino (`magazzino_screen.dart`)

Two tabs carry filters today (Movimenti has none, untouched): Articoli (category, single-select
from a dynamic per-tenant list, lines 190-230) and Giacenze (`soloSottoScorta` boolean toggle,
lines 279-303). Both tabs share one search row (lines 130-158) — the filter button is added to
that same row, and the sheet it opens shows the facet relevant to whichever tab is currently
active:

- Articoli active → sheet shows a single "Categoria" dropdown (`Tutti` + each category from
  `materiali_categories_provider`), mirroring `activeCategory`'s existing state.
- Giacenze active → sheet shows a single "Sotto scorta" toggle/switch, mirroring
  `soloSottoScorta`'s existing boolean state.

`activeCount` for the button badge is `activeCategory != null ? 1 : 0` on Articoli,
`soloSottoScorta ? 1 : 0` on Giacenze — computed from whichever tab is active, same as today's
per-tab chip visibility. The button/sheet do not render at all on the Movimenti tab, matching the
existing `if (tab != _MagazzinoTab.movimenti)` guard around the whole search row.

## Testing

- New widget tests for `AppFilterButton` (renders badge only when `activeCount > 0`, calls
  `onTap`), `AppActiveFiltersLink` (renders the count, calls `onClear`), and
  `AppFilterSheetScaffold` (renders `title`/`child`, Azzera calls `onReset`, Applica calls
  `onApply`) — new, focused, in `test/core/widgets/`.
- Per-screen: all 4 migrated screens already have widget test files —
  `test/features/ticket/ticket_list_screen_test.dart`,
  `test/features/rapportino/rapportini_list_screen_test.dart`,
  `test/features/magazzino/magazzino_screen_test.dart` (plus
  `test/features/admin/magazzini/admin_magazzino_screens_test.dart`), and
  `test/features/admin/schedules/admin_schedule_list_screen_test.dart` — all must still pass.
  Any test that currently taps an `AppChip` filter must be updated to instead tap
  `AppFilterButton` → interact with the sheet's facet field → tap Applica.
