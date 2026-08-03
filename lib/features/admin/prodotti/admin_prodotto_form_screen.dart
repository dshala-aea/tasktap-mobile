// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';

/// Admin prodotto assistenza form — create or edit.
class AdminProdottoFormScreen extends ConsumerStatefulWidget {
  const AdminProdottoFormScreen({super.key, this.prodotto});

  final Map<String, dynamic>? prodotto;

  @override
  ConsumerState<AdminProdottoFormScreen> createState() =>
      _AdminProdottoFormScreenState();
}

class _AdminProdottoFormScreenState
    extends ConsumerState<AdminProdottoFormScreen> {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un cliente')),
      );
      return;
    }
    if (_selectedLocationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona una sede')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      if (_isEditing) {
        await api.updateProdottoAssistenza(
          widget.prodotto!['id'] as String,
          name: _nameCtrl.text.trim(),
          customerId: _selectedCustomerId,
          locationId: _selectedLocationId,
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          serialNumber: _serialNumberCtrl.text.trim().isEmpty
              ? null
              : _serialNumberCtrl.text.trim(),
          warrantyExpiryDate: _warrantyExpiryDate,
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      } else {
        await api.createProdottoAssistenza(
          name: _nameCtrl.text.trim(),
          customerId: _selectedCustomerId!,
          locationId: _selectedLocationId!,
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          serialNumber: _serialNumberCtrl.text.trim().isEmpty
              ? null
              : _serialNumberCtrl.text.trim(),
          warrantyExpiryDate: _warrantyExpiryDate,
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Prodotto aggiornato' : 'Prodotto creato',
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
    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];
    final locationsAsync = ref.watch(allLocationsProvider);
    final locations = locationsAsync.valueOrNull ?? [];

    final warrantyLabel = _warrantyExpiryDate != null
        ? DateFormat('dd/MM/yyyy').format(_warrantyExpiryDate!)
        : 'Seleziona data';

    return Scaffold(
      backgroundColor: AppColors.BG2,
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica prodotto' : 'Nuovo prodotto'),
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
                labelText: 'Cliente *',
                border: OutlineInputBorder(),
              ),
              items: customers
                  .map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.companyName),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedCustomerId = v),
              validator: (v) => v == null ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            DropdownButtonFormField<String>(
              initialValue: _selectedLocationId,
              decoration: const InputDecoration(
                labelText: 'Sede *',
                border: OutlineInputBorder(),
              ),
              items: locations
                  .map((l) => DropdownMenuItem(
                        value: l.id,
                        child: Text(l.name),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _selectedLocationId = v),
              validator: (v) => v == null ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _serialNumberCtrl,
              decoration: const InputDecoration(
                labelText: 'Numero di serie',
                border: OutlineInputBorder(),
              ),
            ),
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
