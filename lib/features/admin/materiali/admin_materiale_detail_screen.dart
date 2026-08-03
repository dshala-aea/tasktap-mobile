// dart format width=100
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';

/// Single materiale by id from Drift cache.
final adminMaterialeDetailProvider =
    StreamProvider.autoDispose.family<MaterialiData?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)..where((m) => m.id.equals(id)))
      .watchSingleOrNull();
});

/// Admin materiale detail — read-only with edit FAB.
class AdminMaterialeDetailScreen extends ConsumerWidget {
  const AdminMaterialeDetailScreen({super.key, required this.materialeId});

  final String materialeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialeAsync =
        ref.watch(adminMaterialeDetailProvider(materialeId));

    return Scaffold(
      backgroundColor: AppColors.BG2,
      floatingActionButton: AppFab(
        icon: LucideIcons.pencil,
        tooltip: 'Modifica',
        onPressed: () async {
          await context.push<bool>(
            '/altro/magazzino/$materialeId/modifica',
          );
        },
      ),
      body: materialeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Errore: $e')),
        data: (materiale) {
          if (materiale == null) {
            return const Center(child: Text('Materiale non trovato'));
          }
          return _MaterialeDetailBody(materiale: materiale);
        },
      ),
    );
  }
}

class _MaterialeDetailBody extends StatelessWidget {
  const _MaterialeDetailBody({required this.materiale});

  final MaterialiData materiale;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: materiale.name,
            subtitle: materiale.code,
            showBack: true,
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(LucideIcons.moreVertical, size: 20),
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Text('Modifica'),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'edit') {
                    context.push('/altro/magazzino/${materiale.id}/modifica');
                  }
                },
              ),
            ],
          ),
        ),
        // ── Image ──────────────────────────────────────────────────────
        if (materiale.imageUrl != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(19, 0, 19, 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  materiale.imageUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    color: AppColors.BG3,
                    child: const Center(
                      child: Icon(LucideIcons.imageOff, size: 40, color: AppColors.MUTED),
                    ),
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!materiale.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'INATTIVO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                _InfoRow(label: 'Codice', value: materiale.code),
                _InfoRow(label: 'Nome', value: materiale.name),
                _InfoRow(
                    label: 'Descrizione',
                    value: materiale.description?.isNotEmpty == true
                        ? materiale.description!
                        : '—'),
                _InfoRow(
                    label: 'Unità di misura',
                    value: materiale.unitOfMeasure ?? '—'),
                _InfoRow(
                    label: 'Categoria',
                    value: materiale.category ?? '—'),
                _InfoRow(
                    label: 'Marca',
                    value: materiale.marca ?? '—'),
                _InfoRow(
                    label: 'Prezzo acquisto',
                    value: materiale.purchasePrice != null
                        ? '€${materiale.purchasePrice!.toStringAsFixed(2)}'
                        : '—'),
                _InfoRow(
                    label: 'Prezzo vendita',
                    value: materiale.salePrice != null
                        ? '€${materiale.salePrice!.toStringAsFixed(2)}'
                        : '—',
                    showDivider: false),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.MUTED,
                  letterSpacing: 1.2,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppColors.textPrimary,
                ),
          ),
        ],
      ),
    );
  }
}
