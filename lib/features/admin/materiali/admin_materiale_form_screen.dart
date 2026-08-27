// dart format width=100
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin materiale form — create or edit.
class AdminMaterialeFormScreen extends ConsumerStatefulWidget {
  const AdminMaterialeFormScreen({super.key, this.materialeId});

  final String? materialeId;

  @override
  ConsumerState<AdminMaterialeFormScreen> createState() => _AdminMaterialeFormScreenState();
}

class _AdminMaterialeFormScreenState extends ConsumerState<AdminMaterialeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _unitOfMeasureCtrl = TextEditingController();
  final _categoryCtrl = TextEditingController();
  final _marcaCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  final _salePriceCtrl = TextEditingController();
  final _aliquotaIvaCtrl = TextEditingController();
  bool _isSaving = false;

  /// True once an edit-mode load has completed and found nothing in the
  /// local cache. `db.materiali` IS populated by sync (`sync_service.dart`
  /// mirrors it, and `magazzino_screen.dart`'s Articoli tab reads the same
  /// table) — this used to claim otherwise, citing a doc gap that was fixed.
  /// This flag is still worth surfacing explicitly, just for a narrower
  /// reason: a materialeId can legitimately be missing from the mirror (not
  /// yet synced, or created directly on the server moments ago) and a save
  /// on a blank-prefilled form would overwrite the real record with empty
  /// values, so we refuse to silently render one.
  bool _prefillFailed = false;

  // ── Barcodes + image (Gap 5) ────────────────────────────────────────────────
  // Neither is mirrored in Drift (no local table for either), so both are read live from
  // `GET /api/materiali/{id}` on open — best-effort: offline just leaves this section
  // unavailable for the session rather than blocking the base-field prefill above, which
  // already comes from Drift and works offline.
  List<Map<String, dynamic>> _barcodes = [];
  String? _imageContentUrl;
  bool _detailLoaded = false;
  bool _isUploadingImage = false;

  bool get _isEditing => widget.materialeId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadMateriale();
      _loadDetail();
    }
  }

  Future<void> _loadMateriale() async {
    final db = ref.read(appDatabaseProvider);
    final mat = await (db.select(
      db.materiali,
    )..where((m) => m.id.equals(widget.materialeId!))).getSingleOrNull();
    if (!mounted) return;
    if (mat != null) {
      setState(() {
        _codeCtrl.text = mat.code;
        _nameCtrl.text = mat.name;
        _descriptionCtrl.text = mat.description ?? '';
        _unitOfMeasureCtrl.text = mat.unitOfMeasure ?? '';
        _categoryCtrl.text = mat.category ?? '';
        _marcaCtrl.text = mat.marca ?? '';
        _purchasePriceCtrl.text = mat.purchasePrice?.toStringAsFixed(2) ?? '';
        _salePriceCtrl.text = mat.salePrice?.toStringAsFixed(2) ?? '';
      });
    } else {
      setState(() => _prefillFailed = true);
    }
  }

  Future<void> _loadDetail() async {
    try {
      final api = ref.read(adminApiClientProvider);
      final detail = await api.fetchMaterialeDetail(widget.materialeId!);
      if (!mounted || detail == null) return;
      final iva = detail['aliquotaIVA'];
      setState(() {
        if (iva is num) _aliquotaIvaCtrl.text = iva.toStringAsFixed(2);
        _barcodes = (detail['barcodes'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>();
        _imageContentUrl = detail['imageContentUrl'] as String?;
        _detailLoaded = true;
      });
    } catch (_) {
      // Offline or transient failure — barcode/image management just stays unavailable this
      // session. The rest of the form (Drift-backed) still works.
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
    _aliquotaIvaCtrl.dispose();
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
      final aliquotaIva = double.tryParse(_aliquotaIvaCtrl.text.trim());

      if (_isEditing) {
        await api.updateMateriale(
          widget.materialeId!,
          code: _codeCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
          unitOfMeasure: _unitOfMeasureCtrl.text.trim().isEmpty
              ? null
              : _unitOfMeasureCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
          marca: _marcaCtrl.text.trim().isEmpty ? null : _marcaCtrl.text.trim(),
          purchasePrice: purchasePrice,
          salePrice: salePrice,
          aliquotaIva: aliquotaIva,
        );
      } else {
        await api.createMateriale(
          code: _codeCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty ? null : _descriptionCtrl.text.trim(),
          unitOfMeasure: _unitOfMeasureCtrl.text.trim().isEmpty
              ? null
              : _unitOfMeasureCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty ? null : _categoryCtrl.text.trim(),
          marca: _marcaCtrl.text.trim().isEmpty ? null : _marcaCtrl.text.trim(),
          purchasePrice: purchasePrice,
          salePrice: salePrice,
          aliquotaIva: aliquotaIva,
        );
      }

      unawaited(ref.read(syncProvider.notifier).performSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? 'Materiale aggiornato' : 'Materiale creato'),
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

  // ── Barcodes ─────────────────────────────────────────────────────────────────

  void _showAddBarcodeDialog() {
    final barcodeCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    var isPrimary = _barcodes.isEmpty;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog.adaptive(
          title: const Text('Aggiungi barcode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppFieldShell(
                label: 'Barcode',
                child: TextField(controller: barcodeCtrl, autofocus: true),
              ),
              const SizedBox(height: 8),
              AppFieldShell(
                label: 'Tipo',
                child: TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(hintText: 'EAN13, Code128…'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Primario')),
                  AppToggle(
                    value: isPrimary,
                    onChanged: (v) => setDialogState(() => isPrimary = v),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
            ElevatedButton(
              onPressed: () async {
                final barcode = barcodeCtrl.text.trim();
                if (barcode.isEmpty) return;
                Navigator.pop(ctx);
                await _mutateBarcode(
                  () => ref
                      .read(adminApiClientProvider)
                      .addMaterialeBarcode(
                        widget.materialeId!,
                        barcode: barcode,
                        barcodeType: typeCtrl.text.trim().isEmpty ? null : typeCtrl.text.trim(),
                        isPrimary: isPrimary,
                      ),
                );
              },
              child: const Text('Aggiungi'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mutateBarcode(Future<void> Function() action) async {
    if (!ensureOnlineOrWarn(context, ref)) return;
    try {
      await action();
      await _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile aggiornare i barcode. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    }
  }

  // ── Image ────────────────────────────────────────────────────────────────────

  Future<void> _pickAndUploadImage(ImageSource source) async {
    if (!ensureOnlineOrWarn(context, ref)) return;
    final picker = ImagePicker();
    try {
      final xfile = await picker.pickImage(source: source, imageQuality: 85);
      if (xfile == null) return;
      final bytes = await File(xfile.path).readAsBytes();

      setState(() => _isUploadingImage = true);
      await ref
          .read(adminApiClientProvider)
          .uploadMaterialeImage(
            widget.materialeId!,
            bytes: bytes,
            fileName: xfile.name,
            contentType: 'image/jpeg',
          );
      unawaited(ref.read(syncProvider.notifier).performSync());
      await _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Immagine non caricata. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _deleteImage() async {
    if (!ensureOnlineOrWarn(context, ref)) return;
    setState(() => _isUploadingImage = true);
    try {
      await ref.read(adminApiClientProvider).deleteMaterialeImage(widget.materialeId!);
      unawaited(ref.read(syncProvider.notifier).performSync());
      await _loadDetail();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile rimuovere l\'immagine. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing && _prefillFailed) {
      return Scaffold(
        backgroundColor: context.colors.bg2,
        appBar: ScreenHeaderBar(title: 'Modifica materiale', showBack: true),
        body: const UnavailableState(
          titolo: 'Materiale non disponibile',
          motivo:
              'Il catalogo materiali non è ancora sincronizzato sul '
              'dispositivo, quindi non è possibile precompilare o '
              'modificare questo materiale da qui.',
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.bg2,
      appBar: ScreenHeaderBar(
        title: _isEditing ? 'Modifica materiale' : 'Nuovo materiale',
        showBack: true,
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                context.navClearance,
              ),
              children: [
            AppTextField(
              label: 'Codice *',
              controller: _codeCtrl,
              validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            AppTextField(
              label: 'Nome *',
              controller: _nameCtrl,
              validator: (v) => v == null || v.trim().isEmpty ? 'Campo obbligatorio' : null,
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Descrizione', controller: _descriptionCtrl, maxLines: 3),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Unità di misura',
                    hint: 'pz, kg, mt…',
                    controller: _unitOfMeasureCtrl,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(label: 'Marca', controller: _marcaCtrl),
                ),
              ],
            ),
            const SizedBox(height: 16),

            AppTextField(label: 'Categoria', controller: _categoryCtrl),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Prezzo acquisto (€)',
                    controller: _purchasePriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: AppTextField(
                    label: 'Prezzo vendita (€)',
                    controller: _salePriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            AppTextField(
              label: 'Aliquota IVA (%)',
              hint: 'Vuoto = aliquota di default del tenant',
              controller: _aliquotaIvaCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),

            if (_isEditing) ...[
              const SizedBox(height: 24),
              _ImageSection(
                imageUrl: _imageContentUrl,
                isBusy: _isUploadingImage,
                onPickGallery: () => _pickAndUploadImage(ImageSource.gallery),
                onPickCamera: () => _pickAndUploadImage(ImageSource.camera),
                onDelete: _deleteImage,
              ),
              const SizedBox(height: 24),
              _BarcodesSection(
                barcodes: _barcodes,
                loaded: _detailLoaded,
                onAdd: _showAddBarcodeDialog,
                onSetPrimary: (barcodeId) => _mutateBarcode(
                  () => ref
                      .read(adminApiClientProvider)
                      .setPrimaryMaterialeBarcode(widget.materialeId!, barcodeId),
                ),
                onDelete: (barcodeId) => _mutateBarcode(
                  () => ref
                      .read(adminApiClientProvider)
                      .deleteMaterialeBarcode(widget.materialeId!, barcodeId),
                ),
              ),
            ],
            const SizedBox(height: 32),

            VetroButton(
              label: _isEditing ? 'Salva modifiche' : 'Crea materiale',
              onPressed: _isSaving ? null : _save,
              isLoading: _isSaving,
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Image section ──────────────────────────────────────────────────────────────

class _ImageSection extends StatelessWidget {
  const _ImageSection({
    required this.imageUrl,
    required this.isBusy,
    required this.onPickGallery,
    required this.onPickCamera,
    required this.onDelete,
  });

  final String? imageUrl;
  final bool isBusy;
  final VoidCallback onPickGallery;
  final VoidCallback onPickCamera;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Immagine'),
        const SizedBox(height: 8),
        if (imageUrl != null)
          ClipRRect(
            borderRadius: AppRack.freeShape,
            child: Image.network(
              imageUrl!,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 160,
                color: context.colors.bg3,
                child: Center(
                  child: Icon(LucideIcons.imageOff, size: 32, color: context.colors.inkMuted),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onPickGallery,
                icon: const Icon(LucideIcons.image),
                label: Text(imageUrl == null ? 'Galleria' : 'Sostituisci'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onPickCamera,
                icon: const Icon(LucideIcons.camera),
                label: const Text('Fotocamera'),
              ),
            ),
            if (imageUrl != null) ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: isBusy ? null : onDelete,
                icon: Icon(LucideIcons.trash2, color: context.colors.red),
              ),
            ],
          ],
        ),
        if (isBusy)
          const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
      ],
    );
  }
}

// ── Barcodes section ─────────────────────────────────────────────────────────

class _BarcodesSection extends StatelessWidget {
  const _BarcodesSection({
    required this.barcodes,
    required this.loaded,
    required this.onAdd,
    required this.onSetPrimary,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> barcodes;
  final bool loaded;
  final ValueChanged<String> onSetPrimary;
  final ValueChanged<String> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Barcode'),
        const SizedBox(height: 8),
        if (!loaded)
          Text(
            'Barcode non disponibili offline.',
            style: TextStyle(color: context.colors.inkMuted, fontSize: 12),
          )
        else if (barcodes.isEmpty)
          Text('Nessun barcode.', style: TextStyle(color: context.colors.inkMuted, fontSize: 12))
        else
          VetroCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
            child: Column(
              children: [
                for (final b in barcodes)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      LucideIcons.fingerprint,
                      color: (b['isPrimary'] as bool? ?? false)
                          ? context.colors.amber
                          : context.colors.inkMuted,
                    ),
                    title: Text(b['barcode'] as String? ?? ''),
                    subtitle: Text(
                      [
                        if ((b['barcodeType'] as String?)?.isNotEmpty ?? false)
                          b['barcodeType'] as String,
                        if (b['isPrimary'] as bool? ?? false) 'Primario',
                      ].join(' · '),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!(b['isPrimary'] as bool? ?? false))
                          IconButton(
                            tooltip: 'Imposta come primario',
                            icon: const Icon(LucideIcons.checkCircle2, size: 18),
                            onPressed: () => onSetPrimary(b['id'] as String),
                          ),
                        IconButton(
                          icon: Icon(LucideIcons.trash2, size: 18, color: context.colors.red),
                          onPressed: () => onDelete(b['id'] as String),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(LucideIcons.plusSquare),
          label: const Text('Aggiungi barcode'),
        ),
      ],
    );
  }
}
