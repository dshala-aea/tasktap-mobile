// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';
import '../admin_widgets.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Commesse for the form's picker — live fetch, no local Drift mirror (same as Squadre/
/// ProdottoAssistenza elsewhere in admin). Gap 5 of the feature audit: `Cantiere.CommessaId`
/// existed on the entity, but `CreateCantiereRequest`/`UpdateCantiereRequest` didn't accept it
/// until af9039c on the backend — this picker was left unbuilt until then.
final adminCommesseProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  return ref.watch(adminApiClientProvider).fetchCommesse();
});

/// Admin cantiere form — create or edit.
class AdminCantiereFormScreen extends ConsumerStatefulWidget {
  const AdminCantiereFormScreen({super.key, this.cantiereId});

  final String? cantiereId;

  @override
  ConsumerState<AdminCantiereFormScreen> createState() => _AdminCantiereFormScreenState();
}

class _AdminCantiereFormScreenState extends ConsumerState<AdminCantiereFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String? _selectedCustomerId;
  String? _selectedCommessaId;
  // CantiereStatusEnum (WorkEnums.cs): Active=0, Completed=1, Cancelled=2. New cantieri default to
  // Active; edits prefill from the cached row in _loadCantiere.
  int _status = 0;
  bool _isSaving = false;

  /// True once an edit-mode load has completed and found nothing in the
  /// local cache. `db.cantieri` IS populated by sync (`SyncService._upsertCantieri`) — this now
  /// only happens for a cantiere created on another device/surface that this device has not yet
  /// pulled down, or one deleted server-side since the last sync — surfaced explicitly instead of
  /// silently leaving every field blank, which would let a save overwrite the real record with
  /// empty values.
  bool _prefillFailed = false;

  bool get _isEditing => widget.cantiereId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadCantiere();
  }

  Future<void> _loadCantiere() async {
    final db = ref.read(appDatabaseProvider);
    final cantiere = await (db.select(
      db.cantieri,
    )..where((c) => c.id.equals(widget.cantiereId!))).getSingleOrNull();
    if (!mounted) return;
    if (cantiere != null) {
      setState(() {
        _nameCtrl.text = cantiere.name;
        _addressCtrl.text = cantiere.address ?? '';
        _cityCtrl.text = cantiere.city ?? '';
        _postalCodeCtrl.text = cantiere.postalCode ?? '';
        _notesCtrl.text = cantiere.notes ?? '';
        _startDate = cantiere.startDate;
        _endDate = cantiere.endDate;
        _selectedCustomerId = cantiere.customerId;
        _selectedCommessaId = cantiere.commessaId;
        _status = cantiere.status;
      });
    } else {
      setState(() => _prefillFailed = true);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postalCodeCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      if (_isEditing) {
        await api.updateCantiere(
          widget.cantiereId!,
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim().isEmpty ? null : _postalCodeCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
          status: _status,
          customerId: _selectedCustomerId,
          commessaId: _selectedCommessaId,
        );
      } else {
        await api.createCantiere(
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim().isEmpty ? null : _postalCodeCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
          status: _status,
          customerId: _selectedCustomerId,
          commessaId: _selectedCommessaId,
        );
      }

      // Pull the new/updated row down immediately so the list shows it
      // without waiting for the next app-level sync.
      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Cantiere aggiornato' : 'Cantiere creato'),
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
    if (_isEditing && _prefillFailed) {
      return Scaffold(
        backgroundColor: context.colors.bg2,
        appBar: ScreenHeaderBar(title: 'Modifica cantiere', showBack: true),
        body: const UnavailableState(
          titolo: 'Cantiere non disponibile',
          motivo:
              "L'elenco cantieri non è ancora sincronizzato sul "
              'dispositivo, quindi non è possibile precompilare o '
              'modificare questo cantiere da qui.',
        ),
      );
    }

    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];
    final commesseAsync = ref.watch(adminCommesseProvider);
    final commesse = commesseAsync.valueOrNull ?? [];
    // If the cached value isn't in the fetched (first-page) list — e.g. an inactive or
    // otherwise-filtered commessa — keep it selectable rather than silently blanking the field on
    // open, which would let an unrelated save clear a real link.
    final commessaCodici = {
      for (final c in commesse) c['id'] as String: c['codice'] as String? ?? '',
    };
    final missingCommessaId =
        _selectedCommessaId != null && !commessaCodici.containsKey(_selectedCommessaId);

    final startLabel = _startDate != null
        ? DateFormat('dd/MM/yyyy').format(_startDate!)
        : 'Seleziona data';
    final endLabel = _endDate != null
        ? DateFormat('dd/MM/yyyy').format(_endDate!)
        : 'Seleziona data';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica cantiere' : 'Nuovo cantiere',
        showBack: true,
      ),
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
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

                AppFieldShell(
                  label: 'Cliente',
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedCustomerId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Nessun cliente')),
                      ...customers.map(
                        (c) => DropdownMenuItem(value: c.id, child: Text(c.companyName)),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCustomerId = v),
                  ),
                ),
                const SizedBox(height: 16),

                AppFieldShell(
                  label: 'Commessa',
                  child: DropdownButtonFormField<String?>(
                    initialValue: _selectedCommessaId,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Nessuna commessa')),
                      if (missingCommessaId)
                        DropdownMenuItem(
                          value: _selectedCommessaId,
                          child: Text(_selectedCommessaId!),
                        ),
                      ...commesse.map((c) {
                        final codice = c['codice'] as String? ?? '';
                        final descrizione = c['descrizione'] as String?;
                        final label = descrizione != null && descrizione.isNotEmpty
                            ? '$codice ($descrizione)'
                            : codice;
                        return DropdownMenuItem(value: c['id'] as String, child: Text(label));
                      }),
                    ],
                    onChanged: (v) => setState(() => _selectedCommessaId = v),
                  ),
                ),
                const SizedBox(height: 16),

                AppTextField(label: 'Indirizzo', controller: _addressCtrl),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: AppTextField(label: 'Città', controller: _cityCtrl),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppTextField(label: 'CAP', controller: _postalCodeCtrl),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: AdminDateField(
                        label: 'Data inizio',
                        value: startLabel,
                        onTap: _pickStartDate,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AdminDateField(
                        label: 'Data fine',
                        value: endLabel,
                        onTap: _pickEndDate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                AppTextField(label: 'Note', controller: _notesCtrl, maxLines: 3),
                const SizedBox(height: 16),

                // CantiereStatusEnum (WorkEnums.cs): every cantiere created from mobile used to be
                // silently forced to Active (status: 0) with no way to pick anything else.
                AppFieldShell(
                  label: 'Stato',
                  child: DropdownButtonFormField<int>(
                    initialValue: _status,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Attivo')),
                      DropdownMenuItem(value: 1, child: Text('Completato')),
                      DropdownMenuItem(value: 2, child: Text('Annullato')),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 0),
                  ),
                ),
                const SizedBox(height: 32),

                VetroButton(
                  label: _isEditing ? 'Salva modifiche' : 'Crea cantiere',
                  onPressed: _isSaving ? null : _save,
                  isLoading: _isSaving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
