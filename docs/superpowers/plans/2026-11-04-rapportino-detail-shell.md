# Rapportino Detail-Shell Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** Move the read-only `RapportinoViewScreen` onto the shared detail shell with a document hero, PDF/share/rework actions and the six report sections.

**Architecture:** Reuse `DetailScaffold`, `DetailHeroData`, `DetailSectionData` from `lib/core/widgets/detail/`. The hero owns the report identity, status, three facts and the primary/secondary actions; the view keeps its existing providers and section widgets. No new network reads.

**Spec:** `docs/superpowers/specs/2026-11-04-detail-shell-design.md`

## Global Constraints

- Il Documento tokens only; flat surfaces, 1px Rule, 2px radius, no shadows.
- Header is generic `Rapportino`; hero owns `draft.title`.
- Hero facts: Cliente, Sede, Tecnico (max 3).
- Primary: `Scarica PDF`; `Rilavora` when `rapportinoIsRejected(draft)`; secondary `Condividi`.
- Sections: Attività (Cronologia), Sintesi, Ore, Materiali, Controlli, Documenti & mappa.
- Preserve all existing read-only content, offline PDF cache behavior, signatures, photos, map, rejection copy and navigation.
- No new packages, tables or network reads; `flutter analyze` clean.

## Review Focus

1. Rejected report: one `Rilavora` action, not two; it creates the rework draft and pushes the editor.
2. PDF actions: offline uses the cached copy; share uses the same resolver; no duplicate bottom row.
3. Long report title / fact values clamp at 320px.
4. Empty sections disappear (no materiali, no controlli, no photos/signatures).
5. Existing tests for status, map, rework, PDF and signatures still pass.

---

### Task 1: Shell + document hero

**Files:**
- Modify: `lib/features/rapportino/rapportino_view_screen.dart`
- Modify: `test/features/rapportino/rapportino_view_screen_test.dart`
- Modify: `docs/superpowers/specs/2026-11-04-detail-shell-design.md` (already updated; verify)

**Interfaces:**
- Consumes: `DetailScaffold`, `DetailHeroData`, `DetailStatus`, `DetailFact`, `DetailAction`, `DetailSectionData` from `lib/core/widgets/detail/`.
- Produces: private `DetailHeroData _buildRapportinoHero(BuildContext, WidgetRef, DraftReport)`; top-level `_shareReportPdf(BuildContext, WidgetRef, String reportId)`; top-level `_reworkReport(BuildContext, WidgetRef, DraftReport)`.

- [ ] **Step 1: Write failing tests**

Add to `test/features/rapportino/rapportino_view_screen_test.dart`:
```dart
testWidgets('renders the generic Rapportino header and the report title in the hero', (tester) async { ... });
testWidgets('hero offers Scarica PDF and Condividi for a submitted report', (tester) async { ... });
testWidgets('a rejected report promotes Rilavora to the hero and shows it once', (tester) async { ... });
testWidgets('hero shows Cliente, Sede, Tecnico facts and the status stamp', (tester) async { ... });
```
Use the existing pump helpers/seed data in that file. For rejected, use the existing rejection fixture.

- [ ] **Step 2: Run to confirm RED**
`flutter test test/features/rapportino/rapportino_view_screen_test.dart --plain-name "hero"`

- [ ] **Step 3: Implement**
- Replace the loading/error/empty frames with `DetailScaffold.loading` / `.unavailable` (`screenTitle: 'Rapportino'`).
- `_RapportinoViewBody` returns `DetailScaffold(screenTitle: 'Rapportino', hero: _buildRapportinoHero(...), sections: [DetailSectionData(title: 'Documento', child: <existing CustomScrollView body>)])` as the temporary one-section migration.
- Hero: `title: draft.title`, `status: DetailStatus(label: statusLabel)`, facts Cliente/Sede/Tecnico, primary `Scarica PDF` or `Rilavora` when rejected, secondary `Condividi`.
- Extract `_shareReportPdf` from `_SharePdfButtonState._share` and use it in the hero and the existing share widget.
- Extract `_reworkReport` from `_RejectionBannerState._rielabora`; use it in the hero. Make `_RejectionBanner` text-only (remove its duplicate `Rilavora` button) or pass it a callback; the hero must be the only `Rilavora` action.
- Remove the bottom download/share row; the hero owns those actions.
- Keep the existing body content, providers, map, signatures and PDF cache.

- [ ] **Step 4: Run tests**
`flutter test test/features/rapportino/rapportino_view_screen_test.dart`
Expected: PASS; update any old test expecting the bottom PDF row or two Rilavora buttons.

- [ ] **Step 5: Commit**
`feat(rapportino): move the report view onto the detail shell`

---

### Task 2: Six-section mapping

**Files:**
- Modify: `lib/features/rapportino/rapportino_view_screen.dart`
- Modify: `test/features/rapportino/rapportino_view_screen_test.dart`

- [ ] **Step 1: Write failing tests**
```dart
testWidgets('renders Attività, Sintesi, Ore, Materiali, Controlli, Documenti in order', ...);
testWidgets('omits Materiali, Controlli and Documenti when the report has none', ...);
```

- [ ] **Step 2: Run to confirm RED**
`flutter test test/features/rapportino/rapportino_view_screen_test.dart --plain-name "sections"`

- [ ] **Step 3: Implement**
- **Attività**: Cronologia card and the rejection banner (when rejected).
- **Sintesi**: Ore total, report date/status metadata, AI redaction row, Descrizione and Note tecnico. Do not repeat the hero facts.
- **Ore**: `Squadra e ore` card.
- **Materiali**: existing materiali card, including the “no materiali — confermato” empty case.
- **Controlli**: existing controlli card.
- **Documenti & mappa**: map, Foto grid, Firma cliente, Firma tecnico. PDF/share stay in the hero.
- Use `DetailSectionData(isEmpty: ...)` so empty sections disappear.

- [ ] **Step 4: Run tests**
`flutter test test/features/rapportino/rapportino_view_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**
`refactor(rapportino): group the report view into the detail sections`

---

### Task 3: Verification

- [ ] **Step 1:** `dart format` the new/changed files that are safe to format; `flutter analyze` → clean.
- [ ] **Step 2:** `flutter test test/features/rapportino` and `flutter test test/core/widgets/detail`.
- [ ] **Step 3:** Verify: submitted report shows Scarica PDF + Condividi; rejected shows one Rilavora; offline PDF uses cached copy; map/signatures/photos still render; long title/facts clamp at 320px.
- [ ] **Step 4:** Commit any verification fixes.
