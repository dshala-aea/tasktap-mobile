// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../admin_api_client.dart';

/// Admin squadra form — create or edit.
class AdminSquadraFormScreen extends ConsumerStatefulWidget {
  const AdminSquadraFormScreen({super.key, this.squadra});

  final Map<String, dynamic>? squadra;

  @override
  ConsumerState<AdminSquadraFormScreen> createState() =>
      _AdminSquadraFormScreenState();
}

class _AdminSquadraFormScreenState
    extends ConsumerState<AdminSquadraFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _descrizioneCtrl = TextEditingController();
  final _specializzazioneCtrl = TextEditingController();
  final _coloreCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isSaving = false;

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

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);

      if (_isEditing) {
        await api.updateSquadra(
          widget.squadra!['id'] as String,
          nome: _nomeCtrl.text.trim(),
          descrizione: _descrizioneCtrl.text.trim().isEmpty
              ? null
              : _descrizioneCtrl.text.trim(),
          specializzazione: _specializzazioneCtrl.text.trim().isEmpty
              ? null
              : _specializzazioneCtrl.text.trim(),
          coloreCalendario: _coloreCtrl.text.trim().isEmpty
              ? null
              : _coloreCtrl.text.trim(),
          note: _noteCtrl.text.trim().isEmpty
              ? null
              : _noteCtrl.text.trim(),
        );
      } else {
        await api.createSquadra(
          nome: _nomeCtrl.text.trim(),
          descrizione: _descrizioneCtrl.text.trim().isEmpty
              ? null
              : _descrizioneCtrl.text.trim(),
          specializzazione: _specializzazioneCtrl.text.trim().isEmpty
              ? null
              : _specializzazioneCtrl.text.trim(),
          coloreCalendario: _coloreCtrl.text.trim().isEmpty
              ? null
              : _coloreCtrl.text.trim(),
          note: _noteCtrl.text.trim().isEmpty
              ? null
              : _noteCtrl.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Squadra aggiornata' : 'Squadra creata',
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
    return Scaffold(
      backgroundColor: AppColors.BG2,
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica squadra' : 'Nuova squadra'),
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
              controller: _nomeCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _descrizioneCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _specializzazioneCtrl,
              decoration: const InputDecoration(
                labelText: 'Specializzazione',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _coloreCtrl,
              decoration: const InputDecoration(
                labelText: 'Colore calendario (hex)',
                border: OutlineInputBorder(),
                hintText: '#FF5722',
              ),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _noteCtrl,
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
