// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';

/// Admin materiale form — create or edit.
class AdminMaterialeFormScreen extends ConsumerStatefulWidget {
  const AdminMaterialeFormScreen({super.key, this.materialeId});

  final String? materialeId;

  @override
  ConsumerState<AdminMaterialeFormScreen> createState() =>
      _AdminMaterialeFormScreenState();
}

class _AdminMaterialeFormScreenState
    extends ConsumerState<AdminMaterialeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _unitOfMeasureCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController();
  bool _isSaving = false;

  /// True once an edit-mode load has completed and found nothing in the
  /// local cache. `db.materiali` is never populated by sync (see
  /// docs/api-gap-list.md), so this is the normal outcome for every
  /// materialeId today — surfaced explicitly instead of silently leaving
  /// every field blank, which would let a save overwrite the real record
  /// with empty values.
  bool _prefillFailed = false;

  bool get _isEditing => widget.materialeId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadMateriale();
  }

  Future<void> _loadMateriale() async {
    final db = ref.read(appDatabaseProvider);
    final mat = await (db.select(db.materiali)
          ..where((m) => m.id.equals(widget.materialeId!)))
        .getSingleOrNull();
    if (!mounted) return;
    if (mat != null) {
      setState(() {
        _codeCtrl.text = mat.code;
        _nameCtrl.text = mat.name;
        _descriptionCtrl.text = mat.description ?? '';
        _unitOfMeasureCtrl.text = mat.unitOfMeasure ?? '';
        _categoryCtrl.text = mat.category ?? '';
        _marcaCtrl.text = mat.marca ?? '';
        _purchasePriceCtrl.text =
            mat.purchasePrice?.toStringAsFixed(2) ?? '';
        _salePriceCtrl.text = mat.salePrice?.toStringAsFixed(2) ?? '';
      });
    } else {
      setState(() => _prefillFailed = true);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _unitOfMeasureCtrl.dispose();
    _categoryCtrl.dispose();
    _marcaCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _salePriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!ensureOnlineOrWarn(context, ref)) return;

    setState(() => _isSaving = true);
    try {
      final api = ref.read(adminApiClientProvider);
      final purchasePrice = double.tryParse(_purchasePriceCtrl.text.trim());
      final salePrice = double.tryParse(_salePriceCtrl.text.trim());

      if (_isEditing) {
        await api.updateMateriale(
          widget.materialeId!,
          code: _codeCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          unitOfMeasure: _unitOfMeasureCtrl.text.trim().isEmpty
              ? null
              : _unitOfMeasureCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty
              ? null
              : _categoryCtrl.text.trim(),
          marca: _marcaCtrl.text.trim().isEmpty
              ? null
              : _marcaCtrl.text.trim(),
          purchasePrice: purchasePrice,
          salePrice: salePrice,
        );
      } else {
        await api.createMateriale(
          code: _codeCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          unitOfMeasure: _unitOfMeasureCtrl.text.trim().isEmpty
              ? null
              : _unitOfMeasureCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty
              ? null
              : _categoryCtrl.text.trim(),
          marca: _marcaCtrl.text.trim().isEmpty
              ? null
              : _marcaCtrl.text.trim(),
          purchasePrice: purchasePrice,
          salePrice: salePrice,
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? 'Materiale aggiornato' : 'Materiale creato',
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
          title: const Text('Modifica materiale'),
          backgroundColor: AppColors.BG2,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: const UnavailableState(
          titolo: 'Materiale non disponibile',
          motivo: 'Il catalogo materiali non è ancora sincronizzato sul '
              'dispositivo, quindi non è possibile precompilare o '
              'modificare questo materiale da qui.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.BG2,
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica materiale' : 'Nuovo materiale'),
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
              controller: _codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Codice *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

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

            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                labelText: 'Descrizione',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _unitOfMeasureCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Unità di misura',
                      border: OutlineInputBorder(),
                      hintText: 'pz, kg, mt…',
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _marcaCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Marca',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _categoryCtrl,
              decoration: const InputDecoration(
                labelText: 'Categoria',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _purchasePriceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prezzo acquisto (€)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _salePriceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Prezzo vendita (€)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
