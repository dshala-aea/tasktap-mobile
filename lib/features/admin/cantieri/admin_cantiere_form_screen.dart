// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

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
  bool _isSaving = false;

  /// True once an edit-mode load has completed and found nothing in the
  /// local cache. `db.cantieri` is never populated by sync (see
  /// docs/api-gap-list.md), so this is the normal outcome for every
  /// cantiereId today — surfaced explicitly instead of silently leaving
  /// every field blank, which would let a save overwrite the real record
  /// with empty values.
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
          customerId: _selectedCustomerId,
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
          customerId: _selectedCustomerId,
        );
      }

      // Pull the new/updated row down immediately so the list shows it
      // without waiting for the next app-level sync.
      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Cantiere aggiornato' : 'Cantiere creato')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore: $e')));
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
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salva'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(19, 19, 19, context.navClearance),
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

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data inizio'),
              subtitle: Text(startLabel),
              trailing: const Icon(LucideIcons.calendar),
              onTap: _pickStartDate,
            ),
            const Divider(),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data fine'),
              subtitle: Text(endLabel),
              trailing: const Icon(LucideIcons.calendar),
              onTap: _pickEndDate,
            ),
            const Divider(),
            const SizedBox(height: 8),

            AppTextField(label: 'Note', controller: _notesCtrl, maxLines: 3),
          ],
        ),
      ),
    );
  }
}
