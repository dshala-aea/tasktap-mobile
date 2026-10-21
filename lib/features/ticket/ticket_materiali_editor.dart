// dart format width=100
import 'dart:async';

import 'package:dio/dio.dart';
// `&`, `|` and `like` are extension members (BooleanExpressionOperators /
// StringExpressionOperators), not methods on the generated columns, so a `show` list that omits
// them compiles to "undefined_operator"/"undefined_method". `Expression` is named for the same
// reason: it is the receiver type the extensions attach to.
import 'package:drift/drift.dart'
    show
        BooleanExpressionOperators,
        Expression,
        OrderingTerm,
        StringExpressionOperators;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/icons/app_lucide_icons.dart';
import '../../core/scanner/barcode_scan_sheet.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart';
import '../../data/materiali/materiale_barcode_lookup.dart'
    show MaterialeMatch, lookupMaterialeByBarcode;
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_service.dart' show appDatabaseProvider;
import 'ticket_detail_api_client.dart';

// ══════════════════════════════════════════════════════════════════════════════
// TicketMaterialiEditor — Fabbisogno tab's edit mode.
//
// One row is a catalogue article (resolved via AppLookupField, backed by a live debounced
// search) OR a free-text name — never both, mirroring web's TicketMaterialiEditor.tsx: choosing
// an article clears the free text and vice versa, so a row can never claim to be both and leave
// the server to decide which it meant. Quantity is required; unit and notes are optional.
//
// A "Scansiona codice" button adds a row from a barcode: the code is resolved against the local
// materiali mirror first (offline-safe, then the live lookup when online) via the same
// lookupMaterialeByBarcode the rapportino Materiali step and the magazzino screen use. A code
// already on the list bumps that row's quantity instead of adding a duplicate; a code the catalogue
// does not know becomes a free-text row named after the raw code, as in the rapportino step.
//
// Save PUTs the full replacement list (TicketDetailApiClient.setMateriali — the endpoint has no
// per-row server id to reconcile against, so there is nothing to diff).
// ══════════════════════════════════════════════════════════════════════════════

/// One row's editable state. Mutable on purpose — this list is rebuilt wholesale on save, not
/// diffed, so there is no benefit to immutability here (unlike NewTicketFormState, which is
/// diffed against a server record).
class MaterialeEditRow {
  MaterialeEditRow({
    this.materialeId,
    this.freeTextName,
    this.quantity = 1,
    this.unitOfMeasure,
    this.notes,
    this.initialArticleName,
    this.initialArticleCode,
  });

  String? materialeId;
  String? freeTextName;
  double quantity;
  String? unitOfMeasure;
  String? notes;

  /// Display-only — the resolved article's name/code when this row started as a catalogue
  /// reference, so [AppLookupField] has something to show before any search runs. Never sent to
  /// the server; [toWriteRow] only carries [materialeId].
  final String? initialArticleName;
  final String? initialArticleCode;

  /// Seeds an editable row from a resolved read-side [TicketMaterialeDto] — a catalogue row's
  /// `nome` is the resolved article name, not a free-text value, so only a row with no
  /// `materialeId` carries `nome` forward as `freeTextName`.
  factory MaterialeEditRow.fromDto(TicketMaterialeDto dto) => MaterialeEditRow(
    materialeId: dto.materialeId,
    freeTextName: dto.materialeId == null ? dto.nome : null,
    quantity: dto.quantita,
    unitOfMeasure: dto.unitaMisura,
    notes: dto.note,
    initialArticleName: dto.materialeId != null ? dto.nome : null,
    initialArticleCode: dto.materialeId != null ? dto.codice : null,
  );

  TicketMaterialeWriteRow toWriteRow() => TicketMaterialeWriteRow(
    materialeId: materialeId,
    freeTextName: freeTextName,
    quantity: quantity,
    unitOfMeasure: unitOfMeasure,
    notes: notes,
  );
}

/// Opens the camera scan sheet and returns the raw scanned code, or null if the technician backed
/// out. Swappable in tests, where there is no camera.
typedef BarcodeScanner = Future<String?> Function(BuildContext context);

Future<String?> _openCameraScanner(BuildContext context) =>
    openBarcodeScanSheet(context, title: 'Scansiona materiale');

class TicketMaterialiEditor extends ConsumerStatefulWidget {
  const TicketMaterialiEditor({
    super.key,
    required this.initialRows,
    required this.onSave,
    required this.onCancel,
    this.scanner,
  });

  /// Defaults to the shared camera sheet. Only tests pass one.
  final BarcodeScanner? scanner;

  final List<TicketMaterialeDto> initialRows;
  final Future<void> Function(List<TicketMaterialeWriteRow> rows) onSave;
  final VoidCallback onCancel;

