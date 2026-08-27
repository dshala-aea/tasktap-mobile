// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Single-step form for creating or editing a customer.
///
/// If [customerId] is null → create mode.
/// If [customerId] is provided → edit mode (pre-fills from Drift cache).
class AdminCustomerFormScreen extends ConsumerStatefulWidget {
  const AdminCustomerFormScreen({super.key, this.customerId});

  final String? customerId;

  bool get isEditMode => customerId != null;

  @override
  ConsumerState<AdminCustomerFormScreen> createState() => _AdminCustomerFormScreenState();
}

class _AdminCustomerFormScreenState extends ConsumerState<AdminCustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _companyNameCtrl;
  late final TextEditingController _taxIdCtrl;
  late final TextEditingController _contactPersonCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _postalCodeCtrl;
  late final TextEditingController _countryCtrl;
  late final TextEditingController _notesCtrl;
  bool _isActive = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _companyNameCtrl = TextEditingController();
    _taxIdCtrl = TextEditingController();
    _contactPersonCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _cityCtrl = TextEditingController();
    _postalCodeCtrl = TextEditingController();
    _countryCtrl = TextEditingController();
    _notesCtrl = TextEditingController();

    // In edit mode, pre-fill from Drift cache after first frame.
    if (widget.isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomer());
    }
  }

  Future<void> _loadCustomer() async {
    final db = ref.read(appDatabaseProvider);
    final customer = await (db.select(
      db.customers,
    )..where((c) => c.id.equals(widget.customerId!))).getSingleOrNull();
    if (customer == null || !mounted) return;
    _companyNameCtrl.text = customer.companyName;
    _taxIdCtrl.text = customer.taxId ?? '';
    _contactPersonCtrl.text = customer.contactPerson ?? '';
    _phoneCtrl.text = customer.phone ?? '';
    _emailCtrl.text = customer.email ?? '';
    _addressCtrl.text = customer.address ?? '';
    _cityCtrl.text = customer.city ?? '';
    _postalCodeCtrl.text = customer.postalCode ?? '';
    _countryCtrl.text = customer.country ?? '';
    _notesCtrl.text = customer.notes ?? '';
    setState(() => _isActive = customer.isActive);
  }

  @override
  void dispose() {
    _companyNameCtrl.dispose();
    _taxIdCtrl.dispose();
    _contactPersonCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _postalCodeCtrl.dispose();
    _countryCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (!_formKey.currentState!.validate() || _isSubmitting) return;
    if (!ensureOnlineOrWarn(context, ref)) return;
    setState(() => _isSubmitting = true);

    try {
      final client = ref.read(adminApiClientProvider);

      if (widget.isEditMode) {
        await client.updateCustomer(
          widget.customerId!,
          companyName: _companyNameCtrl.text.trim(),
          taxId: _taxIdCtrl.text.trim(),
          contactPerson: _contactPersonCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim(),
          country: _countryCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
          isActive: _isActive,
        );
      } else {
        await client.createCustomer(
          companyName: _companyNameCtrl.text.trim(),
          taxId: _taxIdCtrl.text.trim(),
          contactPerson: _contactPersonCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          address: _addressCtrl.text.trim(),
          city: _cityCtrl.text.trim(),
          postalCode: _postalCodeCtrl.text.trim(),
          country: _countryCtrl.text.trim(),
          notes: _notesCtrl.text.trim(),
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditMode ? 'Cliente aggiornato' : 'Cliente creato con successo'),
            backgroundColor: context.colors.green,
          ),
        );
        Navigator.of(context).pop(true);
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: widget.isEditMode ? 'Modifica cliente' : 'Nuovo cliente',
        showBack: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.pagePadding,
            AppSpacing.base,
            AppSpacing.pagePadding,
            context.navClearance,
          ),
          children: [
            // ── Required ───────────────────────────────────────────────────
            AppTextField(
              label: 'Ragione sociale *',
              hint: 'Es. Rossi S.r.l.',
              controller: _companyNameCtrl,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(label: 'P.IVA', controller: _taxIdCtrl),
            const SizedBox(height: 24),

            // ── Contact ────────────────────────────────────────────────────
            const StepLabel(title: 'Contatto'),
            const SizedBox(height: 12),
            AppTextField(label: 'Referente', controller: _contactPersonCtrl),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Telefono',
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Email',
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 24),

            // ── Address ────────────────────────────────────────────────────
            const StepLabel(title: 'Indirizzo'),
            const SizedBox(height: 12),
            AppTextField(label: 'Indirizzo', controller: _addressCtrl),
            const SizedBox(height: 16),
            AppTextField(label: 'Città', controller: _cityCtrl),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'CAP',
                    controller: _postalCodeCtrl,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppTextField(label: 'Paese', controller: _countryCtrl),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Notes ──────────────────────────────────────────────────────
            const StepLabel(title: 'Note'),
            const SizedBox(height: 12),
            AppTextField.multiline(label: 'Note', controller: _notesCtrl, maxLines: 4),
            const SizedBox(height: 24),

            // ── Stato (Gap 11) — edit mode only: `createCustomer` has no isActive param, every
            // new customer starts active server-side, so there is nothing to toggle at creation.
            if (widget.isEditMode) ...[
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
                        style: AppTextStyles.titleMedium.copyWith(color: context.colors.ink),
                      ),
                    ),
                    AppToggle(value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Submit ─────────────────────────────────────────────────────
            VetroButton(
              label: widget.isEditMode ? 'Salva modifiche' : 'Crea cliente',
              onPressed: _isSubmitting ? null : _onSubmit,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }
}
