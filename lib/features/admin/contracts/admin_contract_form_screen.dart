// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../../clienti/clienti_providers.dart';
import '../admin_api_client.dart';
import '../admin_widgets.dart';
import 'prodotto_multi_picker_sheet.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin contract form — create or edit.
///
/// Feature audit module #11, Gap A: the original scaffold only ever collected name/customerId/
/// locationId/description/startDate/endDate/frequencyValue/frequencyUnit/price/notes. This now
/// covers the full field set web's `ContrattoCreateSheet.tsx`/`ContrattoEditSheet.tsx` expose —
/// numero, codice, tipo, externalId, autoRenewal, scadenzaGiorni, condizioni — through the same
/// single create/edit screen rather than web's split create-sheet/edit-sheet, matching this
/// app's own established one-screen-for-both convention (see `admin_prodotto_form_screen.dart`),
/// not web's. Maintenance-template
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
  String? _selectedTipo;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  int _frequencyValue = 1;

  /// Assets this contract covers. Always resent in full on save (never omitted) — see
  /// [_save]'s own comment.
  List<String> _selectedProdottoIds = [];
  List<Map<String, dynamic>> _prodotti = [];
  bool _isLoadingProdotti = false;

  /// `ContractFrequencyUnit`'s own wire spelling — see [AdminApiClient.createContract]'s doc
  /// comment for why this is a string, not the ordinal int the form used to send.
  String _frequencyUnit = 'Months';
  bool _autoRenewal = false;
  bool _isSaving = false;

  bool get _isEditing => widget.contract != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadContract();
      unawaited(_refreshContractAssetIds());
    }
    if (_selectedCustomerId != null) {
      unawaited(_loadProdottiForCustomer(_selectedCustomerId));
    }
  }

  /// `widget.contract` is whatever the list screen last fetched (`extra`-passed on navigation),
  /// which never carries `prodottoAssistenzaIds` — only `ContractsController.GetById`
  /// ([AdminApiClient.fetchContractById]) populates it. Best-effort: if this fails, the picker
  /// just starts empty rather than blocking the form.
  Future<void> _refreshContractAssetIds() async {
    try {
      final api = ref.read(adminApiClientProvider);
      final fresh = await api.fetchContractById(widget.contract!['id'] as String);
      final ids = (fresh?['prodottoAssistenzaIds'] as List<dynamic>?)?.cast<String>() ?? [];
      if (mounted) setState(() => _selectedProdottoIds = ids);
    } catch (_) {
      // Best-effort, see doc comment above.
    }
  }

  /// Assets are scoped to a customer (same reasoning as Sede) — reloads the candidate list
  /// whenever the customer changes. Does NOT touch `_selectedProdottoIds` itself: the initial
  /// edit-mode load calls this directly (leaving the ids [_refreshContractAssetIds] just set
  /// alone), while a genuine user-driven customer change goes through [_onCustomerChanged],
  /// which clears them first.
  Future<void> _loadProdottiForCustomer(String? customerId) async {
    if (customerId == null) {
      setState(() => _prodotti = []);
      return;
    }
    setState(() => _isLoadingProdotti = true);
    try {
      final api = ref.read(adminApiClientProvider);
      final items = await api.fetchProdottiAssistenza(customerId: customerId);
      if (mounted) setState(() => _prodotti = items);
    } finally {
      if (mounted) setState(() => _isLoadingProdotti = false);
    }
  }

  Future<void> _openAssetPicker() async {
    final result = await openProdottoMultiPickerSheet(
      context,
      prodotti: _prodotti,
      initialIds: _selectedProdottoIds,
    );
    if (result != null) setState(() => _selectedProdottoIds = result);
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

  void _onCustomerChanged(String? customerId) {
    setState(() {
      _selectedCustomerId = customerId;
      // A sede belongs to exactly one customer: a switch must not leave the previous customer's
      // location selected. Left in place it either files the contract against a sede the server
      // rejects (cross-customer), or silently keeps a sede no longer offered by the scoped picker.
      _selectedLocationId = null;
      // Covered assets belong to a customer too — a switch must not leave a cross-customer
      // selection behind, same reasoning as Sede.
      _selectedProdottoIds = [];
    });
    unawaited(_loadProdottiForCustomer(customerId));
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
          // Always resent as the current full selection, never omitted — a non-null list is a
          // full replace server-side, and the picker always holds a real (possibly empty) list.
          prodottoAssistenzaIds: _selectedProdottoIds,
        );
      } else {
        await api.createContract(
          name: _nameCtrl.text.trim(),
          customerId: _selectedCustomerId!,
          startDate: _startDate,
          description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
          locationId: _selectedLocationId,
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
          prodottoAssistenzaIds: _selectedProdottoIds,
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
    // Sedi are scoped to the selected customer, never the whole tenant book.
    //
    // `allLocationsProvider` (every active location in the tenant) was the defect: it fed the
    // picker locations belonging to *other* customers, and — because branch names repeat across a
    // tenant ("Sede", "Magazzino", "Milano") — rendered the same label several times over. Those
    // are distinct rows sharing a name, not duplicate rows: the Drift mirror is keyed by `id`
    // (`Locations.primaryKey = {id}`) and synced via `insertOnConflictUpdate`, so it cannot hold
    // two rows for one location. The fix is scoping, not de-duplication.
    //
    // Scoping reads the customer→location relation already on the device
    // (`locationsForCustomerProvider`, the same one the customer detail screen's Sedi section
    // uses) rather than a server query. The API does expose a customer filter
    // (`GET /api/Locations?customerId=`), but the mirror is the form's source of truth for its
    // reference fields and keeps it offline-capable; a live fetch here would blank the Sede field
    // on an existing contract opened without signal. Limitation, stated rather than hidden: the
    // mirror is refreshed on sync, so a sede another user creates on the web after this device's
    // last sync will not appear until the next one — the same bound the Cliente field already has.
    final locationsAsync = _selectedCustomerId == null
        ? null
        : ref.watch(locationsForCustomerProvider(_selectedCustomerId!));
    final locations = locationsAsync?.valueOrNull ?? const [];
    // A chosen sede absent from the scoped list (customer just switched, or the location is
    // inactive/not yet synced) must not be handed to the dropdown as its value — Flutter asserts
    // when `initialValue` is not among `items`. [_onCustomerChanged] sets the field to null on a
    // switch; this guard covers the inactive/unsynced case.
    final selectedLocationId =
        _selectedLocationId != null && locations.any((l) => l.id == _selectedLocationId)
        ? _selectedLocationId
        : null;

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
                // Rekeyed by customer so a customer switch rebuilds the field. `FormField` keeps its
                // own value across rebuilds, so merely setting [_selectedLocationId] to null in
                // [_onCustomerChanged] would leave the previous customer's sede on screen — the
                // widget has to be recreated for the cleared `initialValue` to take. Same reasoning
                // as `step_cliente_sede.dart`'s own `ValueKey('sede-...')`.
                key: ValueKey('sede-$_selectedCustomerId'),
                initialValue: selectedLocationId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('Nessuna sede')),
                  ...locations.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))),
                ],
                onChanged: (v) => setState(() => _selectedLocationId = v),
              ),
            ),
            const SizedBox(height: 16),

            AdminDateField(
              label: 'Asset coperti',
              value: _isLoadingProdotti
                  ? 'Caricamento…'
                  : _selectedProdottoIds.isEmpty
                  ? 'Nessun asset selezionato'
                  : '${_selectedProdottoIds.length} asset selezionati',
              onTap: _selectedCustomerId == null ? () {} : _openAssetPicker,
              icon: LucideIcons.package,
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

            AppCard(
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

            AppButton(
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
