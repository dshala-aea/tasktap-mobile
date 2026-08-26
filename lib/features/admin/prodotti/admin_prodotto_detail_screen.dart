// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/error_message.dart';
import '../../../core/widgets/vetro_button.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Admin prodotto assistenza detail — read-only with edit FAB.
///
/// Feature audit module #10: gaps 3/4/5/7 land here — commercial + lifecycle fields now shown
/// (gap 4), a delete action behind a confirm dialog (gap 5), externalId (gap 7), and the
/// Matricole sub-resource section (gap 3, see [_MatricoleSection] below).
class AdminProdottoDetailScreen extends ConsumerWidget {
  const AdminProdottoDetailScreen({super.key, required this.prodotto});

  final Map<String, dynamic> prodotto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = prodotto['id'] as String? ?? '';
    final name = prodotto['name'] as String? ?? '';
    final codice = prodotto['codice'] as String? ?? '';
    final description = prodotto['description'] as String? ?? '';
    final serialNumber = prodotto['serialNumber'] as String? ?? '';
    final notes = prodotto['notes'] as String? ?? '';
    final marca = prodotto['marchio'] as String? ?? '';
    final modello = prodotto['modello'] as String? ?? '';
    final tipo = prodotto['tipo'] as String? ?? '';
    final categoria = prodotto['categoria'] as String? ?? '';
    final um = prodotto['um'] as String? ?? '';
    final externalId = prodotto['externalId'] as String? ?? '';
    final contrattoId = prodotto['contrattoId'] as String?;

    String dateLabel(String? key) {
      final raw = prodotto[key] as String?;
      return raw != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(raw)) : '—';
    }

    // The one field a technician actually needs to act on immediately — highlighted, matching
    // the Vetro mockup's own call: "Overdue maintenance highlighted in red".
    bool isOverdue(String? key) {
      final raw = prodotto[key] as String?;
      if (raw == null) return false;
      return DateTime.parse(raw).isBefore(DateTime.now());
    }

    final isActive = prodotto['isActive'] as bool? ?? true;

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/prodotti/${prodotto['id']}/modifica', extra: prodotto);
          },
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ScreenHeader(
              title: name,
              subtitle: [
                if (codice.isNotEmpty) codice,
                if (serialNumber.isNotEmpty) 'S/N: $serialNumber',
              ].join(' · '),
              showBack: true,
              actions: id.isEmpty
                  ? const []
                  : [
                      HeaderIconBtn(
                        icon: LucideIcons.trash2,
                        label: 'Elimina prodotto',
                        glass: true,
                        onTap: () => _deleteProdotto(context, ref, id, name),
                      ),
                    ],
            ),
          ),
          // ── Stato ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                AppSpacing.pagePadding,
                0,
              ),
              child: StatusPill(stato: isActive ? 'Attivo' : 'Inattivo', outlined: true),
            ),
          ),

          // ── Dati tecnici — commercial fields (prezzo acquisto/vendita) deliberately left off
          // this view, matching the Vetro mockup's own call; still editable from the form.
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: VetroCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Dati tecnici'),
                    const SizedBox(height: 4),
                    KeyVal(label: 'Nome', value: name),
                    KeyVal(label: 'Codice', value: codice.isNotEmpty ? codice : '—'),
                    KeyVal(label: 'Marca', value: marca.isNotEmpty ? marca : '—'),
                    KeyVal(label: 'Modello', value: modello.isNotEmpty ? modello : '—'),
                    KeyVal(label: 'Tipo', value: tipo.isNotEmpty ? tipo : '—'),
                    KeyVal(label: 'Categoria', value: categoria.isNotEmpty ? categoria : '—'),
                    KeyVal(label: 'Unità di misura', value: um.isNotEmpty ? um : '—'),
                    KeyVal(
                      label: 'Numero di serie',
                      value: serialNumber.isNotEmpty ? serialNumber : '—',
                    ),
                    KeyVal(label: 'Data installazione', value: dateLabel('dataInstallazione')),
                    KeyVal(label: 'Ultima manutenzione', value: dateLabel('ultimaManutenzione')),
                    // The one field a technician needs to act on immediately — red when overdue.
                    KeyVal(
                      label: 'Prossima manutenzione',
                      value: dateLabel('prossimaManutenzione'),
                      valueColor: isOverdue('prossimaManutenzione') ? context.colors.red : null,
                      showDivider: description.isNotEmpty || notes.isNotEmpty || externalId.isNotEmpty,
                    ),
                    if (description.isNotEmpty)
                      KeyVal(
                        label: 'Descrizione',
                        value: description,
                        showDivider: notes.isNotEmpty || externalId.isNotEmpty,
                      ),
                    if (notes.isNotEmpty)
                      KeyVal(label: 'Note', value: notes, showDivider: externalId.isNotEmpty),
                    if (externalId.isNotEmpty)
                      KeyVal(label: 'ID gestionale', value: externalId, showDivider: false),
                  ],
                ),
              ),
            ),
          ),

          // ── Garanzia ───────────────────────────────────────────────────
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: VetroCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: 'Garanzia'),
                    const SizedBox(height: 4),
                    KeyVal(
                      label: 'Scadenza',
                      value: dateLabel('warrantyExpiryDate'),
                      showDivider: false,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Contratto collegato ────────────────────────────────────────
          if (contrattoId != null && contrattoId.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
                child: VetroCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionTitle(title: 'Contratto collegato'),
                      const SizedBox(height: 4),
                      KeyVal(label: 'Contratto', value: contrattoId, showDivider: false),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // ── Matricole (Gap 3) ────────────────────────────────────────────
          if (id.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(child: _MatricoleSection(prodottoId: id)),
          ],

          SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
        ],
      ),
    );
  }
}

