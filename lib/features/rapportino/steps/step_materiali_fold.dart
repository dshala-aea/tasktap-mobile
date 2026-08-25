// dart format width=100
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/error_message.dart';
// Uses StepLabel — the padding-free sibling of SectionTitle, for headings inside a padded card.
import '../../../data/local/app_database.dart';
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../../data/reports/ticket_controls_cache_repository.dart';
import '../../../presentation/providers/auth_providers.dart';
import '../../../presentation/providers/report_editor_providers.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../magazzino/magazzino_providers.dart';
import '../../ticket/ticket_detail_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Step 3 — Materiali  (folds Controlli + Foto/Allegati as sub-sections)
//
// - Qty steppers (− value +) per MaterialeRow
// - "Aggiungi materiale" opens picker dialog
// - "Nessun materiale" toggle (setMaterialiNotRequired)
// - Controlli sub-section (upsertControllo)
// - Foto/allegati sub-section (addAllegato/removeAllegato)
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
    final currentUser = ref.watch(currentUserProvider);
    final furgoneAsync = currentUser == null
        ? const AsyncValue<MagazzinoDto?>.data(null)
        : ref.watch(furgoneDiUserProvider(currentUser.id));

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
            padding: EdgeInsets.fromLTRB(
              AppSpacing.base,
              AppSpacing.xs,
              AppSpacing.base,
              context.navClearance,
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
            OutlinedButton.icon(
              onPressed: () => _showAddMaterialeDialog(context, ref, furgoneAsync.valueOrNull),
              icon: const Icon(LucideIcons.plusSquare),
              label: const Text('Aggiungi materiale'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // ── Controlli sub-section ──────────────────────────────────────────
          // The checklist for this intervention, resolved server-side from the
          // ticket's maintenance-template version (ADR-0012) — not a free-text
          // "type an ID" box. See _ControlliChecklist.
          StepLabel(title: 'Controlli'),
          const SizedBox(height: 8),
          _ControlliChecklist(reportId: reportId, ticketId: state.ticketId),
          const SizedBox(height: 24),

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
                child: OutlinedButton.icon(
                  onPressed: () => _pickImage(context, ref, ImageSource.gallery),
                  icon: const Icon(LucideIcons.image),
                  label: const Text('Galleria'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickImage(context, ref, ImageSource.camera),
                  icon: const Icon(LucideIcons.camera),
                  label: const Text('Fotocamera'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand,
                    foregroundColor: context.colors.brandOn,
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddMaterialeDialog(
    BuildContext context,
    WidgetRef ref,
    MagazzinoDto? defaultMagazzino,
  ) {
    final notifier = ref.read(reportEditorProvider(reportId).notifier);
    final materialiAsync = ref.read(allMaterialiProvider);

    final catalogo = materialiAsync.valueOrNull ?? const <MaterialiData>[];

    final qtyCtrl = TextEditingController(text: '1');
    final uomCtrl = TextEditingController();
    String? selectedMaterialeId;
    String freeTextName = '';
    // Defaults to the technician's own furgone (zero extra taps for the common case — see Gap 1 in
    // the feature audit). "Cambia" below lets them source a line from a different warehouse, e.g.
    // stock picked up from a Sede for a job done off the van.
    String? selectedMagazzinoId = defaultMagazzino?.id;
    String? selectedMagazzinoNome = defaultMagazzino?.nome;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Aggiungi materiale'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Same single field as the rest of the wizard. This dialog is opened once per
                // material — often a dozen times on one job — so the catalogo/testo-libero mode
                // switch was being paid over and over on the same rapportino.
                AppLookupField(
                  label: 'Materiale',
                  hint: 'Cerca a catalogo o scrivi il nome',
                  items: [
                    for (final m in catalogo) LookupItem(id: m.id, name: m.name, subtitle: m.code),
                  ],
                  onSelected: (id) {
                    selectedMaterialeId = id;
                    freeTextName = '';
                    // The catalogue knows the unit. Asking the technician to type "pz" after
                    // picking a part that is already measured in pieces is a question with a
                    // known answer.
                    for (final m in catalogo) {
                      if (m.id == id && (m.unitOfMeasure?.isNotEmpty ?? false)) {
                        uomCtrl.text = m.unitOfMeasure!;
                      }
                    }
                    setDialogState(() {});
                  },
                  onFreeText: (v) {
                    selectedMaterialeId = null;
                    freeTextName = v;
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: AppFieldShell(
                        label: 'Qtà',
                        child: TextField(
                          controller: qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppFieldShell(
                        label: 'Unità',
                        child: TextField(
                          controller: uomCtrl,
                          decoration: const InputDecoration(hintText: 'pz'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(LucideIcons.warehouse, size: 16, color: ctx.colors.inkMuted),
                    const SizedBox(width: 6),
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
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(qtyCtrl.text) ?? 1.0;
                final id = 'mat-${DateTime.now().millisecondsSinceEpoch}';
                final typed = freeTextName.trim();
                notifier.addMateriale(
                  MaterialeRow(
                    id: id,
                    reportId: reportId,
                    materialeId: selectedMaterialeId,
                    // Whichever one holds the answer. There is no mode to consult any more, so
                    // the row records what is actually there.
                    freeTextName: selectedMaterialeId == null && typed.isNotEmpty ? typed : null,
                    quantity: qty,
                    unitOfMeasure: uomCtrl.text.trim().isEmpty ? null : uomCtrl.text.trim(),
                    magazzinoId: selectedMagazzinoId,
                  ),
                );
                Navigator.pop(ctx);
              },
              child: const Text('Aggiungi'),
            ),
          ],
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
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text(humanErrorMessage(e, azione: 'caricare i magazzini')),
              ),
              data: (list) => list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Foto non salvata. Riprova, e controlla lo spazio libero sul telefono.',
            ),
            backgroundColor: context.colors.red,
          ),
        );
      }
    }
  }
}

// ── Qty stepper card ──────────────────────────────────────────────────────────

class _MaterialeQtyStepper extends StatelessWidget {
  const _MaterialeQtyStepper({
    required this.row,
    required this.onQtyChanged,
    required this.onRemove,
  });

  final MaterialeRow row;
  final ValueChanged<double> onQtyChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
                  row.displayName,
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
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(row.localPath),
            fit: BoxFit.cover,
            errorBuilder: (ctx, e, _) => Container(
              color: context.colors.bg3,
              child: Icon(LucideIcons.imageOff, color: context.colors.inkMuted),
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
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  void _save({String? stringValue, bool? boolValue, DateTime? dateValue}) {
    final notifier = ref.read(reportEditorProvider(widget.reportId).notifier);
    notifier.upsertControllo(
      ControlloRow(
        id: _rowId,
        reportId: widget.reportId,
        controlId: widget.flat.control.id,
        stringValue: stringValue,
        boolValue: boolValue,
        dateValue: dateValue,
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
      case ControlType.radioOnOff:
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
      case ControlType.date:
        final value = existing?.dateValue ?? c.dateValue;
        return OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value ?? DateTime.now(),
              firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
            );
            if (picked != null) _save(dateValue: picked);
          },
          icon: const Icon(LucideIcons.calendar, size: 16),
          label: Text(
            value != null ? DateFormat('dd/MM/yyyy', 'it').format(value) : 'Seleziona data',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            alignment: Alignment.centerLeft,
          ),
        );
      case ControlType.singleChoice:
        final options = c.choiceOptions;
        if (options.isEmpty) {
          // No choice list published for this item — degrade to free text
          // rather than a dropdown with nothing to pick.
          return _freeTextField();
        }
        final currentValue = existing?.stringValue ?? c.stringValue;
        return DropdownButtonFormField<String>(
          initialValue: options.contains(currentValue) ? currentValue : null,
          decoration: const InputDecoration(isDense: true),
          isExpanded: true,
          items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
          onChanged: (v) {
            if (v != null) _save(stringValue: v);
          },
        );
      case ControlType.freeText:
      case ControlType.unknown:
        return _freeTextField();
    }
  }

  Widget _freeTextField() {
    return TextField(
      controller: _textCtrl,
      decoration: const InputDecoration(hintText: 'Valore', isDense: true),
      onChanged: (v) => _save(stringValue: v.trim().isEmpty ? null : v.trim()),
    );
  }
}
