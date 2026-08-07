// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';

/// Admin location form — create or edit.
class AdminLocationFormScreen extends ConsumerStatefulWidget {
  const AdminLocationFormScreen({
    super.key,
    this.locationId,
    this.initialCustomerId,
  });

  final String? locationId;
  final String? initialCustomerId;

  @override
  ConsumerState<AdminLocationFormScreen> createState() =>
      _AdminLocationFormScreenState();
}

class _AdminLocationFormScreenState
    extends ConsumerState<AdminLocationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String? _selectedCustomerId;
  bool _isSaving = false;

  bool get _isEditing => widget.locationId != null;

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = widget.initialCustomerId;
    if (_isEditing) _loadLocation();
  }

  Future<void> _loadLocation() async {
    final db = ref.read(appDatabaseProvider);
    final loc = await (db.select(db.locations)
          ..where((l) => l.id.equals(widget.locationId!)))
        .getSingleOrNull();
    if (loc != null && mounted) {
      setState(() {
        _nameCtrl.text = loc.name;
        _addressCtrl.text = loc.address ?? '';
        _cityCtrl.text = loc.city ?? '';
        _postalCodeCtrl.text = loc.postalCode ?? '';
        _phoneCtrl.text = loc.phone ?? '';
        _notesCtrl.text = loc.notes ?? '';
        _selectedCustomerId = loc.customerId;
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postalCodeCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un cliente')),
      );
      return;
    }
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      if (_isEditing) {
        await api.updateLocation(
          widget.locationId!,
          customerId: _selectedCustomerId,
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
          phone: _phoneCtrl.text.trim().isEmpty
              ? null
              : _phoneCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      } else {
        await api.createLocation(
          customerId: _selectedCustomerId!,
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
          phone: _phoneCtrl.text.trim().isEmpty
              ? null
              : _phoneCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Sede aggiornata' : 'Sede creata',
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

    return Scaffold(
      backgroundColor: AppColors.BG2,
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica sede' : 'Nuova sede'),
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
            // ── Customer selector ─────────────────────────────────────────
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

            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome sede *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
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

            TextFormField(
              controller: _cityCtrl,
              decoration: const InputDecoration(
                labelText: 'Città',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _postalCodeCtrl,
              decoration: const InputDecoration(
                labelText: 'CAP',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Telefono',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

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
