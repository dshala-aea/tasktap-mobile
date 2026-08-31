// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../../../presentation/providers/schedule_providers.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin location form — create or edit.
class AdminLocationFormScreen extends ConsumerStatefulWidget {
  const AdminLocationFormScreen({super.key, this.locationId, this.initialCustomerId});

  final String? locationId;
  final String? initialCustomerId;

  @override
  ConsumerState<AdminLocationFormScreen> createState() => _AdminLocationFormScreenState();
}

class _AdminLocationFormScreenState extends ConsumerState<AdminLocationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _latitudeCtrl = TextEditingController();
  final _longitudeCtrl = TextEditingController();
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
    final loc = await (db.select(
      db.locations,
    )..where((l) => l.id.equals(widget.locationId!))).getSingleOrNull();
    if (loc != null && mounted) {
      setState(() {
        _nameCtrl.text = loc.name;
        _addressCtrl.text = loc.address ?? '';
        _cityCtrl.text = loc.city ?? '';
        _postalCodeCtrl.text = loc.postalCode ?? '';
        _phoneCtrl.text = loc.phone ?? '';
        _notesCtrl.text = loc.notes ?? '';
        _latitudeCtrl.text = loc.latitude?.toString() ?? '';
        _longitudeCtrl.text = loc.longitude?.toString() ?? '';
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
    _latitudeCtrl.dispose();
    _longitudeCtrl.dispose();
    super.dispose();
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
      final latitude = double.tryParse(_latitudeCtrl.text.trim());
      final longitude = double.tryParse(_longitudeCtrl.text.trim());

      if (_isEditing) {
        await api.updateLocation(
          widget.locationId!,
          customerId: _selectedCustomerId,
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim().isEmpty ? null : _postalCodeCtrl.text.trim(),
          latitude: latitude,
          longitude: longitude,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      } else {
        await api.createLocation(
          customerId: _selectedCustomerId!,
          name: _nameCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim().isEmpty ? null : _postalCodeCtrl.text.trim(),
          latitude: latitude,
          longitude: longitude,
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        showAppToast(
          context,
          message: _isEditing ? 'Sede aggiornata' : 'Sede creata',
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
    final customersAsync = ref.watch(allCustomersProvider);
    final customers = customersAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica sede' : 'Nuova sede',
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
            // ── Customer selector ─────────────────────────────────────────
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

            AppTextField(
              label: 'Nome sede *',
              controller: _nameCtrl,
              validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Indirizzo', controller: _addressCtrl),
            const SizedBox(height: 16),

            AppTextField(label: 'Città', controller: _cityCtrl),
            const SizedBox(height: 16),

            AppTextField(label: 'CAP', controller: _postalCodeCtrl),
            const SizedBox(height: 16),

            AppTextField(label: 'Telefono', controller: _phoneCtrl),
            const SizedBox(height: 16),

            // Plain numeric fields — no map-picker widget exists anywhere in this app yet (web's
            // Sedi tab uses an inline map, but that is a net-new component this pass isn't
            // building). Both optional: a sede with no coordinates is common and not an error.
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Latitudine',
                    controller: _latitudeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(
                    label: 'Longitudine',
                    controller: _longitudeCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Note', controller: _notesCtrl, maxLines: 3),
            const SizedBox(height: 32),

            VetroButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea sede',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }
}
