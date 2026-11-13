// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/constants/catalog_constants.dart';
import '../../core/scanner/barcode_scan_sheet.dart';
import '../../core/utils/error_message.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_rack.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/widgets.dart';
import '../../data/local/app_database.dart' show MaterialiData;
import '../../data/magazzino/magazzino_api_client.dart';
import '../../data/materiali/materiale_barcode_lookup.dart';
import '../../data/sync/connectivity_provider.dart';
import '../../data/sync/sync_freshness_provider.dart';
import '../../presentation/providers/schedule_providers.dart';
import '../magazzino/magazzino_providers.dart';
import '../ticket/ticket_detail_api_client.dart' show TicketMaterialeDto;
import '../ticket/ticket_providers.dart' show ticketMaterialiProvider;
import 'materiale_qty_field.dart';

/// What the shared material picker returns. The caller decides how to store it: the rapportino
/// maps it to a [MaterialeRow] (including `magazzinoId`, which books the scarico), the ticket
/// fabbisogno maps it to an editable row (where `magazzinoId` is planning provenance only).
class MaterialePickerResult {
  const MaterialePickerResult({
    this.materialeId,
    this.freeTextName,
    required this.quantity,
    this.unitOfMeasure,
    this.magazzinoId,
    this.magazzinoNome,
    this.materialeNome,
    this.materialeCodice,
  });

  final String? materialeId;
  final String? freeTextName;
  final double quantity;
  final String? unitOfMeasure;
  final String? magazzinoId;
  final String? magazzinoNome;
  final String? materialeNome;
  final String? materialeCodice;
}

class _PickedMateriale {
  const _PickedMateriale({
    required this.id,
    required this.code,
    required this.name,
    this.unitOfMeasure,
  });

  final String id;
  final String code;
  final String name;
  final String? unitOfMeasure;
}

/// Resolves a catalogue article's source warehouses and exposes the selected one.
///
/// Shared by the rapportino picker and the ticket Fabbisogno editor so both get the same
/// single/multiple/none behaviour: exactly one giacenza is selected automatically, several are
/// offered as a dropdown (largest first), none leaves the source null, and offline falls back to
/// the mirrored warehouse list with an honest warning. Fabbisogno only stores the choice — it
/// never books a stock movement through this class.
class MaterialeSourceResolver extends ChangeNotifier {
  MaterialeSourceResolver(this._ref);

  final WidgetRef _ref;

  bool loading = false;
  String? error;
  List<GiacenzaDto>? giacenze;
  List<MagazzinoDto>? offlineMagazzini;
  String? magazzinoId;
  String? magazzinoNome;

  int _generation = 0;
  bool _disposed = false;

  void clear() {
    _generation++;
    loading = false;
    error = null;
    giacenze = null;
    offlineMagazzini = null;
    magazzinoId = null;
    magazzinoNome = null;
    _notify();
  }

  void select(String? id, String? nome) {
    if (magazzinoId == id && magazzinoNome == nome) return;
    magazzinoId = id;
    magazzinoNome = nome;
    _notify();
  }

