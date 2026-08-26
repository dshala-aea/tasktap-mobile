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

import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';
import '../admin_widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin prodotto assistenza form — create or edit.
///
/// Feature audit module #10, Gaps 1/2/7: the original scaffold only ever sent name/customerId/
/// locationId/description/serialNumber/warrantyExpiryDate/notes. This form now covers the full
/// field set web's `ProdottoEditSheet.tsx` exposes (commercial + lifecycle + externalId), sent
/// through the same single create/edit screen rather than web's split create-sheet/edit-sheet —
/// matching this app's own established one-screen-for-both convention (see
/// `admin_materiale_form_screen.dart`), not web's.
class AdminProdottoFormScreen extends ConsumerStatefulWidget {
  const AdminProdottoFormScreen({super.key, this.prodotto});

  final Map<String, dynamic>? prodotto;

  @override
  ConsumerState<AdminProdottoFormScreen> createState() => _AdminProdottoFormScreenState();
}

class _AdminProdottoFormScreenState extends ConsumerState<AdminProdottoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _codiceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _serialNumberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _modelloCtrl = TextEditingController();
  final _tipoCtrl = TextEditingController();
  final _categoriaCtrl = TextEditingController();
  final _umCtrl = TextEditingController();
  final _prezzoAcquistoCtrl = TextEditingController();
  final _prezzoVenditaCtrl = TextEditingController();
  final _externalIdCtrl = TextEditingController();

  String? _selectedCustomerId;
  String? _selectedLocationId;
  String? _selectedContrattoId;
  DateTime? _warrantyExpiryDate;
  DateTime? _dataInstallazione;
  DateTime? _ultimaManutenzione;
  DateTime? _prossimaManutenzione;
  bool _isActive = true;
  bool _isSaving = false;

  // Contratti are fetched live, scoped to the selected customer — same pattern as
  // ProdottoEditSheet.tsx's `loadContractOptionsByCustomer`, and the same "no local Drift mirror"
  // shape this file already uses for customers/locations vs. commesse/squadre elsewhere in this
  // app. Re-fetched whenever the customer changes.
  List<Map<String, dynamic>> _contratti = [];
  bool _isLoadingContratti = false;

  bool get _isEditing => widget.prodotto != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadProdotto();
    if (_selectedCustomerId != null) _loadContratti(_selectedCustomerId!);
  }

  void _loadProdotto() {
    final p = widget.prodotto!;
    _nameCtrl.text = p['name'] as String? ?? '';
    _codiceCtrl.text = p['codice'] as String? ?? '';
    _descriptionCtrl.text = p['description'] as String? ?? '';
    _serialNumberCtrl.text = p['serialNumber'] as String? ?? '';
    _notesCtrl.text = p['notes'] as String? ?? '';
    _marcaCtrl.text = p['marchio'] as String? ?? '';
    _modelloCtrl.text = p['modello'] as String? ?? '';
    _tipoCtrl.text = p['tipo'] as String? ?? '';
    _categoriaCtrl.text = p['categoria'] as String? ?? '';
    _umCtrl.text = p['um'] as String? ?? '';
    final purchasePrice = p['prezzoAcquisto'];
    if (purchasePrice is num) _prezzoAcquistoCtrl.text = purchasePrice.toStringAsFixed(2);
    final salePrice = p['prezzoVendita'];
    if (salePrice is num) _prezzoVenditaCtrl.text = salePrice.toStringAsFixed(2);
    _externalIdCtrl.text = p['externalId'] as String? ?? '';
    _selectedCustomerId = p['customerId'] as String?;
    _selectedLocationId = p['locationId'] as String?;
    _selectedContrattoId = p['contrattoId'] as String?;
    _isActive = p['isActive'] as bool? ?? true;
    if (p['warrantyExpiryDate'] != null) {
      _warrantyExpiryDate = DateTime.tryParse(p['warrantyExpiryDate'] as String);
    }
    if (p['dataInstallazione'] != null) {
      _dataInstallazione = DateTime.tryParse(p['dataInstallazione'] as String);
    }
    if (p['ultimaManutenzione'] != null) {
      _ultimaManutenzione = DateTime.tryParse(p['ultimaManutenzione'] as String);
    }
    if (p['prossimaManutenzione'] != null) {
      _prossimaManutenzione = DateTime.tryParse(p['prossimaManutenzione'] as String);
    }
  }

  Future<void> _loadContratti(String customerId) async {
    setState(() => _isLoadingContratti = true);
    try {
      final contratti = await ref.read(adminApiClientProvider).fetchContracts(customerId: customerId);
      if (!mounted) return;
      setState(() {
        _contratti = contratti;
        _isLoadingContratti = false;
      });
    } catch (_) {
      // Best-effort, offline or transient failure — contratto picker just stays empty this
      // session, mirroring _loadDetail's convention in the materiale form.
      if (mounted) setState(() => _isLoadingContratti = false);
    }
  }

  void _onCustomerChanged(String? customerId) {
    setState(() {
      _selectedCustomerId = customerId;
      _selectedContrattoId = null;
      _contratti = [];
    });
    if (customerId != null) _loadContratti(customerId);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codiceCtrl.dispose();
    _descriptionCtrl.dispose();
    _serialNumberCtrl.dispose();
    _notesCtrl.dispose();
    _marcaCtrl.dispose();
    _modelloCtrl.dispose();
    _tipoCtrl.dispose();
    _categoriaCtrl.dispose();
    _umCtrl.dispose();
    _prezzoAcquistoCtrl.dispose();
    _prezzoVenditaCtrl.dispose();
    _externalIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime? current, ValueChanged<DateTime> onPicked) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) onPicked(picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleziona un cliente')));
      return;
    }
    if (_selectedLocationId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleziona una sede')));
      return;
    }
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);
      final purchasePrice = double.tryParse(_prezzoAcquistoCtrl.text.trim());
      final salePrice = double.tryParse(_prezzoVenditaCtrl.text.trim());

      if (_isEditing) {
        await api.updateProdottoAssistenza(
          widget.prodotto!['id'] as String,
          name: _nameCtrl.text.trim(),
          customerId: _selectedCustomerId,
          locationId: _selectedLocationId,
          description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
          serialNumber: _serialNumberCtrl.text.trim().isEmpty
              ? null
              : _serialNumberCtrl.text.trim(),
          warrantyExpiryDate: _warrantyExpiryDate,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          isActive: _isActive,
          code: _codiceCtrl.text.trim().isEmpty ? null : _codiceCtrl.text.trim(),
          category: _categoriaCtrl.text.trim().isEmpty ? null : _categoriaCtrl.text.trim(),
          unitOfMeasure: _umCtrl.text.trim().isEmpty ? null : _umCtrl.text.trim(),
          purchasePrice: purchasePrice,
          salePrice: salePrice,
          marca: _marcaCtrl.text.trim().isEmpty ? null : _marcaCtrl.text.trim(),
          modello: _modelloCtrl.text.trim().isEmpty ? null : _modelloCtrl.text.trim(),
          tipo: _tipoCtrl.text.trim().isEmpty ? null : _tipoCtrl.text.trim(),
          dataInstallazione: _dataInstallazione,
          ultimaManutenzione: _ultimaManutenzione,
          prossimaManutenzione: _prossimaManutenzione,
          contrattoId: _selectedContrattoId,
          externalId: _externalIdCtrl.text.trim().isEmpty ? null : _externalIdCtrl.text.trim(),
        );
      } else {
        await api.createProdottoAssistenza(
          name: _nameCtrl.text.trim(),
          customerId: _selectedCustomerId!,
          locationId: _selectedLocationId!,
          description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
          serialNumber: _serialNumberCtrl.text.trim().isEmpty
              ? null
              : _serialNumberCtrl.text.trim(),
          warrantyExpiryDate: _warrantyExpiryDate,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          code: _codiceCtrl.text.trim().isEmpty ? null : _codiceCtrl.text.trim(),
          category: _categoriaCtrl.text.trim().isEmpty ? null : _categoriaCtrl.text.trim(),
          unitOfMeasure: _umCtrl.text.trim().isEmpty ? null : _umCtrl.text.trim(),
          purchasePrice: purchasePrice,
          salePrice: salePrice,
          marca: _marcaCtrl.text.trim().isEmpty ? null : _marcaCtrl.text.trim(),
          modello: _modelloCtrl.text.trim().isEmpty ? null : _modelloCtrl.text.trim(),
          tipo: _tipoCtrl.text.trim().isEmpty ? null : _tipoCtrl.text.trim(),
          dataInstallazione: _dataInstallazione,
          ultimaManutenzione: _ultimaManutenzione,
          prossimaManutenzione: _prossimaManutenzione,
          contrattoId: _selectedContrattoId,
          externalId: _externalIdCtrl.text.trim().isEmpty ? null : _externalIdCtrl.text.trim(),
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Prodotto aggiornato' : 'Prodotto creato'),
            backgroundColor: context.colors.green,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile salvare. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = locationsAsync.valueOrNull ?? [];

    String dateLabel(DateTime? d) => d != null ? DateFormat('dd/MM/yyyy').format(d) : 'Seleziona data';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica prodotto' : 'Nuovo prodotto',
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

            AppTextField(label: 'Codice', hint: 'Es. PROD-001', controller: _codiceCtrl),
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
              label: 'Sede *',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedLocationId,
                items: locations
                    .map((l) => DropdownMenuItem(value: l.id, child: Text(l.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedLocationId = v),
                validator: (v) => v == null ? 'Campo obbligatorio' : null,
              ),
            ),
            const SizedBox(height: 16),

            AppFieldShell(
              label: 'Contratto',
              enabled: _selectedCustomerId != null,
              // If the prefilled contrattoId hasn't shown up in the live fetch yet (still
              // loading, or scoped to a customer the fetch hasn't resolved for), a bare fallback
              // item keeps `initialValue` matching exactly one item — same `missingCommessaId`
              // defensive shape admin_cantiere_form_screen.dart's own Commessa picker uses,
              // otherwise DropdownButtonFormField asserts.
              child: DropdownButtonFormField<String?>(
                initialValue: _selectedContrattoId,
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nessun contratto')),
                  if (_selectedContrattoId != null &&
                      !_contratti.any((c) => c['id'] == _selectedContrattoId))
                    DropdownMenuItem<String?>(
                      value: _selectedContrattoId,
                      child: Text(_selectedContrattoId!),
                    ),
                  for (final c in _contratti)
                    DropdownMenuItem<String?>(
                      value: c['id'] as String,
                      child: Text(c['name'] as String? ?? '—'),
                    ),
                ],
                onChanged: _selectedCustomerId == null
                    ? null
                    : (v) => setState(() => _selectedContrattoId = v),
                hint: Text(
                  _selectedCustomerId == null
                      ? 'Seleziona prima un cliente'
                      : _isLoadingContratti
                      ? 'Caricamento…'
                      : 'Nessun contratto',
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: AppTextField(label: 'Marca', controller: _marcaCtrl)),
                const SizedBox(width: 16),
                Expanded(child: AppTextField(label: 'Modello', controller: _modelloCtrl)),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: AppTextField(label: 'Categoria', controller: _categoriaCtrl)),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    label: 'Unità di misura',
                    hint: 'pz, kg, mt…',
                    controller: _umCtrl,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Prezzo acquisto (€)',
                    controller: _prezzoAcquistoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    label: 'Prezzo vendita (€)',
                    controller: _prezzoVenditaCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(child: AppTextField(label: 'Tipo', controller: _tipoCtrl)),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(label: 'Numero di serie', controller: _serialNumberCtrl),
                ),
              ],
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Descrizione', controller: _descriptionCtrl, maxLines: 3),
            const SizedBox(height: 16),

            AdminDateField(
              label: 'Scadenza garanzia',
              value: dateLabel(_warrantyExpiryDate),
              onTap: () => _pickDate(
                _warrantyExpiryDate,
                (d) => setState(() => _warrantyExpiryDate = d),
              ),
            ),
            const SizedBox(height: 16),

            AdminDateField(
              label: 'Data installazione',
              value: dateLabel(_dataInstallazione),
              onTap: () => _pickDate(
                _dataInstallazione,
                (d) => setState(() => _dataInstallazione = d),
              ),
            ),
            const SizedBox(height: 16),

            AdminDateField(
              label: 'Ultima manutenzione',
              value: dateLabel(_ultimaManutenzione),
              onTap: () => _pickDate(
                _ultimaManutenzione,
                (d) => setState(() => _ultimaManutenzione = d),
              ),
            ),
            const SizedBox(height: 16),

            AdminDateField(
              label: 'Prossima manutenzione',
              value: dateLabel(_prossimaManutenzione),
              onTap: () => _pickDate(
                _prossimaManutenzione,
                (d) => setState(() => _prossimaManutenzione = d),
              ),
            ),
            const SizedBox(height: 16),

            AppTextField(
              label: 'ID gestionale',
              hint: 'Identificativo del sistema legacy',
              controller: _externalIdCtrl,
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Note', controller: _notesCtrl, maxLines: 3),
            const SizedBox(height: 16),

            // ── Stato — edit mode only, mirrors admin_customer_form_screen.dart's own Gap 11
            // convention: `createProdottoAssistenza` has no isActive param, every new prodotto
            // starts active server-side, so there is nothing to toggle at creation.
            if (_isEditing) ...[
              VetroCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Attivo',
                        style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
                      ),
                    ),
                    AppToggle(value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            const SizedBox(height: 16),

            VetroButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea prodotto',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }
}
