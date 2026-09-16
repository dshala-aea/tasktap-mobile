// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/catalog_constants.dart';
import '../../../core/utils/error_message.dart';
import '../../admin/admin_widgets.dart';
// Uses StepLabel — the padding-free sibling of SectionTitle, for headings inside a padded card.
import '../../../core/scanner/barcode_scan_sheet.dart';
import '../../../data/local/app_database.dart';
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../../data/materiali/materiale_barcode_lookup.dart';
import '../../../data/reports/ticket_controls_cache_repository.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../magazzino/magazzino_providers.dart';
import '../../ticket/ticket_detail_api_client.dart';
import '../../ticket/ticket_providers.dart' show ticketMaterialiProvider;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_rack.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 3 — Materiali  (folds Foto/Allegati as a sub-section)
//
// - Qty steppers (− value +) per MaterialeRow
// - "Aggiungi materiale" opens picker dialog
// - "Nessun materiale" toggle (setMaterialiNotRequired)
// - Foto/allegati sub-section (addAllegato/removeAllegato)
//
// Controlli used to fold in here too — it's its own compartment tile now (StepControlli, bottom
// of this file); see that class's own doc comment for why.
// ══════════════════════════════════════════════════════════════════════════════

class StepMaterialiFold extends ConsumerWidget {
  const StepMaterialiFold({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportEditorProvider(reportId));
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final photos = state.allegatoRows.where((a) => !a.isSignature).toList();

    // The technician's assigned van warehouse — watched here (not inside the dialog) so it is
    // fetched once per visit to this step and every "Aggiungi materiale" tap reuses it, rather
    // than re-fetching over the network on a dialog a technician can open a dozen times on one job.
    // The internal database Guid, not currentUserProvider.id (the Zitadel OIDC sub) — the
    // furgone-lookup endpoint is keyed by the internal Guid, so the sub never matched anyone.
    final internalUserId = ref.watch(internalUserIdProvider).valueOrNull;
    final furgoneAsync = internalUserId == null
        ? const AsyncValue<MagazzinoDto?>.data(null)
        : ref.watch(furgoneDiUserProvider(internalUserId));

    // A Column, not a ListView: this sits inside the compartment sheet's own ambient
    // SingleChildScrollView now, not a screen-height-bounded Expanded body — an inner scrollable
    // here would fight the outer one for an unbounded height and crash on layout.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── "Nessun materiale" toggle ──────────────────────────────────────
          AppCard(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.xs,
              AppSpacing.base,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Nessun materiale utilizzato',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: context.colors.ink,
                    ),
                  ),
                ),
                AppToggle(
                  value: state.materialiNotRequired,
                  onChanged: (v) => notifier.setMaterialiNotRequired(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (!state.materialiNotRequired) ...[
            // ── Materiali list ──────────────────────────────────────────────
            StepLabel(title: 'Materiali (${state.materialeRows.length})'),
            const SizedBox(height: 8),
            if (state.materialeRows.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  'Nessun materiale aggiunto.',
                  style: TextStyle(color: context.colors.inkMuted),
                ),
              )
            else
              ...state.materialeRows.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _MaterialeQtyStepper(
                    row: row,
                    onQtyChanged: (qty) => notifier.updateMateriale(row.copyWith(quantity: qty)),
                    onRemove: () => notifier.removeMateriale(row.id),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            AppButton.secondary(
              label: 'Aggiungi materiale',
              icon: const Icon(LucideIcons.plusSquare),
              onPressed: () =>
                  _showAddMaterialeDialog(context, ref, furgoneAsync.valueOrNull, state.ticketId),
            ),
            const SizedBox(height: 24),
          ],

          // Controlli moved to its own compartment tile (see StepControlli, bottom of this file)
          // — it used to live here, bundling a third unrelated sub-flow (a server-driven
          // checklist with its own loading/error/empty states) into a tile already carrying
          // materials-picking and photo capture. Densest screen in the rapportino, on the one
          // task where a mis-tap has real cost; splitting it was the fix, not just a nice-to-have.

          // ── Foto / Allegati sub-section ────────────────────────────────────
          StepLabel(title: 'Foto / Allegati (${photos.length})'),
          const SizedBox(height: 8),
          if (photos.isNotEmpty) ...[
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: photos.length,
              itemBuilder: (ctx, i) => _PhotoThumb(
                row: photos[i],
                onRemove: () => notifier.removeAllegato(photos[i].id),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Galleria',
                  icon: const Icon(LucideIcons.image),
                  onPressed: () => _pickImage(context, ref, ImageSource.gallery),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Fotocamera',
                  icon: const Icon(LucideIcons.camera),
                  onPressed: () => _pickImage(context, ref, ImageSource.camera),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Item 7: image_picker only ever offers camera/gallery, so a PDF (a datasheet, a signed
          // delivery note, a manufacturer certificate) could never be attached from here at all —
          // separate from any backend-side content-type restriction, which a backend agent is
          // relaxing concurrently. Goes through the same addAllegato path images already use.
          AppButton.secondary(
            label: 'Documento (PDF)',
            icon: const Icon(LucideIcons.fileText),
            onPressed: () => _pickDocument(context, ref),
          ),
        ],
      ),
    );
  }

  void _showAddMaterialeDialog(
    BuildContext context,
    WidgetRef ref,
    MagazzinoDto? defaultMagazzino,
    String? ticketId,
  ) {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);

    // Same +/- stepper the saved row uses (_MaterialeQtyStepper below), not raw text entry —
    // this dialog used to be the one place quantity was typed rather than stepped.
    double qty = 1.0;
    // Closed vocabulary (catalog_constants.dart), not free text — null means "not set".
    String? uom;
    String? selectedMaterialeId;
    String freeTextName = '';
    // AppLookupField only reads selectedId/initialText once, in initState — it doesn't watch
    // them for later external changes (see its own didUpdateWidget doc comment). A scan resolves
    // outside the field's own onSelected/onFreeText callbacks, so this key is bumped on every scan
    // result to force a fresh instance that picks the new value up.
    var lookupFieldGeneration = 0;
    // Defaults to the technician's own furgone (zero extra taps for the common case — see Gap 1 in
    // the feature audit). "Cambia" below lets them source a line from a different warehouse, e.g.
    // stock picked up from a Sede for a job done off the van.
    String? selectedMagazzinoId = defaultMagazzino?.id;
    String? selectedMagazzinoNome = defaultMagazzino?.nome;
    // Unità/magazzino collapse behind one disclosure by default — both are usually already
    // resolved (unit from the catalog pick, magazzino from the technician's own furgone), so
    // showing two more decision rows every time competed with the two decisions that actually
    // need a tap on every add (what, how much). Collapsed values still apply silently; expanding
    // only matters for the exception (a part with no catalog unit, stock from a different
    // magazzino). See critique P2 "Materiali add-dialog cognitive overload."
    var showAdvanced = false;

    showDialog<void>(
      context: context,
      // Vetro chrome, not a stock AlertDialog — same AppCard + AppButton shell as the rest of
      // the app's dialogs (see altro_hub_screen.dart's logout confirmation).
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: AppCard(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Aggiungi materiale',
                  style: TextStyle(
                    fontFamily: 'Archivo Narrow',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: ctx.colors.ink,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Fabbisogno was already fetched and shown read-only on the ticket's own Materiali
                        // tab, disconnected from the one screen a technician actually adds materiali from.
                        // Nothing to type here — tapping a suggestion is the whole interaction.
                        if (ticketId != null)
                          _FabbisognoSuggestions(
                            ticketId: ticketId,
                            onPicked: (m) {
                              selectedMaterialeId = m.materialeId;
                              freeTextName = m.materialeId == null ? m.nome : '';
                              qty = m.quantita > 0 ? m.quantita : 1.0;
                              if (m.unitaMisura?.isNotEmpty ?? false) uom = m.unitaMisura;
                              lookupFieldGeneration++;
                              setDialogState(() {});
                            },
                          ),
                        // Same single field as the rest of the wizard. This dialog is opened once per
                        // material — often a dozen times on one job — so the catalogo/testo-libero mode
                        // switch was being paid over and over on the same rapportino.
                        //
                        // A ConsumerWidget of its own, watching allMaterialiProvider live, rather than a
                        // `catalogo` list captured once via `ref.read` when the dialog opened. That read
                        // used to hit the provider cold: allMaterialiProvider is StreamProvider.autoDispose
                        // and nothing else in this screen keeps it warm, so the very first open (the common
                        // case — a technician adds several materiali per job, but the provider is torn down
                        // between dialogs once nothing is left watching it) read it before the underlying
                        // Drift stream had delivered its first emission and got back AsyncLoading, i.e. an
                        // empty catalogo. The search box was never broken; it had nothing to search yet.
                        _MaterialeLookupField(
                          key: ValueKey(lookupFieldGeneration),
                          selectedId: selectedMaterialeId,
                          initialText: freeTextName,
                          onMaterialeSelected: (m) {
                            selectedMaterialeId = m.id;
                            freeTextName = '';
                            // The catalogue knows the unit. Asking the technician to type "pz" after
                            // picking a part that is already measured in pieces is a known answer.
                            if (m.unitOfMeasure?.isNotEmpty ?? false) uom = m.unitOfMeasure;
                            setDialogState(() {});
                          },
                          onFreeText: (v) {
                            selectedMaterialeId = null;
                            freeTextName = v;
                          },
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: const Icon(LucideIcons.scanLine, size: 18),
                            tooltip: 'Scansiona codice',
                            onPressed: () async {
                              final code = await openBarcodeScanSheet(
                                ctx,
                                title: 'Scansiona materiale',
                              );
                              if (code == null || !ctx.mounted) return;
                              final match = await lookupMaterialeByBarcode(ref, code);
                              if (match != null) {
                                selectedMaterialeId = match.id;
                                freeTextName = '';
                                if (match.unitOfMeasure?.isNotEmpty ?? false) {
                                  uom = match.unitOfMeasure;
                                }
                              } else {
                                // Not in the catalog (or its barcode) — the scan wasn't wasted, the raw
                                // code becomes the free-text name, same as if it had been typed.
                                selectedMaterialeId = null;
                                freeTextName = code;
                              }
                              lookupFieldGeneration++;
                              setDialogState(() {});
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              'Qtà',
                              style: TextStyle(
                                fontFamily: 'Archivo',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: ctx.colors.inkMuted,
                              ),
                            ),
                            const Spacer(),
                            _QtyBtn(
                              icon: LucideIcons.minus,
                              label: 'Diminuisci quantità',
                              onTap: qty > 1 ? () => setDialogState(() => qty -= 1) : null,
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                              child: Text(
                                qty.toStringAsFixed(qty == qty.truncateToDouble() ? 0 : 1),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: ctx.colors.ink,
                                ),
                              ),
                            ),
                            _QtyBtn(
                              icon: LucideIcons.plus,
                              label: 'Aumenta quantità',
                              onTap: () => setDialogState(() => qty += 1),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Unità + magazzino: one collapsed summary row instead of two always-open
                        // ones. Both already hold a real value (catalog-derived unit, the
                        // technician's own furgone) in the common case — "Modifica" is for the
                        // exception, not the default path.
                        InkWell(
                          onTap: () => setDialogState(() => showAdvanced = !showAdvanced),
                          borderRadius: AppRack.insetShape,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                            child: Row(
                              children: [
                                Icon(LucideIcons.warehouse, size: 14, color: ctx.colors.inkMuted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${uom ?? 'Unità non impostata'} · '
                                    '${selectedMagazzinoNome ?? 'Nessun magazzino'}',
                                    style: TextStyle(fontSize: 12, color: ctx.colors.inkMuted),
                                  ),
                                ),
                                AnimatedRotation(
                                  turns: showAdvanced ? 0.5 : 0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Icon(
                                    LucideIcons.chevronDown,
                                    size: 16,
                                    color: ctx.colors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (showAdvanced) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: AppFieldShell(
                                  label: 'Unità',
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: uom,
                                    hint: const Text('pz'),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('Nessuna'),
                                      ),
                                      for (final u in materialeSelectOptions(
                                        kUnitOfMeasureOptions,
                                        uom,
                                      ))
                                        DropdownMenuItem<String?>(value: u, child: Text(u)),
                                    ],
                                    onChanged: (v) => setDialogState(() => uom = v),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selectedMagazzinoNome != null
                                      ? 'Da: $selectedMagazzinoNome'
                                      : 'Nessun magazzino assegnato',
                                  style: TextStyle(fontSize: 12, color: ctx.colors.inkMuted),
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final picked = await _pickMagazzino(ctx, ref);
                                  if (picked != null) {
                                    selectedMagazzinoId = picked.id;
                                    selectedMagazzinoNome = picked.nome;
                                    setDialogState(() {});
                                  }
                                },
                                child: const Text('Cambia'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: AppButton.ghost(label: 'Annulla', onPressed: () => Navigator.pop(ctx)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppButton(
                        label: 'Aggiungi',
                        onPressed: () {
                          final id = 'mat-${DateTime.now().millisecondsSinceEpoch}';
                          final typed = freeTextName.trim();
                          notifier.addMateriale(
                            MaterialeRow(
                              id: id,
                              reportId: reportId,
                              materialeId: selectedMaterialeId,
                              // Whichever one holds the answer. There is no mode to consult any
                              // more, so the row records what is actually there.
                              freeTextName: selectedMaterialeId == null && typed.isNotEmpty
                                  ? typed
                                  : null,
                              quantity: qty,
                              unitOfMeasure: uom,
                              magazzinoId: selectedMagazzinoId,
                            ),
                          );
                          Navigator.pop(ctx);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Lets the technician override the auto-selected warehouse for one material line — e.g. a part
  /// picked up from a Sede rather than their own furgone. Returns null if they dismiss without
  /// choosing.
  Future<MagazzinoDto?> _pickMagazzino(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<MagazzinoDto>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Consumer(
          builder: (ctx, ref, _) {
            final async = ref.watch(magazziniProvider);
            return async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(humanErrorMessage(e, azione: 'caricare i magazzini')),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text('Nessun magazzino disponibile.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final m in list)
                          ListTile(
                            leading: const Icon(LucideIcons.warehouse),
                            title: Text(m.nome),
                            subtitle: Text(m.tipo),
                            onTap: () => Navigator.pop(ctx, m),
                          ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context, WidgetRef ref, ImageSource source) async {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final picker = ImagePicker();
    try {
      final xfile = await picker.pickImage(source: source, imageQuality: 80);
      if (xfile == null) return;
      final file = File(xfile.path);
      final bytes = await file.readAsBytes();
      final id = 'photo-${DateTime.now().millisecondsSinceEpoch}';
      await notifier.addAllegato(
        AllegatoRow(
          id: id,
          localPath: xfile.path,
          fileName: xfile.name,
          contentType: 'image/jpeg',
          sizeBytes: bytes.length,
        ),
      );
    } catch (e) {
      // Local capture and file write — never a server call, so there is no status to interpret and
      // one honest sentence covers every way it fails. It used to print the exception, which on a
      // full phone read as the app crashing rather than the storage being full.
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Foto non salvata. Riprova, e controlla lo spazio libero sul telefono.',
          tone: ToastTone.error,
        );
      }
    }
  }

  /// Item 7: a document (PDF) alongside the camera/gallery photo pickers above. Goes through the
  /// same `addAllegato` path — same local row shape, same pending-upload flag, same eventual
  /// upload — images already use; only the source and the resulting `contentType` differ.
  Future<void> _pickDocument(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    try {
      final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
      final files = result?.files ?? const <PlatformFile>[];
      if (files.isEmpty) return;
      final picked = files.first;
      // Path-based, like image_picker's XFile above — this app ships mobile-only (no web/
      // target), where FilePicker always returns a real file path.
      if (picked.path == null) return;
      final file = File(picked.path!);
      final bytes = await file.readAsBytes();
      final id = 'doc-${DateTime.now().millisecondsSinceEpoch}';
      await notifier.addAllegato(
        AllegatoRow(
          id: id,
          localPath: picked.path!,
          fileName: picked.name,
          contentType: 'application/pdf',
          sizeBytes: bytes.length,
        ),
      );
    } catch (e) {
      // Same reasoning as _pickImage's own catch above — local pick + file read, no server call.
      if (context.mounted) {
        showAppToast(
          context,
          message: 'Documento non salvato. Riprova, e controlla lo spazio libero sul telefono.',
          tone: ToastTone.error,
        );
      }
    }
  }
}

// ── Fabbisogno suggestions ──────────────────────────────────────────────────
//
// One tap fills the picker with a planned line's name/quantity/unit — the technician still
// reviews and hits "Aggiungi" like any other entry, they just never type what the office already
// planned. Silent (no error state) when offline or when the ticket has nothing planned: it's a
// convenience layered on the picker, not a thing the dialog depends on to function.
class _FabbisognoSuggestions extends ConsumerWidget {
  const _FabbisognoSuggestions({required this.ticketId, required this.onPicked});

  final String ticketId;
  final ValueChanged<TicketMaterialeDto> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketMaterialiProvider(ticketId));
    final planned = async.valueOrNull ?? const <TicketMaterialeDto>[];
    if (planned.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dal fabbisogno del ticket',
            style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in planned)
                AppChip(label: m.nome, icon: LucideIcons.plusSquare, onTap: () => onPicked(m)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Materiale catalog lookup ────────────────────────────────────────────────
//
// A ConsumerWidget rather than a `catalogo` list read once when the dialog opens. The dialog
// itself (`_showAddMaterialeDialog`) is a plain function, not part of the widget tree, so a
// one-time `ref.read(allMaterialiProvider)` there froze the catalog at whatever the provider
// happened to already hold — usually nothing, since `allMaterialiProvider` is a
// `StreamProvider.autoDispose` with no other watcher on this screen: it starts in `AsyncLoading`,
// the Drift stream's first emission lands a frame later, and by then that one-time read had
// already happened and returned an empty list. Watching it here, live, exactly like
// `_FabbisognoSuggestions` above watches `ticketMaterialiProvider`, means the field's suggestions
// fill in the moment the stream actually delivers data — including mid-dialog, on a cold start
// before the first sync has finished.
class _MaterialeLookupField extends ConsumerWidget {
  const _MaterialeLookupField({
    super.key,
    required this.selectedId,
    required this.initialText,
    required this.onMaterialeSelected,
    required this.onFreeText,
  });

  final String? selectedId;
  final String initialText;
  final ValueChanged<MaterialiData> onMaterialeSelected;
  final ValueChanged<String> onFreeText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialiAsync = ref.watch(allMaterialiProvider);
    final catalogo = materialiAsync.valueOrNull ?? const <MaterialiData>[];

    return AppLookupField(
      label: 'Materiale',
      hint: 'Cerca a catalogo o scrivi il nome',
      selectedId: selectedId,
      initialText: initialText,
      items: [for (final m in catalogo) LookupItem(id: m.id, name: m.name, subtitle: m.code)],
      // Distinguishes "still syncing" from "genuinely nothing at catalog" — silence either way
      // used to read as the field being broken rather than as a sync state.
      emptyCacheHint: materialiAsync.isLoading
          ? 'Catalogo in caricamento…'
          : 'Nessun materiale a catalogo: scrivi il nome per registrarlo comunque.',
      onSelected: (id) {
        for (final m in catalogo) {
          if (m.id == id) {
            onMaterialeSelected(m);
            return;
          }
        }
      },
      onFreeText: onFreeText,
    );
  }
}

// ── Qty stepper card ──────────────────────────────────────────────────────────

class _MaterialeQtyStepper extends ConsumerWidget {
  const _MaterialeQtyStepper({
    required this.row,
    required this.onQtyChanged,
    required this.onRemove,
  });

  final MaterialeRow row;
  final ValueChanged<double> onQtyChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A catalog pick (materialeId set, no free text) only carries the raw id on this row — the
    // name lives in the local materiali mirror, same resolver used by rapportino_view_screen.dart
    // and _MaterialeLookupField in this same file. Without this, a technician sees a bare GUID
    // for every catalog material until the report reloads.
    final resolvedName = row.freeTextName != null || row.materialeId == null
        ? null
        : ref.watch(materialeNameProvider(row.materialeId!)).valueOrNull;
    final displayName = row.freeTextName ?? resolvedName ?? row.materialeId ?? '';

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: 10),
      child: Row(
        children: [
          Icon(LucideIcons.package, size: 18, color: context.colors.inkMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: context.colors.ink,
                  ),
                ),
                if (row.unitOfMeasure != null)
                  Text(
                    row.unitOfMeasure!,
                    style: TextStyle(color: context.colors.inkMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
          // − qty + stepper
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _QtyBtn(
                icon: LucideIcons.minus,
                label: 'Diminuisci quantità',
                onTap: row.quantity > 1 ? () => onQtyChanged(row.quantity - 1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  row.quantity.toStringAsFixed(
                    row.quantity == row.quantity.truncateToDouble() ? 0 : 1,
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: context.colors.ink,
                  ),
                ),
              ),
              _QtyBtn(
                icon: LucideIcons.plus,
                label: 'Aumenta quantità',
                onTap: () => onQtyChanged(row.quantity + 1),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(LucideIcons.trash2, color: context.colors.red, size: 18),
            tooltip: 'Rimuovi materiale',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.label, this.onTap});

  final IconData icon;

  /// Announced by TalkBack. `LucideIcons.plus` carries no text, so without this the stepper was two
  /// unnamed buttons either side of a number.
  final String label;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      // The circle stays 32dp — it is a deliberate part of the row's density — but the tap
      // area around it is padded out to 48dp. A quantity stepper is tapped repeatedly, with
      // gloves on, and a miss here silently bills the customer for the wrong number of parts.
      // Which is also why it is the control that most needs to acknowledge a press: the row's
      // number changing is the only other confirmation, and it is small and far from the thumb.
      child: AppTappable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: onTap != null ? context.colors.bg3 : context.colors.bg4,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 16,
                color: onTap != null ? context.colors.ink : context.colors.inkDisabled,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Photo thumbnail ───────────────────────────────────────────────────────────

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.row, required this.onRemove});

  final AllegatoRow row;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    // The grid renders these three-up (see the `SliverGridDelegateWithFixedCrossAxisCount`
    // above) at a small square tile, but a camera photo decodes at full sensor resolution —
    // easily 3000+ px on a side. Without cacheWidth/cacheHeight, Flutter decodes and holds every
    // thumbnail at that full size, which is a lot of memory for a grid of tiles this small.
    final tileWidth = (MediaQuery.sizeOf(context).width - AppSpacing.pagePadding * 2 - 8 * 2) / 3;
    final cachePx = (tileWidth * MediaQuery.devicePixelRatioOf(context)).round();
    // Item 7: a PDF attachment lands in this same grid (addAllegato doesn't distinguish photos
    // from documents) but isn't decodable as an image — Image.file's errorBuilder would already
    // catch that, just as a generic "broken image" rather than naming what the tile actually is.
    final isImage = row.contentType.startsWith('image/');
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isImage
              ? Image.file(
                  File(row.localPath),
                  fit: BoxFit.cover,
                  cacheWidth: cachePx,
                  cacheHeight: cachePx,
                  errorBuilder: (ctx, e, _) => Container(
                    color: context.colors.bg3,
                    child: Icon(LucideIcons.imageOff, color: context.colors.inkMuted),
                  ),
                )
              : Container(
                  color: context.colors.bg3,
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(LucideIcons.fileText, color: context.colors.inkMuted),
                      const SizedBox(height: 2),
                      Text(
                        row.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9, color: context.colors.inkMuted),
                      ),
                    ],
                  ),
                ),
        ),
        Positioned(
          top: 4,
          right: 4,
          // Destructive, and it used to be a ~22dp circle sitting between other photo
          // thumbnails — the easiest mis-tap in the app, and the one that costs a photo the
          // technician cannot retake once they have left the site.
          child: Semantics(
            button: true,
            label: 'Rimuovi foto',
            child: AppTappable(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Container(
                    decoration: BoxDecoration(color: context.colors.red, shape: BoxShape.circle),
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: const Icon(LucideIcons.x, color: Colors.white, size: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Controlli checklist — the real thing, not a "type an ID" dialog.
//
// A ticket's checklist is resolved server-side from the maintenance-template
// version it materialised at creation (ADR-0012 §B.3): a fixed list of items,
// each with its own label and input type. A field technician was never meant
// to type a control ID — that requirement only existed because nothing wired
// the real checklist through. This reads it via GET
// /api/tickets/{ticketId}/controls through `cachedTicketControlsProvider`
// (ticket_controls_cache_repository.dart) — the same fetch, plus a local cache so the
// checklist is still viewable/answerable if connectivity drops mid-draft — and renders
// one input per item, driven by ControlType. Answers are still collected into
// ControlloRow / upserted the same way as before — only how the checklist itself is
// fetched changed, not the submit payload shape.
// ══════════════════════════════════════════════════════════════════════════════

/// Controlli's own compartment tile — the checklist for this intervention, resolved
/// server-side from the ticket's maintenance-template version (ADR-0012), not a free-text
/// "type an ID" box. Split out from [StepMaterialiFold] (see that class's own doc comment on
/// this sheet's build method for why): a server-driven checklist with its own loading/error/
/// empty states doesn't belong bundled into the materials-and-photos tile.
class StepControlli extends StatelessWidget {
  const StepControlli({super.key, required this.reportId, required this.ticketId});

  final String reportId;
  final String? ticketId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.base,
        AppSpacing.pagePadding,
        AppSpacing.xl,
      ),
      child: _ControlliChecklist(reportId: reportId, ticketId: ticketId),
    );
  }
}

/// Whether every control this ticket's maintenance template requires already has a recorded
/// answer — vacuously true when the ticket has none (nothing to do), or when this report isn't
/// linked to a ticket at all. Read by the compartment grid's completion dot; see [StepControlli].
bool controlliCompletionFor({
  required List<String> requiredControlIds,
  required List<ControlloRow> recordedRows,
}) {
  if (requiredControlIds.isEmpty) return true;
  final answered = recordedRows.map((r) => r.controlId).toSet();
  return requiredControlIds.every(answered.contains);
}

class _ControlliChecklist extends ConsumerWidget {
  const _ControlliChecklist({required this.reportId, required this.ticketId});

  final String reportId;
  final String? ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticket = ticketId;
    if (ticket == null || ticket.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          'I controlli sono legati al ticket: questo rapportino non è '
          'collegato a nessun ticket, quindi non è previsto alcun controllo.',
          style: TextStyle(color: context.colors.inkMuted, fontSize: 13),
        ),
      );
    }

    final controlsAsync = ref.watch(cachedTicketControlsProvider(ticket));

    return controlsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.base),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          e is TicketDetailOfflineException
              ? 'Controlli non disponibili offline: riprova quando torni online.'
              : 'Impossibile caricare i controlli. Riprova più tardi.',
          style: TextStyle(color: context.colors.inkMuted, fontSize: 13),
        ),
      ),
      data: (groups) {
        final flat = flattenTicketControls(groups);
        if (flat.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              'Nessun controllo previsto per questo intervento.',
              style: TextStyle(color: context.colors.inkMuted, fontSize: 13),
            ),
          );
        }
        return Column(
          children: flat
              .map(
                (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _ControlloInputCard(
                    key: ValueKey(f.control.id),
                    reportId: reportId,
                    flat: f,
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

/// One checklist item's input, driven by [TicketControlDto.type]. Pre-filled
/// from whatever this session has already recorded for it, falling back to
/// the ticket's last known answer (from a previous visit) as a starting
/// point — never auto-submitted until the technician actually interacts.
class _ControlloInputCard extends ConsumerStatefulWidget {
  const _ControlloInputCard({super.key, required this.reportId, required this.flat});

  final String reportId;
  final FlatTicketControl flat;

  @override
  ConsumerState<_ControlloInputCard> createState() => _ControlloInputCardState();
}

class _ControlloInputCardState extends ConsumerState<_ControlloInputCard> {
  late final TextEditingController _textCtrl;
  late final TextEditingController _numberCtrl;

  String get _rowId => 'ctrl-${widget.reportId}-${widget.flat.control.id}';

  ControlloRow? _findExisting(List<ControlloRow> rows) {
    for (final row in rows) {
      if (row.controlId == widget.flat.control.id) return row;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final state = ref.read(reportEditorProvider(widget.reportId));
    final existing = _findExisting(state.controlloRows);
    _textCtrl = TextEditingController(
      text: existing?.stringValue ?? widget.flat.control.stringValue ?? '',
    );
    final numberValue = existing?.numberValue ?? widget.flat.control.numberValue;
    _numberCtrl = TextEditingController(text: numberValue != null ? '$numberValue' : '');
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  void _save({String? stringValue, bool? boolValue, DateTime? dateValue, double? numberValue}) {
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    notifier.upsertControllo(
      ControlloRow(
        id: _rowId,
        reportId: widget.reportId,
        controlId: widget.flat.control.id,
        stringValue: stringValue,
        boolValue: boolValue,
        dateValue: dateValue,
        numberValue: numberValue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.flat.control;
    final rows = ref.watch(reportEditorProvider(widget.reportId).select((s) => s.controlloRows));
    final existing = _findExisting(rows);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.flat.groupPath.isNotEmpty)
            Text(
              widget.flat.groupPath,
              style: TextStyle(color: context.colors.inkMuted, fontSize: 11),
            ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  c.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: context.colors.ink,
                  ),
                ),
              ),
              if (c.isRequired)
                Padding(
                  padding: EdgeInsets.only(left: AppSpacing.xs),
                  child: Text(
                    '*',
                    style: TextStyle(color: context.colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          if (c.description != null && c.description!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: AppSpacing.xs),
              child: Text(
                c.description!,
                style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
              ),
            ),
          const SizedBox(height: 8),
          _buildInput(c, existing),
        ],
      ),
    );
  }

  Widget _buildInput(TicketControlDto c, ControlloRow? existing) {
    switch (c.type) {
      case ControlType.checkbox:
      case ControlType.trueFalse:
        final value = existing?.boolValue ?? c.boolValue ?? false;
        return Row(
          children: [
            Text('No', style: TextStyle(color: context.colors.inkMuted, fontSize: 12)),
            const SizedBox(width: 8),
            AppToggle(
              value: value,
              onChanged: (v) => _save(boolValue: v),
            ),
            const SizedBox(width: 8),
            Text('Sì', style: TextStyle(color: context.colors.inkMuted, fontSize: 12)),
          ],
        );
      case ControlType.number:
        return AppTextField(
          label: 'Valore',
          controller: _numberCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => _save(numberValue: v.trim().isEmpty ? null : double.tryParse(v.trim())),
        );
      case ControlType.dateTime:
        final value = existing?.dateValue ?? c.dateValue;
        return AdminDateField(
          label: 'Valore',
          value: value != null ? DateFormat('dd/MM/yyyy', 'it').format(value) : 'Seleziona data',
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
            );
            if (picked != null) _save(dateValue: picked);
          },
        );
      case ControlType.options:
        final options = c.choiceOptions;
        if (options.isEmpty) {
          // No choice list published for this item — degrade to free text
          // rather than a dropdown with nothing to pick.
          return _freeTextField();
        }
        final currentValue = existing?.stringValue ?? c.stringValue;
        return AppFieldShell(
          label: 'Valore',
          child: DropdownButtonFormField<String>(
            initialValue: options.contains(currentValue) ? currentValue : null,
            isExpanded: true,
            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) {
              if (v != null) _save(stringValue: v);
            },
          ),
        );
      case ControlType.text:
      case ControlType.unknown:
        return _freeTextField();
    }
  }

  Widget _freeTextField() {
    return AppTextField(
      label: 'Valore',
      controller: _textCtrl,
      onChanged: (v) => _save(stringValue: v.trim().isEmpty ? null : v.trim()),
    );
  }
}
