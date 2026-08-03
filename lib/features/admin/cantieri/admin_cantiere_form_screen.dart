// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';

/// Admin cantiere form — create or edit.
class AdminCantiereFormScreen extends ConsumerStatefulWidget {
  const AdminCantiereFormScreen({super.key, this.cantiereId});

  final String? cantiereId;

  @override
  ConsumerState<AdminCantiereFormScreen> createState() =>
      _AdminCantiereFormScreenState();
}

class _AdminCantiereFormScreenState
    extends ConsumerState<AdminCantiereFormScreen> {
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
    final cantiere = await (db.select(db.cantieri)
          ..where((c) => c.id.equals(widget.cantiereId!)))
        .getSingleOrNull();
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

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      if (_isEditing) {
        await api.updateCantiere(
          widget.cantiereId!,
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim().isEmpty
              ? null
              : _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim().isEmpty
              ? null
              : _postalCodeCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
          customerId: _selectedCustomerId,
        );
      } else {
        await api.createCantiere(
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim().isEmpty
              ? null
              : _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim().isEmpty
              ? null
              : _postalCodeCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
          customerId: _selectedCustomerId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Cantiere aggiornato' : 'Cantiere creato',
            ),
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e')),
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
        backgroundColor: AppColors.BG2,
        appBar: AppBar(
          title: const Text('Modifica cantiere'),
          backgroundColor: AppColors.BG2,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: const UnavailableState(
          titolo: 'Cantiere non disponibile',
          motivo: "L'elenco cantieri non è ancora sincronizzato sul "
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
      backgroundColor: AppColors.BG2,
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica cantiere' : 'Nuovo cantiere'),
        backgroundColor: AppColors.BG2,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
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
          padding: const EdgeInsets.all(19),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _selectedCustomerId,
              decoration: const InputDecoration(
                labelText: 'Cliente',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Nessun cliente'),
                ),
                ...customers.map((c) => DropdownMenuItem(
                      value: c.id,
                      child: Text(c.companyName),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedCustomerId = v),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                labelText: 'Indirizzo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _cityCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Città',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _postalCodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'CAP',
                      border: OutlineInputBorder(),
                    ),
                  ),
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

            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
