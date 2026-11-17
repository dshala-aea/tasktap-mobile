# Shared material picker + mobile carico/scarico — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify the rapportino and ticket-fabbisogno material add flow on one search + qty modal, resolve the source warehouse from the material's giacenze, and add a mobile carico/scarico/trasferimento flow on `/altro/magazzino`.

**Architecture:** Extract the rapportino add-material dialog into a reusable `MaterialePickerDialog` returning a `MaterialePickerResult`; it resolves the source magazzino from `giacenze` (online) or the mirror (offline). The ticket fabbisogno calls the same dialog for search/qty/unit only (its API has no `magazzinoId` yet). A second dialog reuses the same article/qty widgets for stock movements against the existing endpoints. No backend changes.

**Tech Stack:** Flutter, Riverpod, Drift, Dio, go_router, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-11-material-picker-magazzino-design.md`

## Global Constraints

- **Do not touch the backend or `test/contract/openapi.snapshot.json`.**
- Do not send `magazzinoId` on `TicketMaterialeWriteRow` until the backend contract lands (the request-body contract test rejects undeclared keys).
- Quantity accepts a numeric keyboard with decimal separator (`.` or `,`); the −/+ buttons remain.
- No default to the technician's furgone. The source comes from the material's giacenze.
- Multi-giacenza: user-selectable, defaulting to the largest available qty.
- No giacenza: allowed with a "no scarico will be recorded" notice.
- Offline: giacenze are unavailable; use the `magazzini` mirror with a "stock non verificabile" notice.
- Italian copy: `Aggiungi materiale`, `Carico`, `Scarico`, `Trasferisci`, `Nessuna giacenza`, `Nessun magazzino`.
- Do not commit or push unless asked.

## Review Focus

Each line is pinned by a test in the owning task.

- Quantity typed `2,5` on the numeric keyboard must reach the saved row as `2.5` (and `2.` / `.5` must not crash).
- A material with one giacenza must auto-select it; with several, the default is the largest qty and the user can change it.
- A material with no giacenza must still add, with `magazzinoId == null`, and say no scarico will be recorded.
- Offline must not invent a furgone; it offers the mirror list or no source.
- The ticket material request body must not gain a key the OpenAPI schema does not declare.
- Carico/scarico/trasferisci must hit the correct endpoint with the chosen magazzino(s), material and qty.

---

### Task 1: Extract the shared picker and use it in the rapportino

**Files:**
- Create: `lib/features/materiali/materiale_picker_dialog.dart`
- Modify: `lib/features/rapportino/steps/step_materiali_fold.dart:60-530` (call the shared picker; remove moved private widgets)
- Test: `test/features/rapportino/steps/step_materiali_fold_test.dart`
- Test: `test/features/materiali/materiale_picker_dialog_test.dart` (new)

**Interfaces:**
- Consumes: `allMaterialiProvider` (`List<MaterialiData>` in `presentation/providers/schedule_providers.dart`), `MaterialiData`, `MaterialeMatch`, `lookupMaterialeByBarcode`, `openBarcodeScanSheet`, `ticketMaterialiProvider`, `TicketMaterialeDto`, `MagazzinoApiClient.getGiacenze`, `GiacenzaDto`, `magazziniProvider`, `MagazzinoDto`, `isOnlineProvider`, `hasSyncedAtLeastOnceProvider`, `materialeSelectOptions`, `kUnitOfMeasureOptions`.
- Produces:
  - `class MaterialePickerResult { final String? materialeId; final String? freeTextName; final double quantity; final String? unitOfMeasure; final String? magazzinoId; final String? magazzinoNome; final String? materialeNome; final String? materialeCodice; }`
  - `Future<MaterialePickerResult?> showMaterialePickerDialog(BuildContext context, {String? ticketId, bool showSource = true, bool showFabbisognoSuggestions = true, BarcodeScanner? scanner})`
  - `typedef BarcodeScanner = Future<String?> Function(BuildContext context);`
  - `class QtyStepButton` (public, moved from the step) and `class MaterialeLookupField` (public, moved from the step).

- [ ] **Step 1: Add the failing picker source tests**

Create `test/features/materiali/materiale_picker_dialog_test.dart` with a harness that mounts a button that opens the picker and a Dio mock for `GET /api/app/magazzino/giacenze`. Seed `materiali` + `materialeBarcodes` in an in-memory DB.

Tests (names matter for the run commands):

```dart
testWidgets('a single giacenza is selected automatically', ...);
testWidgets('multiple giacenze default to the largest and can be changed', ...);
testWidgets('no giacenza adds with a null source and a notice', ...);
testWidgets('offline offers the magazzini mirror with a stock warning', ...);
testWidgets('quantity accepts a decimal typed on the numeric keyboard', ...);
```

For the online cases, stub:
```dart
when(() => mockDio.get<Map<String, dynamic>>(
  '/api/app/magazzino/giacenze',
  queryParameters: any(named: 'queryParameters'),
)).thenAnswer((_) async => Response<Map<String, dynamic>>(
  requestOptions: RequestOptions(path: '/api/app/magazzino/giacenze'),
  statusCode: 200,
  data: {'elementi': [/* GiacenzaDto JSON */], 'pagina': 1, 'dimensionePagina': 100, 'totaleElementi': 1, 'totalePagine': 1},
));
```

For offline, override `isOnlineProvider` to `false` and seed `magazzini`.

- [ ] **Step 2: Run the picker tests to verify they fail**

Run: `flutter test test/features/materiali/materiale_picker_dialog_test.dart`
Expected: FAIL — `MaterialePickerDialog`/`showMaterialePickerDialog` undefined.

- [ ] **Step 3: Create the shared picker file**

Create `lib/features/materiali/materiale_picker_dialog.dart` with:
- `MaterialePickerResult` (fields above).
- `showMaterialePickerDialog(...)` → `showDialog<MaterialePickerResult>(barrierDismissible: true, builder: (_) => MaterialePickerDialog(...))`.
- `MaterialePickerDialog extends ConsumerStatefulWidget` with `ticketId`, `showSource`, `showFabbisognoSuggestions`, `scanner`.
- State: `double qty = 1`, `String? uom`, `String? selectedMaterialeId`, `String? freeTextName`, `_PickedMateriale? picked`, `List<GiacenzaDto>? _giacenze`, `List<MagazzinoDto>? _offlineMagazzini`, `String? magazzinoId`, `String? magazzinoNome`, `bool _sourceLoading`, `String? _sourceError`, `int lookupGeneration`.
- On catalogue selection (`MaterialiData m`): set `picked`, `selectedMaterialeId = m.id`, `freeTextName = null`, auto-fill `uom` from `m.unitOfMeasure`; if `showSource`, call `_loadSources(m)`.
- `_loadSources`:
```dart
Future<void> _loadSources(_PickedMateriale m) async {
  setState(() { _sourceLoading = true; _sourceError = null; });
  if (!ref.read(isOnlineProvider)) {
    final list = await ref.read(magazziniProvider.future).catchError((_) => const <MagazzinoDto>[]);
    setState(() { _offlineMagazzini = list; _sourceLoading = false; magazzinoId = null; magazzinoNome = null; });
    return;
  }
  try {
    final page = await ref.read(magazzinoApiClientProvider).getGiacenze(
      q: m.code.isNotEmpty ? m.code : m.name,
      pageSize: 100,
    );
    final matches = page.elementi.where((g) => g.materialeId == m.id).toList()
      ..sort((a, b) => b.quantita.compareTo(a.quantita));
    setState(() {
      _giacenze = matches;
      _sourceLoading = false;
      if (matches.isEmpty) { magazzinoId = null; magazzinoNome = null; }
      else { magazzinoId = matches.first.magazzinoId; magazzinoNome = matches.first.magazzinoNome; }
    });
  } catch (_) {
    final list = await ref.read(magazziniProvider.future).catchError((_) => const <MagazzinoDto>[]);
    setState(() { _offlineMagazzini = list; _sourceLoading = false; _sourceError = 'Disponibilità non verificabile offline'; });
  }
}
```
- Source UI (`showSource == true`):
  - `_sourceLoading` → small `CircularProgressIndicator` + `Verifica giacenze…`.
  - `_giacenze` with 1 entry → read-only `Da: <nome> · <qty> <unit>`.
  - `_giacenze` with >1 → `DropdownButtonFormField<String>` with `magazzinoId` values and `'<nome> · <qty> <unit>'` labels.
  - `_giacenze` empty → notice `Nessuna giacenza: lo scarico non sarà registrato.`
  - Offline → notice `Disponibilità non verificabile offline` + `DropdownButtonFormField<String?>` from `_offlineMagazzini` (include a `Nessun magazzino` null item).
- Qty UI: `Row` with `QtyStepButton(minus)`, a `SizedBox(width: 72)` `TextField` (controller, `keyboardType: TextInputType.numberWithOptions(decimal: true)`, `inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))]`, `textAlign: TextAlign.center`), `QtyStepButton(plus)`. Parse with `double.tryParse(text.replaceAll(',', '.'))`, clamp `> 0`.
- Add button disabled unless `(selectedMaterialeId != null || freeTextName.trim().isNotEmpty) && qty > 0`; on press `Navigator.pop(ctx, MaterialePickerResult(...))`.
- Cancel returns null.
- Move `_FabbisognoSuggestions`, `_MaterialeLookupField` (rename `MaterialeLookupField`), and `_QtyBtn` (rename `QtyStepButton`) from `step_materiali_fold.dart` into this file.

- [ ] **Step 4: Run the picker tests to verify they pass**

Run: `flutter test test/features/materiali/materiale_picker_dialog_test.dart`
Expected: PASS.

- [ ] **Step 5: Replace the rapportino dialog with the shared one**

In `step_materiali_fold.dart`:
- Delete `_showAddMaterialeDialog`'s dialog body, `_FabbisognoSuggestions`, `_MaterialeLookupField`, `_QtyBtn` (now in the shared file).
- Replace `_showAddMaterialeDialog` with:
```dart
Future<void> _showAddMaterialeDialog(BuildContext context, WidgetRef ref, String? ticketId) async {
  final result = await showMaterialePickerDialog(context, ticketId: ticketId);
  if (result == null || !context.mounted) return;
  final notifier = ref.read(reportEditorProvider(reportId).notifier);
  await notifier.addMateriale(MaterialeRow(
    id: 'mat-${DateTime.now().millisecondsSinceEpoch}',
    reportId: reportId,
    materialeId: result.materialeId,
    freeTextName: result.materialeId == null ? result.freeTextName : null,
    quantity: result.quantity,
    unitOfMeasure: result.unitOfMeasure,
    magazzinoId: result.magazzinoId,
  ));
}
```
- At the call site, drop the `furgoneAsync.valueOrNull` argument and the `internalUserIdProvider`/`furgoneDiUserProvider` watches if no longer used.
- Update the saved-row `_MaterialeQtyStepper` to use the imported `QtyStepButton` instead of the deleted `_QtyBtn`.
- Add `import '../../materiali/materiale_picker_dialog.dart';`.

- [ ] **Step 6: Run the rapportino material tests**

Run: `flutter test test/features/rapportino/steps/step_materiali_fold_test.dart`
Expected: PASS. If a test asserted a furgone default, update it to the new giacenza-based expectation.

---

### Task 2: Use the shared picker in the ticket Fabbisogno editor

**Files:**
- Modify: `lib/features/ticket/ticket_materiali_editor.dart:110-245` (`_addRow` / "Aggiungi materiale")
- Test: `test/features/ticket/ticket_materiali_editor_test.dart`
- Test: `test/features/ticket/ticket_detail_screen_test.dart` (the "Aggiungi materiale" interaction)

**Interfaces:**
- Consumes: `showMaterialePickerDialog`, `MaterialePickerResult`, `MaterialeEditRow`.
- Produces: "Aggiungi materiale" opens the modal with `showSource: false`, `showFabbisognoSuggestions: false`; adding a row maps the result into `MaterialeEditRow`.

- [ ] **Step 1: Rewrite the failing ticket-editor add tests**

Replace the old “appends a new empty row” expectation with:

```dart
testWidgets('"Aggiungi materiale" opens the shared picker and adds a free-text row', (tester) async {
  await tester.pumpWidget(_wrap(
    TicketMaterialiEditor(initialRows: const [], onSave: (_) async {}, onCancel: () {}),
    dio: mockDio,
  ));

  await tester.tap(find.text('Aggiungi materiale'));
  await tester.pumpAndSettle();

  // The shared modal is up: it has the search field and the numeric qty field.
  expect(find.text('Qtà'), findsOneWidget);
  expect(find.text('Aggiungi materiale'), findsWidgets); // button + dialog title

  await tester.enterText(find.byType(TextFormField).first, 'Guarnizione custom');
  await tester.pump();
  await tester.enterText(find.byType(TextFormField).at(1), '2,5');
  await tester.pump();

  await tester.tap(find.text('Aggiungi').last);
  await tester.pumpAndSettle();

  // Back in the editor: the added row is editable and save emits the free text + 2.5.
  List<TicketMaterialeWriteRow>? saved;
  // ... use the same editor with onSave capture, or assert the row text and 2.5 ...
});
```

Add:
- a catalogue add test (seed `materiali`, select it, add; assert the row shows the article and qty).
- a cancel test (modal dismissed; no row).
- keep the barcode tests on the standalone “Scansiona codice” button.
- the contract test remains unchanged (no `magazzinoId` sent).

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/ticket/ticket_materiali_editor_test.dart`
Expected: FAIL — tapping “Aggiungi materiale” no longer creates an inline row / no modal.