  Future<void> resolve({
    required String id,
    required String name,
    required String code,
    String? preferredMagazzinoId,
  }) async {
    final generation = ++_generation;
    loading = true;
    error = null;
    giacenze = null;
    offlineMagazzini = null;
    magazzinoId = null;
    magazzinoNome = null;
    _notify();

    bool stale() => _disposed || generation != _generation;

    Future<List<GiacenzaDto>> query(String q) async {
      final page = await _ref.read(magazzinoApiClientProvider).getGiacenze(q: q, pageSize: 100);
      return page.elementi.where((g) => g.materialeId == id).toList()
        ..sort((a, b) => b.quantita.compareTo(a.quantita));
    }

    Future<List<MagazzinoDto>> mirror() async {
      try {
        return await _ref.read(magazziniProvider.future);
      } catch (_) {
        return const [];
      }
    }

    if (!_ref.read(isOnlineProvider)) {
      final list = await mirror();
      if (stale()) return;
      offlineMagazzini = list;
      loading = false;
      error = 'Disponibilità non verificabile offline';
      _notify();
      return;
    }

    try {
      // Name first, code as a fallback: the giacenze `q` is a general search and the code may
      // not be indexed by it.
      var matches = await query(name.isNotEmpty ? name : code);
      if (matches.isEmpty && code.isNotEmpty && name.isNotEmpty) {
        matches = await query(code);
      }
      if (stale()) return;
      giacenze = matches;
      loading = false;
      if (matches.isNotEmpty) {
        final preferred = preferredMagazzinoId == null
            ? null
            : matches.where((g) => g.magazzinoId == preferredMagazzinoId).firstOrNull;
        final selected = preferred ?? matches.first;
        magazzinoId = selected.magazzinoId;
        magazzinoNome = selected.magazzinoNome;
      }
      _notify();
    } catch (e) {
      if (!isTransportOrServerFault(e)) {
        if (stale()) return;
        loading = false;
        error = humanErrorMessage(e, azione: 'verificare le giacenze');
        _notify();
        return;
      }
      final list = await mirror();
      if (stale()) return;
      offlineMagazzini = list;
      loading = false;
      error = 'Disponibilità non verificabile offline';
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The one add-material modal used by the rapportino and the ticket fabbisogno.
///
/// Search or free text, barcode, a decimal numeric-pad quantity, unit, and — when [showSource] is
/// true — the source warehouse resolved from the article's giacenze. The rapportino books a stock
/// scarico from that choice; ticket fabbisogno records it as planning provenance only (no stock
/// movement is ever created from a ticket's planned materials).
Future<MaterialePickerResult?> showMaterialePickerDialog(
  BuildContext context, {
  String? ticketId,
  bool showSource = true,
  bool showFabbisognoSuggestions = true,
  BarcodeScanner? scanner,
}) {
  return showDialog<MaterialePickerResult>(
    context: context,
    builder: (_) => MaterialePickerDialog(
      ticketId: ticketId,
      showSource: showSource,
      showFabbisognoSuggestions: showFabbisognoSuggestions,
      scanner: scanner,
    ),
  );
}

class MaterialePickerDialog extends ConsumerStatefulWidget {
  const MaterialePickerDialog({
    super.key,
    this.ticketId,
    this.showSource = true,
    this.showFabbisognoSuggestions = true,
    this.scanner,
  });

  final String? ticketId;
  final bool showSource;
  final bool showFabbisognoSuggestions;
  final BarcodeScanner? scanner;

  @override
  ConsumerState<MaterialePickerDialog> createState() => _MaterialePickerDialogState();
}

class _MaterialePickerDialogState extends ConsumerState<MaterialePickerDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  late final MaterialeSourceResolver _source;

  String? _materialeId;
  String? _freeTextName;
  String? _uom;
  _PickedMateriale? _picked;
  int _lookupGeneration = 0;
  bool _showAdvanced = false;

  double get _qty => parseMaterialeQty(_qtyCtrl.text) ?? 0;

  bool get _canAdd {
    final identified = _materialeId != null || (_freeTextName?.trim().isNotEmpty ?? false);
    final sourcePending = widget.showSource && _picked != null && _source.loading;
    return identified && _qty > 0 && !sourcePending;
  }

  @override
  void initState() {
    super.initState();
    _source = MaterialeSourceResolver(ref)..addListener(_onSourceChanged);
  }

  void _onSourceChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _source
      ..removeListener(_onSourceChanged)
      ..dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _onMaterialeSelected(MaterialiData m) {
    _source.clear();
    setState(() {
      _materialeId = m.id;
      _freeTextName = null;
      _uom = (m.unitOfMeasure?.isNotEmpty ?? false) ? m.unitOfMeasure : _uom;
      _picked = _PickedMateriale(
        id: m.id,
        code: m.code,
        name: m.name,
        unitOfMeasure: m.unitOfMeasure,
      );
    });
    if (widget.showSource) _resolveSources(_picked!);
  }

  void _onFreeText(String text) {
    _source.clear();
    setState(() {
      _materialeId = null;
      _freeTextName = text;
      _picked = null;
    });
  }

  Future<void> _onScanPressed() async {
    final code = await (widget.scanner ?? _openCameraScanner)(context);
    if (code == null || !mounted) return;

    final match = await lookupMaterialeByBarcode(ref, code);
    if (!mounted) return;

    _source.clear();
    setState(() {
      _lookupGeneration++;
      if (match != null) {
        _materialeId = match.id;
        _freeTextName = null;
        if (match.unitOfMeasure?.isNotEmpty ?? false) _uom = match.unitOfMeasure;
        _picked = _PickedMateriale(
          id: match.id,
          code: match.code,
          name: match.name,
          unitOfMeasure: match.unitOfMeasure,
        );
      } else {
        _materialeId = null;
        _freeTextName = code;
        _picked = null;
      }
    });
    if (match != null && widget.showSource) _resolveSources(_picked!);
  }

  Future<void> _resolveSources(_PickedMateriale m) =>
      _source.resolve(id: m.id, name: m.name, code: m.code);

  void _bumpQty(double delta) {
    final next = (_qty + delta).clamp(1, 999999).toDouble();
    _qtyCtrl.text = formatMaterialeQty(next);
    setState(() {});
  }

  void _submit() {
    if (!_canAdd) return;
    final typed = _freeTextName?.trim();
    Navigator.pop(
      context,
      MaterialePickerResult(
        materialeId: _materialeId,
        freeTextName: _materialeId == null ? (typed?.isEmpty ?? true ? null : typed) : null,
        quantity: _qty,
        unitOfMeasure: _uom,
        magazzinoId: _source.magazzinoId,
        magazzinoNome: _source.magazzinoNome,
        materialeNome: _picked?.name,
        materialeCodice: _picked?.code,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.showFabbisognoSuggestions && widget.ticketId != null)
                      _FabbisognoSuggestions(
                        ticketId: widget.ticketId!,
                        onPicked: (m) {
                          _source.clear();
                          setState(() {
                            _materialeId = m.materialeId;
                            _freeTextName = m.materialeId == null ? m.nome : null;
                            _qtyCtrl.text = formatMaterialeQty(m.quantita > 0 ? m.quantita : 1);
                            if (m.unitaMisura?.isNotEmpty ?? false) _uom = m.unitaMisura;
                            _picked = m.materialeId == null
                                ? null
                                : _PickedMateriale(
                                    id: m.materialeId!,
                                    code: m.codice ?? '',
                                    name: m.nome,
                                    unitOfMeasure: m.unitaMisura,
                                  );
                            _lookupGeneration++;
                          });
                          if (m.materialeId != null && widget.showSource) {
                            _resolveSources(_picked!);
                          }
                        },
                      ),
                    MaterialeLookupField(
                      key: ValueKey(_lookupGeneration),
                      selectedId: _materialeId,
                      initialText: _freeTextName,
                      onMaterialeSelected: _onMaterialeSelected,
                      onFreeText: _onFreeText,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(LucideIcons.scanLine, size: 18),
                        tooltip: 'Scansiona codice',
                        onPressed: _onScanPressed,
                      ),
                    ),
                    const SizedBox(height: 8),
                    MaterialeQtyField(
                      controller: _qtyCtrl,
                      onChanged: () => setState(() {}),
                      onMinus: _qty > 1 ? () => _bumpQty(-1) : null,
                      onPlus: () => _bumpQty(1),
                      errorText: _qty > 0 ? null : 'Inserisci una quantità valida.',
                    ),
                    if (widget.showSource && _picked != null) ...[
                      const SizedBox(height: 10),
                      MaterialeSourceSection(
                        loading: _source.loading,
                        error: _source.error,
                        giacenze: _source.giacenze,
                        offlineMagazzini: _source.offlineMagazzini,
                        selectedMagazzinoId: _source.magazzinoId,
                        onChanged: _source.select,
                      ),
                    ],
                    if (widget.showSource &&
                        _picked == null &&
                        (_freeTextName?.trim().isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Testo libero: lo scarico non sarà registrato.',
                          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                        ),
                      ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                      borderRadius: AppRack.insetShape,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Row(
                          children: [
                            Icon(LucideIcons.package, size: 14, color: context.colors.inkMuted),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Unità: ${_uom ?? 'non impostata'}',
                                style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                              ),
                            ),
                            AnimatedRotation(
                              turns: _showAdvanced ? 0.5 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: Icon(
                                LucideIcons.chevronDown,
                                size: 16,
                                color: context.colors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showAdvanced) ...[
                      const SizedBox(height: 8),
                      AppFieldShell(
                        label: 'Unità',
                        child: DropdownButtonFormField<String?>(
                          initialValue: _uom,
                          hint: const Text('pz'),
                          items: [
                            const DropdownMenuItem<String?>(value: null, child: Text('Nessuna')),
                            for (final u in materialeSelectOptions(kUnitOfMeasureOptions, _uom))
                              DropdownMenuItem<String?>(value: u, child: Text(u)),
                          ],
                          onChanged: (v) => setState(() => _uom = v),
                        ),
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
                  child: AppButton.ghost(label: 'Annulla', onPressed: () => Navigator.pop(context)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(label: 'Aggiungi', onPressed: _canAdd ? _submit : null),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _openCameraScanner(BuildContext context) =>
    openBarcodeScanSheet(context, title: 'Scansiona materiale');

// ── Quantity: numeric keyboard + steppers ────────────────────────────────────

// ── Source magazzino ──────────────────────────────────────────────────────────

/// The shared source-warehouse control: auto-selected single giacenza, dropdown for several,
/// honest notices for none/offline. Used by the report picker and the ticket Fabbisogno editor.
class MaterialeSourceSection extends StatelessWidget {
  const MaterialeSourceSection({
    super.key,
    required this.loading,
    required this.error,
    required this.giacenze,
    required this.offlineMagazzini,
    required this.selectedMagazzinoId,
    required this.onChanged,
  });

  final bool loading;
  final String? error;
  final List<GiacenzaDto>? giacenze;
  final List<MagazzinoDto>? offlineMagazzini;
  final String? selectedMagazzinoId;
  final void Function(String? id, String? nome) onChanged;

  static String _qtyLabel(GiacenzaDto g) {
    final q = g.quantita;
    final text = q == q.truncateToDouble() ? q.toInt().toString() : q.toString();
    final unit = g.unitOfMeasure;
    return unit == null || unit.isEmpty ? text : '$text $unit';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Row(
        children: [
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 8),
          Text(
            'Verifica giacenze…',
            style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
          ),
        ],
      );
    }

    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error!, style: TextStyle(fontSize: 12, color: context.colors.inkMuted)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            key: ValueKey(
              'offline-source|$selectedMagazzinoId|${(offlineMagazzini ?? const []).length}',
            ),
            initialValue: selectedMagazzinoId,
            hint: const Text('Nessun magazzino'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Nessun magazzino')),
              for (final m in offlineMagazzini ?? const <MagazzinoDto>[])
                DropdownMenuItem<String?>(value: m.id, child: Text(m.nome)),
            ],
            onChanged: (id) {
              final nome = (offlineMagazzini ?? const <MagazzinoDto>[])
                  .where((m) => m.id == id)
                  .map((m) => m.nome)
                  .firstOrNull;
              onChanged(id, nome);
            },
          ),
        ],
      );
    }

    final list = giacenze;
    if (list == null) return const SizedBox.shrink();
    if (list.isEmpty) {
      return Text(
        'Nessuna giacenza: lo scarico non sarà registrato.',
        style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
      );
    }
    if (list.length == 1) {
      final g = list.first;
      return Text(
        'Da: ${g.magazzinoNome ?? 'Magazzino'} · ${_qtyLabel(g)}',
        style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
      );
    }
    return AppFieldShell(
      label: 'Magazzino di scarico',
      child: DropdownButtonFormField<String>(
        key: ValueKey('giacenza-source|$selectedMagazzinoId|${list.length}'),
        initialValue: selectedMagazzinoId,
        items: [
          for (final g in list)
            DropdownMenuItem<String>(
              value: g.magazzinoId,
              child: Text('${g.magazzinoNome ?? 'Magazzino'} · ${_qtyLabel(g)}'),
            ),
        ],
        onChanged: (id) {
          final g = list.where((x) => x.magazzinoId == id).firstOrNull;
          onChanged(id, g?.magazzinoNome);
        },
      ),
    );
  }
}

// ── Catalog lookup ───────────────────────────────────────────────────────────

/// Live catalog search for the picker and the movement dialog. Watches [allMaterialiProvider]
/// rather than capturing it once, because the provider is `autoDispose` and a one-time read often
/// catches it before the Drift stream's first emission.
class MaterialeLookupField extends ConsumerWidget {
  const MaterialeLookupField({
    super.key,
    required this.selectedId,
    required this.initialText,
    required this.onMaterialeSelected,
    required this.onFreeText,
  });

  final String? selectedId;
  final String? initialText;
  final ValueChanged<MaterialiData> onMaterialeSelected;
  final ValueChanged<String> onFreeText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialiAsync = ref.watch(allMaterialiProvider);
    final catalogo = materialiAsync.value ?? const <MaterialiData>[];

    return AppLookupField(
      label: 'Materiale',
      hint: 'Cerca a catalogo o scrivi il nome',
      selectedId: selectedId,
      initialText: initialText ?? '',
      items: [for (final m in catalogo) LookupItem(id: m.id, name: m.name, subtitle: m.code)],
      emptyCacheHint: materialiAsync.isLoading
          ? 'Catalogo in caricamento…'
          : ref.watch(hasSyncedAtLeastOnceProvider).value == false
          ? 'Catalogo non ancora scaricato su questo telefono: scrivi il nome per registrarlo '
                'comunque.'
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

// ── Fabbisogno suggestions ───────────────────────────────────────────────────

/// One tap fills the picker with a planned line's name/quantity/unit — the technician still reviews
/// and hits "Aggiungi" like any other entry, they just never type what the office already planned.
class _FabbisognoSuggestions extends ConsumerWidget {
  const _FabbisognoSuggestions({required this.ticketId, required this.onPicked});

  final String ticketId;
  final ValueChanged<TicketMaterialeDto> onPicked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketMaterialiProvider(ticketId));
    final planned = async.value ?? const <TicketMaterialeDto>[];
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
