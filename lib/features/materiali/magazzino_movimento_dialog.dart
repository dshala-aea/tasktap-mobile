// dart format width=100
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../core/scanner/barcode_scan_sheet.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/error_message.dart';
import '../../core/utils/offline_guard.dart';
import '../../core/widgets/widgets.dart';
import '../../data/magazzino/magazzino_api_client.dart';
import '../../data/materiali/materiale_barcode_lookup.dart';
import '../../data/sync/connectivity_provider.dart';
import '../magazzino/magazzino_providers.dart';
import 'materiale_picker_dialog.dart';
import 'materiale_qty_field.dart';

enum MagazzinoMovimentoTipo { carico, scarico, trasferimento }

/// Mobile carico / scarico / trasferimento: pick the operation, the warehouse(s), the article and
/// a decimal quantity, then call the existing movement endpoints.
Future<void> showMagazzinoMovimentoDialog(BuildContext context, {BarcodeScanner? scanner}) {
  return showDialog<void>(
    context: context,
    builder: (_) => MagazzinoMovimentoDialog(scanner: scanner),
  );
}

class MagazzinoMovimentoDialog extends ConsumerStatefulWidget {
  const MagazzinoMovimentoDialog({super.key, this.scanner});

  final BarcodeScanner? scanner;

  @override
  ConsumerState<MagazzinoMovimentoDialog> createState() => _MagazzinoMovimentoDialogState();
}