- [ ] **Step 3: Implement the ticket-editor integration**

In `ticket_materiali_editor.dart`:
- Add `import '../materiali/materiale_picker_dialog.dart';`.
- Replace `_addRow` with:
```dart
Future<void> _addMateriale() async {
  final result = await showMaterialePickerDialog(
    context,
    showSource: false,
    showFabbisognoSuggestions: false,
    scanner: widget.scanner,
  );
  if (result == null || !mounted) return;
  setState(() => _rows.add(MaterialeEditRow(
    materialeId: result.materialeId,
    freeTextName: result.materialeId == null ? result.freeTextName : null,
    quantity: result.quantity,
    unitOfMeasure: result.unitOfMeasure,
    initialArticleName: result.materialeNome,
    initialArticleCode: result.materialeCodice,
  )));
}
```
- Change the button's `onPressed` to `_isSaving ? null : _addMateriale`.
- Remove the now-unused `_addRow`.
- Keep the standalone “Scansiona codice” flow and `scanner`.
- Do **not** change `TicketMaterialeWriteRow`.

- [ ] **Step 4: Update the ticket detail test**

In `test/features/ticket/ticket_detail_screen_test.dart:2432`, replace the old inline-row expectation with the modal flow: tap “Aggiungi materiale”, enter free text + qty, tap “Aggiungi”, assert the editor row.

