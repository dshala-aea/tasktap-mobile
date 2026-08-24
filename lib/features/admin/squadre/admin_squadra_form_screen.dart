// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import '../../../core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin squadra form — create or edit.
class AdminSquadraFormScreen extends ConsumerStatefulWidget {
  const AdminSquadraFormScreen({super.key, this.squadra});

  final Map<String, dynamic>? squadra;

  @override
  ConsumerState<AdminSquadraFormScreen> createState() => _AdminSquadraFormScreenState();
}

class _AdminSquadraFormScreenState extends ConsumerState<AdminSquadraFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descrizioneCtrl = TextEditingController();
  final _specializzazioneCtrl = TextEditingController();
  final _coloreCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isSaving = false;
  // Backend forces IsActive=true on create (SquadreController.Create) — there is nothing to
  // toggle until the squadra exists, so this only matters (and is only shown) while editing.
  bool _isActive = true;

  bool get _isEditing => widget.squadra != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadSquadra();
  }

  void _loadSquadra() {
    final s = widget.squadra!;
    _nomeCtrl.text = s['nome'] as String? ?? '';
    _descrizioneCtrl.text = s['descrizione'] as String? ?? '';
    _specializzazioneCtrl.text = s['specializzazione'] as String? ?? '';
    _coloreCtrl.text = s['coloreCalendario'] as String? ?? '';
    _noteCtrl.text = s['note'] as String? ?? '';
    _isActive = s['isActive'] as bool? ?? true;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _descrizioneCtrl.dispose();
    _specializzazioneCtrl.dispose();
    _coloreCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      if (_isEditing) {
        await api.updateSquadra(
          widget.squadra!['id'] as String,
          nome: _nomeCtrl.text.trim(),
          descrizione: _descrizioneCtrl.text.trim().isEmpty ? null : _descrizioneCtrl.text.trim(),
          specializzazione: _specializzazioneCtrl.text.trim().isEmpty
              ? null
              : _specializzazioneCtrl.text.trim(),
          coloreCalendario: _coloreCtrl.text.trim().isEmpty ? null : _coloreCtrl.text.trim(),
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          isActive: _isActive,
        );
      } else {
        await api.createSquadra(
          nome: _nomeCtrl.text.trim(),
          descrizione: _descrizioneCtrl.text.trim().isEmpty ? null : _descrizioneCtrl.text.trim(),
          specializzazione: _specializzazioneCtrl.text.trim().isEmpty
              ? null
              : _specializzazioneCtrl.text.trim(),
          coloreCalendario: _coloreCtrl.text.trim().isEmpty ? null : _coloreCtrl.text.trim(),
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Squadra aggiornata' : 'Squadra creata'),
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
    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica squadra' : 'Nuova squadra',
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
            AppTextField(
              label: 'Nome *',
              controller: _nomeCtrl,
              validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Descrizione', controller: _descrizioneCtrl, maxLines: 3),
            const SizedBox(height: 16),

            AppTextField(label: 'Specializzazione', controller: _specializzazioneCtrl),
            const SizedBox(height: 16),

            AppTextField(
              label: 'Colore calendario (hex)',
              hint: '#FF5722',
              controller: _coloreCtrl,
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Note', controller: _noteCtrl, maxLines: 3),
            const SizedBox(height: 16),

            // Only shown while editing — a new squadra is always created active
            // (SquadreController.Create hardcodes IsActive=true), so there is nothing to toggle
            // yet. This is the only way to deactivate/reactivate a squadra from mobile.
            if (_isEditing)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isActive ? 'Squadra attiva' : 'Squadra disattivata',
                      style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
                    ),
                  ),
                  AppToggle(value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
                ],
              ),
            const SizedBox(height: 32),

            AppButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea squadra',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }
}