class _MagazzinoMovimentoDialogState extends ConsumerState<MagazzinoMovimentoDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _noteCtrl = TextEditingController();

  MagazzinoMovimentoTipo _tipo = MagazzinoMovimentoTipo.carico;
  String? _sourceId;
  String? _destinationId;
  String? _materialeId;
  String? _materialeNome;
  int _lookupGeneration = 0;
  bool _saving = false;

  double get _qty => double.tryParse(_qtyCtrl.text.replaceAll(',', '.')) ?? 0;

  bool get _needsSource => _tipo != MagazzinoMovimentoTipo.carico;
  bool get _needsDestination => _tipo != MagazzinoMovimentoTipo.scarico;

  bool get _canSubmit {
    if (_saving || _materialeId == null || _qty <= 0) return false;
    if (_needsSource && _sourceId == null) return false;
    if (_needsDestination && _destinationId == null) return false;
    if (_tipo == MagazzinoMovimentoTipo.trasferimento && _sourceId == _destinationId) {
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _bumpQty(double delta) {
    final next = (_qty + delta).clamp(1, 999999).toDouble();
    _qtyCtrl.text = next == next.truncateToDouble() ? next.toInt().toString() : next.toString();
    setState(() {});
  }

  Future<void> _onScanPressed() async {
    final code = await (widget.scanner ??
        (ctx) => openBarcodeScanSheet(ctx, title: 'Scansiona materiale'))(context);
    if (code == null || !mounted) return;
    final match = await lookupMaterialeByBarcode(ref, code);
    if (!mounted) return;
    setState(() {
      _lookupGeneration++;
      _materialeId = match?.id;
      _materialeNome = match?.name ?? code;
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _saving = true);
    final client = ref.read(magazzinoApiClientProvider);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();
    try {
      switch (_tipo) {
        case MagazzinoMovimentoTipo.carico:
          await client.carico(
            magazzinoId: _destinationId!,
            materialeId: _materialeId!,
            quantita: _qty,
            note: note,
          );
        case MagazzinoMovimentoTipo.scarico:
          await client.scarico(
            magazzinoId: _sourceId!,
            materialeId: _materialeId!,
            quantita: _qty,
            note: note,
          );
        case MagazzinoMovimentoTipo.trasferimento:
          await client.trasferimento(
            magazzinoId: _sourceId!,
            materialeId: _materialeId!,
            quantita: _qty,
            magazzinoDestinazioneId: _destinationId!,
            note: note,
          );
      }
      if (!mounted) return;
      Navigator.pop(context);
      ref.invalidate(giacenzeProvider);
      ref.invalidate(movimentiProvider);
      showAppToast(context, message: 'Movimento registrato', tone: ToastTone.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, message: _movementError(e), tone: ToastTone.error);
    }
  }

  static String _movementError(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is String && data.trim().isNotEmpty) return data;
    }
    return humanErrorMessage(e, azione: 'registrare il movimento');
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    final magazziniAsync = ref.watch(magazziniProvider);

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
              'Movimento magazzino',
              style: TextStyle(
                fontFamily: 'Archivo Narrow',
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: context.colors.ink,
              ),
            ),
            const SizedBox(height: 12),
            AppTabs(
              tabs: const [
                AppTab(label: 'Carico'),
                AppTab(label: 'Scarico'),
                AppTab(label: 'Trasferisci'),
              ],
              selectedIndex: _tipo.index,
              onSelected: (i) => setState(() {
                _tipo = MagazzinoMovimentoTipo.values[i];
                if (_tipo == MagazzinoMovimentoTipo.carico) _sourceId = null;
                if (_tipo == MagazzinoMovimentoTipo.scarico) _destinationId = null;
              }),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!online)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          'Serve una connessione per registrare un movimento.',
                          style: TextStyle(fontSize: 12, color: context.colors.red),
                        ),
                      ),
                    MaterialeLookupField(
                      key: ValueKey(_lookupGeneration),
                      selectedId: _materialeId,
                      initialText: _materialeNome,
                      onMaterialeSelected: (m) => setState(() {
                        _materialeId = m.id;
                        _materialeNome = m.name;
                      }),
                      onFreeText: (text) => setState(() {
                        _materialeId = null;
                        _materialeNome = text;
                      }),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: const Icon(LucideIcons.scanLine, size: 18),
                        tooltip: 'Scansiona codice',
                        onPressed: _onScanPressed,
                      ),
                    ),
                    if (_materialeId == null && (_materialeNome?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          'Scegli un articolo a catalogo.',
                          style: TextStyle(fontSize: 12, color: context.colors.inkMuted),
                        ),
                      ),
                    _WarehouseDropdown(
                      label: _tipo == MagazzinoMovimentoTipo.carico
                          ? 'Magazzino di destinazione'
                          : 'Magazzino di origine',
                      async: magazziniAsync,
                      value: _tipo == MagazzinoMovimentoTipo.carico ? _destinationId : _sourceId,
                      onChanged: (id) => setState(() {
                        if (_tipo == MagazzinoMovimentoTipo.carico) {
                          _destinationId = id;
                        } else {
                          _sourceId = id;
                          if (_tipo == MagazzinoMovimentoTipo.trasferimento &&
                              _destinationId == id) {
                            _destinationId = null;
                          }
                        }
                      }),
                    ),
                    if (_tipo == MagazzinoMovimentoTipo.trasferimento) ...[
                      const SizedBox(height: 10),
                      _WarehouseDropdown(
                        label: 'Magazzino di destinazione',
                        async: magazziniAsync,
                        value: _destinationId,
                        excludeId: _sourceId,
                        onChanged: (id) => setState(() => _destinationId = id),
                      ),
                    ],
                    const SizedBox(height: 10),
                    MaterialeQtyField(
                      controller: _qtyCtrl,
                      fieldKey: const Key('movimento-qty-field'),
                      onChanged: () => setState(() {}),
                      onMinus: _qty > 1 ? () => _bumpQty(-1) : null,
                      onPlus: () => _bumpQty(1),
                      errorText: _qty > 0 ? null : 'Inserisci una quantità valida.',
                    ),
                    const SizedBox(height: 10),
                    AppFieldShell(
                      label: 'Note',
                      child: TextField(controller: _noteCtrl),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppButton.ghost(
                    label: 'Annulla',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: _saving ? 'Registrazione…' : 'Registra',
                    onPressed: _canSubmit && online ? _submit : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehouseDropdown extends StatelessWidget {
  const _WarehouseDropdown({
    required this.label,
    required this.async,
    required this.value,
    required this.onChanged,
    this.excludeId,
  });

  final String label;
  final AsyncValue<List<MagazzinoDto>> async;
  final String? value;
  final String? excludeId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: LinearProgressIndicator(),
      ),
      error: (e, _) => Text(
        humanErrorMessage(e, azione: 'caricare i magazzini'),
        style: TextStyle(fontSize: 12, color: context.colors.red),
      ),
      data: (all) {
        final items = all.where((m) => m.id != excludeId).toList();
        return AppFieldShell(
          label: label,
          child: DropdownButtonFormField<String?>(
            key: ValueKey('$label|$value|$excludeId|${items.length}'),
            initialValue: value,
            hint: const Text('Scegli un magazzino'),
            items: [
              for (final m in items)
                DropdownMenuItem<String?>(
                  value: m.id,
                  child: Text('${m.nome} · ${m.tipo}'),
                ),
            ],
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}