  @override
  ConsumerState<TicketMaterialiEditor> createState() => TicketMaterialiEditorState();
}

class TicketMaterialiEditorState extends ConsumerState<TicketMaterialiEditor> {
  late List<MaterialeEditRow> _rows;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.initialRows.map(MaterialeEditRow.fromDto).toList();
  }

  void _addRow() => setState(() => _rows.add(MaterialeEditRow()));

  Future<MaterialeMatch?> _resolveCode(String code) async {
    try {
      return await lookupMaterialeByBarcode(ref, code);
    } on DioException {
      // The live lookup failed (not a 404) — the scan is still kept, as free text.
      return null;
    }
  }

  Future<void> _onScanPressed() async {
    final code = await (widget.scanner ?? _openCameraScanner)(context);
    if (code == null || !mounted) return;

    final match = await _resolveCode(code);
    if (!mounted) return;

    final existing = _rows.where(
      (r) => match != null
          ? r.materialeId == match.id
          : r.materialeId == null && r.freeTextName == code,
    );
    final incremented = existing.isNotEmpty;
    setState(() {
      if (incremented) {
        existing.first.quantity += 1;
      } else if (match != null) {
        _rows.add(
          MaterialeEditRow(
            materialeId: match.id,
            unitOfMeasure: match.unitOfMeasure,
            initialArticleName: match.name,
            initialArticleCode: match.code,
          ),
        );
      } else {
        _rows.add(MaterialeEditRow(freeTextName: code));
      }
    });
    showAppToast(
      context,
      message: match != null
          ? (incremented ? '${match.name}: quantità aumentata' : '${match.name} aggiunto')
          : 'Codice $code non in catalogo: aggiunto come testo libero',
      tone: match != null ? ToastTone.success : ToastTone.warning,
    );
  }

  void _removeRow(int index) => setState(() => _rows.removeAt(index));

  bool get _canSave =>
      !_isSaving &&
      _rows.every(
        (r) =>
            (r.materialeId != null || (r.freeTextName?.trim().isNotEmpty ?? false)) &&
            r.quantity > 0,
      );

  Future<void> _onSavePressed() async {
    if (!_canSave) return;
    setState(() => _isSaving = true);
    try {
      await widget.onSave(_rows.map((r) => r.toWriteRow()).toList());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _rows.length; i++) ...[
          _MaterialeRowEditor(
            key: ValueKey('materiale-row-$i'),
            row: _rows[i],
            onChanged: () => setState(() {}),
            onRemove: () => _removeRow(i),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        AppButton.secondary(
          label: 'Scansiona codice',
          icon: const Icon(LucideIcons.scanLine, size: 18),
          onPressed: _isSaving ? null : _onScanPressed,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppButton.secondary(
          label: 'Aggiungi materiale',
          icon: const Icon(LucideIcons.plus, size: 18),
          onPressed: _addRow,
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: AppButton.secondary(
                label: 'Annulla',
                onPressed: _isSaving ? null : widget.onCancel,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: AppButton(
                label: _isSaving ? 'Salvataggio…' : 'Salva',
                onPressed: _canSave ? _onSavePressed : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MaterialeRowEditor extends ConsumerStatefulWidget {
  const _MaterialeRowEditor({
    required super.key,
    required this.row,
    required this.onChanged,
    required this.onRemove,
  });

  final MaterialeEditRow row;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  ConsumerState<_MaterialeRowEditor> createState() => _MaterialeRowEditorState();
}

class _MaterialeRowEditorState extends ConsumerState<_MaterialeRowEditor> {
  late final TextEditingController _quantityCtrl;
  late final TextEditingController _unitCtrl;
  late final TextEditingController _notesCtrl;

  Timer? _debounce;
  late List<LookupItem> _articleOptions;
  final Map<String, MaterialeSearchResult> _resultCache = {};

  @override
  void initState() {
    super.initState();
    _quantityCtrl = TextEditingController(text: _formatQuantity(widget.row.quantity));
    _unitCtrl = TextEditingController(text: widget.row.unitOfMeasure ?? '');
    _notesCtrl = TextEditingController(text: widget.row.notes ?? '');
    // Seeds AppLookupField's own cache-lookup with the already-resolved article, so a row that
    // started as a catalogue reference shows its name immediately instead of blank until the
    // technician types a new search.
    _articleOptions = widget.row.materialeId != null && widget.row.initialArticleName != null
        ? [
            LookupItem(
              id: widget.row.materialeId!,
              name: widget.row.initialArticleName!,
              subtitle: widget.row.initialArticleCode,
            ),
          ]
        : const [];
  }

  @override
  void didUpdateWidget(_MaterialeRowEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A scan of an article already on the list bumps row.quantity from outside this field; typing
    // always writes the parsed value back to the row first, so equal means nothing to refresh.
    final typed = double.tryParse(_quantityCtrl.text.replaceAll(',', '.')) ?? 0;
    if (typed != widget.row.quantity) {
      _quantityCtrl.text = _formatQuantity(widget.row.quantity);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _quantityCtrl.dispose();
    _unitCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  static String _formatQuantity(double q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();

  void _onArticleQueryChanged(String query) {
    _debounce?.cancel();
    final q = query.trim();
    if (q.isEmpty) {
      setState(() => _articleOptions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _searchCatalogue(q);
      if (!mounted) return;
      for (final r in results) {
        _resultCache[r.id] = r;
      }
      setState(() {
        _articleOptions = results
            .map((r) => LookupItem(id: r.id, name: r.name, subtitle: r.code))
            .toList();
      });
    });
  }

  /// The catalogue search behind the article field: the server while online, the mirrored
  /// catalogue otherwise.
  ///
  /// The field used to be a bare `GET /Materiali`, so on site the call threw out of the timer
  /// callback — nothing caught it, `_articleOptions` was never updated, and the technician saw a
  /// silent "no suggestions" with no way to tell "not found" from "no signal". The sync already
  /// mirrors the catalogue (`materiali`), so the same question is answerable offline; and when the
  /// radio says online and the call still fails, the mirror beats a field that silently stops
  /// working.
  Future<List<MaterialeSearchResult>> _searchCatalogue(String query) async {
    if (!ref.read(isOnlineProvider)) return _searchMirror(query);
    try {
      return await ref.read(ticketDetailApiClientProvider).searchMateriali(query);
    } on DioException {
      return _searchMirror(query);
    }
  }

  /// [_searchCatalogue]'s offline half: name or code contains the query, active articles only.
  ///
  /// Same 20-row cap and alphabetical order as the server's page, so the dropdown behaves the
  /// same either way. `LIKE` rather than a Dart-side pass so a large catalogue never has to be
  /// read off the device to answer one keystroke.
  Future<List<MaterialeSearchResult>> _searchMirror(String query) async {
    final AppDatabase db = ref.read(appDatabaseProvider);
    final rows =
        await (db.select(db.materiali)..where(
              (m) =>
                  m.isActive.equals(true) &
                  (m.name.like('%$query%') | m.code.like('%$query%')),
            )..orderBy([(m) => OrderingTerm.asc(m.name)])..limit(20))
            .get();
    return rows
        .map(
          (m) => MaterialeSearchResult(
            id: m.id,
            name: m.name,
            code: m.code,
            unitOfMeasure: m.unitOfMeasure,
          ),
        )
        .toList();
  }

  void _onArticleSelected(String id) {
    widget.row.materialeId = id;
    widget.row.freeTextName = null;
    // Convenience auto-fill, same as web's TicketMaterialiEditor: a starting value only, still
    // fully editable afterward — never overwrites a unit the technician already typed.
    final picked = _resultCache[id];
    if (picked?.unitOfMeasure != null && _unitCtrl.text.trim().isEmpty) {
      _unitCtrl.text = picked!.unitOfMeasure!;
      widget.row.unitOfMeasure = picked.unitOfMeasure;
    }
    widget.onChanged();
  }

  void _onArticleFreeText(String text) {
    widget.row.freeTextName = text.isEmpty ? null : text;
    widget.row.materialeId = null;
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppLookupField(
                  label: 'Articolo o testo libero',
                  hint: 'Cerca nel catalogo…',
                  items: _articleOptions,
                  selectedId: widget.row.materialeId,
                  initialText: widget.row.freeTextName,
                  onSelected: _onArticleSelected,
                  onFreeText: (text) {
                    _onArticleQueryChanged(text);
                    _onArticleFreeText(text);
                  },
                ),
              ),
              IconButton(
                icon: Icon(LucideIcons.trash2, color: context.colors.red, size: 18),
                tooltip: 'Rimuovi materiale',
                onPressed: () {
                  widget.onRemove();
                },
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Quantità *',
                  controller: _quantityCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (v) {
                    widget.row.quantity = double.tryParse(v.replaceAll(',', '.')) ?? 0;
                    widget.onChanged();
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppTextField(
                  label: 'Unità',
                  controller: _unitCtrl,
                  onChanged: (v) {
                    widget.row.unitOfMeasure = v.isEmpty ? null : v;
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            label: 'Note',
            controller: _notesCtrl,
            onChanged: (v) {
              widget.row.notes = v.isEmpty ? null : v;
              widget.onChanged();
            },
          ),
        ],
      ),
    );
  }
}
