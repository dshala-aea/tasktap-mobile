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

/// Admin prodotto assistenza form — create or edit.
class AdminProdottoFormScreen extends ConsumerStatefulWidget {
  const AdminProdottoFormScreen({super.key, this.prodotto});

  final Map<String, dynamic>? prodotto;

  @override
  ConsumerState<AdminProdottoFormScreen> createState() => _AdminProdottoFormScreenState();
}

class _AdminProdottoFormScreenState extends ConsumerState<AdminProdottoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _serialNumberCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedCustomerId;
  String? _selectedLocationId;
  DateTime? _warrantyExpiryDate;
  bool _isSaving = false;

  bool get _isEditing => widget.prodotto != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadProdotto();
  }

  void _loadProdotto() {
    final p = widget.prodotto!;
    _nameCtrl.text = p['name'] as String? ?? '';
    _descriptionCtrl.text = p['description'] as String? ?? '';
    _serialNumberCtrl.text = p['serialNumber'] as String? ?? '';
    _notesCtrl.text = p['notes'] as String? ?? '';
    _selectedCustomerId = p['customerId'] as String?;
    _selectedLocationId = p['locationId'] as String?;
    if (p['warrantyExpiryDate'] != null) {
      _warrantyExpiryDate = DateTime.tryParse(p['warrantyExpiryDate'] as String);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _serialNumberCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickWarrantyDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _warrantyExpiryDate ?? DateTime.now().add(const Duration(days: 365)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
    );
    if (picked != null) setState(() => _warrantyExpiryDate = picked);
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
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Prodotto aggiornato' : 'Prodotto creato')),
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
    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = locationsAsync.valueOrNull ?? [];

    final warrantyLabel = _warrantyExpiryDate != null
        ? DateFormat('dd/MM/yyyy').format(_warrantyExpiryDate!)
        : 'Seleziona data';

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica prodotto' : 'Nuovo prodotto',
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
              label: 'Cliente *',
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCustomerId,
                items: customers
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.companyName)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedCustomerId = v),
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

            AppTextField(label: 'Descrizione', controller: _descriptionCtrl, maxLines: 3),
            const SizedBox(height: 16),

            AppTextField(label: 'Numero di serie', controller: _serialNumberCtrl),
            const SizedBox(height: 16),

            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Scadenza garanzia'),
              subtitle: Text(warrantyLabel),
              trailing: const Icon(LucideIcons.calendar),
              onTap: _pickWarrantyDate,
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