- [ ] **Step 5: Run the ticket tests**

Run:
```bash
flutter test test/features/ticket/ticket_materiali_editor_test.dart test/features/ticket/ticket_detail_screen_test.dart
flutter test test/contract/request_body_contract_test.dart
```
Expected: PASS; contract test still sees only declared keys.

---

### Task 3: Mobile carico/scarico/trasferimento

**Files:**
- Create: `lib/features/materiali/magazzino_movimento_dialog.dart`
- Modify: `lib/features/magazzino/magazzino_screen.dart:122` (header action)
- Test: `test/features/materiali/magazzino_movimento_dialog_test.dart` (new)
- Test: `test/features/magazzino/magazzino_screen_test.dart` (header action)

**Interfaces:**
- Consumes: `MagazzinoApiClient.carico/scarico/trasferimento`, `magazziniProvider`, `allMaterialiProvider`, `lookupMaterialeByBarcode`, `ensureOnlineOrWarn`, `giacenzeProvider`, `movimentiProvider`, `MaterialeLookupField`, `QtyStepButton`.
- Produces: `Future<void> showMagazzinoMovimentoDialog(BuildContext context, WidgetRef ref)`.

- [ ] **Step 1: Add the failing movement tests**

In `test/features/materiali/magazzino_movimento_dialog_test.dart`, mount a button that calls `showMagazzinoMovimentoDialog`, with a Dio mock capturing `POST` bodies. Tests:
```dart
testWidgets('carico POSTs the chosen magazzino, material and decimal qty', ...);
testWidgets('scarico POSTs to the source magazzino', ...);
testWidgets('trasferimento POSTs source, destination, material and qty', ...);
testWidgets('offline disables confirm and says the movement needs a connection', ...);
```
Assert:
```dart
verify(() => mockDio.post(
  '/api/magazzino/$magazzinoId/carico',
  data: {'materialeId': 'mat-1', 'quantita': 2.5},
)).called(1);
```
(Adjust for `note` when entered.)

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/features/materiali/magazzino_movimento_dialog_test.dart`
Expected: FAIL — `showMagazzinoMovimentoDialog` undefined.

- [ ] **Step 3: Implement the movement dialog**

Create `magazzino_movimento_dialog.dart`:
- `enum MagazzinoMovimentoTipo { carico, scarico, trasferimento }`
- `MaterialeLookupField` for article selection (search/free text is invalid here; only a catalogue article can move stock — if free text is picked, disable confirm and say “Scegli un articolo a catalogo”).
- Barcode icon using `openBarcodeScanSheet` + `lookupMaterialeByBarcode`.
- `QtyStepButton` + numeric `TextField` (decimal, same parsing as the picker).
- `DropdownButtonFormField` for the source/destination magazzini from `magazziniProvider`; for `carico`: destination only; `scarico`: source only; `trasferimento`: both, and hide the source from the destination list.
- Optional note `TextField`.
- Confirm:
```dart
final client = ref.read(magazzinoApiClientProvider);
switch (tipo) {
  case carico: await client.carico(magazzinoId: dest!, materialeId: id, quantita: qty, note: note);
  case scarico: await client.scarico(magazzinoId: source!, materialeId: id, quantita: qty, note: note);
  case trasferimento: await client.trasferimento(magazzinoId: source!, materialeId: id, quantita: qty, magazzinoDestinazioneId: dest!, note: note);
}
if (ctx.mounted) Navigator.pop(ctx);
ref.invalidate(giacenzeProvider);
ref.invalidate(movimentiProvider);
showAppToast(context, message: 'Movimento registrato', tone: ToastTone.success);
```
- Wrap confirm in `ensureOnlineOrWarn(context, ref)` and catch `DioException` to show the server message (insufficient stock).
- Offline: show `MagazzinoOfflineException` state and disable confirm.

- [ ] **Step 4: Run the movement tests to verify they pass**

Run: `flutter test test/features/materiali/magazzino_movimento_dialog_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the header action**

