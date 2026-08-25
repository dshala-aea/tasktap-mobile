// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_rack.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/magazzino/magazzino_api_client.dart';
import '../../magazzino/magazzino_providers.dart';
import '../../ticket/steps/step_assegnazione.dart' show techniciansProvider;
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin magazzino form — create or edit. Gap 2 of the feature audit.
///
/// Fields mirror `CreateMagazzinoRequest`/`UpdateMagazzinoRequest`
/// (`MagazzinoController.cs`): Nome, Tipo, AssegnatoUserId (Furgone only — see its doc comment on
/// `Magazzino.cs`: "For Furgone: the assigned technician's user ID"), Indirizzo, Note, and — edit
/// only — IsActive. There is deliberately no delete button: deactivation via `IsActive` is the
/// backend's own design for this entity (no DELETE route exists).
class AdminMagazzinoFormScreen extends ConsumerStatefulWidget {
  const AdminMagazzinoFormScreen({super.key, this.magazzino});

  /// Non-null when editing — carried as `extra` from the list/detail row.
  final MagazzinoDto? magazzino;

  @override
  ConsumerState<AdminMagazzinoFormScreen> createState() => _AdminMagazzinoFormScreenState();
}

class _AdminMagazzinoFormScreenState extends ConsumerState<AdminMagazzinoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _indirizzoCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late String _tipo;
  String? _assegnatoUserId;
  bool _isActive = true;
  bool _isSaving = false;

  bool get _isEditing => widget.magazzino != null;

  @override
  void initState() {
    super.initState();
    final mag = widget.magazzino;
    _tipo = mag?.tipo ?? 'Sede';
    _assegnatoUserId = mag?.assegnatoUserId;
    _isActive = mag?.isActive ?? true;
    if (mag != null) {
      _nomeCtrl.text = mag.nome;
      _indirizzoCtrl.text = mag.indirizzo ?? '';
      _noteCtrl.text = mag.note ?? '';
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _indirizzoCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final client = ref.read(magazzinoApiClientProvider);
      final assegnato = _tipo == 'Furgone' ? _assegnatoUserId : null;

      if (_isEditing) {
        await client.updateMagazzino(
          widget.magazzino!.id,
          nome: _nomeCtrl.text.trim(),
          // `MagazzinoController.Update` does `mag.AssegnatoUserId = request.AssegnatoUserId ??
          // mag.AssegnatoUserId` — unlike schedules' assignment fields, there is no sentinel this
          // endpoint recognises as "clear". Switching Furgone → Sede here cannot drop a
          // previously-assigned technician from the record; sending null just leaves it as-is
          // rather than corrupting it with a fabricated value.
          assegnatoUserId: assegnato,
          indirizzo: _indirizzoCtrl.text.trim().isEmpty ? null : _indirizzoCtrl.text.trim(),
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          isActive: _isActive,
        );
      } else {
        await client.createMagazzino(
          nome: _nomeCtrl.text.trim(),
          tipo: _tipo,
          assegnatoUserId: assegnato,
          indirizzo: _indirizzoCtrl.text.trim().isEmpty ? null : _indirizzoCtrl.text.trim(),
          note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        );
      }

      unawaited(ref.refresh(magazziniProvider.future));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Magazzino aggiornato' : 'Magazzino creato'),
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
    final techniciansAsync = ref.watch(techniciansProvider);
    final technicians = techniciansAsync.valueOrNull ?? const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica magazzino' : 'Nuovo magazzino',
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

            AppFieldShell(
              label: 'Tipo *',
              child: Row(
                children: [
                  Expanded(
                    child: _TipoChip(
                      label: 'Sede',
                      selected: _tipo == 'Sede',
                      onTap: () => setState(() => _tipo = 'Sede'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TipoChip(
                      label: 'Furgone',
                      selected: _tipo == 'Furgone',
                      onTap: () => setState(() => _tipo = 'Furgone'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Only meaningful for a Furgone — a Sede is not "assigned" to a technician.
            if (_tipo == 'Furgone') ...[
              AppFieldShell(
                label: 'Tecnico assegnato',
                child: DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use — controlled field, needs value not initialValue
                  value: technicians.any((t) => t['id'] == _assegnatoUserId)
                      ? _assegnatoUserId
                      : null,
                  decoration: const InputDecoration(isDense: true, hintText: 'Nessuno'),
                  isExpanded: true,
                  items: [
                    for (final t in technicians)
                      DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(t['displayName'] as String? ?? t['email'] as String? ?? ''),
                      ),
                  ],
                  onChanged: (v) => setState(() => _assegnatoUserId = v),
                ),
              ),
              const SizedBox(height: 16),
            ],

            AppTextField(label: 'Indirizzo', controller: _indirizzoCtrl),
            const SizedBox(height: 16),

            AppTextField(label: 'Note', controller: _noteCtrl, maxLines: 3),
            const SizedBox(height: 16),

            if (_isEditing)
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.base,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Attivo',
                        style: TextStyle(fontWeight: FontWeight.w600, color: context.colors.ink),
                      ),
                    ),
                    AppToggle(value: _isActive, onChanged: (v) => setState(() => _isActive = v)),
                  ],
                ),
              ),
            const SizedBox(height: 32),

            AppButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea magazzino',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
          ],
        ),
      ),
    );
  }
}

class _TipoChip extends StatelessWidget {
  const _TipoChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppChip(label: label, active: selected, onTap: onTap);
  }
}
