// dart format width=100
import 'package:flutter/material.dart';
import '../../../core/theme/app_rack.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tasktap_mobile/core/icons/app_lucide_icons.dart';

import '../../../core/widgets/widgets.dart';
import '../../../data/local/app_database.dart';
import '../../../data/sync/sync_service.dart';
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
        padding: EdgeInsets.only(bottom: context.navClearance - AppRack.navGap),
        child: AppFab(
          icon: LucideIcons.pencil,
          tooltip: 'Modifica',
          onPressed: () async {
            await context.push<bool>('/altro/magazzino/$materialeId/modifica');
          },
        ),
      ),
      body: materialeAsync.when(
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
          child: ScreenHeader(title: materiale.name, subtitle: materiale.code, showBack: true),
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
                AppCard(
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
                  AppCard(
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

        SliverPadding(padding: EdgeInsets.only(bottom: context.navClearance)),
      ],
    );
  }
}