In `magazzino_screen.dart`, change:
```dart
SliverToBoxAdapter(child: ScreenHeader(title: 'Magazzino', showBack: true)),
```
to:
```dart
SliverToBoxAdapter(
  child: ScreenHeader(
    title: 'Magazzino',
    showBack: true,
    actions: [
      HeaderIconBtn(
        icon: LucideIcons.arrowLeftRight,
        label: 'Carico/Scarico',
        onTap: () => showMagazzinoMovimentoDialog(context, ref),
      ),
    ],
  ),
),
```
Add the import. Add a widget test in `magazzino_screen_test.dart` asserting the action exists.

- [ ] **Step 6: Run the magazzino tests**

Run: `flutter test test/features/magazzino`
Expected: PASS.

---

### Task 4: Documentation and final verification

**Files:**
- Add: `docs/handoffs/2026-11-11-ticket-materiale-magazzino.md` (already drafted; verify it is present and accurate)
- Add: `docs/superpowers/specs/2026-11-11-material-picker-magazzino-design.md` (already drafted)
- Add: `docs/superpowers/plans/2026-11-11-material-picker-magazzino.md` (this plan)

- [ ] **Step 1: Verify the handoff**

Confirm the handoff states: no backend changes in this branch; nullable `magazzinoId` needed on the ticket material entity/write/read/sync + office web; contract snapshot update; mobile contract test forbids undeclared keys; DDT/bolla out of scope.

