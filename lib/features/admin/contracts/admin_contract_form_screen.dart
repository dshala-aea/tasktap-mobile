// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';

/// Admin contract form — create or edit.
class AdminContractFormScreen extends ConsumerStatefulWidget {
  const AdminContractFormScreen({super.key, this.contract});

  final Map<String, dynamic>? contract;

  @override
  ConsumerState<AdminContractFormScreen> createState() => _AdminContractFormScreenState();
}

class _AdminContractFormScreenState extends ConsumerState<AdminContractFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedCustomerId;
  String? _selectedLocationId;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  int _frequencyValue = 1;
  int _frequencyUnit = 1;
  bool _isSaving = false;

  bool get _isEditing => widget.contract != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadContract();
  }

  void _loadContract() {
    final c = widget.contract!;
    _nameCtrl.text = c['name'] as String? ?? '';
    _descriptionCtrl.text = c['description'] as String? ?? '';
    _priceCtrl.text = c['price'] != null ? (c['price'] as num).toStringAsFixed(2) : '';
    _notesCtrl.text = c['notes'] as String? ?? '';
    _selectedCustomerId = c['customerId'] as String?;
    _selectedLocationId = c['locationId'] as String?;
    if (c['startDate'] != null) {
      _startDate = DateTime.parse(c['startDate'] as String);
    }
    if (c['endDate'] != null) {
      _endDate = DateTime.parse(c['endDate'] as String);
    }
    _frequencyValue = c['frequencyValue'] as int? ?? 1;
    _frequencyUnit = c['frequencyUnit'] as int? ?? 1;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _priceCtrl.dispose();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Seleziona un cliente')));
      return;
    }
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);
      final price = double.tryParse(_priceCtrl.text.trim());

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
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Contratto aggiornato' : 'Contratto creato')),
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

  String _frequencyUnitLabel(int unit) => switch (unit) {
    0 => 'Giorni',
    1 => 'Mesi',
    2 => 'Anni',
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
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _selectedCustomerId,
              decoration: const InputDecoration(labelText: 'Cliente *'),
              items: customers
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.companyName)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCustomerId = v),
              validator: (v) => v == null ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _selectedLocationId,
              decoration: const InputDecoration(labelText: 'Sede'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Nessuna sede')),
                ...locations.map((l) => DropdownMenuItem(value: l.id, child: Text(l.name))),
              ],
              onChanged: (v) => setState(() => _selectedLocationId = v),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(labelText: 'Descrizione'),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // ── Dates ────────────────────────────────────────────────────
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data inizio *'),
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

            // ── Frequency ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: _frequencyValue.toString(),
                    decoration: const InputDecoration(labelText: 'Frequenza'),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _frequencyValue = int.tryParse(v) ?? 1,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _frequencyUnit,
                    decoration: const InputDecoration(labelText: 'Unità'),
                    items: [0, 1, 2]
                        .map((u) => DropdownMenuItem(value: u, child: Text(_frequencyUnitLabel(u))))
                        .toList(),
                    onChanged: (v) => setState(() => _frequencyUnit = v ?? 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _priceCtrl,
              decoration: const InputDecoration(labelText: 'Prezzo (€)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'Note'),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }
}
