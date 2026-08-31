// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';
import '../admin_widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin contract form — create or edit.
///
/// Feature audit module #11, Gap A: the original scaffold only ever collected name/customerId/
/// locationId/description/startDate/endDate/frequencyValue/frequencyUnit/price/notes. This now
/// covers the full field set web's `ContrattoCreateSheet.tsx`/`ContrattoEditSheet.tsx` expose —
/// numero, codice, tipo, externalId, autoRenewal, scadenzaGiorni, condizioni and a
/// prodottoAssistenzaId picker — through the same single create/edit screen rather than web's
/// split create-sheet/edit-sheet, matching this app's own established one-screen-for-both
/// convention (see `admin_prodotto_form_screen.dart`), not web's. Maintenance-template
/// pinning fields are deliberately not here — out of scope for this pass, matching the
/// Extension Fields precedent from an earlier module.
class AdminContractFormScreen extends ConsumerStatefulWidget {
  const AdminContractFormScreen({super.key, this.contract});

  final Map<String, dynamic>? contract;

  @override
  ConsumerState<AdminContractFormScreen> createState() => _AdminContractFormScreenState();
}

/// The three `ContractTipoEnum` values (`Contract.cs`), in the wire spelling the backend's
/// `JsonStringEnumConverter` both reads and writes — the same fixed set `ContrattoCreateSheet
/// .tsx`'s own `TIPO_OPTIONS` uses. No "custom" free-text option: the backend enum is closed.
const _tipoOptions = ['Manutenzione', 'Assistenza', 'Garanzia'];