- [ ] **Step 2: Run analysis**

Run: `flutter analyze`
Expected: `No issues found!`.

- [ ] **Step 3: Run the full suite**

Run: `flutter test`
Expected: all pass. Report any unrelated pre-existing failure by name.

- [ ] **Step 4: Report, do not commit**

Report changed files, test/analyze output, and the handoff path. Do not commit or push.

## Deferred minors (addressed on this branch)

Carried from the final review and addressed on this branch: shared `MaterialeQtyField` with a 2-decimal formatter, explicit invalid-qty feedback, the free-text no-scarico notice, transport/server-fault splitting, the `magazzino.warehouse.write` gate on the header action, and one `BarcodeScanner` typedef.

1. **Max 2 decimals + invalid-qty feedback.** The shared qty fields accept any digits/separators,
   so `1,234` becomes `1.234` and `1,2,3` silently parses to 0. Add one shared parser/formatter
   (one separator, ≤2 decimals) used by both dialogs, and say why the value is invalid.
2. **Free-text lines get no “no scarico” notice.** The source section is hidden when no catalogue
   article is picked, unlike the no-giacenza case. Show the same notice for free text.
3. **Every giacenze failure is labelled “offline”.** A 401/403/500 while online also falls back to
   the mirror with the offline wording. Split transport/server faults and keep the message
   specific.
4. **Header Carico/Scarico is not capability-gated.** The per-row stock actions require
   `magazzino.warehouse.write`; the new header action is always shown. Gate/hide it the same way.
5. **Duplicated qty control and `BarcodeScanner` typedef.** `_QtyRow`/the numeric field and the
   typedef exist in both new dialog files. Extract one shared `MaterialeQtyField` and keep one
   public typedef.