/// Delete confirmation dialog + API call — mirrors `_deleteCantiere` in
/// admin_cantiere_detail_screen.dart (no shared confirm-dialog widget exists yet in this app).
Future<void> _deleteProdotto(BuildContext context, WidgetRef ref, String prodottoId, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Eliminare il prodotto?'),
      content: Text('Il prodotto "$name" verrà eliminato definitivamente. L\'operazione non può '
          'essere annullata.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(adminApiClientProvider).deleteProdottoAssistenza(prodottoId);
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Prodotto eliminato')));
      context.pop(true);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(humanErrorMessage(e, azione: 'eliminare il prodotto')),
          backgroundColor: context.colors.red,
        ),
      );
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Matricole (Gap 3) — real 1:N serial-number sub-resource, previously entirely absent on mobile.
// Add-only bottom sheet + confirm-delete, mirroring admin_cantiere_detail_screen.dart's
// `_CrewSection`/`_AddAssignmentSheet` shape (add/remove only, no in-place edit — the backend
// itself has no update route for a matricola either) rather than web's inline-form layout, per
// this app's own established mobile sub-resource pattern.
// ══════════════════════════════════════════════════════════════════════════════

final adminProdottoMatricoleProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, prodottoId) async {
      final api = ref.watch(adminApiClientProvider);
      return api.fetchMatricole(prodottoId);
    });

class _MatricoleSection extends ConsumerWidget {
  const _MatricoleSection({required this.prodottoId});

  final String prodottoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matricoleAsync = ref.watch(adminProdottoMatricoleProvider(prodottoId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: 'Matricole',
          action: IconButton(
            icon: const Icon(LucideIcons.plus),
            tooltip: 'Aggiungi matricola',
            onPressed: () => _openAddMatricolaSheet(context, ref),
          ),
        ),
        matricoleAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.pagePadding,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(LucideIcons.alertTriangle, size: 16, color: context.colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text('Impossibile caricare. Riprova.')),
                TextButton(
                  onPressed: () => ref.invalidate(adminProdottoMatricoleProvider(prodottoId)),
                  child: const Text('Riprova'),
                ),
              ],
            ),
          ),
          data: (matricole) {
            if (matricole.isEmpty) {
              return const EmptyState(
                icon: LucideIcons.fingerprint,
                title: 'Nessuna matricola registrata',
                body: 'Aggiungi un numero di serie con il pulsante +.',
              );
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.pagePadding),
              child: Column(
                children: matricole.asMap().entries.map((entry) {
                  final m = entry.value;
                  final numero = m['numero'] as String? ?? '';
                  final note = m['note'] as String?;
                  return ListRow(
                    leading: const RowIconTile(icon: LucideIcons.fingerprint),
                    title: numero.isNotEmpty ? numero : 'Matricola',
                    subtitle: note != null && note.isNotEmpty ? note : null,
                    meta: IconButton(
                      icon: const Icon(LucideIcons.trash2, size: 18),
                      tooltip: 'Rimuovi matricola',
                      onPressed: () => _deleteMatricola(
                        context,
                        ref,
                        prodottoId: prodottoId,
                        matricolaId: m['id'] as String,
                        numero: numero,
                      ),
                    ),
                    showDivider: entry.key < matricole.length - 1,
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _deleteMatricola(
    BuildContext context,
    WidgetRef ref, {
    required String prodottoId,
    required String matricolaId,
    required String numero,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovere la matricola?'),
        content: Text('Vuoi rimuovere la matricola "$numero" da questo prodotto?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rimuovi')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(adminApiClientProvider).deleteMatricola(prodottoId, matricolaId);
      ref.invalidate(adminProdottoMatricoleProvider(prodottoId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Matricola rimossa')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Impossibile eliminare. Riprova.'),
            backgroundColor: context.colors.red,
          ),
        );
      }
    }
  }

  void _openAddMatricolaSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddMatricolaSheet(
        prodottoId: prodottoId,
        api: ref.read(adminApiClientProvider),
        onSaved: () => ref.invalidate(adminProdottoMatricoleProvider(prodottoId)),
      ),
    );
  }
}

/// Bottom sheet to add a matricola — mirrors `AddMatricolaRequest` (numero required, note
/// optional). No edit: the backend has no update route for a matricola, only add/remove.
class _AddMatricolaSheet extends StatefulWidget {
  const _AddMatricolaSheet({required this.prodottoId, required this.api, required this.onSaved});

  final String prodottoId;
  final AdminApiClient api;
  final VoidCallback onSaved;

  @override
  State<_AddMatricolaSheet> createState() => _AddMatricolaSheetState();
}

class _AddMatricolaSheetState extends State<_AddMatricolaSheet> {
  final _numeroCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _numeroCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final numero = _numeroCtrl.text.trim();
    if (numero.isEmpty) return;
    setState(() => _isSaving = true);
    try {
      await widget.api.addMatricola(
        widget.prodottoId,
        numero: numero,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      widget.onSaved();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Matricola aggiunta')));
        Navigator.of(context).pop();
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        AppSpacing.pagePadding,
        MediaQuery.of(context).viewInsets.bottom + 19,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aggiungi matricola', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            AppTextField(
              label: 'Numero di serie *',
              hint: 'Es. SN-00123',
              controller: _numeroCtrl,
            ),
            const SizedBox(height: 16),
            AppTextField(label: 'Note', controller: _noteCtrl),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: VetroButton(
                label: _isSaving ? 'Salvataggio…' : 'Salva',
                onPressed: _isSaving ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