class _AdminContractFormScreenState extends ConsumerState<AdminContractFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _numeroCtrl = TextEditingController();
  final _codiceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _scadenzaGiorniCtrl = TextEditingController();
  final _condizioniCtrl = TextEditingController();
  final _externalIdCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedCustomerId;
  String? _selectedLocationId;
  String? _selectedProdottoId;
  String? _selectedTipo;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  int _frequencyValue = 1;

  /// `ContractFrequencyUnit`'s own wire spelling — see [AdminApiClient.createContract]'s doc
  /// comment for why this is a string, not the ordinal int the form used to send.
  String _frequencyUnit = 'Months';
  bool _autoRenewal = false;
  bool _isSaving = false;

  // Prodotti in assistenza are fetched live, scoped to the selected customer — the same
  // "pick a related entity scoped by customer" shape admin_prodotto_form_screen.dart's own
  // Contratto picker uses, mirrored in reverse (that form picks a Contratto scoped by customer;
  // this one picks a ProdottoAssistenza scoped by customer).
  List<Map<String, dynamic>> _prodotti = [];
  bool _isLoadingProdotti = false;

  bool get _isEditing => widget.contract != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadContract();
    if (_selectedCustomerId != null) _loadProdotti(_selectedCustomerId!);
  }

  void _loadContract() {
    final c = widget.contract!;
    _nameCtrl.text = c['name'] as String? ?? '';
    _numeroCtrl.text = c['numero'] as String? ?? '';
    _codiceCtrl.text = c['codice'] as String? ?? '';
    _descriptionCtrl.text = c['description'] as String? ?? '';
    _priceCtrl.text = c['price'] != null ? (c['price'] as num).toStringAsFixed(2) : '';
    final scadenzaGiorni = c['scadenzaGiorni'];
    _scadenzaGiorniCtrl.text = scadenzaGiorni is num ? scadenzaGiorni.toStringAsFixed(0) : '';
    _condizioniCtrl.text = c['condizioni'] as String? ?? '';
    _externalIdCtrl.text = c['externalId'] as String? ?? '';
    _notesCtrl.text = c['notes'] as String? ?? '';
    _selectedCustomerId = c['customerId'] as String?;
    _selectedLocationId = c['locationId'] as String?;
    _selectedProdottoId = c['prodottoAssistenzaId'] as String?;
    final tipo = c['tipo'] as String?;
    _selectedTipo = _tipoOptions.contains(tipo) ? tipo : null;
    if (c['startDate'] != null) {
      _startDate = DateTime.parse(c['startDate'] as String);
    }
    if (c['endDate'] != null) {
      _endDate = DateTime.parse(c['endDate'] as String);
    }
    _frequencyValue = c['frequencyValue'] as int? ?? 1;
    // The backend serializes ContractFrequencyUnit as a STRING ("Days"/"Months"/"Years") — see
    // AdminApiClient.createContract's doc comment. Anything else (missing key, an unrecognized
    // value) falls back to the same "Months" default the form starts on for a new contract.
    final unit = c['frequencyUnit'] as String?;
    _frequencyUnit = unit == 'Days' || unit == 'Months' || unit == 'Years' ? unit! : 'Months';
    _autoRenewal = c['autoRenewal'] as bool? ?? false;
  }

  Future<void> _loadProdotti(String customerId) async {
    setState(() => _isLoadingProdotti = true);
    try {
      final prodotti = await ref
          .read(adminApiClientProvider)
          .fetchProdottiAssistenza(customerId: customerId);
      if (!mounted) return;
      setState(() {
        _prodotti = prodotti;
        _isLoadingProdotti = false;
      });
    } catch (_) {
      // Best-effort, offline or transient failure — prodotto picker just stays empty this
      // session, mirroring admin_prodotto_form_screen.dart's own `_loadContratti` convention.
      if (mounted) setState(() => _isLoadingProdotti = false);
    }
  }

  void _onCustomerChanged(String? customerId) {
    setState(() {
      _selectedCustomerId = customerId;
      _selectedProdottoId = null;
      _prodotti = [];
    });
    if (customerId != null) _loadProdotti(customerId);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _numeroCtrl.dispose();
    _codiceCtrl.dispose();
    _descriptionCtrl.dispose();
    _priceCtrl.dispose();
    _scadenzaGiorniCtrl.dispose();
    _condizioniCtrl.dispose();
    _externalIdCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 365)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      showAppToast(context, message: 'Seleziona un cliente', tone: ToastTone.warning);
      return;
    }
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);
      final price = double.tryParse(_priceCtrl.text.trim());
      final scadenzaGiorni = int.tryParse(_scadenzaGiorniCtrl.text.trim());

      if (_isEditing) {
        await api.updateContract(
          widget.contract!['id'] as String,
          name: _nameCtrl.text.trim(),
          customerId: _selectedCustomerId,
          startDate: _startDate,
          description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
          locationId: _selectedLocationId,
          prodottoAssistenzaId: _selectedProdottoId,
          endDate: _endDate,
          price: price,
          frequencyValue: _frequencyValue,
          frequencyUnit: _frequencyUnit,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          numero: _numeroCtrl.text.trim(),
          autoRenewal: _autoRenewal,
          scadenzaGiorni: scadenzaGiorni,
          // Bucket 1 (`if (request.Condizioni != null)`) — sent raw, including "", so it can be
          // cleared, matching ContrattoEditSheet.tsx's own treatment of the same field.
          condizioni: _condizioniCtrl.text.trim(),
          tipo: _selectedTipo,
          externalId: _externalIdCtrl.text.trim(),
          // Never "" — see AdminApiClient.updateContract's doc comment on the partial unique
          // index trap.
          codice: _codiceCtrl.text.trim().isEmpty ? null : _codiceCtrl.text.trim(),
        );
      } else {
        await api.createContract(
          name: _nameCtrl.text.trim(),
          customerId: _selectedCustomerId!,
          startDate: _startDate,
          description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
          locationId: _selectedLocationId,
          prodottoAssistenzaId: _selectedProdottoId,
          endDate: _endDate,
          price: price,
          frequencyValue: _frequencyValue,
          frequencyUnit: _frequencyUnit,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          numero: _numeroCtrl.text.trim().isEmpty ? null : _numeroCtrl.text.trim(),
          autoRenewal: _autoRenewal,
          scadenzaGiorni: scadenzaGiorni,
          condizioni: _condizioniCtrl.text.trim().isEmpty ? null : _condizioniCtrl.text.trim(),
          tipo: _selectedTipo,
          externalId: _externalIdCtrl.text.trim().isEmpty ? null : _externalIdCtrl.text.trim(),
          codice: _codiceCtrl.text.trim().isEmpty ? null : _codiceCtrl.text.trim(),
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        showAppToast(
          context,
          message: _isEditing ? 'Contratto aggiornato' : 'Contratto creato',
          tone: ToastTone.success,
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, message: 'Impossibile salvare. Riprova.', tone: ToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _frequencyUnitLabel(String unit) => switch (unit) {
    'Days' => 'Giorni',
    'Years' => 'Anni',
    _ => 'Mesi',
  };

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = locationsAsync.valueOrNull ?? [];

    final startLabel = DateFormat('dd/MM/yyyy').format(_startDate);
    final endLabel = _endDate != null
        ? DateFormat('dd/MM/yyyy').format(_endDate!)
        : 'Nessuna data fine';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica contratto' : 'Nuovo contratto',
        showBack: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            AppSpacing.pagePadding,
            context.navClearance,
          ),
          children: [
            AppTextField(
              label: 'Nome *',
              controller: _nameCtrl,
              validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Numero contratto',
                    hint: 'Es. CTR-2026-001',
                    controller: _numeroCtrl,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(label: 'Codice', controller: _codiceCtrl),
                ),
              ],
            ),
            const SizedBox(height: 16),

            AppFieldShell(
              label: 'Cliente *',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCustomerId,
                items: customers
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.companyName)))
                    .toList(),
                onChanged: _onCustomerChanged,
                validator: (v) => v == null ? 'Campo obbligatorio' : null,
              ),
            ),
            const SizedBox(height: 16),

            AppFieldShell(
              label: 'Sede',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedLocationId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nessuna sede')),
                  ...locations.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => setState(() => _selectedLocationId = v),
              ),
            ),
            const SizedBox(height: 16),

            AppFieldShell(
              label: 'Prodotto in assistenza',
              enabled: _selectedCustomerId != null,
              // If the prefilled prodottoAssistenzaId hasn't shown up in the live fetch yet
              // (still loading, or scoped to a customer the fetch hasn't resolved for), a bare
              // fallback item keeps `initialValue` matching exactly one item — same defensive
              // shape admin_prodotto_form_screen.dart's own Contratto picker uses.
              child: DropdownButtonFormField<String?>(
                initialValue: _selectedProdottoId,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nessun prodotto')),
                  if (_selectedProdottoId != null &&
                      !_prodotti.any((p) => p['id'] == _selectedProdottoId))
                    DropdownMenuItem<String?>(
                      value: _selectedProdottoId,
                      child: Text(_selectedProdottoId!),
                    ),
                  for (final p in _prodotti)
                    DropdownMenuItem<String?>(
                      value: p['id'] as String,
                      child: Text(p['name'] as String? ?? '—'),
                    ),
                ],
                onChanged: _selectedCustomerId == null
                    ? null
                    : (v) => setState(() => _selectedProdottoId = v),
                hint: Text(
                  _selectedCustomerId == null
                      ? 'Seleziona prima un cliente'
                      : _isLoadingProdotti
                      ? 'Caricamento…'
                      : 'Nessun prodotto',
                ),
              ),
            ),
            const SizedBox(height: 16),

            AppFieldShell(
              label: 'Tipo',
              // `Tipo` can never be cleared once set (`ContractTipoEnum?` is `.HasValue`-gated
              // server-side, same bucket as Sede/Prodotto) — no "nessuno" item is offered, the
              // same structural reason ContrattoEditSheet.tsx's own Tipo Select has none. A fresh
              // contract simply starts unset (null) and shows the placeholder hint below.
              child: DropdownButtonFormField<String?>(
                initialValue: _selectedTipo,
                items: [
                  for (final t in _tipoOptions) DropdownMenuItem<String?>(value: t, child: Text(t)),
                ],
                onChanged: (v) => setState(() => _selectedTipo = v),
                hint: const Text('Seleziona tipo'),
              ),
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Descrizione', controller: _descriptionCtrl, maxLines: 3),
            const SizedBox(height: 16),

            // ── Dates ────────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AdminDateField(
                    label: 'Data inizio *',
                    value: startLabel,
                    onTap: _pickStartDate,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AdminDateField(label: 'Data fine', value: endLabel, onTap: _pickEndDate),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Frequency ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Frequenza',
                    initialValue: _frequencyValue.toString(),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _frequencyValue = int.tryParse(v) ?? 1,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppFieldShell(
                    label: 'Unità',
                    child: DropdownButtonFormField<String>(
                      initialValue: _frequencyUnit,
                      items: ['Days', 'Months', 'Years']
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(_frequencyUnitLabel(u))),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _frequencyUnit = v ?? 'Months'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            AppTextField(
              label: 'Prezzo (€)',
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),

            AppTextField(
              label: 'Preavviso scadenza (giorni)',
              controller: _scadenzaGiorniCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            VetroCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.base,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Rinnovo automatico',
                      style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
                    ),
                  ),
                  AppToggle(
                    value: _autoRenewal,
                    onChanged: (v) => setState(() => _autoRenewal = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Condizioni', controller: _condizioniCtrl, maxLines: 3),
            const SizedBox(height: 16),

            AppTextField(
              label: 'ID esterno',
              hint: 'Identificativo del sistema legacy',
              controller: _externalIdCtrl,
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Note', controller: _notesCtrl, maxLines: 3),
            const SizedBox(height: 32),

            VetroButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea contratto',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }
}
