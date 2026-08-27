// dart format width=100
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/utils/offline_guard.dart';
import '../../../core/widgets/vetro_card.dart';
import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
import '../admin_api_client.dart';
import 'package:tasktap_mobile/core/theme/app_palette.dart';
import 'package:tasktap_mobile/core/theme/app_spacing.dart';

/// Single materiale by id from Drift cache.
final adminMaterialeDetailProvider = StreamProvider.autoDispose.family<MaterialiData?, String>((
  ref,
  id,
) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.materiali)..where((m) => m.id.equals(id))).watchSingleOrNull();
});

/// Admin materiale detail — read-only with edit FAB.
class AdminMaterialeDetailScreen extends ConsumerWidget {
  const AdminMaterialeDetailScreen({super.key, required this.materialeId});

  final String materialeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final materialeAsync = ref.watch(adminMaterialeDetailProvider(materialeId));

    return Scaffold(
      backgroundColor: context.colors.bg2,
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: context.fabSafeBottom),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/magazzino/$materialeId/modifica');
          },
        ),
      ),
      body: SafeArea(
        child: materialeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              ErrorState(onRetry: () => ref.invalidate(adminMaterialeDetailProvider(materialeId))),
          data: (materiale) {
            if (materiale == null) {
              return const UnavailableState(
                titolo: 'Materiale non disponibile',
                motivo:
                    'Il catalogo materiali non è ancora sincronizzato sul '
                    'dispositivo, quindi questo materiale non può essere '
                    'letto dalla cache locale anche se esiste sul server.',
              );
            }
            return _MaterialeDetailBody(materiale: materiale);
          },
        ),
      ),
    );
  }
}

/// Toggles a materiale's active state — Gap 5 of the feature audit: `isActive` was only ever
/// *displayed* here (and on the list row), never written from mobile, even though the backend's
/// soft-delete (`DELETE /api/materiali/{id}` → `IsActive = false`) and reactivate
/// (`PUT` with `isActive: true`) both already exist.
Future<void> _toggleActive(BuildContext context, WidgetRef ref, MaterialiData materiale) async {
  final deactivating = materiale.isActive;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(deactivating ? 'Disattiva materiale' : 'Riattiva materiale'),
      content: Text(
        deactivating
            ? 'Il materiale "${materiale.name}" non sarà più selezionabile nei nuovi rapportini o carichi/scarichi. Puoi riattivarlo in qualsiasi momento.'
            : 'Il materiale "${materiale.name}" tornerà selezionabile.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: deactivating ? TextButton.styleFrom(foregroundColor: ctx.colors.red) : null,
          child: Text(deactivating ? 'Disattiva' : 'Riattiva'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  if (!ensureOnlineOrWarn(context, ref)) return;

  try {
    final api = ref.read(adminApiClientProvider);
    if (deactivating) {
      await api.deleteMateriale(materiale.id);
    } else {
      await api.updateMateriale(materiale.id, isActive: true);
    }
    unawaited(ref.read(syncProvider.notifier).performSync());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(deactivating ? 'Materiale disattivato' : 'Materiale riattivato'),
          backgroundColor: context.colors.green,
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Impossibile aggiornare lo stato. Riprova.'),
          backgroundColor: context.colors.red,
        ),
      );
    }
  }
}

class _MaterialeDetailBody extends ConsumerWidget {
  const _MaterialeDetailBody({required this.materiale});

  final MaterialiData materiale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: ScreenHeader(
            title: materiale.name,
            subtitle: materiale.code,
            showBack: true,
            actions: [
              HeaderIconBtn(
                icon: materiale.isActive ? LucideIcons.xCircle : LucideIcons.checkCircle,
                label: materiale.isActive ? 'Disattiva' : 'Riattiva',
                glass: true,
                onTap: () => _toggleActive(context, ref, materiale),
              ),
            ],
          ),
        ),
        // ── Image ──────────────────────────────────────────────────────
        if (materiale.imageUrl != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pagePadding,
                0,
                AppSpacing.pagePadding,
                AppSpacing.base,
              ),
              child: ClipRRect(
                borderRadius: AppRack.freeShape,
                child: Image.network(
                  materiale.imageUrl!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 180,
                    color: context.colors.bg3,
                    child: Center(
                      child: Icon(LucideIcons.imageOff, size: 40, color: context.colors.inkMuted),
                    ),
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!materiale.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    margin: const EdgeInsets.only(bottom: AppSpacing.base),
                    decoration: BoxDecoration(
                      color: context.colors.red.withValues(alpha: 0.1),
                      borderRadius: AppRack.insetShape,
                    ),
                    child: Text(
                      'INATTIVO',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.colors.red,
                      ),
                    ),
                  ),
                VetroCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.base),
                  child: Column(
                    children: [
                      KeyVal(label: 'Codice', value: materiale.code),
                      KeyVal(label: 'Nome', value: materiale.name),
                      KeyVal(label: 'Unità di misura', value: materiale.unitOfMeasure ?? '—'),
                      KeyVal(label: 'Categoria', value: materiale.category ?? '—'),
                      KeyVal(label: 'Marca', value: materiale.marca ?? '—'),
                      KeyVal(
                        label: 'Prezzo acquisto',
                        value: materiale.purchasePrice != null
                            ? '€${materiale.purchasePrice!.toStringAsFixed(2)}'
                            : '—',
                      ),
                      KeyVal(
                        label: 'Prezzo vendita',
                        value: materiale.salePrice != null
                            ? '€${materiale.salePrice!.toStringAsFixed(2)}'
                            : '—',
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                if (materiale.description?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.base),
                  VetroCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionTitle(title: 'Descrizione'),
                        const SizedBox(height: 4),
                        Text(materiale.description!, style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        SliverPadding(padding: EdgeInsets.only(bottom: context.fabSafeBottom)),
      ],
    );
  }
}
