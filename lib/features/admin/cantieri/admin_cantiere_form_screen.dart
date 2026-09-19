// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
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
///
/// Keyed by the selected client id (item 2 of the admin-form audit): refetches, server-filtered
/// via `fetchCommesse`'s own `customerId` param, whenever the client picker changes, instead of
/// showing every commessa across every customer.
final adminCommesseProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, customerId) {
      return ref.watch(adminApiClientProvider).fetchCommesse(customerId: customerId);
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
  // AppLookupField only reads initialText once, in initState (see its own doc comment on
  // didUpdateWidget) — the address fields loaded asynchronously in _loadCantiere (edit mode) land
  // after that first build, so this is bumped once the load completes to force a fresh instance
  // that picks the loaded value up. Same pattern step_materiali_fold.dart's own lookupFieldGeneration
  // uses for the same reason.
  int _indirizzoGeneration = 0;
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
        _indirizzoGeneration++;
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
    // Constrained to not precede the start date, once one is set — matches
    // admin_contract_form_screen.dart's own end-date picker, which already does this.
    final firstDate = _startDate ?? DateTime.now().subtract(const Duration(days: 365));
    final initialDate = _endDate != null && !_endDate!.isBefore(firstDate) ? _endDate! : firstDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
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
        showAppToast(
          context,
          message: _isEditing ? 'Cantiere aggiornato' : 'Cantiere creato',
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
    // Server-filtered by the selected client (item 2 of the admin-form audit) — refetches
    // whenever _selectedCustomerId changes, since adminCommesseProvider is keyed by it.
    final commesseAsync = ref.watch(adminCommesseProvider(_selectedCustomerId));
    final commesse = commesseAsync.valueOrNull ?? [];
    // If the cached value isn't in the fetched (client-scoped) list — e.g. it belongs to a
    // different client than the one currently selected, or is inactive — keep it selectable
    // rather than silently blanking the field on open, which would let an unrelated save clear a
    // real link.
    final commessaCodici = {
      for (final c in commesse) c['id'] as String: c['codice'] as String? ?? '',
    };
    final missingCommessaId =
        _selectedCommessaId != null && !commessaCodici.containsKey(_selectedCommessaId);

    // Existing sedi (Locations) for the selected client — offered as quick-fill suggestions for
    // the cantiere's own address fields (item 10 of the admin-form audit). A cantiere has no
    // Location FK — plain address/city/postalCode strings live directly on the Cantiere entity
    // (see Cantiere.cs) — so picking one here copies its address into these fields rather than
    // linking it, and typing something new (or nothing matching) just sets the address text
    // directly, same "type and it stands on its own" behavior AppLookupField uses everywhere else.
    final allLocationsAsync = ref.watch(allLocationsProvider);
    final allLocations = allLocationsAsync.valueOrNull ?? [];
    final clientLocations = _selectedCustomerId != null
        ? allLocations.where((l) => l.customerId == _selectedCustomerId).toList()
        : const <Location>[];

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

                // Searchable, same AppLookupField the ticket-creation flow's client/location step
                // (step_cliente_sede.dart) already uses — item 1 of the admin-form audit: a plain
                // dropdown doesn't scale once the client list is more than a handful of rows.
                AppLookupField(
                  key: ValueKey('cliente-$_selectedCustomerId'),
                  label: 'Cliente',
                  hint: 'Cerca cliente…',
                  items: [for (final c in customers) LookupItem(id: c.id, name: c.companyName)],
                  selectedId: _selectedCustomerId,
                  onSelected: (id) => setState(() {
                    _selectedCustomerId = id;
                    // Commesse (and the sede suggestions below) are scoped to the selected client
                    // — a previously-picked commessa from a different client no longer applies.
                    _selectedCommessaId = null;
                  }),
                  onFreeText: (text) {
                    if (text.isEmpty) {
                      setState(() {
                        _selectedCustomerId = null;
                        _selectedCommessaId = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                AppLookupField(
                  key: ValueKey('commessa-$_selectedCommessaId'),
                  label: 'Commessa',
                  hint: 'Cerca commessa…',
                  items: [
                    for (final c in commesse)
                      LookupItem(
                        id: c['id'] as String,
                        name: c['codice'] as String? ?? '',
                        subtitle: c['descrizione'] as String?,
                      ),
                    // Same "keep it selectable" reasoning as missingCommessaId above.
                    if (missingCommessaId)
                      LookupItem(id: _selectedCommessaId!, name: _selectedCommessaId!),
                  ],
                  selectedId: _selectedCommessaId,
                  emptyCacheHint: commesseAsync.isLoading
                      ? 'Commesse in caricamento…'
                      : 'Nessuna commessa trovata.',
                  onSelected: (id) => setState(() => _selectedCommessaId = id),
                  onFreeText: (text) {
                    if (text.isEmpty) setState(() => _selectedCommessaId = null);
                  },
                ),
                const SizedBox(height: 16),

                AppLookupField(
                  key: ValueKey('indirizzo-$_indirizzoGeneration'),
                  label: 'Indirizzo',
                  hint: _selectedCustomerId != null
                      ? 'Cerca una sede esistente o scrivi un nuovo indirizzo…'
                      : 'Scrivi un indirizzo (seleziona un cliente per cercare le sedi esistenti)',
                  initialText: _addressCtrl.text,
                  items: [
                    for (final l in clientLocations)
                      LookupItem(
                        id: l.id,
                        name: (l.address != null && l.address!.isNotEmpty) ? l.address! : l.name,
                        subtitle: l.city,
                      ),
                  ],
                  emptyCacheHint: _selectedCustomerId == null
                      ? null
                      : 'Nessuna sede esistente per questo cliente: scrivi per inserirne un nuovo indirizzo.',
                  // Picking a suggestion copies that sede's address into these fields — see the
                  // clientLocations doc comment above for why this isn't a real link.
                  onSelected: (id) {
                    final loc = clientLocations.where((l) => l.id == id).firstOrNull;
                    if (loc == null) return;
                    _addressCtrl.text = (loc.address != null && loc.address!.isNotEmpty)
                        ? loc.address!
                        : loc.name;
                    _cityCtrl.text = loc.city ?? '';
                    _postalCodeCtrl.text = loc.postalCode ?? '';
                  },
                  // A brand new address, typed rather than picked — stands on its own, same as
                  // every other AppLookupField in the app. Nothing to persist as a Location here:
                  // unlike a ticket's Sede (a real FK), the cantiere's address is just its own
                  // text fields.
                  onFreeText: (text) => _addressCtrl.text = text,
                ),
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

                // Tenant-configured custom fields (web-only admin config, see
                // ExtensionFieldsSection's own doc comment) — only once the cantiere actually
                // exists: PUT /extension-fields/cantiere/{id}/values needs a real id, which a
                // brand-new cantiere doesn't have until this screen's own "Crea cantiere" call
                // returns one.
                if (_isEditing)
                  ExtensionFieldsSection(entityType: 'cantiere', entityId: widget.cantiereId!),

                const SizedBox(height: 32),

                AppButton(
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
